import 'dart:math';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identifiant technique persistant, indépendant du nom donné au téléphone.
class ClubDevice {
  final String id;
  final String name;
  final String version;
  final String build;
  final DateTime firstUsed;
  const ClubDevice({required this.id, required this.name, required this.version,
    required this.build, required this.firstUsed});

  static String newId() {
    final random = Random.secure();
    return List.generate(4, (_) => random.nextInt(0x100000000)
        .toRadixString(16).padLeft(8, '0')).join();
  }

  static Future<ClubDevice> load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('clubnage_device_id_v724');
    if (id == null || id.isEmpty) {
      id = newId();
      if (!await prefs.setString('clubnage_device_id_v724', id)) {
        throw StateError('Identifiant de téléphone non sauvegardé.');
      }
    }
    var first = prefs.getString('clubnage_device_first_used_v724');
    if (first == null) {
      first = DateTime.now().toUtc().toIso8601String();
      if (!await prefs.setString('clubnage_device_first_used_v724', first)) {
        throw StateError('Date de première utilisation non sauvegardée.');
      }
    }
    final info = await PackageInfo.fromPlatform();
    return ClubDevice(id: id, name: prefs.getString('clubnage_device_name_v724') ?? 'Téléphone ClubNage',
      version: info.version, build: info.buildNumber, firstUsed: DateTime.parse(first));
  }

  Future<ClubDevice> renamed(String value) async {
    final name = value.trim();
    if (name.isEmpty || name.length > 60) throw ArgumentError('Nom de téléphone invalide.');
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('clubnage_device_name_v724', name)) {
      throw StateError('Nom de téléphone non sauvegardé.');
    }
    return ClubDevice(id: id, name: name, version: version, build: build, firstUsed: firstUsed);
  }
}

/// Événement immuable et idempotent : une révision ne supprime jamais les précédentes.
class AttendanceCorrection {
  final String id;
  final String pointageId;
  final String sessionId;
  final String memberId;
  final String previousStatus;
  final String newStatus;
  final int previousRevision;
  final int newRevision;
  final DateTime at;
  final String deviceId;
  final String deviceName;
  final String appVersion;
  final bool afterClosure;

  const AttendanceCorrection({required this.id, required this.pointageId,
    required this.sessionId, required this.memberId, required this.previousStatus,
    required this.newStatus, required this.previousRevision, required this.newRevision,
    required this.at, required this.deviceId, required this.deviceName,
    required this.appVersion, required this.afterClosure});

  static AttendanceCorrection create({required String pointageId,
    required String sessionId, required String memberId, required String previousStatus,
    required String newStatus, required int previousRevision, required int newRevision,
    required ClubDevice device, required bool afterClosure, required DateTime now}) {
    if (newRevision <= previousRevision || previousStatus == newStatus) {
      throw ArgumentError('Correction sans changement ou révision invalide.');
    }
    return AttendanceCorrection(id: '${device.id}-${ClubDevice.newId()}', pointageId: pointageId,
      sessionId: sessionId, memberId: memberId, previousStatus: previousStatus,
      newStatus: newStatus, previousRevision: previousRevision,
      newRevision: newRevision, at: now.toUtc(), deviceId: device.id,
      deviceName: device.name, appVersion: '${device.version}+${device.build}',
      afterClosure: afterClosure);
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'pointageId': pointageId, 'sessionId': sessionId,
    'memberId': memberId, 'previousStatus': previousStatus, 'newStatus': newStatus,
    'previousRevision': previousRevision, 'newRevision': newRevision,
    'at': at.toUtc().toIso8601String(), 'deviceId': deviceId,
    'deviceName': deviceName, 'appVersion': appVersion, 'afterClosure': afterClosure,
  };

  factory AttendanceCorrection.fromJson(Map<String, dynamic> v) => AttendanceCorrection(
    id: v['id'] as String, pointageId: v['pointageId'] as String,
    sessionId: v['sessionId'] as String, memberId: v['memberId'] as String,
    previousStatus: v['previousStatus'] as String, newStatus: v['newStatus'] as String,
    previousRevision: (v['previousRevision'] as num).toInt(),
    newRevision: (v['newRevision'] as num).toInt(),
    at: DateTime.parse(v['at'] as String), deviceId: v['deviceId'] as String,
    deviceName: v['deviceName'] as String, appVersion: v['appVersion'] as String,
    afterClosure: v['afterClosure'] as bool? ?? false,
  );
}
