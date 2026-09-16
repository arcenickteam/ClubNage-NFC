import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'services/nfc_service.dart';

const navy = Color(0xFF071A2B);
const panel = Color(0xFF0D263B);
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
  Widget build(BuildContext context) => MaterialApp(
        title: 'Club MN NFC',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: navy,
          colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.dark),
          useMaterial3: true,
          cardTheme: CardThemeData(color: panel, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const ClubNageHome(),
      );
}

class ClubNageHome extends StatefulWidget {
  const ClubNageHome({super.key});
  @override
  State<ClubNageHome> createState() => _ClubNageHomeState();
}

class _ClubNageHomeState extends State<ClubNageHome> {
  final NfcService nfc = NfcService();
  int page = 0;
  String groupId = 'mercredi';
  bool sessionOpen = true;
  bool scanning = false;
  AttendanceResult? result;
  String memberSearch = '';
  final Map<String, String> assignedUids = {};
  final List<AttendanceRecord> records = [];

  final groups = const [
    TrainingGroup('mercredi', 'Groupe du mercredi', 'Mercredi', '17:00', '18:00'),
    TrainingGroup('jaune', 'Groupe jaune', 'Samedi', '10:00', '11:00'),
    TrainingGroup('ecole', 'École de nage', 'Jeudi', '17:30', '18:30'),
  ];

  final members = const [
    Member(id: 'M1001', firstName: 'Lucas', lastName: 'Martin', groups: ['mercredi'], nfcUid: '04:11:22:33:44:55:66', qrToken: 'CN:M1001', email: 'lucas@example.fr'),
    Member(id: 'M1002', firstName: 'Emma', lastName: 'Dupont', groups: ['mercredi', 'jaune'], nfcUid: '04:22:33:44:55:66:77', qrToken: 'CN:M1002', phone: '06 00 00 00 02'),
    Member(id: 'M1003', firstName: 'Hugo', lastName: 'Bernard', groups: ['jaune'], nfcUid: '04:33:44:55:66:77:88', qrToken: 'CN:M1003', dossierStatus: 'À compléter'),
    Member(id: 'M1004', firstName: 'Léa', lastName: 'Robert', groups: ['mercredi', 'ecole'], nfcUid: '04:44:55:66:77:88:99', qrToken: 'CN:M1004'),
  ];

