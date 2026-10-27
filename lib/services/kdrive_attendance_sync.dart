import '../models.dart';
import 'infomaniak_kdrive_service.dart';
import 'xlsx_pointage_writer.dart';
import 'xlsx_data_reader.dart';

class KdriveAttendanceSync {
  final InfomaniakKdriveService api;
  KdriveAttendanceSync(this.api);

  static String recordId(AttendanceRecord record) =>
      '${record.sessionId ?? 'sans-seance'}|${record.memberId}|${record.timestamp.toUtc().toIso8601String()}';

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
        r.status == AttendanceStatus.late).toList();
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
    final oldIds = existing.skip(1).where((r) => r.isNotEmpty).map((r) => r.first).toSet();
    final people = {for (final m in members) m.id: m};
    final sessionMap = {for (final s in sessions) s.id: s};
    final syncDate = DateTime.now().toIso8601String();
    final newRows = <List<String>>[];
    for (final record in local) {
      final id = recordId(record);
      if (oldIds.contains(id)) continue;
      final member = people[record.memberId];
      final session = sessionMap[record.sessionId];
      final stamp = record.timestamp.toLocal();
      final iso = stamp.toIso8601String();
      newRows.add([
        id, iso.substring(0, 10), iso.substring(11, 19), record.memberId,
        member?.lastName ?? '', member?.firstName ?? '',
        session?.label ?? record.groupId, record.groupId,
        record.sessionId ?? '', record.method, 'ClubNage Android', syncDate,
      ]);
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
    final confirmed = checked.skip(1).where((r) => r.isNotEmpty).map((r) => r.first).toSet();
    if (!newRows.every((r) => confirmed.contains(r.first))) {
      throw StateError('Téléversement reçu, mais pointages non confirmés dans Excel.');
    }
    return newRows.length;
  }
}
