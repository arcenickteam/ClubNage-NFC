import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';
import 'infomaniak_kdrive_service.dart';
import 'xlsx_pointage_writer.dart';
import 'xlsx_data_reader.dart';

/// Résultat d'une synchronisation bidirectionnelle. Aucune donnée locale
/// n'est supprimée tant que le classeur n'a pas été confirmé par relecture.
class AttendanceSyncResult {
  final List<TrainingSession> sessions;
  final List<AttendanceRecord> records;
  final int uploadedPointages;
  final int uploadedSessions;
  final int importedPointages;
  final int importedSessions;
  final List<String> conflicts;

  const AttendanceSyncResult({
    required this.sessions,
    required this.records,
    required this.uploadedPointages,
    required this.uploadedSessions,
    required this.importedPointages,
    required this.importedSessions,
    required this.conflicts,
  });
}

class KdriveAttendanceSync {
  final InfomaniakKdriveService api;
  KdriveAttendanceSync(this.api);

  static const sessionSheet = 'Sessions NFC';
  static const sessionHeaders = <String>[
    'ID_Seance', 'Groupe', 'Date', 'Ouverture', 'Fermeture',
    'Licencies_attendus_JSON', 'Libelle', 'Debut', 'Fin',
    'Groupes_autorises_JSON', 'Type_manuel', 'Exclure_statistiques',
  ];

  static String recordId(AttendanceRecord record) =>
      '${record.sessionId ?? 'sans-seance'}|${record.memberId}|${record.timestamp.toUtc().toIso8601String()}';

  // Date_synchronisation est un champ technique, non une modification métier.
  static bool samePointage(List<String> a, List<String> b) =>
      a.length == b.length && List.generate(b.length,
          (i) => i == 11 || a[i] == b[i]).every((equal) => equal);

  static bool _sameSession(List<String> a, List<String> b) =>
      a.length == b.length && List.generate(b.length,
          (i) => a[i] == b[i]).every((equal) => equal);