  static const pageNames = ['Accueil', 'Scanner', 'Licenciés', 'Groupes', 'Séances', 'Présences', 'Statistiques'];
  static const pageIcons = [Icons.home, Icons.nfc, Icons.people, Icons.groups, Icons.calendar_month, Icons.fact_check, Icons.bar_chart];

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = <String, String>{};
    for (final m in members) {
      final uid = prefs.getString('uid_${m.id}');
      if (uid != null && uid.isNotEmpty) loaded[m.id] = uid;
    }
    if (mounted) setState(() => assignedUids.addAll(loaded));
  }

  Member? _memberForUid(String uid, {String? excludeId}) {
    final wanted = uid.toUpperCase();
    for (final m in members) {
      if (m.id == excludeId) continue;
      final saved = assignedUids[m.id];
      if (saved != null && saved.toUpperCase() == wanted) return m;
    }
    for (final m in members) {
      if (m.id == excludeId) continue;
      if (!assignedUids.containsKey(m.id) && m.nfcUid.toUpperCase() == wanted) return m;
    }
    return null;
  }

  Future<String?> _saveAssignment(Member member, String uid) async {
    final normalized = uid.trim().toUpperCase();
    final other = _memberForUid(normalized, excludeId: member.id);
    if (other != null) return 'Ce badge est déjà associé à ${other.fullName}.';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid_${member.id}', normalized);
    if (mounted) setState(() => assignedUids[member.id] = normalized);
    return null;
  }

  TrainingGroup get currentGroup => groups.firstWhere((g) => g.id == groupId);
  List<Member> get expectedMembers => members.where((m) => m.groups.contains(groupId)).toList();
  List<AttendanceRecord> get currentRecords => records.where((r) => r.groupId == groupId).toList();
  int get presentCount => currentRecords.where((r) => r.status == AttendanceStatus.present || r.status == AttendanceStatus.late).map((r) => r.memberId).toSet().length;
  int get lateCount => currentRecords.where((r) => r.status == AttendanceStatus.late).length;

  void _go(int index) {
    setState(() => page = index);
    Navigator.of(context).maybePop();
  }

  Future<void> _startNfcPointage() async {
    if (scanning || !sessionOpen) return;
    setState(() { scanning = true; result = null; });
    await nfc.scan(
      onRead: (read) {
        if (!mounted) return;
        setState(() => scanning = false);
        _processIdentifier(read.uid, 'NFC');
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          scanning = false;
          result = AttendanceResult(status: AttendanceStatus.unknown, title: 'Lecture NFC interrompue', message: message);
        });
      },
    );
  }

  void _processIdentifier(String identifier, String method) {
    Member? member;
    if (method == 'NFC') {
      member = _memberForUid(identifier);
    } else {
      for (final m in members) {
        if (m.qrToken == identifier) { member = m; break; }
      }
    }
    if (member == null) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.unknown, title: 'Licencié inconnu', message: '$method non associé à un licencié.', uid: identifier));
      return;
    }
    if (!member.groups.contains(groupId)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.denied, title: 'Mauvais groupe', message: '${member!.fullName} n’est pas inscrit sur ${currentGroup.name}.', member: member, uid: identifier));
      return;
    }
    if (currentRecords.any((r) => r.memberId == member!.id)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.duplicate, title: 'Déjà pointé', message: '${member!.fullName} est déjà enregistré pour cette séance.', member: member, uid: identifier));
      return;
    }
    final now = DateTime.now();
    final parts = currentGroup.startTime.split(':');
    final start = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
    final status = now.isAfter(start.add(const Duration(minutes: 10))) ? AttendanceStatus.late : AttendanceStatus.present;
    setState(() {
      records.add(AttendanceRecord(memberId: member!.id, groupId: groupId, timestamp: now, status: status, method: method));
      result = AttendanceResult(status: status, title: status == AttendanceStatus.late ? 'Retard enregistré' : 'Présent', message: member!.fullName, member: member, uid: identifier);
    });
  }

  Future<void> _openQrScanner() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QrScannerPage(onCode: (code) {
      Navigator.of(context).pop();
      _processIdentifier(code, 'QR');
    })));
  }

  Future<void> _associate(Member member) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BadgeAssociationPage(nfc: nfc, member: member, onSave: (uid) => _saveAssignment(member, uid)),
    ));
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_homePage(), _scannerPage(), _membersPage(), _groupsPage(), _sessionsPage(), _presencePage(), _statsPage()];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: navy,
        surfaceTintColor: Colors.transparent,
        title: Text(pageNames[page], style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: Tooltip(message: 'Synchronisation kDrive', child: Icon(Icons.cloud_outlined, color: Colors.white.withValues(alpha: .75)))),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: page,
        onDestinationSelected: _go,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 12), child: Row(children: [
            Container(width: 58, height: 58, padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: Image.asset('assets/montchanin_natation_logo.png')),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Club MN NFC', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), Text('Montchanin Natation', style: TextStyle(color: Colors.white60))])),
          ])),
          const Divider(),
          for (var i = 0; i < pageNames.length; i++) NavigationDrawerDestination(icon: Icon(pageIcons[i]), label: Text(pageNames[i])),
          const Divider(),
          const ListTile(leading: Icon(Icons.cloud_sync_outlined), title: Text('kDrive'), subtitle: Text('Synchronisation sécurisée')),
        ],
      ),
      body: SafeArea(child: pages[page]),
      floatingActionButton: page == 1 ? FloatingActionButton.extended(onPressed: scanning ? null : _startNfcPointage, icon: const Icon(Icons.nfc), label: Text(scanning ? 'NFC ACTIF' : 'SCANNER NFC')) : null,
    );
  }

  Widget _homePage() {
    final expected = expectedMembers.length;
    final absent = (expected - presentCount).clamp(0, expected);
    return ListView(padding: const EdgeInsets.all(16), children: [
      _hero('Séance actuelle', currentGroup.name, currentGroup.schedule, sessionOpen ? 'OUVERTE' : 'FERMÉE'),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _metric('Attendus', '$expected', Icons.people_alt_outlined, cyan)), const SizedBox(width: 8), Expanded(child: _metric('Présents', '$presentCount', Icons.check_circle, green))]),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: _metric('Absents', '$absent', Icons.person_off_outlined, Colors.redAccent)), const SizedBox(width: 8), Expanded(child: _metric('Retards', '$lateCount', Icons.schedule, orange))]),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: () => setState(() => page = 1), icon: const Icon(Icons.nfc), label: const Text('SCANNER NFC'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58))),
      const SizedBox(height: 9),
      OutlinedButton.icon(onPressed: sessionOpen ? _openQrScanner : null, icon: const Icon(Icons.qr_code_scanner), label: const Text('SCANNER QR'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54))),
      const SizedBox(height: 16),
      _syncCard(),
    ]);
  }

  Widget _scannerPage() => ListView(padding: const EdgeInsets.all(16), children: [
    _groupSelector(),
    const SizedBox(height: 14),
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      Icon(scanning ? Icons.contactless : Icons.nfc, size: 72, color: scanning ? cyan : blue),
      const SizedBox(height: 10),
      Text(scanning ? 'EN ATTENTE DU BADGE NFC' : 'Scanner de présence', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
      const SizedBox(height: 7),
      Text(scanning ? 'Approchez le porte-clé du téléphone\n🔵 NFC actif' : 'Appuyez sur Scanner NFC ou utilisez le QR de secours.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
    ]))),
    if (result != null) ...[const SizedBox(height: 12), _resultCard(result!)],
    const SizedBox(height: 14),
    FilledButton.icon(onPressed: scanning || !sessionOpen ? null : _startNfcPointage, icon: const Icon(Icons.contactless), label: Text(scanning ? 'NFC ACTIF…' : 'SCANNER NFC'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58))),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: scanning || !sessionOpen ? null : _openQrScanner, icon: const Icon(Icons.qr_code_scanner), label: const Text('SCANNER QR')),
  ]);

  Widget _membersPage() {
    final filtered = members.where((m) => m.fullName.toLowerCase().contains(memberSearch.toLowerCase())).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(onChanged: (v) => setState(() => memberSearch = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un licencié')),
      const SizedBox(height: 12),
      ...filtered.map((m) => Card(child: ListTile(
        leading: CircleAvatar(child: Text(m.firstName.substring(0, 1))),
        title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_groupNames(m.groups)}\nDossier : ${m.dossierStatus}'),
        isThreeLine: true,
        trailing: Icon(assignedUids.containsKey(m.id) ? Icons.nfc : Icons.nfc_outlined, color: assignedUids.containsKey(m.id) ? green : orange),
        onTap: () => _memberSheet(m),
      ))),
    ]);
  }

  Widget _groupsPage() => ListView(padding: const EdgeInsets.all(16), children: [
    for (final g in groups) Card(child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.groups)),
      title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(g.schedule),
      trailing: Text('${members.where((m) => m.groups.contains(g.id)).length} licenciés'),
    )),
  ]);

  Widget _sessionsPage() => ListView(padding: const EdgeInsets.all(16), children: [
    _groupSelector(),
    const SizedBox(height: 12),
    _hero('Séance', currentGroup.name, currentGroup.schedule, sessionOpen ? 'OUVERTE' : 'FERMÉE'),
    const SizedBox(height: 12),
    FilledButton.icon(
      onPressed: () => setState(() { sessionOpen = !sessionOpen; result = null; }),
      icon: Icon(sessionOpen ? Icons.lock : Icons.lock_open),
      label: Text(sessionOpen ? 'FERMER LA SÉANCE' : 'OUVRIR LA SÉANCE'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
    ),
    const SizedBox(height: 18),
    const Text('Calendrier des groupes', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    for (final g in groups) ListTile(leading: const Icon(Icons.event), title: Text(g.name), subtitle: Text(g.schedule)),
  ]);

  Widget _presencePage() {
    final current = expectedMembers;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _groupSelector(),
      const SizedBox(height: 12),
      Text('${currentGroup.name} • $presentCount/${current.length} présents', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ...current.map((m) {
        AttendanceRecord? rec;
        for (final r in currentRecords) { if (r.memberId == m.id) { rec = r; break; } }
        final isLate = rec?.status == AttendanceStatus.late;
        final isPresent = rec != null;
        return Card(child: ListTile(
          leading: Icon(isPresent ? (isLate ? Icons.schedule : Icons.check_circle) : Icons.radio_button_unchecked, color: isPresent ? (isLate ? orange : green) : Colors.white38),
          title: Text(m.fullName),
          subtitle: Text(isPresent ? '${isLate ? 'Retard' : 'Présent'} • ${rec.method} • ${_time(rec.timestamp)}' : 'Absent / non pointé'),
        ));
      }),
      const SizedBox(height: 12),
      const Text('Historique', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      for (final r in records.reversed) ListTile(dense: true, leading: const Icon(Icons.history), title: Text(_memberById(r.memberId).fullName), subtitle: Text('${_groupById(r.groupId).name} • ${_time(r.timestamp)} • ${r.method}')),
    ]);
  }

  Widget _statsPage() {
    final expected = expectedMembers.length;
    final rate = expected == 0 ? 0 : (presentCount / expected * 100).round();
    return ListView(padding: const EdgeInsets.all(16), children: [
      _groupSelector(),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _metric('Présence', '$rate %', Icons.percent, cyan)), const SizedBox(width: 8), Expanded(child: _metric('Retards', '$lateCount', Icons.schedule, orange))]),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: _metric('Licenciés', '${members.length}', Icons.people, blue)), const SizedBox(width: 8), Expanded(child: _metric('Badges', '${assignedUids.length}', Icons.nfc, green))]),
      const SizedBox(height: 16),
      const Card(child: ListTile(leading: Icon(Icons.date_range), title: Text('Statistiques par période'), subtitle: Text('Structure prête pour alimentation par le journal de présences synchronisé.'))),
      const SizedBox(height: 8),
      _syncCard(),
    ]);
  }

  Widget _groupSelector() => DropdownButtonFormField<String>(
    initialValue: groupId,
    decoration: const InputDecoration(labelText: 'Groupe / séance'),
    items: groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
    onChanged: (v) { if (v != null) setState(() { groupId = v; result = null; }); },
  );

  Widget _hero(String eyebrow, String title, String subtitle, String status) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text(eyebrow.toUpperCase(), style: const TextStyle(color: cyan, fontWeight: FontWeight.w800))), Chip(label: Text(status))]),
    const SizedBox(height: 8), Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: Colors.white70)),
  ])));

  Widget _metric(String title, String value, IconData icon, Color color) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Icon(icon, color: color, size: 28), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white60)), Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))]))])));

  Widget _resultCard(AttendanceResult r) {
    final color = r.status == AttendanceStatus.present ? green : r.status == AttendanceStatus.late || r.status == AttendanceStatus.duplicate ? orange : Colors.redAccent;
    final icon = r.status == AttendanceStatus.present ? Icons.check_circle : r.status == AttendanceStatus.late ? Icons.schedule : r.status == AttendanceStatus.duplicate ? Icons.warning_amber : Icons.cancel;
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [Icon(icon, color: color, size: 48), const SizedBox(height: 6), Text(r.title, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(r.message, textAlign: TextAlign.center), if (r.uid != null) ...[const SizedBox(height: 8), Text('UID : ${r.uid}', style: const TextStyle(color: Colors.white60))]])));
  }

  Widget _syncCard() => const Card(child: ListTile(
    leading: Icon(Icons.cloud_sync_outlined, color: cyan),
    title: Text('kDrive • mode hors ligne'),
    subtitle: Text('Journal local immuable prêt pour synchronisation. OAuth Infomaniak à configurer avant connexion réelle.'),
    trailing: Icon(Icons.chevron_right),
  ));

  void _memberSheet(Member m) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(m.fullName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('Groupes 1 et 2 : ${_groupNames(m.groups)}'),
      Text('Statut du dossier : ${m.dossierStatus}'),
      Text('Badge NFC : ${assignedUids[m.id] ?? 'Non associé'}'),
      Text('QR : ${m.qrToken}'),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: () { Navigator.pop(context); _associate(m); }, icon: const Icon(Icons.nfc), label: const Text('SCANNER ET ASSOCIER LE BADGE'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54))),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), label: const Text('FERMER')),
    ]))));
  }

  String _groupNames(List<String> ids) => ids.map((id) => _groupById(id).name).join(' • ');
  TrainingGroup _groupById(String id) => groups.firstWhere((g) => g.id == id);
  Member _memberById(String id) => members.firstWhere((m) => m.id == id);
  String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class BadgeAssociationPage extends StatefulWidget {
  final NfcService nfc;
  final Member member;
  final Future<String?> Function(String uid) onSave;
  const BadgeAssociationPage({super.key, required this.nfc, required this.member, required this.onSave});
  @override
  State<BadgeAssociationPage> createState() => _BadgeAssociationPageState();
}

