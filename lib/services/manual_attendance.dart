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
    bool authorizedClosedCorrection = false,
    String deviceId = '',
  }) {
    if (!session.expectedMemberIds.contains(memberId)) {
      throw StateError('Licencié hors séance.');
    }
    if (!session.isOpen && !authorizedClosedCorrection) {
      throw StateError('Séance fermée : autorisation nécessaire.');
    }
    if (![AttendanceStatus.present, AttendanceStatus.late, AttendanceStatus.absent].contains(status)) {
      throw ArgumentError('Statut non enregistrable.');
    }
    final previous = records.where((r) => r.sessionId == session.id && r.memberId == memberId).toList();
    if (!session.isOpen && previous.isEmpty) {
      throw StateError('Correction impossible : aucun pointage initial.');
    }
    if (previous.length > 1) throw StateError('Plusieurs pointages existent pour ce licencié.');
    return AttendanceRecord(
      memberId: memberId, groupId: session.groupId, sessionId: session.id,
      timestamp: previous.isEmpty ? now : previous.first.timestamp,
      status: status, method: method,
      revision: previous.isEmpty ? 0 : previous.first.revision + 1,
      updatedAt: now, deviceId: deviceId,
    );
  }
}
