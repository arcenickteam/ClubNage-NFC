import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'services/infomaniak_kdrive_service.dart';
import 'services/xlsx_data_reader.dart';

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
  final kdrive = InfomaniakKdriveService();

  @override
  void initState() {
    super.initState();
    _restoreKdrive();
  }

  Future<void> _restoreKdrive() async {
    try {
      final restored = await kdrive.restoreSavedApiToken();
      if (mounted && restored) {
        setState(() => status = 'Jeton kDrive retrouvé sur ce téléphone. Vous pouvez synchroniser.');
      }
    } catch (_) {
      if (mounted) setState(() => status = 'Stockage sécurisé indisponible sur cet appareil.');
    }
  }

  Future<void> configureApiToken() async {
    final controller = TextEditingController();
    try {
      final token = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Connexion kDrive sécurisée'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Saisissez un jeton API dédié à ClubNage, limité à kDrive. Il restera dans le stockage sécurisé du téléphone.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(labelText: 'Jeton API Infomaniak'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Tester et enregistrer')),
          ],
        ),
      );
      if (token == null || token.trim().isEmpty || !mounted) return;
      setState(() { busy = true; status = 'Vérification des droits kDrive…'; });
      try {
        final folder = await kdrive.connectWithApiToken(token);
        if (mounted) setState(() => status = 'Connexion validée : ${folder['name']}. Jeton enregistré de façon sécurisée.');
      } catch (e) {
        if (mounted) setState(() => status = 'Connexion refusée : $e');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> forgetApiToken() async {
    setState(() => busy = true);
    try {
      await kdrive.forgetApiToken();
      if (mounted) setState(() => status = 'Jeton kDrive effacé de ce téléphone.');
    } catch (e) {
      if (mounted) setState(() => status = 'Impossible de supprimer le jeton : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }


  Future<void> connectKdrive() async {
    setState(() { busy = true; status = 'Connexion Infomaniak en cours…'; });
    try {
      await kdrive.connect();
      if (!mounted) return;
      setState(() => status = 'Connecté à Infomaniak. Vérification du dossier…');
      final folder = await kdrive.verifyFolder();
      if (!mounted) return;
      setState(() => status = 'Dossier API confirmé : ${folder['name']}. Prêt à synchroniser.');
    } catch (e) {
      if (mounted) setState(() => status = 'Connexion / dossier : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> synchronizeKdrive() async {
    setState(() { busy = true; status = 'Début du diagnostic kDrive V7.4…'; });
    String step = 'initialisation';
    void progress(String message) {
      step = message;
      if (mounted) setState(() => status = 'Diagnostic kDrive : $message');
    }
    try {
      progress('Base licenciés : vérification et téléchargement');
      final members = await kdrive.downloadWorkbook(
        InfomaniakKdriveService.membersName,
        onProgress: (s) => progress('Base licenciés : $s'),
      );
      progress('Base licenciés : décodage Excel');
      late final List<Map<String, String>> parsedPeople;
      try {
        parsedPeople = parseMembers(XlsxDataReader.readSheet(members, 'Licenciés'));
      } catch (e) {
        throw FormatException('Décodage base licenciés : $e');
      }
      progress('Planning : vérification et téléchargement');
      final schedule = await kdrive.downloadWorkbook(
        InfomaniakKdriveService.scheduleName,
        onProgress: (s) => progress('Planning : $s'),
      );
      progress('Planning : décodage Excel');
      late final List<Map<String, String>> parsedSlots;
      try {
        parsedSlots = parseSchedule(XlsxDataReader.readSheet(schedule, 'Planning référentiel'));
      } catch (e) {
        throw FormatException('Décodage planning : $e');
      }
      if (!mounted) return;
      setState(() {
        people = parsedPeople;
        slots = parsedSlots;
        status = 'kDrive : ${people.length} licenciés et ${slots.length} '
            'créneaux actualisés (lecture seule).';
      });
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Échec à l’étape « $step » : $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }


  String cell(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  Future<Uint8List?> pickWorkbook() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final Uint8List? bytes = picked.files.single.bytes;
    if (bytes == null) {
      throw StateError('Impossible de lire le fichier sélectionné.');
    }
    return bytes;
  }

  List<Map<String, String>> parseMembers(List<List<String>> rows) {
      if (rows.length < 5) {
        throw const FormatException('Onglet « Licenciés » absent ou vide.');
      }
      final header = List<String>.generate(rows[3].length, (i) => cell(rows[3], i));
      int col(String name) => header.indexWhere((x) => x.toLowerCase() == name.toLowerCase());
      final id = col('Licencie_ID');
      final nom = col('Nom');
      final prenom = col('Prénom');
      if (id < 0 || nom < 0 || prenom < 0) {
        throw const FormatException('Colonnes identifiant / nom / prénom absentes.');
      }
    final result = <Map<String, String>>[];
      for (final row in rows.skip(4)) {
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
    return result;
  }

  Future<void> loadMembers() async {
    setState(() => busy = true);
    try {
      final excel = await pickWorkbook();
      if (excel == null) return;
      final result = parseMembers(XlsxDataReader.readSheet(excel, 'Licenciés'));
      if (!mounted) return;
      setState(() { people = result; status = 'Base V4 : ${result.length} licenciés chargés en lecture seule'; });
    } catch (e) {
      if (mounted) setState(() => status = 'Erreur de lecture : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Map<String, String>> parseSchedule(List<List<String>> rows) {
      if (rows.isEmpty) throw const FormatException('Onglet « Planning référentiel » vide.');
      final result = <Map<String, String>>[];
      for (final row in rows.skip(1)) {
        final group = cell(row, 0);
        if (group.isEmpty) continue;
        result.add({
          'groupe': group, 'jour': cell(row, 1), 'debut': cell(row, 2),
          'fin': cell(row, 3), 'statut': cell(row, 4),
        });
      }
    return result;
  }

  Future<void> loadSchedule() async {
    setState(() => busy = true);
    try {
      final excel = await pickWorkbook();
      if (excel == null) return;
      final result = parseSchedule(XlsxDataReader.readSheet(excel, 'Planning référentiel'));
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
      appBar: AppBar(title: const Text('V7 · kDrive (lecture seule)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('V7.5 : lecture XLSX indépendante des styles et diagnostic kDrive par jeton API stocké de manière sécurisée sur cet appareil. Lecture seule des deux fichiers V4. Les badges et présences restent inchangés.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : configureApiToken, icon: const Icon(Icons.key), label: const Text('Configurer le jeton API kDrive')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : forgetApiToken, icon: const Icon(Icons.logout), label: const Text('Oublier le jeton sur ce téléphone')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: busy || !kdrive.isConnected ? null : synchronizeKdrive, icon: const Icon(Icons.sync), label: const Text('Synchroniser les deux fichiers kDrive')),
        const SizedBox(height: 12),
        const Text('Dépannage : import manuel des fichiers XLSX'),
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
