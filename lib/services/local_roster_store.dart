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
      ));
    }
    return result;
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
        'dossierStatus': 'Importé',
      });
    }
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(key, jsonEncode({'schema': 1, 'members': members}));
    if (!ok) throw StateError('Impossible de conserver les licenciés localement.');
  }
}
