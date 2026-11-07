import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';
import 'infomaniak_kdrive_service.dart';
import 'xlsx_pointage_writer.dart';
import 'xlsx_data_reader.dart';
import 'correction_journal.dart';

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
  final List<AttendanceCorrection> corrections;
  final int uploadedCorrections;
  final Set<String> conflictingPointageIds;
  final Map<String, AttendanceRecord> remoteConflicts;

  const AttendanceSyncResult({
    required this.sessions,
    required this.records,
    required this.uploadedPointages,
    required this.uploadedSessions,
    required this.importedPointages,
    required this.importedSessions,
    required this.conflicts,
    this.corrections = const [],
    this.uploadedCorrections = 0,
    this.conflictingPointageIds = const {},
    this.remoteConflicts = const {},
  });
}

class KdriveAttendanceSync {
  final InfomaniakKdriveService api;
  KdriveAttendanceSync(this.api);

  static const sessionSheet = 'Sessions NFC';
  static const correctionSheet = 'Historique corrections';
  static const deviceSheet = 'Appareils';
  static const correctionHeaders = <String>[
    'ID_Correction','ID_Pointage','ID_Seance','Licencie_ID',
    'Ancien_statut','Nouveau_statut','Revision_avant','Revision_apres',
    'Date_correction_UTC','Appareil_ID','Nom_appareil','Version_application',
    'Apres_cloture','Statut_sync','Conflit',
  ];
  static const deviceHeaders = <String>[
    'Appareil_ID','Nom_appareil','Version_application','Numero_build',
    'Premiere_utilisation_UTC','Derniere_synchronisation_UTC',
    'Derniere_activite_UTC','Etat_synchronisation',
  ];

  static List<String> _correctionRow(AttendanceCorrection e, {bool conflict = false}) => [
    e.id, e.pointageId, e.sessionId, e.memberId, e.previousStatus,
    e.newStatus, '${e.previousRevision}', '${e.newRevision}',
    e.at.toUtc().toIso8601String(), e.deviceId, e.deviceName,
    e.appVersion, e.afterClosure ? '1' : '0',
    conflict ? 'Conflit' : 'Enregistré', conflict ? '1' : '0',
  ];

