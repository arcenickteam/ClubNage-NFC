import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Versioned, app-private local snapshot. Never modifies existing uid_*/qr_* keys.
/// Contains only member IDs, group IDs and attendance timestamps (no names).
class AttendanceSnapshot {
  final List<TrainingSession> sessions;
  final List<AttendanceRecord> records;
  final String? activeSessionId;

  const AttendanceSnapshot({
    required this.sessions,
    required this.records,
    required this.activeSessionId,
  });
}

class LocalAttendanceStore {
  static const _key = 'clubnage_v7_attendance_snapshot_v1';

  Future<AttendanceSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      return const AttendanceSnapshot(sessions: [], records: [], activeSessionId: null);
    }
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> || data['schema'] != 1) {
      throw const FormatException('Format de sauvegarde inconnu.');
    }
    final sessions = (data['sessions'] as List<dynamic>)
        .map((v) => _decodeSession(v as Map<String, dynamic>)).toList();
    final records = (data['records'] as List<dynamic>)
        .map((v) => _decodeRecord(v as Map<String, dynamic>)).toList();
    return AttendanceSnapshot(
      sessions: sessions,
      records: records,
      activeSessionId: data['activeSessionId'] as String?,
    );
  }

  Future<void> save(AttendanceSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode({
      'schema': 1,
      'activeSessionId': snapshot.activeSessionId,
      'sessions': snapshot.sessions.map(_encodeSession).toList(),
      'records': snapshot.records.map(_encodeRecord).toList(),
    });
    final ok = await prefs.setString(_key, raw);
    if (!ok) throw StateError('Écriture locale refusée.');
  }

  static Map<String, dynamic> _encodeSession(TrainingSession s) => {
    'id': s.id,
    'groupId': s.groupId,
    'date': s.date.toIso8601String(),
    'openedAt': s.openedAt.toIso8601String(),
    'closedAt': s.closedAt?.toIso8601String(),
    'expectedMemberIds': s.expectedMemberIds,
    'label': s.label,
    'startTime': s.startTime?.toIso8601String(),
    'endTime': s.endTime?.toIso8601String(),
    'eligibleGroupIds': s.eligibleGroupIds,
    'manualType': s.manualType,
    'excludeFromStats': s.excludeFromStats,
  };

  static TrainingSession _decodeSession(Map<String, dynamic> s) => TrainingSession(
    id: s['id'] as String,
    groupId: s['groupId'] as String,
    date: DateTime.parse(s['date'] as String),
    openedAt: DateTime.parse(s['openedAt'] as String),
    closedAt: _date(s['closedAt']),
    expectedMemberIds: List<String>.from(s['expectedMemberIds'] as List),
    label: s['label'] as String?,
    startTime: _date(s['startTime']),
    endTime: _date(s['endTime']),
    eligibleGroupIds: List<String>.from(s['eligibleGroupIds'] as List),
    manualType: s['manualType'] as String?,
    excludeFromStats: s['excludeFromStats'] as bool? ?? false,
  );

  static Map<String, dynamic> _encodeRecord(AttendanceRecord r) => {
    'memberId': r.memberId,
    'groupId': r.groupId,
    'sessionId': r.sessionId,
    'timestamp': r.timestamp.toIso8601String(),
    'status': r.status.name,
    'method': r.method,
    'isExceptional': r.isExceptional,
  };

  static AttendanceRecord _decodeRecord(Map<String, dynamic> r) => AttendanceRecord(
    memberId: r['memberId'] as String,
    groupId: r['groupId'] as String,
    sessionId: r['sessionId'] as String?,
    timestamp: DateTime.parse(r['timestamp'] as String),
    status: AttendanceStatus.values.byName(r['status'] as String),
    method: r['method'] as String,
    isExceptional: r['isExceptional'] as bool? ?? false,
  );

  static DateTime? _date(dynamic value) => value == null ? null : DateTime.parse(value as String);
}
