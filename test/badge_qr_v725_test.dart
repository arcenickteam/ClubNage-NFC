import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clubnage_nfc/models.dart';
import 'package:clubnage_nfc/services/kdrive_badge_sync.dart';
import 'package:clubnage_nfc/services/infomaniak_kdrive_service.dart';
import 'package:clubnage_nfc/services/xlsx_data_reader.dart';

class QrTestDrive extends InfomaniakKdriveService {
  Uint8List bytes = File('test/fixtures/minimal.xlsx').readAsBytesSync();
  int writes = 0;
  @override
  Future<bool> restoreSavedApiToken() async => true;
  @override
  Future<String> scheduleEtag() async => '$writes';
  @override
  Future<Uint8List> downloadWorkbook(String name,
      {void Function(String stage)? onProgress}) async => bytes;
  @override
  Future<void> replaceScheduleIfUnchanged(Uint8List content,
      String expectedEtag) async {
    if (expectedEtag != '$writes') throw StateError('Conflit ETag');
    bytes = content;
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final a = Member(id: 'MN26-0001', firstName: 'Camille', lastName: 'Test',
    groups: const ['Junior'], nfcUid: '', qrToken: '');
  final b = Member(id: 'MN26-0002', firstName: 'Alex', lastName: 'Test',
    groups: const ['Junior'], nfcUid: '', qrToken: '');

  test('QR attribué sur A retrouvé sur B, sans doublon au second passage', () async {
    final drive = QrTestDrive();
    SharedPreferences.setMockInitialValues({});
    await KdriveBadgeSync.queueQrAssignment(a, 'QR-MN-123');
    final first = await KdriveBadgeSync(drive).synchronize([a, b]);
    expect(first.sharedQrTokens[a.id], 'QR-MN-123');
    expect(first.uploaded, 1);
    final writes = drive.writes;
    SharedPreferences.setMockInitialValues({}); // Téléphone B indépendant.
    final second = await KdriveBadgeSync(drive).synchronize([a, b]);
    expect(second.sharedQrTokens[a.id], 'QR-MN-123');
    expect(second.uploaded, 0);
    expect(drive.writes, writes);
    final rows = XlsxDataReader.readSheet(drive.bytes, 'Badges V715');
    expect(rows.where((r) => r.length > 4 && r[4] == 'QR').length, 1);
  });

  test('migration des QR déjà locaux avant la mise à jour', () async {
    final drive = QrTestDrive();
    SharedPreferences.setMockInitialValues({'qr_${a.id}': 'QR-ANCIEN'});
    final result = await KdriveBadgeSync(drive).synchronize([a, b]);
    expect(result.sharedQrTokens[a.id], 'QR-ANCIEN');
    expect(result.uploaded, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('qr_${a.id}'), 'QR-ANCIEN');
  });

  test('même QR sur deux licenciés : conflit et file locale conservée', () async {
    final drive = QrTestDrive();
    SharedPreferences.setMockInitialValues({});
    await KdriveBadgeSync.queueQrAssignment(a, 'QR-COMMUN');
    await KdriveBadgeSync(drive).synchronize([a, b]);
    SharedPreferences.setMockInitialValues({});
    await KdriveBadgeSync.queueQrAssignment(b, 'QR-COMMUN');
    final result = await KdriveBadgeSync(drive).synchronize([a, b]);
    expect(result.conflicts, isNotEmpty);
    expect(result.pending, 1);
    expect(result.sharedQrTokens[a.id], 'QR-COMMUN');
    expect(result.sharedQrTokens[b.id], isNull);
  });

  test('deux QR concurrents pour un licencié : aucun écrasement', () async {
    final drive = QrTestDrive();
    SharedPreferences.setMockInitialValues({});
    await KdriveBadgeSync.queueQrAssignment(a, 'QR-ACCUEIL');
    await KdriveBadgeSync(drive).synchronize([a]);
    SharedPreferences.setMockInitialValues({'qr_${a.id}': 'QR-ENTRAINEUR'});
    final result = await KdriveBadgeSync(drive).synchronize([a]);
    expect(result.conflicts, isNotEmpty);
    expect(result.pendingQrTokens[a.id], 'QR-ENTRAINEUR');
    expect(result.sharedQrTokens[a.id], 'QR-ACCUEIL');
  });
}
