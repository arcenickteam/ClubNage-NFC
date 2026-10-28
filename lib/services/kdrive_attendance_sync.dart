import '../models.dart';
import 'infomaniak_kdrive_service.dart';
import 'xlsx_pointage_writer.dart';
import 'xlsx_data_reader.dart';

class KdriveAttendanceSync {
  final InfomaniakKdriveService api;
  KdriveAttendanceSync(this.api);

  static String recordId(AttendanceRecord record) =>
      '${record.sessionId ?? 'sans-seance'}|${record.memberId}|${record.timestamp.toUtc().toIso8601String()}';

  // La date de synchronisation ne constitue pas une modification du pointage.
  static bool samePointage(List<String> a, List<String> b) =>
      a.length == b.length && List.generate(b.length,
          (i) => i == 11 || a[i] == b[i]).every((equal) => equal);

  /// Les entrées sont relues dans Excel après l'envoi. Sans confirmation,
  /// le pointage reste dans le journal local et sera réessayé sans doublon.
  Future<int> synchronize({
    required List<AttendanceRecord> records,
    required List<TrainingSession> sessions,
    required List<Member> members,
  }) async {
    if (!await api.restoreSavedApiToken()) {
      throw StateError('Configurer le jeton API kDrive dans l’écran d’import.');
    }
    final local = records.where((r) => r.status == AttendanceStatus.present ||
        r.status == AttendanceStatus.late || r.status == AttendanceStatus.absent).toList();
    if (local.isEmpty) return 0;
    final etag = await api.scheduleEtag();
    final before = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
    List<List<String>> existing;
    try {
      existing = XlsxDataReader.readSheet(before, XlsxPointageWriter.sheetName);
    } on FormatException catch (e) {
      if (!e.message.toString().contains('absent du classeur')) rethrow;
      existing = [];
    }
    final oldRows = {for (final r in existing.skip(1)) if (r.isNotEmpty) r.first: r};
    final people = {for (final m in members) m.id: m};
    final sessionMap = {for (final s in sessions) s.id: s};
    final syncDate = DateTime.now().toIso8601String();
    final newRows = <List<String>>[];
    for (final record in local) {
      final id = recordId(record);
      final member = people[record.memberId];
      final session = sessionMap[record.sessionId];
      final stamp = record.timestamp.toLocal();
      final iso = stamp.toIso8601String();
      final row = <String>[
        id, iso.substring(0, 10), iso.substring(11, 19), record.memberId,
        member?.lastName ?? '', member?.firstName ?? '',
        session?.label ?? record.groupId, record.groupId,
        record.sessionId ?? '', record.method, 'ClubNage Android', syncDate,
        record.status == AttendanceStatus.absent ? 'Absent' :
            record.status == AttendanceStatus.late ? 'Retard' : 'Présent',
      ];
      final previous = oldRows[id];
      if (previous == null || !samePointage(previous, row)) newRows.add(row);
    }
    if (newRows.isEmpty) return 0;
    final latestEtag = await api.scheduleEtag();
    if (latestEtag != etag) {
      throw StateError('Classeur modifié pendant la lecture : recommencer.');
    }
    // Évite une fenêtre de concurrence avant le POST. L'If-Match doit
    // également être honoré par le serveur pendant l'écriture.
    final bytes = XlsxPointageWriter.merge(before, newRows);
    await api.replaceScheduleIfUnchanged(bytes, etag);
    final after = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
    final checked = XlsxDataReader.readSheet(after, XlsxPointageWriter.sheetName);
    final confirmed = {for (final r in checked.skip(1)) if (r.isNotEmpty) r.first: r};
    if (!newRows.every((r) => confirmed[r.first] != null && samePointage(confirmed[r.first]!, r))) {
      throw StateError('Téléversement reçu, mais pointages non confirmés dans Excel.');
    }
    return newRows.length;
  }
}
