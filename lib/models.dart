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
  });

  String get fullName => '$firstName $lastName';
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
  final DateTime timestamp;
  final AttendanceStatus status;
  final String method;

  const AttendanceRecord({required this.memberId, required this.groupId, required this.timestamp, required this.status, required this.method});
}
