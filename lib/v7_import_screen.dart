import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// V7: consultation isolée des exports kDrive, sans écriture ni migration
/// des associations NFC/QR de la V6.
class V7ImportScreen extends StatefulWidget {
  const V7ImportScreen({super.key});
  @override
  State<V7ImportScreen> createState() => _V7ImportScreenState();
}

class _V7ImportScreenState extends State<V7ImportScreen> {
  List<Map<String, String>> people = [];
  List<Map<String, String>> slots = [];
  String status = 'Aucun fichier chargé';
  String filter = '';
  bool busy = false;

  String cell(List<Data?> row, int index) {
    if (index >= row.length) return '';
    final v = row[index]?.value;
    if (v == null) return '';
    if (v is TextCellValue) return (v.value.text ?? '').trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    if (v is BoolCellValue) return v.value ? '1' : '0';
    return v.toString().trim();
  }

  Future<Excel?> pickWorkbook() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final Uint8List? bytes = picked.files.single.bytes;
    if (bytes == null) throw StateError('Impossible de lire le fichier sélectionné.');
    return Excel.decodeBytes(bytes);
  }

  Future<void> loadMembers() async {
    setState(() => busy = true);
    try {
      final excel = await pickWorkbook();
      if (excel == null) return;
      final sheet = excel.tables['Licenciés'];
      if (sheet == null || sheet.rows.length < 5) {
        throw const FormatException('Onglet « Licenciés » absent ou vide.');
      }
      final header = List<String>.generate(sheet.rows[3].length, (i) => cell(sheet.rows[3], i));
      int col(String name) => header.indexWhere((x) => x.toLowerCase() == name.toLowerCase());
      final id = col('Licencie_ID');
      final nom = col('Nom');
      final prenom = col('Prénom');
      if (id < 0 || nom < 0 || prenom < 0) {
        throw const FormatException('Colonnes identifiant / nom / prénom absentes.');
      }
      final result = <Map<String, String>>[];
      for (final row in sheet.rows.skip(4)) {
        if (cell(row, id).isEmpty) continue;
        final activeGroups = <String>[];
        for (var i = 25; i < header.length && i < row.length; i++) {
          final v = cell(row, i).toLowerCase();
          if (v == '1' || v == 'true' || v == 'vrai') activeGroups.add(header[i]);
        }
        result.add({
          'id': cell(row, id), 'nom': cell(row, nom), 'prenom': cell(row, prenom),
          'categorie': col('Catégorie') >= 0 ? cell(row, col('Catégorie')) : '',
          'session1': col('Session 1') >= 0 ? cell(row, col('Session 1')) : '',
          'session2': col('Session 2') >= 0 ? cell(row, col('Session 2')) : '',
          'niveau': col('Niveau') >= 0 ? cell(row, col('Niveau')) : '',
          'groupes': activeGroups.join(', '),
        });
      }
      if (!mounted) return;
      setState(() { people = result; status = 'Base V4 : ${result.length} licenciés chargés en lecture seule'; });
    } catch (e) {
      if (mounted) setState(() => status = 'Erreur de lecture : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadSchedule() async {
    setState(() => busy = true);
    try {
      final excel = await pickWorkbook();
      if (excel == null) return;
      final sheet = excel.tables['Planning référentiel'];
      if (sheet == null) throw const FormatException('Onglet « Planning référentiel » absent.');
      final result = <Map<String, String>>[];
      for (final row in sheet.rows.skip(1)) {
        final group = cell(row, 0);
        if (group.isEmpty) continue;
        result.add({
          'groupe': group, 'jour': cell(row, 1), 'debut': cell(row, 2),
          'fin': cell(row, 3), 'statut': cell(row, 4),
        });
      }
      if (!mounted) return;
      setState(() { slots = result; status = 'Planning V4 : ${result.length} entrées chargées en lecture seule'; });
    } catch (e) {
      if (mounted) setState(() => status = 'Erreur de lecture : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = filter.toLowerCase().trim();
    final visible = people.where((p) => '${p['nom']} ${p['prenom']} ${p['groupes']} ${p['id']}'
        .toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('V7 · Essais kDrive (lecture seule)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Sélectionnez les deux fichiers V4 téléchargés depuis kDrive. Aucune donnée n’est envoyée, aucun badge ni historique V6 n’est modifié.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : loadMembers, icon: const Icon(Icons.people), label: const Text('Importer la base licenciés V4')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : loadSchedule, icon: const Icon(Icons.calendar_month), label: const Text('Importer le suivi / planning V4')),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 12), Text(status),
        const Divider(height: 32),
        Text('Licenciés : ${people.length}', style: Theme.of(context).textTheme.titleLarge),
        TextField(onChanged: (v) => setState(() => filter = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher nom, identifiant ou groupe')),
        const SizedBox(height: 8),
        for (final p in visible.take(50)) ListTile(
          title: Text('${p['prenom']} ${p['nom']}'),
          subtitle: Text('${p['id']} · ${p['groupes']}\n${p['categorie']} · ${p['session1']} ${p['session2']} · ${p['niveau']}'),
          isThreeLine: true,
        ),
        if (visible.length > 50) Text('50 premiers résultats sur ${visible.length} : affinez la recherche.'),
        const Divider(height: 32),
        Text('Créneaux : ${slots.length}', style: Theme.of(context).textTheme.titleLarge),
        for (final s in slots) ListTile(
          title: Text('${s['groupe']} · ${s['jour']}'),
          subtitle: Text('${s['debut']}–${s['fin']} · ${s['statut']}'),
          dense: true,
        ),
      ]),
    );
  }
}
