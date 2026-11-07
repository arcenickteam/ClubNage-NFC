import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clubnage_nfc/models.dart';
import 'package:clubnage_nfc/services/manual_attendance.dart';
import 'package:clubnage_nfc/services/correction_journal.dart';
import 'package:clubnage_nfc/services/local_attendance_store.dart';
import 'package:clubnage_nfc/services/kdrive_attendance_sync.dart';
import 'package:clubnage_nfc/services/infomaniak_kdrive_service.dart';
import 'package:clubnage_nfc/services/xlsx_data_reader.dart';

class MemoryDrive extends InfomaniakKdriveService {
  Uint8List bytes = File('test/fixtures/minimal.xlsx').readAsBytesSync();
  int uploads = 0;
  bool offline = false;
  bool loseAcknowledgement = false;
  @override
  Future<bool> restoreSavedApiToken() async => true;
  @override
  Future<String> scheduleEtag() async {
    if (offline) throw const SocketException('Hors connexion');
    return '$uploads';
  }
  @override
  Future<Uint8List> downloadWorkbook(String name, {void Function(String stage)? onProgress}) async => bytes;
  @override
  Future<void> replaceScheduleIfUnchanged(Uint8List content, String expectedEtag) async {
    if (expectedEtag != '$uploads') throw StateError('Conflit');
    bytes = content;
    uploads++;
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw const SocketException('Réponse perdue après écriture');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 28, 18);
  final session = TrainingSession(id: 's1', groupId: 'g1', date: now,
      openedAt: now, expectedMemberIds: ['m1', 'm2', 'm3']);
  AttendanceRecord record(String id, AttendanceStatus status) => AttendanceRecord(
      memberId: id, groupId: 'g1', sessionId: 's1', timestamp: now,
      status: status, method: 'MANUEL');
  final device = ClubDevice(id: 'test-phone', name: 'Test',
    version: '7.24.0', build: '1024', firstUsed: now);
  AttendanceCorrection event(AttendanceRecord before, AttendanceRecord after) =>
    AttendanceCorrection.create(pointageId: KdriveAttendanceSync.recordId(after),
      sessionId: session.id, memberId: before.memberId,
      previousStatus: before.status.name, newStatus: after.status.name,
      previousRevision: before.revision, newRevision: after.revision,
      device: device, afterClosure: false, now: after.updatedAt!);
  Future<int> sync(MemoryDrive drive, List<AttendanceRecord> records,
      {List<AttendanceCorrection> corrections = const []}) async =>
      (await KdriveAttendanceSync(drive).synchronize(
        records: records,
        sessions: [session], members: [], corrections: corrections,
      )).uploadedPointages;
  List<List<String>> rows(MemoryDrive drive) => XlsxDataReader.readSheet(drive.bytes, 'Pointages NFC');

  test('3 pointages restent 3 après répétition; correction sans doublon', () async {
    final drive = MemoryDrive();
    final data = ['m1', 'm2', 'm3'].map((id) => record(id, AttendanceStatus.present)).toList();
    final original = ZipDecoder().decodeBytes(drive.bytes).findFile('xl/worksheets/sheet1.xml')!.content;
    expect(await sync(drive, data), 3);
    expect(await sync(drive, data), 0);
    expect(rows(drive).length, 4);
    expect(drive.uploads, 1);
    final before = data[0];
    data[0] = ManualAttendance.update(records: data, session: session, memberId: 'm1',
        status: AttendanceStatus.absent, now: now.add(const Duration(minutes: 5)));
    final correction = event(before, data[0]);
    expect(await sync(drive, data, corrections: [correction]), 1);
    expect(rows(drive).length, 4);
    expect(rows(drive)[1][12], 'Absent');
    expect(await sync(drive, data, corrections: [correction]), 0);
    expect(ZipDecoder().decodeBytes(drive.bytes).findFile('xl/worksheets/sheet1.xml')!.content, original);
  });

