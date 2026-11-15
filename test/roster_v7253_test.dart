import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clubnage_nfc/models.dart';
import 'package:clubnage_nfc/services/local_roster_store.dart';
import 'package:clubnage_nfc/services/manual_attendance.dart';
import 'package:clubnage_nfc/services/session_roster.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 15, 12);
  const marie = Member(id: 'marie', firstName: 'Marie-Agnès', lastName: 'CAZIN',
      groups: ['Aqua M2'], authorizedSlots: 'Aqua M2', nfcUid: '', qrToken: '');
  const other = Member(id: 'other', firstName: 'Autre', lastName: 'Créneau',
      groups: ['Aqua M2'], authorizedSlots: 'Aqua S', nfcUid: '', qrToken: '');
  TrainingSession session() => TrainingSession(id: 's', groupId: 'Aqua M2',
      date: now, openedAt: now, expectedMemberIds: ['nora']);
  AttendanceRecord record(String id, AttendanceStatus status) => AttendanceRecord(
      memberId: id, groupId: 'Aqua M2', sessionId: 's', timestamp: now,
      status: status, method: 'MANUEL');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('réimport remplace les actifs, archive les noms et conserve les badges', () async {
    final store = LocalRosterStore();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid_nora', '1234');
    await prefs.setString('pointages_test', 'historique');
    await store.save([{'id': 'nora', 'prenom': 'Nora', 'nom': 'Ancienne'}]);
    final rows = [{'id': 'marie', 'prenom': 'Marie-Agnès', 'nom': 'CAZIN'}];
    await store.save(rows);
    await store.save(rows);
    expect((await store.load())!.map((m) => m.id), ['marie']);
    expect((await store.load(archive: true))!.any((m) => m.id == 'nora'), isTrue);
    expect(prefs.getString('uid_nora'), '1234');
    expect(prefs.getString('pointages_test'), 'historique');
    await expectLater(store.save([]), throwsStateError);
    await expectLater(store.save([...rows, ...rows]), throwsStateError);
    expect((await store.load())!.single.id, 'marie');
    await store.clear();
    expect(await store.load(), isNull);
    expect(prefs.getString('uid_nora'), '1234');
  });

  test('séance ouverte : nouveaux autorisés, retrait des absents, pas de doublon', () {
    final refreshed = SessionRoster.refresh(session(), [marie, other], []);
    expect(refreshed.expectedMemberIds, ['marie']);
    final attendance = ManualAttendance.update(records: [], session: refreshed,
        memberId: 'marie', status: AttendanceStatus.present, now: now);
    expect(attendance.memberId, 'marie');
    expect(() => ManualAttendance.update(records: [], session: refreshed,
        memberId: 'other', status: AttendanceStatus.present, now: now), throwsStateError);
    expect(identical(SessionRoster.refresh(refreshed, [marie, other], []), refreshed), isTrue);
  });

  test('anciens pointages et séances closes restent intacts', () {
    final records = [record('nora', AttendanceStatus.present)];
    final refreshed = SessionRoster.refresh(session(), [marie], records);
    expect(refreshed.expectedMemberIds.toSet(), {'marie', 'nora'});
    expect(records.single.memberId, 'nora');
    final closed = session().close(now);
    expect(identical(SessionRoster.refresh(closed, [marie], records), closed), isTrue);
  });

  test('un refus antérieur ne bloque pas la présence ni sa correction', () {
    final refreshed = SessionRoster.refresh(session(), [marie], []);
    final denied = record('marie', AttendanceStatus.refused);
    final attendance = ManualAttendance.update(records: [denied], session: refreshed,
        memberId: 'marie', status: AttendanceStatus.present, now: now);
    expect(attendance.revision, 0);
    final changed = ManualAttendance.update(records: [denied, attendance], session: refreshed,
        memberId: 'marie', status: AttendanceStatus.late, now: now.add(const Duration(minutes: 1)));
    expect(changed.revision, 1);
    expect(changed.timestamp, attendance.timestamp);
  });
}
