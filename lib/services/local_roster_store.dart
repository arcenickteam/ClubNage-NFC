import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';

/// Référentiel local : écriture atomique d'une liste validée.
class LocalRosterStore {
  static const key = 'clubnage_v76_roster_v1';

  Future<List<Member>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map || value['schema'] != 1 || value['members'] is! List) {
      throw const FormatException('Référentiel licenciés incompatible.');
    }
    final result = <Member>[];
    for (final item in value['members'] as List) {
      if (item is! Map) throw const FormatException('Licencié invalide.');
      result.add(Member(
        id: item['id'] as String,
        firstName: item['firstName'] as String,
        lastName: item['lastName'] as String,
        groups: List<String>.from(item['groups'] as List),
        nfcUid: '', qrToken: '',
        dossierStatus: item['dossierStatus'] as String? ?? 'Importé',
        category: item['category'] as String? ?? '',
        session1: item['session1'] as String? ?? '',
        session2: item['session2'] as String? ?? '',
        authorizedSlots: item['authorizedSlots'] as String? ?? '',
        level: item['level'] as String? ?? '',
        dateOfBirth: item['dateOfBirth'] as String? ?? '',
        city: item['city'] as String? ?? '',
        phone: item['phone'] as String? ?? '',
        guardianPhone: item['guardianPhone'] as String? ?? '',
        legalRepresentative: item['legalRepresentative'] as String? ?? '',
      ));
    }
    return result;
  }

  /// Efface uniquement le référentiel local après confirmation explicite.
  /// Ne touche pas aux badges, aux pointages ni au jeton kDrive.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.remove(key);
    if (!ok) throw StateError('Suppression du référentiel local impossible.');
  }

  Future<void> save(List<Map<String, String>> rows) async {
    if (rows.isEmpty) throw StateError('Import vide : base locale conservée.');
    final ids = <String>{};
    final members = <Map<String, Object>>[];
    for (final row in rows) {
      final id = (row['id'] ?? '').trim();
      final first = (row['prenom'] ?? '').trim();
      final last = (row['nom'] ?? '').trim();
      if (id.isEmpty || first.isEmpty || last.isEmpty || !ids.add(id)) {
        throw StateError('Identifiant doublon ou licencié incomplet : $id');
      }
      members.add({
        'id': id, 'firstName': first, 'lastName': last,
        'groups': (row['groupes'] ?? '').split(',').map((s) => s.trim())
            .where((s) => s.isNotEmpty).toList(),
        'dossierStatus': (row['statutDossier'] ?? '').trim(),
        'category': row['categorie'] ?? '',
        'session1': row['session1'] ?? '',
        'session2': row['session2'] ?? '',
        'authorizedSlots': row['creneau'] ?? '',
        'level': row['niveau'] ?? '',
        'dateOfBirth': row['dateNaissance'] ?? '',
        'city': row['ville'] ?? '',
        'phone': row['telephone'] ?? '',
        'guardianPhone': row['telephoneTuteur'] ?? '',
        'legalRepresentative': row['representantLegal'] ?? '',
      });
    }
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(key, jsonEncode({'schema': 1, 'members': members}));
    if (!ok) throw StateError('Impossible de conserver les licenciés localement.');
  }
}
