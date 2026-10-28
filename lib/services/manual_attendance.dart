import '../models.dart';

/// Conserve l'identité des anciens pointages, y compris après export Excel.
class ManualAttendance {
  static AttendanceRecord update({
    required List<AttendanceRecord> records,
    required TrainingSession session,
    required String memberId,
    required AttendanceStatus status,
    required DateTime now,
    String method = 'MANUEL',
  }) {
    if (!session.isOpen || !session.expectedMemberIds.contains(memberId)) {
      throw StateError('Licencié hors séance ou séance fermée.');
    }
    if (![AttendanceStatus.present, AttendanceStatus.late, AttendanceStatus.absent].contains(status)) {
      throw ArgumentError('Statut non enregistrable.');
    }
    final previous = records.where((r) => r.sessionId == session.id && r.memberId == memberId).toList();
    if (previous.length > 1) throw StateError('Plusieurs pointages existent pour ce licencié.');
    return AttendanceRecord(
      memberId: memberId, groupId: session.groupId, sessionId: session.id,
      timestamp: previous.isEmpty ? now : previous.first.timestamp,
      status: status, method: method,
    );
  }
}
