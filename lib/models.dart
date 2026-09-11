class Member {
  final String id;
  final String firstName;
  final String lastName;
  final List<String> groups;
  final String nfcUid;
  final String qrToken;

  const Member({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.groups,
    required this.nfcUid,
    required this.qrToken,
  });

  String get fullName => '$firstName $lastName';
}

class TrainingGroup {
  final String id;
  final String name;
  final String schedule;

  const TrainingGroup(this.id, this.name, this.schedule);
}

enum AttendanceStatus { present, duplicate, denied, unknown }

class AttendanceResult {
  final AttendanceStatus status;
  final String title;
  final String message;
  final Member? member;
  final String? uid;

  const AttendanceResult({
    required this.status,
    required this.title,
    required this.message,
    this.member,
    this.uid,
  });

  bool get ok => status == AttendanceStatus.present;
  bool get duplicate => status == AttendanceStatus.duplicate;
}