  test('telephone B recupere une correction du telephone A', () async {
    final drive = MemoryDrive();
    final first = record('m1', AttendanceStatus.present);
    await KdriveAttendanceSync(drive).synchronize(
        records: [first], sessions: [session], members: []);
    final corrected = ManualAttendance.update(
        records: [first], session: session, memberId: 'm1',
        status: AttendanceStatus.absent,
        now: now.add(const Duration(minutes: 5)));
    await KdriveAttendanceSync(drive).synchronize(
        records: [corrected], sessions: [session], members: [],
        corrections: [event(first, corrected)]);
    final result = await KdriveAttendanceSync(drive).synchronize(
        records: [first], sessions: [session], members: []);
    expect(result.records.single.status, AttendanceStatus.absent);
    expect(result.records.single.revision, 1);
    expect(rows(drive).length, 2);
  });

  test('deux corrections concurrentes meme revision ne sont pas ecrasees', () async {
    final drive = MemoryDrive();
    final first = record('m1', AttendanceStatus.present);
    await sync(drive, [first]);
    final a = ManualAttendance.update(records: [first], session: session,
        memberId: 'm1', status: AttendanceStatus.absent,
        now: now.add(const Duration(minutes: 5)));
    final b = ManualAttendance.update(records: [first], session: session,
        memberId: 'm1', status: AttendanceStatus.late,
        now: now.add(const Duration(minutes: 6)));
    await sync(drive, [a], corrections: [event(first, a)]);
    final result = await KdriveAttendanceSync(drive).synchronize(
        records: [b], sessions: [session], members: [],
        corrections: [event(first, b)]);
    expect(result.conflicts, isNotEmpty);
    expect(rows(drive)[1][12], 'Absent');
  });

  test('séance clôturée : correction autorisée, identité et révision conservées', () {
    final first = record('m1', AttendanceStatus.present);
    final closed = session.close(now.add(const Duration(hours: 1)));
    expect(() => ManualAttendance.update(records: [first], session: closed,
        memberId: 'm1', status: AttendanceStatus.absent, now: now), throwsStateError);
    final corrected = ManualAttendance.update(records: [first], session: closed,
        memberId: 'm1', status: AttendanceStatus.absent,
        now: now.add(const Duration(hours: 2)),
        authorizedClosedCorrection: true);
    expect(corrected.status, AttendanceStatus.absent);
    expect(corrected.revision, first.revision + 1);
    expect(KdriveAttendanceSync.recordId(corrected), KdriveAttendanceSync.recordId(first));
    expect(() => ManualAttendance.update(records: [], session: closed,
        memberId: 'm2', status: AttendanceStatus.present,
        now: now, authorizedClosedCorrection: true), throwsStateError);
  });

  test('réponse perdue après écriture : nouvel essai sans doublon', () async {
    final drive = MemoryDrive()..loseAcknowledgement = true;
    final data = [record('m1', AttendanceStatus.late)];
    await expectLater(sync(drive, data), throwsA(isA<SocketException>()));
    expect(await sync(drive, data), 0);
    expect(rows(drive).length, 2);
    expect(drive.uploads, 1);
  });

  test('hors connexion, restauration locale et envoi après reconnexion', () async {
    SharedPreferences.setMockInitialValues({});
    final data = [record('m1', AttendanceStatus.present), record('m2', AttendanceStatus.late), record('m3', AttendanceStatus.absent)];
    await LocalAttendanceStore().save(AttendanceSnapshot(sessions: [session], records: data, activeSessionId: session.id));
    final drive = MemoryDrive()..offline = true;
    await expectLater(sync(drive, data), throwsA(isA<SocketException>()));
    final restored = await LocalAttendanceStore().load();
    expect(restored.records.map((r) => r.status), data.map((r) => r.status));
    expect(restored.activeSessionId, session.id);
    drive.offline = false;
    expect(await sync(drive, restored.records), 3);
  });

  test('correction conserve ID; séance fermée et membre extérieur refusés', () {
    final first = record('m1', AttendanceStatus.absent);
    final updated = ManualAttendance.update(records: [first], session: session,
        memberId: 'm1', status: AttendanceStatus.late, now: now.add(const Duration(hours: 1)));
    expect(KdriveAttendanceSync.recordId(updated), KdriveAttendanceSync.recordId(first));
    expect(() => ManualAttendance.update(records: [], session: session.close(now),
        memberId: 'm1', status: AttendanceStatus.present, now: now), throwsStateError);
    expect(() => ManualAttendance.update(records: [], session: session,
        memberId: 'other', status: AttendanceStatus.present, now: now), throwsStateError);
  });
}
