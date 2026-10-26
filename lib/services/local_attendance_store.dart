import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Stockage local des séances et pointages, indépendant de kDrive.
/// Ne modifie pas les anciennes clés uid_*/qr_* des associations.
class LocalAttendanceStore {
  static const _key = 'clubnage_v7_attendance_v1';

  Future<({List<TrainingSession> sessions, List<AttendanceRecord> records})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return (sessions: <TrainingSession>[], records: <AttendanceRecord>[]);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (
      sessions: (data['sessions'] as List<dynamic>).map((e) => _sessionFromJson(e as Map<String, dynamic>)).toList(),
      records: (data['records'] as List<dynamic>).map((e) => _recordFromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<void> save(List<TrainingSession> sessions, List<AttendanceRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'schema': 1,
      'sessions': sessions.map(_sessionToJson).toList(),
      'records': records.map(_recordToJson).toList(),
    });
    if (!await prefs.setString(_key, data)) {
      throw StateError('Impossible de sauvegarder les présences localement.');
    }
  }

  Map<String, dynamic> _sessionToJson(TrainingSession s) => {
    'id': s.id, 'groupId': s.groupId, 'date': s.date.toIso8601String(),
    'openedAt': s.openedAt.toIso8601String(), 'closedAt': s.closedAt?.toIso8601String(),
    'expectedMemberIds': s.expectedMemberIds, 'label': s.label,
    'startTime': s.startTime?.toIso8601String(), 'endTime': s.endTime?.toIso8601String(),
    'eligibleGroupIds': s.eligibleGroupIds, 'manualType': s.manualType,
    'excludeFromStats': s.excludeFromStats,
  };

  TrainingSession _sessionFromJson(Map<String, dynamic> m) => TrainingSession(
    id: m['id'] as String,
    groupId: m['groupId'] as String,
    date: DateTime.parse(m['date'] as String),
    openedAt: DateTime.parse(m['openedAt'] as String),
    closedAt: m['closedAt'] == null ? null : DateTime.parse(m['closedAt'] as String),
    expectedMemberIds: List<String>.from(m['expectedMemberIds'] as List),
    label: m['label'] as String?,
    startTime: m['startTime'] == null ? null : DateTime.parse(m['startTime'] as String),
    endTime: m['endTime'] == null ? null : DateTime.parse(m['endTime'] as String),
    eligibleGroupIds: List<String>.from(m['eligibleGroupIds'] as List? ?? []),
    manualType: m['manualType'] as String?,
    excludeFromStats: m['excludeFromStats'] as bool? ?? false,
  );

  Map<String, dynamic> _recordToJson(AttendanceRecord r) => {
    'memberId': r.memberId, 'groupId': r.groupId, 'sessionId': r.sessionId,
    'timestamp': r.timestamp.toIso8601String(), 'status': r.status.name,
    'method': r.method,
  };

  AttendanceRecord _recordFromJson(Map<String, dynamic> m) => AttendanceRecord(
    memberId: m['memberId'] as String,
    groupId: m['groupId'] as String,
    sessionId: m['sessionId'] as String?,
    timestamp: DateTime.parse(m['timestamp'] as String),
    status: AttendanceStatus.values.byName(m['status'] as String),
    method: m['method'] as String,
  );
}
