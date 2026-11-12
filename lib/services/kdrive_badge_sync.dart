import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import 'infomaniak_kdrive_service.dart';
import 'xlsx_badge_writer.dart';
import 'xlsx_data_reader.dart';

/// Bilan d'une synchronisation de badges. Les conflits restent en attente.
class BadgeSyncResult {
  final Map<String, String> sharedBadges;
  final Map<String, String> sharedQrTokens;
  final List<String> conflicts;
  final int uploaded;
  final int pending;
  /// Affectations locales non confirmées, à préserver sur le téléphone.
  final Map<String, String> pendingBadges;
  final Map<String, String> pendingQrTokens;
  const BadgeSyncResult({
    required this.sharedBadges,
    required this.sharedQrTokens,
    required this.conflicts,
    required this.uploaded,
    required this.pending,
    required this.pendingBadges,
    required this.pendingQrTokens,
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
    await _queue(member, uid.trim().toUpperCase(), 'NFC', '');
  }

  static Future<void> queueQrAssignment(Member member, String token,
      {String previousToken = ''}) async {
    await _queue(member, token.trim(), 'QR', previousToken.trim());
  }

  static Future<void> _queue(Member member, String token,
      String type, String reference) async {
    if (token.isEmpty) throw StateError('Identifiant de badge vide.');
    final prefs = await SharedPreferences.getInstance();
    final device = await _device(prefs);
    final pending = prefs.getStringList(_queueKey) ?? <String>[];
    final now = DateTime.now().toUtc().toIso8601String();
    final event = <String>[
      '$device-$now-${DateTime.now().microsecondsSinceEpoch}', now, token, member.id, type,
      'AFFECTATION', device, member.lastName, member.firstName,
      '', '7.25', reference, 'Affectation depuis téléphone',
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
    // Deux espaces d'identifiants distincts : NFC (UID normalisé) et QR
    // (jeton sensible à la casse). Le journal Excel conserve les deux types.
    final activeNfcByToken = <String, String>{};
    final activeNfcByMember = <String, String>{};
    final activeQrByToken = <String, String>{};
    final activeQrByMember = <String, String>{};
    String tokenOf(List<String> event) => event[4] == 'NFC'
        ? event[2].trim().toUpperCase() : event[2].trim();
    void apply(List<String> event) {
      if (event.length < 6 || event[5] != 'AFFECTATION') return;
      final type = event[4];
      if (type != 'NFC' && type != 'QR') return;
      final token = tokenOf(event);
      final member = event[3].trim();
      if (token.isEmpty || member.isEmpty) return;
      final byToken = type == 'NFC' ? activeNfcByToken : activeQrByToken;
      final byMember = type == 'NFC' ? activeNfcByMember : activeQrByMember;
      final oldToken = byMember[member];
      if (oldToken != null) byToken.remove(oldToken);
      final oldMember = byToken[token];
      if (oldMember != null) byMember.remove(oldMember);
      byToken[token] = member;
      byMember[member] = token;
    }
    final history = existing.values.toList()
      ..sort((a, b) {
        final time = a[1].compareTo(b[1]);
        return time != 0 ? time : a[0].compareTo(b[0]);
      });
    for (final row in history) apply(row);

    final knownIds = members.map((m) => m.id).toSet();
    // Migration non destructive des QR déjà affectés sur les 9 téléphones
    // avant la V7.25 : aucun qr_* n'est effacé ou remplacé.
    final pendingNow = <String>[...rawPending];
    final pendingKeys = <String>{};
    for (final raw in pendingNow) {
      try {
        final event = (jsonDecode(raw) as List).cast<String>();
        if (event.length == 13 && event[4] == 'QR') {
          pendingKeys.add('${event[3]}\u0000${event[2]}');
        }
      } catch (_) { /* Conservé, signalé plus bas. */ }
    }
    final device = await _device(prefs);
    for (final member in members) {
      final localQr = prefs.getString('qr_${member.id}')?.trim() ?? '';
      if (localQr.isEmpty || activeQrByMember[member.id] == localQr ||
          pendingKeys.contains('${member.id}\u0000$localQr')) continue;
      final now = DateTime.now().toUtc().toIso8601String();
      pendingNow.add(jsonEncode(<String>[
        '$device-$now-${DateTime.now().microsecondsSinceEpoch}',
        now, localQr, member.id, 'QR', 'AFFECTATION', device,
        member.lastName, member.firstName, '', '7.25', '',
        'Migration QR local existant : ne pas supprimer',
      ]));
      pendingKeys.add('${member.id}\u0000$localQr');
    }
    if (pendingNow.length != rawPending.length &&
        !await prefs.setStringList(_queueKey, pendingNow)) {
      throw StateError('Migration QR locale non sauvegardée : aucune écriture kDrive.');
    }

    final accepted = <List<String>>[];
    final conflicts = <String>[];
    final remaining = <String>[];
    for (final raw in pendingNow) {
      List<String> event;
      try {
        event = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {
        conflicts.add('Événement local illisible (conservé).');
        remaining.add(raw);
        continue;
      }
      if (event.length != 13 || !knownIds.contains(event[3]) ||
          event[2].trim().isEmpty ||
          (event[4] != 'NFC' && event[4] != 'QR') ||
          event[5] != 'AFFECTATION') {
        conflicts.add('Affectation locale invalide (conservée).');
        remaining.add(raw);
        continue;
      }
      if (existing.containsKey(event[0])) continue;
      final type = event[4];
      final token = tokenOf(event);
      final member = event[3];
      final byToken = type == 'NFC' ? activeNfcByToken : activeQrByToken;
      final byMember = type == 'NFC' ? activeNfcByMember : activeQrByMember;
      final owner = byToken[token];
      if (owner != null && owner != member) {
        conflicts.add('$type $token : kDrive=$owner, local=$member.');
        remaining.add(raw);
        continue;
      }
      final remoteToken = byMember[member];
      if (type == 'QR' && remoteToken != null && remoteToken != token &&
          event[11].trim() != remoteToken) {
        conflicts.add('QR de $member : kDrive=$remoteToken, local=$token. '
            'Réaffectation concurrente : aucune écriture.');
        remaining.add(raw);
        continue;
      }
      // Déjà partagé sur un autre téléphone : ne pas écrire de doublon.
      if (remoteToken == token) continue;
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
    // Un scan peut être enregistré pendant les appels réseau : préserver
    // les événements ajoutés depuis la lecture initiale de la file.
    final latest = prefs.getStringList(_queueKey) ?? <String>[];
    final original = pendingNow.toSet();
    final fresh = latest.where((raw) => !original.contains(raw)).toList();
    final preserved = <String>[...remaining, ...fresh];
    if (preserved.length != latest.length ||
        !List.generate(preserved.length, (i) => preserved[i] == latest[i])
            .every((same) => same)) {
      if (!await prefs.setStringList(_queueKey, preserved)) {
        throw StateError('Journal local non mis à jour : relancer la synchronisation.');
      }
    }
    final pendingBadges = <String, String>{};
    final pendingQrTokens = <String, String>{};
    for (final raw in preserved) {
      try {
        final event = (jsonDecode(raw) as List).cast<String>();
        if (event.length == 13 && event[5] == 'AFFECTATION' &&
            event[3].isNotEmpty && event[2].trim().isNotEmpty) {
          if (event[4] == 'NFC') {
            pendingBadges[event[3]] = event[2].trim().toUpperCase();
          } else if (event[4] == 'QR') {
            pendingQrTokens[event[3]] = event[2].trim();
          }
        }
      } catch (_) {
        // Les événements invalides restent conservés dans la file.
      }
    }

    return BadgeSyncResult(
      sharedBadges: Map.unmodifiable(activeNfcByMember),
      sharedQrTokens: Map.unmodifiable(activeQrByMember),
      conflicts: List.unmodifiable(conflicts),
      uploaded: accepted.length,
      pending: preserved.length,
      pendingBadges: Map.unmodifiable(pendingBadges),
      pendingQrTokens: Map.unmodifiable(pendingQrTokens),
    );
  }
}
