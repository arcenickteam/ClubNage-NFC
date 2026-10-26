import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clubnage_nfc/models.dart';
import 'package:clubnage_nfc/services/local_attendance_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sauvegarde et restauration de séance et pointage', () async {
    SharedPreferences.setMockInitialValues({
      'uid_M2001': 'NFC-EXISTANT',
      'qr_M2001': 'QR-EXISTANT',
    });
    final openedAt = DateTime(2026, 10, 26, 18, 0);
    final session = TrainingSession(
      id: 'seance-1',
      groupId: 'juniors',
      date: DateTime(2026, 10, 26),
      openedAt: openedAt,
      expectedMemberIds: const ['M2001'],
      label: 'Entraînement',
      startTime: openedAt,
      endTime: openedAt.add(const Duration(hours: 1)),
      eligibleGroupIds: const ['juniors'],
    );
    final record = AttendanceRecord(
      memberId: 'M2001',
      groupId: 'juniors',
      sessionId: 'seance-1',
      timestamp: openedAt.add(const Duration(minutes: 3)),
      status: AttendanceStatus.present,
      method: 'NFC',
    );
    final store = LocalAttendanceStore();
    await store.save(AttendanceSnapshot(
      sessions: [session],
      records: [record],
      activeSessionId: 'seance-1',
    ));
    final restored = await LocalAttendanceStore().load();
    expect(restored.activeSessionId, 'seance-1');
    expect(restored.sessions.single.expectedMemberIds, ['M2001']);
    expect(restored.sessions.single.eligibleGroupIds, ['juniors']);
    expect(restored.records.single.memberId, 'M2001');
    expect(restored.records.single.status, AttendanceStatus.present);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('uid_M2001'), 'NFC-EXISTANT');
    expect(prefs.getString('qr_M2001'), 'QR-EXISTANT');
  });

  test('refuse une sauvegarde inconnue sans l’écraser', () async {
    SharedPreferences.setMockInitialValues({
      'clubnage_v7_attendance_snapshot_v1': '{"schema":999}',
    });
    final store = LocalAttendanceStore();
    await expectLater(store.load(), throwsFormatException);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('clubnage_v7_attendance_snapshot_v1'), '{"schema":999}');
  });
}
