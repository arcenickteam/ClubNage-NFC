class Member {
  final String id;
  final String firstName;
  final String lastName;
  final List<String> groups;
  final String nfcUid;
  final String qrToken;
  final String dossierStatus;
  final String email;
  final String phone;
  final String dateOfBirth;
  final String legalRepresentative;

  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.groups,
    required this.nfcUid,
    required this.qrToken,
    this.dossierStatus = 'Validé',
    this.email = '',
    this.phone = '',
    this.dateOfBirth = '',
    this.legalRepresentative = '',
  });

  String get fullName => '$firstName $lastName';

  int? get age {
    final p = dateOfBirth.split('/');
    if (p.length != 3) return null;
    final birth = DateTime.tryParse('${p[2]}-${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}');
    if (birth == null) return null;
    final now = DateTime.now();
    var years = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) years--;
    return years;
  }
}

class TrainingGroup {
  final String id;
  final String name;
  final String day;
  final String startTime;
  final String endTime;

  const TrainingGroup(this.id, this.name, this.day, this.startTime, this.endTime);
  String get schedule => '$day • $startTime–$endTime';
}

class TrainingSession {
  final String id;
  final String groupId;
  final DateTime date;
  final DateTime openedAt;
  final DateTime? closedAt;
  final List<String> expectedMemberIds;
  final String? label;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<String> eligibleGroupIds;
  final String? manualType;
  final bool excludeFromStats;

  const TrainingSession({
    required this.id,
    required this.groupId,
    required this.date,
    required this.openedAt,
    this.closedAt,
    required this.expectedMemberIds,
    this.label,
    this.startTime,
    this.endTime,
    this.eligibleGroupIds = const [],
    this.manualType,
    this.excludeFromStats = false,
  });

  bool get isOpen => closedAt == null;

  TrainingSession close(DateTime time) => TrainingSession(
        id: id,
        groupId: groupId,
        date: date,
        openedAt: openedAt,
        closedAt: time,
        expectedMemberIds: expectedMemberIds,
        label: label,
        startTime: startTime,
        endTime: endTime,
        eligibleGroupIds: eligibleGroupIds,
        manualType: manualType,
        excludeFromStats: excludeFromStats,
      );
}

enum AttendanceStatus { present, late, duplicate, denied, unknown }

class AttendanceResult {
  final AttendanceStatus status;
  final String title;
  final String message;
  final Member? member;
  final String? uid;

  const AttendanceResult({required this.status, required this.title, required this.message, this.member, this.uid});
  bool get ok => status == AttendanceStatus.present || status == AttendanceStatus.late;
  bool get duplicate => status == AttendanceStatus.duplicate;
}

class AttendanceRecord {
  final String memberId;
  final String groupId;
  final String? sessionId;
  final DateTime timestamp;
  final AttendanceStatus status;
  final String method;

  const AttendanceRecord({
    required this.memberId,
    required this.groupId,
    this.sessionId,
    required this.timestamp,
    required this.status,
    required this.method,
  });
}
