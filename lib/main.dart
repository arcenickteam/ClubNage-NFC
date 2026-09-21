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
  String groupId = 'juniors';
  bool sessionOpen = false;
  bool scanning = false;
  AttendanceResult? result;
  String memberSearch = '';
  final Map<String, String> assignedUids = {};
  final List<AttendanceRecord> records = [];

  // Historique des séances réellement ouvertes dans l'application.
  final List<TrainingSession> sessions = [];

  // Séance actuellement utilisée pour le pointage NFC / QR.
  TrainingSession? activeSession;

  // Filtres des statistiques par période.
  String statsPeriod = '30j';
  String statsGroupId = 'all';
  DateTime? statsCustomStart;
  DateTime? statsCustomEnd;

  final groups = const [
    TrainingGroup('juniors', 'Compétition Juniors', 'Planning hebdomadaire', '18:45', '20:30'),
    TrainingGroup('benjamins', 'Compétition Benjamins', 'Planning hebdomadaire', '18:00', '19:30'),
    TrainingGroup('avenirs', 'Compétition Avenirs', 'Planning hebdomadaire', '18:00', '19:00'),
    TrainingGroup('jaune', 'Débutants – Jaune', 'Mercredi / Samedi', '11:00', '11:45'),
    TrainingGroup('rouge', 'Confirmés – Rouge', 'Mardi / Samedi', '18:15', '19:15'),
    TrainingGroup('violet', 'Confirmés – Violet', 'Mardi / Samedi', '18:15', '19:15'),
    TrainingGroup('bleu', 'Confirmés – Bleu', 'Mardi / Samedi', '18:15', '19:15'),
    TrainingGroup('vert', 'Confirmés – Vert', 'Mardi / Samedi', '18:15', '19:15'),
    TrainingGroup('adultes', 'Adultes 18 ans et +', 'Planning hebdomadaire', '12:00', '13:00'),
    TrainingGroup('aqua', 'Aquaforme / Aquafitness', 'Planning hebdomadaire', '10:00', '11:00'),
  ];

  final members = const [
    Member(id: 'M1001', firstName: 'Lucas', lastName: 'Martin', groups: ['juniors'], nfcUid: '04:11:22:33:44:55:66', qrToken: 'CN:M1001', email: 'lucas@example.fr'),
    Member(id: 'M1002', firstName: 'Emma', lastName: 'Dupont', groups: ['jaune', 'bleu'], nfcUid: '04:22:33:44:55:66:77', qrToken: 'CN:M1002', phone: '06 00 00 00 02'),
    Member(id: 'M1003', firstName: 'Hugo', lastName: 'Bernard', groups: ['rouge'], nfcUid: '04:33:44:55:66:77:88', qrToken: 'CN:M1003', dossierStatus: 'À compléter'),
    Member(id: 'M1004', firstName: 'Léa', lastName: 'Robert', groups: ['violet', 'vert'], nfcUid: '04:44:55:66:77:88:99', qrToken: 'CN:M1004'),
  ];



  static const _weeklySlots = <Map<String, Object>>[
    {'id':'jun-lun','label':'Compétition Juniors','groups':['juniors'],'weekday':1,'start':'18:45','end':'20:30'},
    {'id':'jun-mar','label':'Compétition Juniors','groups':['juniors'],'weekday':2,'start':'19:15','end':'20:45'},
    {'id':'jun-mer','label':'Compétition Juniors – préparation physique','groups':['juniors'],'weekday':3,'start':'15:00','end':'16:15'},
    {'id':'jun-jeu','label':'Compétition Juniors','groups':['juniors'],'weekday':4,'start':'18:30','end':'20:15'},
    {'id':'jun-ven','label':'Compétition Juniors','groups':['juniors'],'weekday':5,'start':'18:30','end':'20:00'},
    {'id':'jun-sam','label':'Compétition Juniors','groups':['juniors'],'weekday':6,'start':'12:00','end':'13:15'},
    {'id':'ben-lun','label':'Compétition Benjamins','groups':['benjamins'],'weekday':1,'start':'18:00','end':'19:30'},
    {'id':'ben-jeu','label':'Compétition Benjamins','groups':['benjamins'],'weekday':4,'start':'18:15','end':'19:30'},
    {'id':'ben-ven','label':'Compétition Benjamins','groups':['benjamins'],'weekday':5,'start':'18:30','end':'20:00'},
    {'id':'av-lun','label':'Compétition Avenirs','groups':['avenirs'],'weekday':1,'start':'18:00','end':'19:00'},
    {'id':'av-ven','label':'Compétition Avenirs','groups':['avenirs'],'weekday':5,'start':'17:30','end':'18:30'},
    {'id':'conf-mar','label':'Confirmés – Rouge / Violet / Bleu / Vert','groups':['rouge','violet','bleu','vert'],'weekday':2,'start':'18:15','end':'19:15'},
    {'id':'conf-sam','label':'Confirmés – Rouge / Violet / Bleu / Vert','groups':['rouge','violet','bleu','vert'],'weekday':6,'start':'11:00','end':'12:00'},
    {'id':'jaune-mer','label':'Débutants – Jaune','groups':['jaune'],'weekday':3,'start':'11:00','end':'11:45'},
    {'id':'jaune-sam1','label':'Débutants – Jaune (créneau 1)','groups':['jaune'],'weekday':6,'start':'09:30','end':'10:15'},
    {'id':'jaune-sam2','label':'Débutants – Jaune (créneau 2)','groups':['jaune'],'weekday':6,'start':'10:15','end':'11:00'},
    {'id':'adult-lun-midi','label':'Adultes 18 ans et +','groups':['adultes'],'weekday':1,'start':'12:00','end':'13:00'},
    {'id':'adult-lun-soir','label':'Adultes 18 ans et +','groups':['adultes'],'weekday':1,'start':'19:30','end':'20:30'},
    {'id':'adult-jeu-midi','label':'Adultes 18 ans et +','groups':['adultes'],'weekday':4,'start':'12:00','end':'13:00'},
    {'id':'adult-jeu-soir','label':'Adultes 18 ans et +','groups':['adultes'],'weekday':4,'start':'19:30','end':'20:30'},
    {'id':'aqua-mer-10','label':'Aquaforme','groups':['aqua'],'weekday':3,'start':'10:00','end':'11:00'},
    {'id':'aqua-mer-1230','label':'Aquaforme','groups':['aqua'],'weekday':3,'start':'12:30','end':'13:30'},
    {'id':'aqua-ven','label':'Aquaforme','groups':['aqua'],'weekday':5,'start':'20:00','end':'21:00'},
    {'id':'aqua-sam','label':'Aquafitness','groups':['aqua'],'weekday':6,'start':'09:00','end':'09:30'},
  ];

  String _dayName(int w) => const ['', 'Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'][w];
  DateTime _at(DateTime d,String t){final p=t.split(':');return DateTime(d.year,d.month,d.day,int.parse(p[0]),int.parse(p[1]));}
  List<Map<String,Object>> get _todaySlots => _weeklySlots.where((s)=>s['weekday']==DateTime.now().weekday).toList();
  List<String> _slotGroups(Map<String,Object> s)=>List<String>.from(s['groups'] as List);
  bool _slotCanOpen(Map<String,Object> s){final n=DateTime.now(),st=_at(n,s['start'] as String),en=_at(n,s['end'] as String);return !n.isBefore(st.subtract(const Duration(minutes:30)))&&n.isBefore(en.add(const Duration(hours:4)));}
  List<Member> _membersForGroups(List<String> ids)=>members.where((m)=>m.groups.any(ids.contains)).toList();

  void _openScheduledSession(Map<String,Object> slot){
    if(sessionOpen){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Une séance est déjà ouverte.')));return;}
    if(!_slotCanOpen(slot)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ouverture possible 30 minutes avant le début.')));return;}
    final n=DateTime.now(),ids=_slotGroups(slot),exp=_membersForGroups(ids);
    final s=TrainingSession(id:'${slot['id']}-${n.millisecondsSinceEpoch}',groupId:ids.first,date:DateTime(n.year,n.month,n.day),openedAt:n,expectedMemberIds:List.unmodifiable(exp.map((m)=>m.id)),label:slot['label'] as String,startTime:_at(n,slot['start'] as String),endTime:_at(n,slot['end'] as String),eligibleGroupIds:List.unmodifiable(ids));
    setState((){sessions.add(s);activeSession=s;groupId=ids.first;sessionOpen=true;result=null;});
  }

  Future<void> _openManualSessionDialog() async{
    if(sessionOpen){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Fermez d’abord la séance active.')));return;}
    String type='Entraînement exceptionnel',selectedGroup=groupId;
    final ok=await showDialog<bool>(context:context,builder:(dc)=>StatefulBuilder(builder:(context,setLocal)=>AlertDialog(
      title:const Text('Ouvrir une séance manuelle'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(initialValue:type,decoration:const InputDecoration(labelText:'Type'),items:const [
          DropdownMenuItem(value:'Compétition',child:Text('Compétition')),
          DropdownMenuItem(value:'Entraînement exceptionnel',child:Text('Entraînement exceptionnel')),
          DropdownMenuItem(value:'Stage',child:Text('Stage')),
          DropdownMenuItem(value:'Test badge',child:Text('Test badge')),
        ],onChanged:(v){if(v!=null)setLocal(()=>type=v);}),
        const SizedBox(height:12),
        DropdownButtonFormField<String>(initialValue:selectedGroup,decoration:const InputDecoration(labelText:'Groupe'),items:groups.map((g)=>DropdownMenuItem(value:g.id,child:Text(g.name))).toList(),onChanged:(v){if(v!=null)setLocal(()=>selectedGroup=v);}),
        const SizedBox(height:10),
        const Text('Démarrage immédiat. Fermeture manuelle ou sécurité automatique après 4 h.',style:TextStyle(fontSize:12,color:Colors.white60)),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(dc,false),child:const Text('ANNULER')),FilledButton(onPressed:()=>Navigator.pop(dc,true),child:const Text('OUVRIR'))],
    )));
    if(ok!=true||!mounted)return;
    final n=DateTime.now(),exp=members.where((m)=>m.groups.contains(selectedGroup)).toList();
    final s=TrainingSession(id:'manual-${n.millisecondsSinceEpoch}',groupId:selectedGroup,date:DateTime(n.year,n.month,n.day),openedAt:n,expectedMemberIds:List.unmodifiable(exp.map((m)=>m.id)),label:type,startTime:n,endTime:n,eligibleGroupIds:[selectedGroup],manualType:type,excludeFromStats:type=='Test badge');
    setState((){sessions.add(s);activeSession=s;groupId=selectedGroup;sessionOpen=true;result=null;});
  }

  void _autoCloseExpiredSessionIfNeeded(){
    final s=activeSession;if(s==null||!s.isOpen||s.endTime==null)return;
    if(DateTime.now().isBefore(s.endTime!.add(const Duration(hours:4))))return;
    final i=sessions.indexWhere((x)=>x.id==s.id),closed=s.close(DateTime.now());
    setState((){if(i>=0)sessions[i]=closed;activeSession=null;sessionOpen=false;result=null;});
  }
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
  List<Member> get expectedMembers {
    final s=activeSession;
    if(s!=null&&s.isOpen)return members.where((m)=>s.expectedMemberIds.contains(m.id)).toList();
    return members.where((m)=>m.groups.contains(groupId)).toList();
  }
  List<AttendanceRecord> get currentRecords {
    final session = activeSession;
    if (session == null || session.groupId != groupId) return [];
    return records.where((r) => r.sessionId == session.id).toList();
  }
  int get presentCount => currentRecords.where((r) => r.status == AttendanceStatus.present || r.status == AttendanceStatus.late).map((r) => r.memberId).toSet().length;
  int get lateCount => currentRecords.where((r) => r.status == AttendanceStatus.late).length;

  void _openTrainingSession() { _openManualSessionDialog(); }

  Future<void> _closeTrainingSession() async {
    final session = activeSession;

    if (session != null && session.isOpen) {
      final closed = session.close(DateTime.now());
      final index = sessions.indexWhere((s) => s.id == session.id);

      setState(() {
        if (index >= 0) {
          sessions[index] = closed;
        }
        activeSession = null;
        sessionOpen = false;
        result = null;
      });
    } else {
      setState(() {
        activeSession = null;
        sessionOpen = false;
        result = null;
      });
    }

  }

  Future<void> _go(int index) async {
    // Le Scanner NFC est un mode actif.
    // Lorsque l'on quitte cet écran, on libère proprement Reader Mode.
    if (page == 1 && index != 1 && nfc.isRunning) {
      await nfc.stop();
      if (mounted) {
        setState(() => scanning = false);
      }
    }

    if (!mounted) return;
    setState(() => page = index);
  }

  Future<void> _startNfcPointage() async {
    if (!sessionOpen) return;

    // Si le lecteur Android est déjà actif, on ne démarre pas
    // une deuxième session NFC.
    if (nfc.isRunning) {
      if (mounted) {
        setState(() {
          scanning = true;
          result = null;
        });
      }
      return;
    }

    setState(() {
      scanning = true;
      result = null;
    });

    await nfc.scan(
      onRead: (read) {
        if (!mounted) return;

        // IMPORTANT V6 :
        // scanning reste à true.
        // Le Reader Mode Android continue donc d'attendre
        // immédiatement le badge suivant.
        _processIdentifier(read.uid, 'NFC');
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          scanning = false;
          result = AttendanceResult(
            status: AttendanceStatus.unknown,
            title: 'Lecture NFC interrompue',
            message: message,
          );
        });
      },
    );
  }

  void _processIdentifier(String identifier, String method) {
    _autoCloseExpiredSessionIfNeeded();
    if (!sessionOpen ||
        activeSession == null ||
        activeSession!.groupId != groupId ||
        !activeSession!.isOpen) {
      setState(() {
        result = const AttendanceResult(
          status: AttendanceStatus.denied,
          title: 'Séance fermée',
          message: 'Ouvrez une séance avant de commencer le pointage.',
        );
      });
      return;
    }

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
    final eligible=activeSession!.eligibleGroupIds.isEmpty?[groupId]:activeSession!.eligibleGroupIds;
    if (!member.groups.any(eligible.contains)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.denied, title: 'Mauvais groupe', message: '${member!.fullName} n’est pas inscrit à cette séance.', member: member, uid: identifier));
      return;
    }
    if (currentRecords.any((r) => r.memberId == member!.id)) {
      setState(() => result = AttendanceResult(status: AttendanceStatus.duplicate, title: 'Déjà pointé', message: '${member!.fullName} est déjà enregistré pour cette séance.', member: member, uid: identifier));
      return;
    }
    final now = DateTime.now();
    final start=activeSession!.startTime??now;
    final status=now.isAfter(start.add(const Duration(minutes:15)))?AttendanceStatus.late:AttendanceStatus.present;
    setState(() {
      records.add(AttendanceRecord(
        memberId: member!.id,
        groupId: groupId,
        sessionId: activeSession!.id,
        timestamp: now,
        status: status,
        method: method,
      ));
      result = AttendanceResult(status: status, title: status == AttendanceStatus.late ? 'Retard enregistré' : 'Présent', message: member.fullName, member: member, uid: identifier);
    });
  }

  Future<void> _openQrScanner() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QrScannerPage(onCode: (code) {
      Navigator.of(context).pop();
      _processIdentifier(code, 'QR');
    })));
  }

  Future<void> _associate(Member member) async {
    // L'association d'un badge doit avoir sa propre session NFC.
    // On arrête donc d'abord un éventuel pointage encore actif.
    if (nfc.isRunning) {
      await nfc.stop();
    }

    if (!mounted) return;

    setState(() {
      scanning = false;
      result = null;
    });

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BadgeAssociationPage(
          nfc: nfc,
          member: member,
          onSave: (uid) => _saveAssignment(member, uid),
        ),
      ),
    );

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _homePage(),
      _scannerPage(),
      _membersPage(),
      _groupsPage(),
      _sessionsPage(),
      _presencePage(),
      _statsPage(),
    ];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: navy,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset('assets/montchanin_natation_logo.png'),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MONTCHANIN NATATION',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .3,
                    ),
                  ),
                  Text(
                    _v6PageTitle(),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Icon(
              Icons.cloud_done_outlined,
              color: Colors.white.withValues(alpha: .72),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 92),
          child: pages[page],
        ),
      ),
      bottomNavigationBar: _v6BottomNavigation(),
    );
  }

  String _v6PageTitle() {
    switch (page) {
      case 0:
        return 'Tableau de bord';
      case 1:
        return 'Pointage NFC / QR';
      case 2:
        return 'Licenciés';
      case 3:
        return 'Groupes';
      case 4:
        return 'Séances';
      case 5:
        return 'Présences';
      case 6:
        return 'Statistiques';
      default:
        return 'Club MN NFC';
    }
  }

  Widget _v6BottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: panel,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 78,
          child: Row(
            children: [
              _v6NavItem(
                icon: Icons.home_rounded,
                label: 'Accueil',
                targetPage: 0,
              ),
              _v6NavItem(
                icon: Icons.badge_outlined,
                label: 'Licenciés',
                targetPage: 2,
              ),

              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -17),
                  child: GestureDetector(
                    onTap: () => _go(1),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: blue,
                            border: Border.all(
                              color: navy,
                              width: 5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: blue.withValues(alpha: .38),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.contactless_rounded,
                            color: Colors.white,
                            size: 31,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Scanner',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: page == 1 ? cyan : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              _v6NavItem(
                icon: Icons.fact_check_outlined,
                label: 'Présences',
                targetPage: 5,
              ),
              _v6NavItem(
                icon: Icons.more_horiz_rounded,
                label: 'Plus',
                targetPage: -1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _v6NavItem({
    required IconData icon,
    required String label,
    required int targetPage,
  }) {
    final selected = targetPage >= 0 && page == targetPage;

    return Expanded(
      child: InkWell(
        onTap: () {
          if (targetPage == -1) {
            _showMoreMenu();
          } else {
            _go(targetPage);
          }
        },
        child: SizedBox(
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 25,
                color: selected ? cyan : Colors.white54,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Text(
                    'Administration',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              _moreTile(
                sheetContext,
                Icons.groups_outlined,
                'Groupes',
                'Gestion des groupes de nage',
                3,
              ),
              _moreTile(
                sheetContext,
                Icons.calendar_month_outlined,
                'Séances',
                'Planning et ouverture des séances',
                4,
              ),
              _moreTile(
                sheetContext,
                Icons.bar_chart_rounded,
                'Statistiques',
                'Suivi des présences et retards',
                6,
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.cloud_sync_outlined),
                ),
                title: const Text(
                  'Synchronisation',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('kDrive • mode hors ligne'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Connexion kDrive à configurer avec les accès Infomaniak.',
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.settings_outlined),
                ),
                title: const Text(
                  'Paramètres',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Configuration de Club MN NFC'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Les paramètres avancés seront ajoutés dans la V6.',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreTile(
    BuildContext sheetContext,
    IconData icon,
    String title,
    String subtitle,
    int targetPage,
  ) {
    return ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.pop(sheetContext);
        _go(targetPage);
      },
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

  Widget _scannerPage() {
    final expected = expectedMembers.length;
    final absent = (expected - presentCount).clamp(0, expected);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        // Sélection de la séance
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
          child: _groupSelector(),
        ),

        const SizedBox(height: 14),

        // État de la séance
        Row(
          children: [
            Expanded(
              child: _scannerMiniMetric(
                'Attendus',
                '$expected',
                Icons.groups_outlined,
                cyan,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _scannerMiniMetric(
                'Présents',
                '$presentCount',
                Icons.check_circle_outline,
                green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _scannerMiniMetric(
                'Restants',
                '$absent',
                Icons.hourglass_bottom_rounded,
                orange,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Résultat du dernier badge - visible immédiatement
        if (result != null) ...[
          _v6ScanResult(result!),
          const SizedBox(height: 16),
        ],

        // Zone principale NFC
        Container(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                panel,
                scanning
                    ? blue.withValues(alpha: .22)
                    : const Color(0xFF102C43),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: scanning
                  ? cyan.withValues(alpha: .45)
                  : Colors.white.withValues(alpha: .08),
            ),
            boxShadow: scanning
                ? [
                    BoxShadow(
                      color: blue.withValues(alpha: .17),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scanning
                      ? blue.withValues(alpha: .18)
                      : Colors.white.withValues(alpha: .05),
                  border: Border.all(
                    color: scanning
                        ? cyan
                        : Colors.white.withValues(alpha: .15),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.contactless_rounded,
                  size: 64,
                  color: scanning ? cyan : Colors.white70,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                scanning
                    ? 'LECTURE NFC ACTIVE'
                    : 'POINTAGE DES LICENCIÉS',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                scanning
                    ? 'Approchez un porte-clé NFC du téléphone.\n'
                      'Le lecteur reste actif pour le licencié suivant.'
                    : sessionOpen
                        ? 'Démarrez le lecteur NFC pour enregistrer les présences.'
                        : 'La séance est actuellement fermée.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scanning
                      ? green.withValues(alpha: .14)
                      : Colors.white.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scanning ? green : Colors.white38,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      scanning
                          ? 'NFC ACTIF • EN ATTENTE'
                          : 'NFC EN VEILLE',
                      style: TextStyle(
                        color: scanning ? green : Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              if (!scanning)
                FilledButton.icon(
                  onPressed:
                      sessionOpen ? _startNfcPointage : null,
                  icon: const Icon(Icons.contactless_rounded),
                  label: const Text('DÉMARRER LE POINTAGE NFC'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _stopNfcPointage,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('ARRÊTER LE POINTAGE NFC'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: Colors.white,
                  ),
                ),

              const SizedBox(height: 9),

              OutlinedButton.icon(
                onPressed:
                    sessionOpen && !scanning ? _openQrScanner : null,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('UTILISER LE QR DE SECOURS'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),


        const SizedBox(height: 18),

        Row(
          children: [
            const Expanded(
              child: Text(
                'Présences enregistrées',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$presentCount / $expected',
              style: const TextStyle(
                color: cyan,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        if (currentRecords.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white54),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Aucun licencié pointé pour le moment.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
          )
        else
          ...currentRecords.reversed.take(5).map((r) {
            final m = _memberById(r.memberId);
            final late = r.status == AttendanceStatus.late;

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: (late ? orange : green)
                      .withValues(alpha: .15),
                  child: Icon(
                    late
                        ? Icons.schedule_rounded
                        : Icons.check_rounded,
                    color: late ? orange : green,
                  ),
                ),
                title: Text(
                  m.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${late ? 'Retard' : 'Présent'}'
                  ' • ${_time(r.timestamp)}'
                  ' • ${r.method}',
                ),
                trailing: Icon(
                  r.method == 'NFC'
                      ? Icons.nfc_rounded
                      : Icons.qr_code_rounded,
                  color: Colors.white54,
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _scannerMiniMetric(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _v6ScanResult(AttendanceResult r) {
    lateOrDuplicate() =>
        r.status == AttendanceStatus.late ||
        r.status == AttendanceStatus.duplicate;

    final Color color = r.status == AttendanceStatus.present
        ? green
        : lateOrDuplicate()
            ? orange
            : Colors.redAccent;

    final IconData icon = r.status == AttendanceStatus.present
        ? Icons.check_circle_rounded
        : r.status == AttendanceStatus.late
            ? Icons.schedule_rounded
            : r.status == AttendanceStatus.duplicate
                ? Icons.warning_amber_rounded
                : Icons.cancel_rounded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: color.withValues(alpha: .45),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r.message,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (r.member != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    currentGroup.name,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (scanning)
            const Icon(
              Icons.contactless_rounded,
              color: cyan,
            ),
        ],
      ),
    );
  }

  Future<void> _stopNfcPointage() async {
    await nfc.stop();

    if (!mounted) return;

    setState(() {
      scanning = false;
    });
  }

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

  Widget _sessionsPage() {
    final today=_todaySlots;
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Séances du jour',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),
      const SizedBox(height:4),
      const Text('Ouverture H−30 min • retard H+15 min • fermeture de sécurité fin+4 h',style:TextStyle(color:Colors.white60)),
      const SizedBox(height:14),
      if(sessionOpen&&activeSession!=null) Card(child:ListTile(leading:const Icon(Icons.lock_open_rounded,color:green),title:Text(activeSession!.label??currentGroup.name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('OUVERTE • ${_time(activeSession!.openedAt)}'),trailing:FilledButton(onPressed:_closeTrainingSession,child:const Text('FERMER')))),
      if(!sessionOpen)...today.map((slot){final can=_slotCanOpen(slot);return Card(child:ListTile(leading:Icon(can?Icons.play_circle_fill_rounded:Icons.schedule_rounded,color:can?green:Colors.white38),title:Text(slot['label'] as String,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${_dayName(slot['weekday'] as int)} • ${slot['start']}–${slot['end']}'),trailing:FilledButton(onPressed:can?()=>_openScheduledSession(slot):null,child:const Text('OUVRIR'))));}),
      const SizedBox(height:14),
      OutlinedButton.icon(onPressed:sessionOpen?null:_openManualSessionDialog,icon:const Icon(Icons.add_circle_outline_rounded),label:const Text('OUVRIR UNE SÉANCE MANUELLE'),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(56))),
      const SizedBox(height:18),
      const Text('Planning hebdomadaire',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      ..._weeklySlots.map((slot)=>ListTile(dense:true,leading:const Icon(Icons.event_outlined),title:Text(slot['label'] as String),subtitle:Text('${_dayName(slot['weekday'] as int)} • ${slot['start']}–${slot['end']}'))),
    ]);
  }

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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime get _statsStartDate {
    final today = _dateOnly(DateTime.now());

    switch (statsPeriod) {
      case 'today':
        return today;
      case '7j':
        return today.subtract(const Duration(days: 6));
      case '30j':
        return today.subtract(const Duration(days: 29));
      case 'season':
        return today.month >= 9
            ? DateTime(today.year, 9, 1)
            : DateTime(today.year - 1, 9, 1);
      case 'custom':
        return _dateOnly(statsCustomStart ?? today);
      default:
        return today.subtract(const Duration(days: 29));
    }
  }

  DateTime get _statsEndDate {
    final today = _dateOnly(DateTime.now());

    if (statsPeriod == 'custom') {
      return _dateOnly(statsCustomEnd ?? today);
    }

    return today;
  }

  List<TrainingSession> get _filteredStatsSessions {
    final start = _statsStartDate;
    final endExclusive = _statsEndDate.add(const Duration(days: 1));

    final filtered = sessions.where((session) {
      final date = _dateOnly(session.date);

      final inPeriod =
          !date.isBefore(start) && date.isBefore(endExclusive);

      final inGroup =
          statsGroupId == 'all' || session.groupId == statsGroupId;

      // Une absence n'est définitive qu'une fois la séance clôturée.
      return inPeriod && inGroup && !session.isOpen && !session.excludeFromStats;
    }).toList();

    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  List<AttendanceRecord> _recordsForSession(TrainingSession session) =>
      records.where((r) => r.sessionId == session.id).toList();

  Set<String> _presentMemberIdsForSession(TrainingSession session) =>
      _recordsForSession(session)
          .where((r) =>
              r.status == AttendanceStatus.present ||
              r.status == AttendanceStatus.late)
          .map((r) => r.memberId)
          .toSet();

  int get _statsExpectedCount =>
      _filteredStatsSessions.fold(
        0,
        (sum, session) => sum + session.expectedMemberIds.length,
      );

  int get _statsPresentCount =>
      _filteredStatsSessions.fold(
        0,
        (sum, session) =>
            sum + _presentMemberIdsForSession(session).length,
      );

  int get _statsAbsentCount {
    final absent = _statsExpectedCount - _statsPresentCount;
    return absent < 0 ? 0 : absent;
  }

  int get _statsLateCount =>
      _filteredStatsSessions.fold(
        0,
        (sum, session) =>
            sum +
            _recordsForSession(session)
                .where((r) => r.status == AttendanceStatus.late)
                .map((r) => r.memberId)
                .toSet()
                .length,
      );

  int get _statsAttendanceRate {
    final expected = _statsExpectedCount;
    if (expected == 0) return 0;
    return (_statsPresentCount / expected * 100).round();
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  Future<void> _pickStatsCustomPeriod() async {
    final today = _dateOnly(DateTime.now());

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3, 1, 1),
      lastDate: DateTime(today.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: statsCustomStart ?? today.subtract(const Duration(days: 29)),
        end: statsCustomEnd ?? today,
      ),
      helpText: 'PÉRIODE DES STATISTIQUES',
      cancelText: 'ANNULER',
      confirmText: 'VALIDER',
    );

    if (picked == null || !mounted) return;

    setState(() {
      statsCustomStart = _dateOnly(picked.start);
      statsCustomEnd = _dateOnly(picked.end);
      statsPeriod = 'custom';
    });
  }

  Widget _statsPeriodButton(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: statsPeriod == value,
      onSelected: (_) {
        if (value == 'custom') {
          _pickStatsCustomPeriod();
        } else {
          setState(() => statsPeriod = value);
        }
      },
    );
  }

  Widget _memberStatsCard(
    Member member,
    List<TrainingSession> filteredSessions,
  ) {
    final memberSessions = filteredSessions
        .where((s) => s.expectedMemberIds.contains(member.id))
        .toList();

    final expected = memberSessions.length;

    int present = 0;
    int late = 0;

    for (final session in memberSessions) {
      final memberRecords = _recordsForSession(session)
          .where((r) => r.memberId == member.id)
          .toList();

      final wasPresent = memberRecords.any(
        (r) =>
            r.status == AttendanceStatus.present ||
            r.status == AttendanceStatus.late,
      );

      final wasLate = memberRecords.any(
        (r) => r.status == AttendanceStatus.late,
      );

      if (wasPresent) present++;
      if (wasLate) late++;
    }

    final absent = expected - present;
    final rate = expected == 0
        ? 0
        : (present / expected * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    member.firstName.isNotEmpty
                        ? member.firstName[0].toUpperCase()
                        : '?',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.fullName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '$expected séance${expected > 1 ? 's' : ''} prévue${expected > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$rate %',
                  style: TextStyle(
                    color: rate >= 80
                        ? green
                        : rate >= 60
                            ? orange
                            : Colors.redAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _scannerMiniMetric(
                    'Présences',
                    '$present',
                    Icons.check_circle_rounded,
                    green,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _scannerMiniMetric(
                    'Absences',
                    '$absent',
                    Icons.cancel_rounded,
                    Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _scannerMiniMetric(
                    'Retards',
                    '$late',
                    Icons.schedule_rounded,
                    orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsPage() {
    final filteredSessions = _filteredStatsSessions;
    final sessionCount = filteredSessions.length;

    final start = _statsStartDate;
    final end = _statsEndDate;

    final periodLabel = _shortDate(start) == _shortDate(end)
        ? _shortDate(start)
        : '${_shortDate(start)} → ${_shortDate(end)}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Statistiques par période',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Analyse de l’assiduité des licenciés.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 18),

        const Text(
          'Période',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cyan,
          ),
        ),
        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statsPeriodButton('today', 'Aujourd’hui'),
            _statsPeriodButton('7j', '7 jours'),
            _statsPeriodButton('30j', '30 jours'),
            _statsPeriodButton('season', 'Saison'),
            _statsPeriodButton('custom', 'Personnalisée'),
          ],
        ),

        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          key: ValueKey('stats-$statsGroupId'),
          initialValue: statsGroupId,
          decoration: const InputDecoration(
            labelText: 'Groupe',
            prefixIcon: Icon(Icons.groups_outlined),
          ),
          items: [
            const DropdownMenuItem(
              value: 'all',
              child: Text('Tous les groupes'),
            ),
            ...groups.map(
              (g) => DropdownMenuItem(
                value: g.id,
                child: Text(g.name),
              ),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => statsGroupId = value);
          },
        ),

        const SizedBox(height: 12),

        Card(
          child: ListTile(
            leading: const Icon(
              Icons.date_range_rounded,
              color: cyan,
            ),
            title: Text(
              periodLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              statsGroupId == 'all'
                  ? 'Tous les groupes'
                  : groups
                      .firstWhere((g) => g.id == statsGroupId)
                      .name,
            ),
            trailing: statsPeriod == 'custom'
                ? IconButton(
                    onPressed: _pickStatsCustomPeriod,
                    icon: const Icon(
                      Icons.edit_calendar_outlined,
                    ),
                  )
                : null,
          ),
        ),

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _metric(
                'Séances',
                '$sessionCount',
                Icons.event_available_rounded,
                blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metric(
                'Taux de présence',
                '$_statsAttendanceRate %',
                Icons.percent_rounded,
                cyan,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _metric(
                'Présences',
                '$_statsPresentCount',
                Icons.check_circle_rounded,
                green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metric(
                'Absences',
                '$_statsAbsentCount',
                Icons.cancel_rounded,
                Colors.redAccent,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _metric(
                'Retards',
                '$_statsLateCount',
                Icons.schedule_rounded,
                orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metric(
                'Attendus',
                '$_statsExpectedCount',
                Icons.people_alt_rounded,
                blue,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        if (filteredSessions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.query_stats_rounded,
                    size: 42,
                    color: Colors.white38,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Aucune séance sur cette période',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Les statistiques seront alimentées par les séances enregistrées.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          const Text(
            'Séances de la période',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),

          for (final session in filteredSessions)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.pool_rounded,
                  color: cyan,
                ),
                title: Text(
                  groups
                      .firstWhere((g) => g.id == session.groupId)
                      .name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${_shortDate(session.date)} • '
                  '${_presentMemberIdsForSession(session).length}'
                  '/${session.expectedMemberIds.length} présents',
                ),
                trailing: Icon(
                  session.isOpen
                      ? Icons.lock_open_rounded
                      : Icons.check_circle_outline_rounded,
                  color: session.isOpen ? orange : green,
                ),
              ),
            ),
        ],

        if (filteredSessions.isNotEmpty) ...[
          const SizedBox(height: 22),

          const Text(
            'Assiduité des licenciés',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 4),

          const Text(
            'Résultats calculés sur les séances clôturées de la période.',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 10),

          for (final member in members)
            if (filteredSessions.any(
              (s) => s.expectedMemberIds.contains(member.id),
            ))
              _memberStatsCard(member, filteredSessions),
        ],

        const SizedBox(height: 16),
        _syncCard(),
      ],
    );
  }

  Widget _groupSelector() => DropdownButtonFormField<String>(
    key: ValueKey(groupId),
    initialValue: groupId,
    decoration: InputDecoration(
      labelText: 'Groupe / séance',
      helperText: sessionOpen
          ? 'Fermez la séance pour changer de groupe'
          : 'Sélectionnez le groupe à pointer',
      prefixIcon: Icon(
        sessionOpen ? Icons.lock_outline : Icons.groups_outlined,
      ),
    ),
    items: groups
        .map((g) => DropdownMenuItem(
              value: g.id,
              child: Text(g.name),
            ))
        .toList(),
    onChanged: sessionOpen
        ? null
        : (v) {
            if (v == null || v == groupId) return;
            setState(() {
              groupId = v;
              result = null;
            });
          },
  );

  Widget _hero(String eyebrow, String title, String subtitle, String status) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text(eyebrow.toUpperCase(), style: const TextStyle(color: cyan, fontWeight: FontWeight.w800))), Chip(label: Text(status))]),
    const SizedBox(height: 8), Text(title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: Colors.white70)),
  ])));

  Widget _metric(String title, String value, IconData icon, Color color) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Icon(icon, color: color, size: 28), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white60)), Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))]))])));


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
    setState(() {
      uid = null;
      error = null;
      waiting = true;
    });

    await widget.nfc.scan(
      onRead: (read) {
        if (!mounted) return;

        setState(() {
          uid = read.uid;
          waiting = false;
        });

        // V6 Android :
        // ne pas arrêter Reader Mode ici.
        // Le badge peut encore être physiquement contre le téléphone.
      },
      onError: (message) {
        if (!mounted) return;

        setState(() {
          error = message;
          waiting = false;
        });
      },
    );
  }

  Future<void> _save() async {
    if (uid == null || saving) return;

    setState(() => saving = true);

    final message = await widget.onSave(uid!);

    if (!mounted) return;

    if (message != null) {
      setState(() {
        error = message;
        saving = false;
      });
      return;
    }

    // V6 :
    // Reader Mode reste actif pendant l'enregistrement.
    //
    // L'utilisateur doit retirer le badge avant que l'écran soit fermé.
    // On laisse un court délai afin d'éviter de rendre instantanément
    // le NTAG213 au gestionnaire NFC Samsung.
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    await widget.nfc.stop();

    if (!mounted) return;

    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    // Sécurité uniquement si l'utilisateur quitte l'écran sans enregistrer.
    // L'arrêt est asynchrone : on ne bloque pas dispose().
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
          const SizedBox(height: 18),
          const Text(
            'RETIREZ MAINTENANT LE BADGE DU TÉLÉPHONE',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.orangeAccent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Puis associez ce badge à ${widget.member.fullName}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (error != null) Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
      ])))),
      const SizedBox(height: 14),
      if (uid != null) FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.link), label: Text(saving ? 'ENREGISTREMENT…' : 'ASSOCIER LE BADGE'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58))),
      if (!waiting && uid == null) FilledButton.icon(onPressed: _start, icon: const Icon(Icons.refresh), label: const Text('RÉESSAYER'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58))),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('ANNULER')),
    ]))),
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
