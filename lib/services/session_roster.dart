import '../models.dart';
import 'group_eligibility.dart';
import 'slot_authorization.dart';

/// Actualise uniquement les séances ouvertes, sans modifier leurs pointages.
class SessionRoster {
  static TrainingSession refresh(TrainingSession session,
      List<Member> members, List<AttendanceRecord> records) {
    if (!session.isOpen) return session;
    final groups = session.eligibleGroupIds.isNotEmpty
        ? session.eligibleGroupIds : [session.groupId];
    final expected = <String>{
      for (final member in members)
        if (session.manualType != null
            ? GroupEligibility.anyMatch(member.groups, groups)
            : groups.any((group) => SlotAuthorization.permission(member, group)
                == SlotPermission.authorized)) member.id,
      // Un pointage existant reste corrigeable après un changement de groupe.
      for (final record in records)
        if (record.sessionId == session.id &&
            record.status != AttendanceStatus.refused) record.memberId,
    };
    if (expected.length == session.expectedMemberIds.length &&
        expected.containsAll(session.expectedMemberIds)) return session;
    return TrainingSession(
      id: session.id, groupId: session.groupId, date: session.date,
      openedAt: session.openedAt, closedAt: session.closedAt,
      expectedMemberIds: List.unmodifiable(expected), label: session.label,
      startTime: session.startTime, endTime: session.endTime,
      eligibleGroupIds: session.eligibleGroupIds, manualType: session.manualType,
      excludeFromStats: session.excludeFromStats,
    );
  }
}