class _BadgeAssociationPageState extends State<BadgeAssociationPage> {
  String? uid;
  String? error;
  bool waiting = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() { uid = null; error = null; waiting = true; });
    await widget.nfc.scan(
      onRead: (read) { if (mounted) setState(() { uid = read.uid; waiting = false; }); },
      onError: (message) { if (mounted) setState(() { error = message; waiting = false; }); },
    );
  }

  Future<void> _save() async {
    if (uid == null || saving) return;
    setState(() => saving = true);
    final message = await widget.onSave(uid!);
    if (!mounted) return;
    if (message != null) {
      setState(() { error = message; saving = false; uid = null; });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    widget.nfc.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Associer un badge NFC')),
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.member.fullName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
      const SizedBox(height: 22),
      Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(uid != null ? Icons.check_circle : waiting ? Icons.contactless : Icons.error_outline, size: 88, color: uid != null ? green : waiting ? cyan : Colors.redAccent),
        const SizedBox(height: 18),
        Text(uid != null ? 'BADGE DÉTECTÉ' : waiting ? 'EN ATTENTE DU BADGE NFC' : 'LECTURE INTERROMPUE', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        if (waiting) const Text('Approchez le porte-clé du téléphone\n\n🔵 NFC actif', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: Colors.white70)),
        if (uid != null) ...[
          const Text('UID', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 4), SelectableText(uid!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18), Text('Associer à ${widget.member.fullName} ?', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
        if (error != null) Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
      ])),
      const SizedBox(height: 14),
      if (uid != null) FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.link), label: Text(saving ? 'ENREGISTREMENT…' : 'ASSOCIER LE BADGE'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58))),
      if (!waiting && uid == null) FilledButton.icon(onPressed: _start, icon: const Icon(Icons.refresh), label: const Text('RÉESSAYER'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58))),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ANNULER')),
    ])),
  );
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
    appBar: AppBar(title: const Text('Scanner QR')),
    body: MobileScanner(onDetect: (capture) {
      if (done) return;
      for (final barcode in capture.barcodes) {
        final value = barcode.rawValue;
        if (value != null && value.isNotEmpty) { done = true; widget.onCode(value); break; }
      }
    }),
  );
}
