import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'services/nfc_service.dart';

const navy = Color(0xFF071A2B);
const blue = Color(0xFF18A8E0);
const cyan = Color(0xFF52D8FF);
const green = Color(0xFF36D399);
const orange = Color(0xFFFFB454);

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
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.dark),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: const Color(0xFF0D263B),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
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
  String memberSearch = '';
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
      if (v != null && v.isNotEmpty) map[m.id] = v;
    }
    if (mounted) setState(() => assignedUids.addAll(map));
  }

  Future<bool> _saveAssignment(Member m, String uid) async {
    final normalized = uid.trim().toUpperCase();
    final other = _memberForUid(normalized, excludeId: m.id);
    if (other != null) {
      _showInfo('Badge déjà utilisé', 'Ce badge est déjà associé à ${other.fullName}.');
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid_${m.id}', normalized);
    if (!mounted) return true;
    setState(() => assignedUids[m.id] = normalized);
    return true;
  }

  Member? _memberForUid(String uid, {String? excludeId}) {
    final wanted = uid.toUpperCase();
    for (final m in members) {
      if (m.id == excludeId) continue;
      final saved = assignedUids[m.id];
      if (saved != null && saved.toUpperCase() == wanted) return m;
    }
    // Demo fallback: keep the original demo UID working until it is reassigned.
    for (final m in members) {
      if (m.id == excludeId) continue;
      if (m.nfcUid.toUpperCase() == wanted && !assignedUids.containsKey(m.id)) return m;
    }
    return null;
  }

  Member? _memberFromIdentifier(String identifier, String method) {
    if (method == 'NFC') return _memberForUid(identifier);
    for (final m in members) {
      if (m.qrToken == identifier) return m;
    }
    return null;
  }

  Future<void> _startNfc({Member? associationTarget}) async {
    if (scanning) return;
    setState(() {
      scanning = true;
      if (associationTarget == null) result = null;
    });

    await nfc.scan(
      onRead: (read) async {
        if (!mounted) return;
        setState(() => scanning = false);
        if (associationTarget != null) {
          final saved = await _saveAssignment(associationTarget, read.uid);
          if (!mounted) return;
          if (saved) {
            _showInfo('Badge associé', 'Le badge ${read.uid} est maintenant associé à ${associationTarget.fullName}.');
          }
          return;
        }
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
    final member = _memberFromIdentifier(identifier, method);
    if (member == null) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.unknown, title: 'Badge inconnu', message: '$method non associé à un nageur.', uid: identifier));
      return;
    }

    if (!member.groups.contains(groupId)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.denied, title: 'Mauvais groupe', message: '${member.fullName} n’est pas inscrit sur ${_currentGroup.name}.', member: member, uid: identifier));
      return;
    }

    if (present.contains(member.id)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.duplicate, title: 'Déjà présent', message: '${member.fullName} a déjà été pointé pour cette séance.', member: member, uid: identifier));
      return;
    }

    setState(() {
      present.add(member.id);
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
    final pages = [_homePage(), _scannerPage(), _presencePage(), _membersPage(), _statsPage()];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Image.asset('assets/montchanin_natation_logo.png', fit: BoxFit.contain),
          ),
        ),
        title: const Text('ClubNage', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: () => _showInfo('Synchronisation', 'La synchronisation multi-téléphones sera branchée à l’étape serveur.'), icon: const Icon(Icons.cloud_done_outlined)),
        ],
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.nfc), label: 'Scanner'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Présences'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Nageurs'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Stats'),
        ],
      ),
    );
  }

  Widget _homePage() {
    final current = members.where((m) => m.groups.contains(groupId)).length;
    final rate = current == 0 ? 0 : (present.length / current * 100).round();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        const SizedBox(height: 8),
        Text('Bonjour 👋', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Pointage du club', style: TextStyle(color: Colors.white.withValues(alpha: .65))),
        const SizedBox(height: 18),
        _sessionHeader(),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _metric('Présents', '${present.length}/$current', Icons.check_circle, green)),
          const SizedBox(width: 10),
          Expanded(child: _metric('Taux', '$rate %', Icons.percent, cyan)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _metric('Badges', '${assignedUids.length}', Icons.nfc, blue)),
          const SizedBox(width: 10),
          Expanded(child: _metric('Groupes', '${groups.length}', Icons.groups, orange)),
        ]),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pointage rapide', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => setState(() => tab = 1), icon: const Icon(Icons.nfc), label: const Text('Lire un badge NFC'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54))),
          const SizedBox(height: 9),
          OutlinedButton.icon(onPressed: () => setState(() => tab = 1), icon: const Icon(Icons.qr_code_scanner), label: const Text('Utiliser le QR de secours'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50))),
        ]))),
        const SizedBox(height: 14),
        Card(child: ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFF123D56), child: Icon(Icons.cloud_done_outlined, color: cyan)), title: const Text('Mode hors connexion'), subtitle: const Text('Les associations et présences sont conservées localement.'))),
      ],
    );
  }

  Widget _sessionHeader() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Séance active', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 8),
    DropdownButtonFormField<String>(
      initialValue: groupId,
      decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.pool)),
      items: groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
      onChanged: (v) { if (v != null) setState(() { groupId = v; result = null; present.clear(); }); },
    ),
    const SizedBox(height: 8),
    Text(_currentGroup.schedule, style: const TextStyle(color: Colors.white60)),
  ])));

  Widget _metric(String title, String value, IconData icon, Color color) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Icon(icon, color: color, size: 30), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white60)), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))]))])));

  Widget _scannerPage() {
    return ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 24), children: [
      _sectionTitle('Lecture NFC', 'Pointage rapide par porte-clé NTAG213'),
      _sessionHeader(),
      const SizedBox(height: 14),
      if (result != null) _resultCard(result!) else _waitingCard(),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: scanning ? null : _startNfc, icon: const Icon(Icons.contactless), label: Text(scanning ? 'Approchez le badge…' : 'LIRE UN BADGE NFC'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: scanning ? null : _openQrScanner, icon: const Icon(Icons.qr_code_scanner), label: const Text('QR CODE DE SECOURS')),
    ]);
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: Colors.white60))]));

  Widget _waitingCard() => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16), child: Column(children: const [Icon(Icons.contactless, size: 70, color: cyan), SizedBox(height: 12), Text('Prêt pour le pointage', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)), SizedBox(height: 5), Text('Approchez un porte-clé NTAG213 du téléphone.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))])));

  Widget _resultCard(AttendanceResult r) {
    final color = r.ok ? green : r.duplicate ? orange : Colors.redAccent;
    return Card(child: Container(decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 6))), padding: const EdgeInsets.all(18), child: Column(children: [Icon(r.ok ? Icons.check_circle : r.duplicate ? Icons.info : Icons.cancel, color: color, size: 52), const SizedBox(height: 8), Text(r.title, style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(r.message, textAlign: TextAlign.center), if (r.uid != null) ...[const SizedBox(height: 8), Text(r.uid!, style: const TextStyle(color: Colors.white38, fontSize: 11))]])));
  }

  Widget _presencePage() {
    final current = members.where((m) => m.groups.contains(groupId)).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      _sectionTitle('Présences', '${_currentGroup.name} • ${present.length}/${current.length} présents'),
      ...current.map((m) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: CircleAvatar(backgroundColor: present.contains(m.id) ? const Color(0xFF164D42) : const Color(0xFF123D56), child: Text(m.firstName[0])), title: Text(m.fullName), subtitle: Text(assignedUids.containsKey(m.id) ? 'Badge associé' : 'Badge non associé'), trailing: Icon(present.contains(m.id) ? Icons.check_circle : Icons.radio_button_unchecked, color: present.contains(m.id) ? green : Colors.white38)) )),
    ]);
  }

  Widget _membersPage() {
    final filtered = members.where((m) => m.fullName.toLowerCase().contains(memberSearch.toLowerCase())).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 24), children: [
      _sectionTitle('Nageurs', '${members.length} membres • association des badges'),
      TextField(onChanged: (v) => setState(() => memberSearch = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un nageur', border: OutlineInputBorder())),
      const SizedBox(height: 12),
          ...filtered.map(
        (m) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(m.firstName[0]),
            ),
            title: Text(m.fullName),
            subtitle: Text(
              m.groups
                  .map((id) => groups.firstWhere((g) => g.id == id).name)
                  .join(' • '),
            ),
            trailing: Icon(
              assignedUids.containsKey(m.id) ? Icons.nfc : Icons.link_off,
              color: assignedUids.containsKey(m.id) ? green : Colors.white38,
            ),
            onTap: () => _showMember(m),
          ),
        ),
      ),
    ]);
  }

  Widget _statsPage() {
    final total = members.where((m) => m.groups.contains(groupId)).length;
    final pct = total == 0 ? 0 : (present.length / total * 100).round();
    return ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 24), children: [
      _sectionTitle('Statistiques', _currentGroup.name),
      _stat('Présents', '${present.length}/$total', Icons.check_circle, green),
      _stat('Taux de présence', '$pct %', Icons.percent, cyan),
      _stat('Badges associés', '${assignedUids.length}', Icons.nfc, blue),
      _stat('Groupes actifs', '${groups.length}', Icons.groups, orange),
      const SizedBox(height: 10),
      const Card(child: ListTile(leading: Icon(Icons.cloud_outlined), title: Text('Synchronisation future'), subtitle: Text('Architecture prête pour une base partagée et OneDrive/Excel.'))),
    ]);
  }

  Widget _stat(String title, String value, IconData icon, Color color) => Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(leading: Icon(icon, size: 34, color: color), title: Text(title), trailing: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))));

  void _showMember(Member m) {
    final controller = TextEditingController(text: assignedUids[m.id] ?? '');
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(m.fullName),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerLeft, child: Text(m.groups.map((id) => groups.firstWhere((g) => g.id == id).name).join('\n'))),
        const SizedBox(height: 15),
        TextField(controller: controller, decoration: const InputDecoration(labelText: 'UID NFC', hintText: 'Ex. 04:AB:12:34:56:78:90', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: scanning ? null : () async {
          Navigator.pop(context);
          await _startNfc(associationTarget: m);
        }, icon: const Icon(Icons.contactless), label: Text(scanning ? 'Lecture en cours…' : 'SCANNER ET ASSOCIER LE BADGE'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: () async { final uid = controller.text.trim().toUpperCase(); if (uid.isNotEmpty) await _saveAssignment(m, uid); if (!mounted) return; Navigator.pop(context); }, child: const Text('Enregistrer')),
      ],
    ));
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
