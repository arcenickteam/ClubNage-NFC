import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'services/nfc_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClubNageApp());
}

class ClubNageApp extends StatelessWidget {
  const ClubNageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClubNage NFC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF071A2B),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF18A8E0), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const ClubNageHome(),
    );
  }
}

class ClubNageHome extends StatefulWidget {
  const ClubNageHome({super.key});
  @override
  State<ClubNageHome> createState() => _ClubNageHomeState();
}

class _ClubNageHomeState extends State<ClubNageHome> {
  final NfcService nfc = NfcService();
  int tab = 0;
  String groupId = 'mercredi';
  AttendanceResult? result;
  bool scanning = false;
  final Set<String> present = {};
  final Map<String, String> assignedUids = {};

  final groups = const [
    TrainingGroup('mercredi', 'Groupe du mercredi', 'Mercredi • 17:00–18:00'),
    TrainingGroup('jaune', 'Groupe jaune', 'Samedi • 10:00–11:00'),
  ];

  final members = const [
    Member(id: 'M1001', firstName: 'Lucas', lastName: 'Martin', groups: ['mercredi'], nfcUid: '04:11:22:33:44:55:66', qrToken: 'CN:M1001'),
    Member(id: 'M1002', firstName: 'Emma', lastName: 'Dupont', groups: ['mercredi', 'jaune'], nfcUid: '04:22:33:44:55:66:77', qrToken: 'CN:M1002'),
    Member(id: 'M1003', firstName: 'Hugo', lastName: 'Bernard', groups: ['jaune'], nfcUid: '04:33:44:55:66:77:88', qrToken: 'CN:M1003'),
    Member(id: 'M1004', firstName: 'Léa', lastName: 'Robert', groups: ['mercredi'], nfcUid: '04:44:55:66:77:88:99', qrToken: 'CN:M1004'),
  ];

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, String>{};
    for (final m in members) {
      final v = prefs.getString('uid_${m.id}');
      if (v != null) map[m.id] = v;
    }
    if (mounted) setState(() => assignedUids.addAll(map));
  }

  Future<void> _saveAssignment(Member m, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid_${m.id}', uid);
    setState(() => assignedUids[m.id] = uid);
  }

  Member? _memberForUid(String uid) {
    for (final m in members) {
      if ((assignedUids[m.id] ?? m.nfcUid).toUpperCase() == uid.toUpperCase()) return m;
    }
    return null;
  }

  Future<void> _startNfc() async {
    setState(() { scanning = true; result = null; });
    await nfc.scan(
      onRead: (read) {
        if (!mounted) return;
        setState(() => scanning = false);
        _processIdentifier(read.uid, method: 'NFC');
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          scanning = false;
          result = AttendanceResult(status: AttendanceStatus.unknown, title: 'NFC', message: message);
        });
      },
    );
  }

  void _processIdentifier(String identifier, {required String method}) {
    Member? member;
    if (method == 'NFC') {
      member = _memberForUid(identifier);
    } else {
      member = members.where((m) => m.qrToken == identifier).firstOrNull;
    }

    if (member == null) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.unknown, title: 'Badge inconnu', message: '$method non associé à un nageur.', uid: identifier));
      return;
    }

    if (!member.groups.contains(groupId)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.denied, title: 'Mauvais groupe', message: '${member!.fullName} n’est pas inscrit sur ${_currentGroup.name}.', member: member, uid: identifier));
      return;
    }

    if (present.contains(member.id)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.duplicate, title: 'Déjà présent', message: '${member!.fullName} a déjà été pointé pour cette séance.', member: member, uid: identifier));
      return;
    }

    setState(() {
      present.add(member!.id);
      result = AttendanceResult(status: AttendanceStatus.present, title: 'Présence validée', message: '${member.fullName} est présent(e).', member: member, uid: identifier);
    });
  }

  TrainingGroup get _currentGroup => groups.firstWhere((g) => g.id == groupId);

  Future<void> _openQrScanner() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QrScannerPage(onCode: (code) {
      Navigator.of(context).pop();
      _processIdentifier(code, method: 'QR');
    })));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_scannerPage(), _presencePage(), _membersPage(), _statsPage()];
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Image.asset('assets/montchanin_natation_logo.png', fit: BoxFit.contain),
          ),
        ),
        title: const Text('ClubNage NFC', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: () => _showInfo('Synchronisation', 'La file de synchronisation multi-téléphones sera branchée à l’étape serveur.'), icon: const Icon(Icons.cloud_done_outlined))],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.nfc), label: 'Scanner'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: 'Présences'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Membres'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
        ],
      ),
    );
  }

  Widget _scannerPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        DropdownButtonFormField<String>(
          initialValue: groupId,
          decoration: const InputDecoration(labelText: 'Séance / groupe', border: OutlineInputBorder()),
          items: groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
          onChanged: (v) { if (v != null) setState(() { groupId = v; result = null; }); },
        ),
        const SizedBox(height: 10),
        Card(child: ListTile(leading: const Icon(Icons.schedule), title: Text(_currentGroup.name), subtitle: Text(_currentGroup.schedule), trailing: Text('${present.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)))),
        const SizedBox(height: 14),
        if (result != null) _resultCard(result!) else _waitingCard(),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: scanning ? null : _startNfc,
          icon: const Icon(Icons.contactless),
          label: Text(scanning ? 'Approchez le badge…' : 'LIRE UN BADGE NFC'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: scanning ? null : _openQrScanner, icon: const Icon(Icons.qr_code_scanner), label: const Text('QR CODE DE SECOURS')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => _processIdentifier('04:11:22:33:44:55:66', method: 'NFC'), icon: const Icon(Icons.science_outlined), label: const Text('Tester sans badge')),
      ],
    );
  }

  Widget _waitingCard() => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16), child: Column(children: const [Icon(Icons.contactless, size: 70, color: Color(0xFF18A8E0)), SizedBox(height: 12), Text('Prêt pour le pointage', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), SizedBox(height: 5), Text('Approchez un porte-clé NTAG213 du téléphone.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))])));

  Widget _resultCard(AttendanceResult r) {
    final color = r.ok ? Colors.green : r.duplicate ? Colors.orange : Colors.red;
    return Card(child: Container(decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 6))), padding: const EdgeInsets.all(18), child: Column(children: [Icon(r.ok ? Icons.check_circle : r.duplicate ? Icons.info : Icons.cancel, color: color, size: 52), const SizedBox(height: 8), Text(r.title, style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(r.message, textAlign: TextAlign.center)])));
  }

  Widget _presencePage() {
    final current = members.where((m) => m.groups.contains(groupId)).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      ListTile(title: Text(_currentGroup.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), subtitle: Text('${present.length}/${current.length} présents')),
      ...current.map((m) => Card(child: ListTile(leading: CircleAvatar(child: Text(m.firstName[0])), title: Text(m.fullName), subtitle: Text(m.groups.join(' • ')), trailing: Icon(present.contains(m.id) ? Icons.check_circle : Icons.radio_button_unchecked, color: present.contains(m.id) ? Colors.green : Colors.white38)))),
    ]);
  }

  Widget _membersPage() => ListView(padding: const EdgeInsets.all(12), children: [
    const ListTile(title: Text('Membres', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), subtitle: Text('Nageurs, groupes et association des badges')),
    ...members.map((m) => Card(child: ListTile(leading: const Icon(Icons.person), title: Text(m.fullName), subtitle: Text(m.groups.map((id) => groups.firstWhere((g) => g.id == id).name).join(', ')), trailing: Icon(assignedUids.containsKey(m.id) ? Icons.nfc : Icons.link_off, color: assignedUids.containsKey(m.id) ? Colors.green : Colors.white38), onTap: () => _showMember(m)))),
  ]);

  Widget _statsPage() {
    final total = members.where((m) => m.groups.contains(groupId)).length;
    final pct = total == 0 ? 0 : (present.length / total * 100).round();
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text(_currentGroup.name, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 15),
      _stat('Présents', '${present.length}/$total', Icons.check_circle),
      _stat('Taux de présence', '$pct %', Icons.percent),
      _stat('Groupes actifs', '${groups.length}', Icons.groups),
      _stat('Badges associés', '${assignedUids.length}', Icons.nfc),
    ]);
  }

  Widget _stat(String title, String value, IconData icon) => Card(child: ListTile(leading: Icon(icon, size: 34, color: const Color(0xFF18A8E0)), title: Text(title), trailing: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))));

void _showMember(Member m) {
  final controller = TextEditingController(
    text: assignedUids[m.id] ?? '',
  );

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(m.fullName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            m.groups
                .map((id) => groups.firstWhere((g) => g.id == id).name)
                .join('\n'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'UID NFC',
              hintText: 'Ex. 04:AB:12:34:56:78:90',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () async {
            final uid = controller.text.trim().toUpperCase();

            if (uid.isNotEmpty) {
              await _saveAssignment(m, uid);
            }

            if (!mounted) return;
            Navigator.pop(context);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}

  void _showInfo(String title, String message) => showDialog(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
}

class QrScannerPage extends StatefulWidget {
  final void Function(String code) onCode;
  const QrScannerPage({super.key, required this.onCode});
  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QR de secours')),
    body: MobileScanner(onDetect: (capture) { if (done) return; for (final barcode in capture.barcodes) { final value = barcode.rawValue; if (value != null && value.isNotEmpty) { done = true; widget.onCode(value); break; } } }),
  );
}
