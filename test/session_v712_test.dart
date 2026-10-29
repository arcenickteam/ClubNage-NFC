import 'package:flutter_test/flutter_test.dart';
import 'package:clubnage_nfc/models.dart';

void main() {
  test('La fermeture d’une séance ne ferme pas les autres', () {
    final now = DateTime(2026, 10, 29, 18);
    TrainingSession session(String id) => TrainingSession(
      id: id,
      groupId: 'adultes',
      date: DateTime(2026, 10, 29),
      openedAt: now,
      expectedMemberIds: const ['A'],
      startTime: now,
      endTime: now.add(const Duration(hours: 1)),
    );
    final first = session('adult-1');
    final second = session('adult-2');
    final sessions = [first.close(now.add(const Duration(hours: 1))), second];
    expect(sessions.first.isOpen, isFalse);
    expect(sessions.last.isOpen, isTrue);
    expect(sessions.last.id, 'adult-2');
  });

  test('La date limite de sécurité est calculée depuis le début', () {
    final start = DateTime(2026, 10, 29, 19, 30);
    final deadline = start.add(const Duration(hours: 4));
    expect(deadline, DateTime(2026, 10, 29, 23, 30));
  });
}
