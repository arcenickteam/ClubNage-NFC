import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'services/infomaniak_kdrive_service.dart';
import 'services/xlsx_data_reader.dart';
import 'services/local_roster_store.dart';

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
  final rosterStore = LocalRosterStore();

  @override
  void initState() {
    super.initState();
    _restoreKdrive();
    _restoreRoster();
  }

  Future<void> _restoreRoster() async {
    try {
      final restored = await rosterStore.load();
      if (mounted && restored != null) {
        setState(() {
          people = restored.map((m) => {
            'id': m.id, 'nom': m.lastName, 'prenom': m.firstName,
            'groupes': m.groups.join(', '),
          }).toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Base locale indisponible : $e');
    }
  }

  Future<void> clearLocalRoster() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vider la liste locale des licenciés ?'),
        content: const Text(
          'Cette opération supprime uniquement la liste des licenciés mémorisée '
          'sur ce téléphone. Elle ne supprime pas les fichiers kDrive, les '
          'associations NFC ni les historiques de présence. '
          'Réimportez ensuite la base officielle.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Vider la liste locale')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await rosterStore.clear();
      if (mounted) setState(() {
        people = [];
        status = 'Liste locale vidée. Importez maintenant la base officielle kDrive.';
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Suppression impossible : $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    setState(() { busy = true; status = 'Synchronisation kDrive : démarrage…'; });
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
      await rosterStore.save(parsedPeople);
      if (!mounted) return;
      setState(() {
        people = parsedPeople;
        slots = parsedSlots;
        status = 'kDrive : ${people.length} licenciés enregistrés sur le téléphone et ${slots.length} '
            'créneaux consultés. Rouvrir l’accueil pour utiliser les licenciés.';
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
          'creneau': col('Créneau') >= 0 ? cell(row, col('Créneau')) : '',
          'niveau': col('Niveau') >= 0 ? cell(row, col('Niveau')) : '',
          'dateNaissance': col('Date naissance') >= 0 ? cell(row, col('Date naissance')) : '',
          'ville': col('Ville') >= 0 ? cell(row, col('Ville')) : '',
          'telephone': col('Téléphone licencié') >= 0 ? cell(row, col('Téléphone licencié')) : '',
          'telephoneTuteur': col('Téléphone responsable légal') >= 0 ? cell(row, col('Téléphone responsable légal')) : '',
          'representantLegal': col('Représentant légal') >= 0 ? cell(row, col('Représentant légal')) : '',
          'statutDossier': col('Statut dossier') >= 0 ? cell(row, col('Statut dossier')) : '',
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
      await rosterStore.save(result);
      if (!mounted) return;
      setState(() { people = result; status = 'Base officielle : ${result.length} licenciés importés et mémorisés'; });
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
      setState(() { slots = result; status = 'Planning officiel : ${result.length} créneaux chargés'; });
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
      appBar: AppBar(title: const Text('V7.16 · kDrive')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Importation de la base officielle et du planning depuis kDrive. Les badges et les présences sont synchronisés depuis l’écran principal.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : configureApiToken, icon: const Icon(Icons.key), label: const Text('Configurer le jeton API kDrive')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : forgetApiToken, icon: const Icon(Icons.logout), label: const Text('Oublier le jeton sur ce téléphone')),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: busy || !kdrive.isConnected ? null : synchronizeKdrive, icon: const Icon(Icons.sync), label: const Text('Synchroniser les deux fichiers kDrive')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : clearLocalRoster,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Vider la liste locale avant les tests'),
        ),
        const SizedBox(height: 12),
        const Text('Dépannage : import manuel des fichiers XLSX'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : loadMembers, icon: const Icon(Icons.people), label: const Text('Importer la base licenciés officielle')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: busy ? null : loadSchedule, icon: const Icon(Icons.calendar_month), label: const Text('Importer le suivi / planning officiel')),
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
