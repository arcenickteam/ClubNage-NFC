import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clubnage_nfc/models.dart';
import 'package:clubnage_nfc/services/correction_journal.dart';
import 'package:clubnage_nfc/services/kdrive_attendance_sync.dart';
import 'package:clubnage_nfc/services/infomaniak_kdrive_service.dart';
import 'package:clubnage_nfc/services/local_attendance_store.dart';
import 'package:clubnage_nfc/services/manual_attendance.dart';
import 'package:clubnage_nfc/services/xlsx_data_reader.dart';

class TestDrive extends InfomaniakKdriveService {
  Uint8List bytes = File('test/fixtures/minimal.xlsx').readAsBytesSync();
  int writes = 0;
  @override
  Future<bool> restoreSavedApiToken() async => true;
  @override
  Future<String> scheduleEtag() async => '$writes';
  @override
  Future<Uint8List> downloadWorkbook(String name,
      {void Function(String stage)? onProgress}) async => bytes;
  @override
  Future<void> replaceScheduleIfUnchanged(Uint8List content, String expectedEtag) async {
    if (expectedEtag != '$writes') throw StateError('Conflit ETag');
    bytes = content;
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 6, 18);
  final session = TrainingSession(id: 'seance-v724', groupId: 'g',
    date: now, openedAt: now, expectedMemberIds: ['m']);
  final device = ClubDevice(id: 'telephone-a', name: 'Accueil',
    version: '7.24.0', build: '1024', firstUsed: now);
  final other = ClubDevice(id: 'telephone-b', name: 'Entraîneur',
    version: '7.24.0', build: '1024', firstUsed: now);
  AttendanceRecord initial() => AttendanceRecord(memberId: 'm', groupId: 'g',
    sessionId: session.id, timestamp: now, status: AttendanceStatus.present,
    method: 'MANUEL', deviceId: device.id);
  AttendanceCorrection event(AttendanceRecord from, AttendanceRecord to,
      ClubDevice d) => AttendanceCorrection.create(
    pointageId: KdriveAttendanceSync.recordId(to), sessionId: session.id,
    memberId: 'm', previousStatus: from.status.name,
    newStatus: to.status.name, previousRevision: from.revision,
    newRevision: to.revision, device: d, afterClosure: true,
    now: to.updatedAt!);
  Future<AttendanceSyncResult> sync(TestDrive drive, List<AttendanceRecord> records,
      {List<AttendanceCorrection> events = const [], ClubDevice? device}) =>
    KdriveAttendanceSync(drive).synchronize(records: records,
      sessions: [session], members: [], corrections: events, device: device);
  List<List<String>> sheet(TestDrive drive, String name) =>
    XlsxDataReader.readSheet(drive.bytes, name);

  test('événement persistant, identifiant stable, deux téléphones, sans doublons', () async {
    final drive = TestDrive();
    final first = initial();
    await sync(drive, [first]);
    final updated = ManualAttendance.update(records: [first], session: session,
      memberId: 'm', status: AttendanceStatus.absent,
      now: now.add(const Duration(minutes: 3)), deviceId: device.id);
    final change = event(first, updated, device);
    expect(KdriveAttendanceSync.recordId(first), KdriveAttendanceSync.recordId(updated));
    await sync(drive, [updated], events: [change], device: device);
    final result = await sync(drive, [first], device: other);
    expect(result.records.single.status, AttendanceStatus.absent);
    expect(result.corrections.single.id, change.id);
    expect(sheet(drive, 'Historique corrections').length, 2);
    expect(sheet(drive, 'Appareils').length, 3);
    expect(sheet(drive, 'Pointages NFC').length, 2);
    await sync(drive, [updated], events: [change], device: device);
    expect(sheet(drive, 'Historique corrections').length, 2);
  });

