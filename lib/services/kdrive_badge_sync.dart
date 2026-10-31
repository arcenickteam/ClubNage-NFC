import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'infomaniak_kdrive_service.dart';
import 'xlsx_badge_writer.dart';
import 'xlsx_data_reader.dart';

/// Bilan d'une synchronisation de badges. Les conflits restent en attente.
class BadgeSyncResult {
  final Map<String, String> sharedBadges;
  final List<String> conflicts;
  final int uploaded;
  final int pending;
  const BadgeSyncResult({
    required this.sharedBadges,
    required this.conflicts,
    required this.uploaded,
    required this.pending,
  });
}

/// Journal append-only : ne jamais écraser une affectation concurrente.
class KdriveBadgeSync {
  static const _queueKey = 'v715_pending_badges';
  static const _deviceKey = 'v715_device_id';
  final InfomaniakKdriveService api;
  KdriveBadgeSync(this.api);

  static Future<String> _device(SharedPreferences prefs) async {
    var id = prefs.getString(_deviceKey);
    if (id == null || id.isEmpty) {
      id = 'android-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

  static Future<void> queueAssignment(Member member, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final device = await _device(prefs);
    final pending = prefs.getStringList(_queueKey) ?? <String>[];
    final now = DateTime.now().toUtc().toIso8601String();
    final event = <String>[
      '$device-$now', now, uid.toUpperCase(), member.id, 'NFC',
      'AFFECTATION', device, member.lastName, member.firstName,
      '', '7.19', '', 'Affectation depuis téléphone',
    ];
    pending.add(jsonEncode(event));
    if (!await prefs.setStringList(_queueKey, pending)) {
      throw StateError('Journal local des badges non enregistré.');
    }
  }

  Future<BadgeSyncResult> synchronize(List<Member> members) async {
    if (!await api.restoreSavedApiToken()) {
      throw StateError('Configurer le jeton API kDrive dans l’écran d’import.');
    }
    final prefs = await SharedPreferences.getInstance();
    final rawPending = prefs.getStringList(_queueKey) ?? <String>[];
    final etag = await api.scheduleEtag();
    final before = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
    List<List<String>> rows;
    try {
      rows = XlsxDataReader.readSheet(before, XlsxBadgeWriter.sheetName);
    } on FormatException catch (e) {
      if (!e.message.toString().contains('absent du classeur')) rethrow;
      rows = [];
    }
    if (rows.isNotEmpty && rows.first.join('|') != XlsxBadgeWriter.headers.join('|')) {
      throw StateError('Onglet Badges V715 incompatible : aucune modification.');
    }
    final existing = <String, List<String>>{};
    for (final row in rows.skip(1)) {
      if (row.isNotEmpty && row.first.isNotEmpty) {
        if (existing.containsKey(row.first)) {
          throw StateError('Événement badge dupliqué dans Excel.');
        }
        existing[row.first] = row;
      }
    }
    final activeByUid = <String, String>{};
    final activeByMember = <String, String>{};
    void apply(List<String> event) {
      if (event.length < 6 || event[4] != 'NFC') return;
      final uid = event[2].trim().toUpperCase();
      final member = event[3].trim();
      if (uid.isEmpty || member.isEmpty || event[5] != 'AFFECTATION') return;
      final oldUid = activeByMember[member];
      if (oldUid != null) activeByUid.remove(oldUid);
      final oldMember = activeByUid[uid];
      if (oldMember != null) activeByMember.remove(oldMember);
      activeByUid[uid] = member;
      activeByMember[member] = uid;
    }
    final history = existing.values.toList()
      ..sort((a, b) => a[1].compareTo(b[1]));
    for (final row in history) apply(row);

    final knownIds = members.map((m) => m.id).toSet();
    final accepted = <List<String>>[];
    final conflicts = <String>[];
    final remaining = <String>[];
    for (final raw in rawPending) {
      List<String> event;
      try {
        event = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {
        conflicts.add('Événement local illisible (conservé).');
        remaining.add(raw);
        continue;
      }
      if (event.length != 13 || !knownIds.contains(event[3]) ||
          event[2].trim().isEmpty || event[4] != 'NFC' ||
          event[5] != 'AFFECTATION') {
        conflicts.add('Affectation locale invalide (conservée).');
        remaining.add(raw);
        continue;
      }
      if (existing.containsKey(event[0])) {
        // Événement déjà confirmé lors d'une synchronisation précédente.
        continue;
      }
      final uid = event[2].trim().toUpperCase();
      final member = event[3];
      final owner = activeByUid[uid];
      if (owner != null && owner != member) {
        conflicts.add('Badge $uid : kDrive=$owner, local=$member.');
        remaining.add(raw);
        continue;
      }
      accepted.add(event);
      apply(event);
    }

    if (accepted.isNotEmpty) {
      if (await api.scheduleEtag() != etag) {
        throw StateError('Classeur modifié par un autre téléphone : relancer.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      for (final event in accepted) event[9] = now;
      final updated = XlsxBadgeWriter.merge(before, accepted);
      await api.replaceScheduleIfUnchanged(updated, etag);
      final after = await api.downloadWorkbook(InfomaniakKdriveService.scheduleName);
      final confirmed = XlsxDataReader.readSheet(after, XlsxBadgeWriter.sheetName);
      final confirmedIds = confirmed.skip(1)
          .where((r) => r.isNotEmpty).map((r) => r.first).toSet();
      if (!accepted.every((r) => confirmedIds.contains(r.first))) {
        throw StateError('Affectations non confirmées : journal local conservé.');
      }
    }
    // La file n'est réduite qu'après confirmation de tous les ajouts acceptés.
    // Les conflits ne sont jamais effacés automatiquement.
    if (remaining.length != rawPending.length) {
      if (!await prefs.setStringList(_queueKey, remaining)) {
        throw StateError('Journal local non mis à jour : relancer la synchronisation.');
      }
    }
    return BadgeSyncResult(
      sharedBadges: Map.unmodifiable(activeByMember),
      conflicts: List.unmodifiable(conflicts),
      uploaded: accepted.length,
      pending: remaining.length,
    );
  }
}