  static String _statusLabel(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present: return 'Présent';
      case AttendanceStatus.late: return 'Retard';
      case AttendanceStatus.absent: return 'Absent';
      case AttendanceStatus.refused: return 'Refus exceptionnel';
      default: throw ArgumentError('Statut non synchronisable : $status');
    }
  }

  static AttendanceStatus _parseStatus(String value) {
    switch (value.trim()) {
      case 'Présent': return AttendanceStatus.present;
      case 'Retard': return AttendanceStatus.late;
      case 'Absent': return AttendanceStatus.absent;
      case 'Refus exceptionnel': return AttendanceStatus.refused;
      default: throw FormatException('Statut de pointage inconnu : $value');
    }
  }

  static List<String> _recordRow(AttendanceRecord record,
      Map<String, Member> people, Map<String, TrainingSession> sessionMap,
      String syncDate) {
    final member = people[record.memberId];
    final session = sessionMap[record.sessionId];
    final stamp = record.timestamp.toLocal().toIso8601String();
    return <String>[
      recordId(record), stamp.substring(0, 10), stamp.substring(11, 19),
      record.memberId, member?.lastName ?? '', member?.firstName ?? '',
      session?.label ?? record.groupId, record.groupId,
      record.sessionId ?? '', record.method, 'ClubNage Android', syncDate,
      _statusLabel(record.status), record.revision.toString(),
      (record.updatedAt ?? record.timestamp).toUtc().toIso8601String(),
    ];
  }

  static AttendanceRecord _decodeRecord(List<String> row) {
    if (row.length < 13 || row[0].trim().isEmpty || row[3].trim().isEmpty) {
      throw const FormatException('Pointage kDrive incomplet.');
    }
    // L'identifiant contient l'horodatage UTC d'origine, qui est plus précis
    // que les colonnes Date/Heure et ne dépend pas du fuseau du téléphone.
    final id = row[0];
    final split = id.lastIndexOf('|');
    if (split < 0) throw const FormatException('ID de pointage invalide.');
    final stamp = DateTime.tryParse(id.substring(split + 1));
    if (stamp == null) throw const FormatException('Date de pointage invalide.');
    return AttendanceRecord(
      memberId: row[3], groupId: row[7],
      sessionId: row[8].isEmpty ? null : row[8],
      timestamp: stamp.toLocal(), status: _parseStatus(row[12]),
      method: row[9],
      revision: row.length > 13 ? (int.tryParse(row[13]) ?? 0) : 0,
      updatedAt: row.length > 14 ? DateTime.tryParse(row[14]) : null,
    );
  }

  static List<String> _sessionRow(TrainingSession s) => <String>[
    s.id, s.groupId, s.date.toIso8601String(), s.openedAt.toIso8601String(),
    s.closedAt?.toIso8601String() ?? '', jsonEncode(s.expectedMemberIds),
    s.label ?? '', s.startTime?.toIso8601String() ?? '',
    s.endTime?.toIso8601String() ?? '', jsonEncode(s.eligibleGroupIds),
    s.manualType ?? '', s.excludeFromStats ? '1' : '0',
  ];

  static TrainingSession _decodeSession(List<String> row) {
    if (row.length < sessionHeaders.length || row[0].trim().isEmpty) {
      throw const FormatException('Séance kDrive incomplète.');
    }
    DateTime? optionalDate(String value) => value.isEmpty ? null : DateTime.parse(value);
    return TrainingSession(
      id: row[0], groupId: row[1], date: DateTime.parse(row[2]),
      openedAt: DateTime.parse(row[3]), closedAt: optionalDate(row[4]),
      expectedMemberIds: List<String>.from(jsonDecode(row[5]) as List),
      label: row[6].isEmpty ? null : row[6],
      startTime: optionalDate(row[7]), endTime: optionalDate(row[8]),
      eligibleGroupIds: List<String>.from(jsonDecode(row[9]) as List),
      manualType: row[10].isEmpty ? null : row[10],
      excludeFromStats: row[11] == '1',
    );
  }

  static bool _canUpload(AttendanceRecord r) =>
      r.status == AttendanceStatus.present ||
      r.status == AttendanceStatus.late ||
      r.status == AttendanceStatus.absent ||
      r.status == AttendanceStatus.refused;

  static List<List<String>> _sheetOrEmpty(List<int> bytes, String name) {
    try {
      return XlsxDataReader.readSheet(
          // downloadWorkbook retourne Uint8List, List<int> suffit au stockage.
          // La conversion est nécessaire pour le décodeur OOXML.
          Uint8List.fromList(bytes), name);
    } on FormatException catch (e) {
      if (!e.message.toString().contains('absent du classeur')) rethrow;
      return [];
    }
  }

  /// Envoie les nouvelles séances/présences puis relit le classeur pour
  /// rapatrier l'historique partagé sur tous les téléphones.
  Future<AttendanceSyncResult> synchronize({
    required List<AttendanceRecord> records,
    required List<TrainingSession> sessions,
    required List<Member> members,
  }) async {
    if (!await api.restoreSavedApiToken()) {
      throw StateError('Configurer le jeton API kDrive dans l’écran d’import.');
    }
    final etag = await api.scheduleEtag();
    final before = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
    final oldPointages = _sheetOrEmpty(before, XlsxPointageWriter.sheetName);
    final oldSessions = _sheetOrEmpty(before, sessionSheet);
    final legacyPointages = oldPointages.isNotEmpty &&
        oldPointages.first.length == 13 &&
        _sameSession(oldPointages.first, XlsxPointageWriter.headers.sublist(0, 13));
    if (oldPointages.isNotEmpty && !legacyPointages &&
        !_sameSession(oldPointages.first, XlsxPointageWriter.headers)) {
      throw StateError('En-têtes Pointages NFC incompatibles : aucune écriture.');
    }
    if (oldSessions.isNotEmpty &&
        !_sameSession(oldSessions.first, sessionHeaders)) {
      throw StateError('En-têtes Sessions NFC incompatibles : aucune écriture.');
    }

    Map<String, List<String>> byId(List<List<String>> rows) {
      final result = <String, List<String>>{};
      for (final row in rows.skip(1)) {
        if (row.isEmpty || row.first.trim().isEmpty) continue;
        if (result.containsKey(row.first)) {
          throw StateError('Identifiant dupliqué sur kDrive : ${row.first}');
        }
        result[row.first] = row;
      }
      return result;
    }

    final remotePointages = byId(oldPointages);
    final remoteSessions = byId(oldSessions);
    final conflicts = <String>[];
    final localSessions = {for (final s in sessions) s.id: s};
    final mergedSessions = <String, TrainingSession>{};
    for (final entry in remoteSessions.entries) {
      mergedSessions[entry.key] = _decodeSession(entry.value);
    }
    final importedSessions = mergedSessions.keys.where(
        (id) => !localSessions.containsKey(id)).length;
    for (final session in sessions) {
      final remote = mergedSessions[session.id];
      if (remote == null) {
        mergedSessions[session.id] = session;
        continue;
      }
      if (remote.expectedMemberIds.isNotEmpty &&
          session.expectedMemberIds.isNotEmpty &&
          (remote.expectedMemberIds.toSet()
              .difference(session.expectedMemberIds.toSet()).isNotEmpty ||
           session.expectedMemberIds.toSet()
              .difference(remote.expectedMemberIds.toSet()).isNotEmpty)) {
        conflicts.add('Séance ${session.id} : listes attendues différentes.');
      }
      // Conserver le référentiel attendu déjà partagé ; seule la fermeture
      // est propagée, et une liste vide peut être complétée si nécessaire.
      mergedSessions[session.id] = TrainingSession(
        id: remote.id, groupId: remote.groupId,
        date: remote.date, openedAt: remote.openedAt,
        closedAt: remote.closedAt ?? session.closedAt,
        expectedMemberIds: remote.expectedMemberIds.isNotEmpty
            ? remote.expectedMemberIds : session.expectedMemberIds,
        label: remote.label ?? session.label,
        startTime: remote.startTime ?? session.startTime,
        endTime: remote.endTime ?? session.endTime,
        eligibleGroupIds: remote.eligibleGroupIds.isNotEmpty
            ? remote.eligibleGroupIds : session.eligibleGroupIds,
        manualType: remote.manualType ?? session.manualType,
        excludeFromStats: remote.excludeFromStats || session.excludeFromStats,
      );
    }
    final newSessions = <List<String>>[];
    for (final s in mergedSessions.values) {
      final row = _sessionRow(s);
      final previous = remoteSessions[s.id];
      if (previous == null || !_sameSession(previous, row)) newSessions.add(row);
    }

    final people = {for (final m in members) m.id: m};
    // Les lignes anciennes ont une revision implicite 0.
    // Ne jamais utiliser Date_synchronisation comme horodatage metier.
    final localPointages = {for (final r in records.where(_canUpload)) recordId(r): r};
    final newPointages = <List<String>>[];
    final syncDate = DateTime.now().toIso8601String();
    for (final entry in localPointages.entries) {
      final row = _recordRow(entry.value, people, mergedSessions, syncDate);
      final previous = remotePointages[entry.key];
      if (previous == null) {
        newPointages.add(row);
      } else {
        final remoteRevision = previous.length > 13 ? (int.tryParse(previous[13]) ?? 0) : 0;
        if (entry.value.revision > remoteRevision) {
          newPointages.add(row);
        } else if (entry.value.revision == remoteRevision &&
            previous[12] != row[12]) {
          conflicts.add('Pointage ${entry.key} : revisions concurrentes, aucune ecriture.');
        }
      }
    }

    if (newPointages.isNotEmpty || newSessions.isNotEmpty) {
      if (await api.scheduleEtag() != etag) {
        throw StateError('Classeur modifié par un autre téléphone : relancer.');
      }
      var updated = before;
      if (newPointages.isNotEmpty) {
        updated = XlsxPointageWriter.merge(updated, newPointages);
      }
      if (newSessions.isNotEmpty) {
        updated = XlsxPointageWriter.merge(updated, newSessions,
            targetSheetName: sessionSheet, targetHeaders: sessionHeaders);
      }
      await api.replaceScheduleIfUnchanged(updated, etag);
    }

    // Relecture systématique, même lorsqu'aucune donnée n'a été envoyée.
    final after = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
    final confirmedPointages = byId(_sheetOrEmpty(after, XlsxPointageWriter.sheetName));
    final confirmedSessions = byId(_sheetOrEmpty(after, sessionSheet));
    if (!newPointages.every((r) => confirmedPointages[r.first] != null &&
        samePointage(confirmedPointages[r.first]!, r)) ||
        !newSessions.every((r) => confirmedSessions[r.first] != null &&
        _sameSession(confirmedSessions[r.first]!, r))) {
      throw StateError('Synchronisation non confirmée : données locales conservées.');
    }

    final allSessions = <String, TrainingSession>{...localSessions};
    for (final entry in confirmedSessions.entries) {
      final remote = _decodeSession(entry.value);
      final local = allSessions[entry.key];
      if (local == null || (local.isOpen && !remote.isOpen)) {
        allSessions[entry.key] = remote;
      }
    }
    final allRecords = <String, AttendanceRecord>{...localPointages};
    var importedPointages = 0;
    for (final entry in confirmedPointages.entries) {
      final remote = _decodeRecord(entry.value);
      final local = allRecords[entry.key];
      if (local == null || remote.revision > local.revision) {
        allRecords[entry.key] = remote;
        importedPointages++;
      }
    }
    return AttendanceSyncResult(
      sessions: allSessions.values.toList(), records: allRecords.values.toList(),
      uploadedPointages: newPointages.length, uploadedSessions: newSessions.length,
      importedPointages: importedPointages, importedSessions: importedSessions,
      conflicts: conflicts,
    );
  }
}