  test('deux révisions concurrentes : aucune correction distante écrasée', () async {
    final drive = TestDrive();
    final first = initial();
    await sync(drive, [first]);
    final a = ManualAttendance.update(records: [first], session: session,
      memberId: 'm', status: AttendanceStatus.absent,
      now: now.add(const Duration(minutes: 2)), deviceId: device.id);
    final b = ManualAttendance.update(records: [first], session: session,
      memberId: 'm', status: AttendanceStatus.late,
      now: now.add(const Duration(minutes: 3)), deviceId: other.id);
    await sync(drive, [a], events: [event(first, a, device)]);
    final result = await sync(drive, [b], events: [event(first, b, other)]);
    expect(result.conflicts, isNotEmpty);
    expect(result.conflictingPointageIds, contains(KdriveAttendanceSync.recordId(b)));
    expect(sheet(drive, 'Pointages NFC')[1][12], 'Absent');
    expect(sheet(drive, 'Historique corrections').length, 3);
    expect(result.records.single.status, AttendanceStatus.late);
  });

  test('résolution explicite d un conflit : révision suivante propagée', () async {
    final drive = TestDrive();
    final first = initial();
    await sync(drive, [first]);
    final a = ManualAttendance.update(records: [first], session: session,
      memberId: 'm', status: AttendanceStatus.absent,
      now: now.add(const Duration(minutes: 2)), deviceId: device.id);
    final b = ManualAttendance.update(records: [first], session: session,
      memberId: 'm', status: AttendanceStatus.late,
      now: now.add(const Duration(minutes: 3)), deviceId: other.id);
    await sync(drive, [a], events: [event(first, a, device)]);
    final conflict = await sync(drive, [b], events: [event(first, b, other)]);
    expect(conflict.conflicts, isNotEmpty);
    final resolved = ManualAttendance.update(records: [a], session: session,
      memberId: 'm', status: AttendanceStatus.late,
      now: now.add(const Duration(minutes: 4)), deviceId: other.id);
    final resolution = event(a, resolved, other);
    final result = await sync(drive, [resolved],
      events: [event(first, b, other), resolution]);
    expect(result.conflicts, isEmpty);
    expect(sheet(drive, 'Pointages NFC')[1][12], 'Retard');
    expect(sheet(drive, 'Historique corrections').length, 5);
  });

  test('deux téléphones créent le même licencié/séance : pas de double ligne', () async {
    final drive = TestDrive();
    final first = initial();
    await sync(drive, [first]);
    final second = AttendanceRecord(memberId: 'm', groupId: 'g',
      sessionId: session.id, timestamp: now.add(const Duration(minutes: 1)),
      status: AttendanceStatus.late, method: 'NFC', deviceId: other.id);
    final result = await sync(drive, [second]);
    expect(result.conflicts, isNotEmpty);
    expect(result.remoteConflicts, contains(KdriveAttendanceSync.recordId(second)));
    expect(sheet(drive, 'Pointages NFC').length, 2);
  });

  test('révision divergente sans chaîne d événements : refus de remplacer', () async {
    final drive = TestDrive();
    final first = initial();
    await sync(drive, [first]);
    final changed = ManualAttendance.update(records: [first], session: session,
      memberId: 'm', status: AttendanceStatus.late,
      now: now.add(const Duration(minutes: 1)));
    final result = await sync(drive, [changed]);
    expect(result.conflicts, isNotEmpty);
    expect(sheet(drive, 'Pointages NFC')[1][12], 'Présent');
  });

  test('journal local conservé après fermeture et rechargement', () async {
    SharedPreferences.setMockInitialValues({});
    final first = initial();
    final changed = ManualAttendance.update(records: [first], session: session,
      memberId: 'm', status: AttendanceStatus.absent,
      now: now.add(const Duration(minutes: 1)));
    final correction = event(first, changed, device);
    final store = LocalAttendanceStore();
    await store.save(AttendanceSnapshot(sessions: [session.close(now)],
      records: [changed], corrections: [correction], activeSessionId: null));
    final reloaded = await store.load();
    expect(reloaded.corrections.single.id, correction.id);
    expect(reloaded.records.single.revision, 1);
    expect(reloaded.sessions.single.isOpen, false);
  });
}