  static AttendanceCorrection _decodeCorrection(List<String> r) {
    if (r.length != correctionHeaders.length) {
      throw const FormatException('Historique de correction incomplet.');
    }
    return AttendanceCorrection(
      id: r[0], pointageId: r[1], sessionId: r[2], memberId: r[3],
      previousStatus: r[4], newStatus: r[5],
      previousRevision: int.parse(r[6]), newRevision: int.parse(r[7]),
      at: DateTime.parse(r[8]), deviceId: r[9], deviceName: r[10],
      appVersion: r[11], afterClosure: r[12] == '1',
    );
  }

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
      record.sessionId ?? '', record.method,
      record.deviceId.isEmpty ? 'Inconnu (ancienne version)' : record.deviceId, syncDate,
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
      deviceId: row.length > 10 ? row[10] : '',
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
    List<AttendanceCorrection> corrections = const [],
    ClubDevice? device,
  }) async {
    if (!await api.restoreSavedApiToken()) {
      throw StateError('Configurer le jeton API kDrive dans l’écran d’import.');
    }
    final etag = await api.scheduleEtag();
    final before = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
    final oldPointages = _sheetOrEmpty(before, XlsxPointageWriter.sheetName);
    final oldSessions = _sheetOrEmpty(before, sessionSheet);
    final oldCorrections = _sheetOrEmpty(before, correctionSheet);
    final oldDevices = _sheetOrEmpty(before, deviceSheet);
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

    if (oldCorrections.isNotEmpty && !_sameSession(oldCorrections.first, correctionHeaders)) {
      throw StateError('En-têtes Historique corrections incompatibles : aucune écriture.');
    }
    if (oldDevices.isNotEmpty && !_sameSession(oldDevices.first, deviceHeaders)) {
      throw StateError('En-têtes Appareils incompatibles : aucune écriture.');
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
    String logicalKey(List<String> row) => '${row[8]}|${row[3]}';
    final remoteByLogicalKey = <String, List<String>>{};
    final remoteDuplicateKeys = <String>{};
    for (final row in remotePointages.values) {
      if (row.length < 13 || row[12] == 'Refus exceptionnel') continue;
      final key = logicalKey(row);
      if (remoteByLogicalKey.containsKey(key)) {
        remoteDuplicateKeys.add(key);
      } else {
        remoteByLogicalKey[key] = row;
      }
    }
    final remoteSessions = byId(oldSessions);
    final remoteCorrections = byId(oldCorrections);
    final conflicts = <String>[
      for (final key in remoteDuplicateKeys)
        'Doublon historique sur kDrive (séance/licencié) : $key. '
        'À examiner dans Excel, aucune suppression automatique.',
    ];
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
    final conflictingPointageIds = <String>{};
    final remoteConflictingRows = <String, List<String>>{};
    final localLogicalIds = <String, String>{};
    for (final record in records.where((r) => _canUpload(r) &&
        r.status != AttendanceStatus.refused)) {
      final key = '${record.sessionId ?? ''}|${record.memberId}';
      final previous = localLogicalIds[key];
      if (previous != null && previous != recordId(record)) {
        throw StateError('Deux pointages locaux pour $key : synchronisation refusée.');
      }
      localLogicalIds[key] = recordId(record);
    }
    final syncDate = DateTime.now().toIso8601String();
    for (final entry in localPointages.entries) {
      final row = _recordRow(entry.value, people, mergedSessions, syncDate);
      final previous = remotePointages[entry.key];
      if (remoteDuplicateKeys.contains(logicalKey(row)) &&
          entry.value.status != AttendanceStatus.refused) {
        conflicts.add('Pointages métier déjà dupliqués sur kDrive : ${logicalKey(row)}. '
            'Aucune nouvelle écriture pour ce licencié/séance.');
        conflictingPointageIds.add(entry.key);
      } else if (previous == null) {
        final other = remoteByLogicalKey[logicalKey(row)];
        if (other != null && other[0] != entry.key &&
            entry.value.status != AttendanceStatus.refused) {
          conflicts.add('Séance/licencié ${logicalKey(row)} : identifiants distincts entre téléphones.');
          conflictingPointageIds.add(entry.key);
          remoteConflictingRows[entry.key] = other;
        } else {
          newPointages.add(row);
        }
      } else {
        final remoteRevision = previous.length > 13 ? (int.tryParse(previous[13]) ?? 0) : 0;
        if (entry.value.revision > remoteRevision) {
          // Ne pas écraser une modification distante que ce téléphone n'a
          // jamais observée. La chaîne des événements doit être continue.
          final chain = corrections.where((e) => e.pointageId == entry.key &&
              e.newRevision > remoteRevision).toList()
            ..sort((a, b) => a.newRevision.compareTo(b.newRevision));
          var revision = remoteRevision;
          var status = _parseStatus(previous[12]).name;
          for (final event in chain) {
            if (event.previousRevision != revision || event.previousStatus != status) break;
            revision = event.newRevision;
            status = event.newStatus;
          }
          if (revision == entry.value.revision && status == entry.value.status.name) {
            newPointages.add(row);
          } else {
            conflicts.add('Pointage ${entry.key} : historique divergent, aucune ecriture.');
            conflictingPointageIds.add(entry.key);
            remoteConflictingRows[entry.key] = previous;
          }
        } else if (entry.value.revision == remoteRevision &&
            previous[12] != row[12]) {
          conflicts.add('Pointage ${entry.key} : revisions concurrentes, aucune ecriture.');
          conflictingPointageIds.add(entry.key);
          remoteConflictingRows[entry.key] = previous;
        } else if (entry.value.revision < remoteRevision &&
            corrections.any((e) => e.pointageId == entry.key &&
              !remoteCorrections.containsKey(e.id))) {
          conflicts.add('Pointage ${entry.key} : correction locale non confirmee, aucune suppression.');
          conflictingPointageIds.add(entry.key);
          remoteConflictingRows[entry.key] = previous;
        }
      }
    }

    final localCorrectionMap = <String, AttendanceCorrection>{};
    for (final e in corrections) {
      final existing = localCorrectionMap[e.id];
      if (existing != null && existing.toJson().toString() != e.toJson().toString()) {
        throw StateError('ID de correction réutilisé avec un contenu différent : ${e.id}');
      }
      localCorrectionMap[e.id] = e;
    }
    final newCorrections = <List<String>>[];
    for (final e in localCorrectionMap.values) {
      final existing = remoteCorrections[e.id];
      if (existing != null) {
        // Le statut de conflit peut être enrichi mais l'événement reste immuable.
        if (existing.take(13).join('|') != _correctionRow(e).take(13).join('|')) {
          throw StateError('Correction distante contradictoire : ${e.id}');
        }
        continue;
      }
      newCorrections.add(_correctionRow(e,
        conflict: conflictingPointageIds.contains(e.pointageId)));
    }
    final deviceRows = <List<String>>[];
    if (device != null) {
      final now = DateTime.now().toUtc().toIso8601String();
      deviceRows.add([
        device.id, device.name, device.version, device.build,
        device.firstUsed.toUtc().toIso8601String(), now, now,
        conflicts.isEmpty ? 'Synchronisé' : 'Conflits à vérifier',
      ]);
    }
    if (newPointages.isNotEmpty || newSessions.isNotEmpty ||
        newCorrections.isNotEmpty || deviceRows.isNotEmpty) {
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
      if (newCorrections.isNotEmpty) {
        updated = XlsxPointageWriter.merge(updated, newCorrections,
            targetSheetName: correctionSheet, targetHeaders: correctionHeaders);
      }
      if (deviceRows.isNotEmpty) {
        updated = XlsxPointageWriter.merge(updated, deviceRows,
            targetSheetName: deviceSheet, targetHeaders: deviceHeaders);
      }
      await api.replaceScheduleIfUnchanged(updated, etag);
    }

    // Relecture systématique, même lorsqu'aucune donnée n'a été envoyée.
    final after = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
    final confirmedPointages = byId(_sheetOrEmpty(after, XlsxPointageWriter.sheetName));
    final confirmedSessions = byId(_sheetOrEmpty(after, sessionSheet));
    final confirmedCorrections = byId(_sheetOrEmpty(after, correctionSheet));
    if (!newPointages.every((r) => confirmedPointages[r.first] != null &&
        samePointage(confirmedPointages[r.first]!, r)) ||
        !newSessions.every((r) => confirmedSessions[r.first] != null &&
        _sameSession(confirmedSessions[r.first]!, r)) ||
        !newCorrections.every((r) => confirmedCorrections[r.first] != null &&
        _sameSession(confirmedCorrections[r.first]!, r))) {
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
      if (!conflictingPointageIds.contains(entry.key) &&
          (local == null || remote.revision > local.revision)) {
        allRecords[entry.key] = remote;
        importedPointages++;
      }
    }
    final mergedCorrections = <String, AttendanceCorrection>{...localCorrectionMap};
    for (final entry in confirmedCorrections.entries) {
      mergedCorrections[entry.key] = _decodeCorrection(entry.value);
    }
    return AttendanceSyncResult(
      sessions: allSessions.values.toList(), records: allRecords.values.toList(),
      uploadedPointages: newPointages.length, uploadedSessions: newSessions.length,
      importedPointages: importedPointages, importedSessions: importedSessions,
      conflicts: conflicts, corrections: mergedCorrections.values.toList(),
      uploadedCorrections: newCorrections.length,
      conflictingPointageIds: conflictingPointageIds,
      remoteConflicts: {
        for (final entry in remoteConflictingRows.entries)
          entry.key: _decodeRecord(entry.value),
      },
    );
  }
}
