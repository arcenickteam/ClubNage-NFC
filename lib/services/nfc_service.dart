import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

class NfcReadResult {
  final String uid;
  final String platform;
  const NfcReadResult(this.uid, this.platform);
}

class NfcService {
  bool _running = false;

  Future<bool> isAvailable() async {
    final availability = await NfcManager.instance.checkAvailability();
    return availability == NfcAvailability.enabled;
  }

  Future<void> stop() async {
    if (!_running) return;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    _running = false;
  }

  Future<void> scan({
    required void Function(NfcReadResult result) onRead,
    required void Function(String message) onError,
  }) async {
    if (_running) return;
    final available = await isAvailable();
    if (!available) {
      onError('Le NFC est indisponible ou désactivé sur cet appareil.');
      return;
    }

    _running = true;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        alertMessageIos: 'Approchez le porte-clé Montchanin Natation',
        invalidateAfterFirstReadIos: true,
        noPlatformSoundsAndroid: false,
        onSessionErrorIos: (error) {
          _running = false;
          onError('Lecture NFC interrompue : ${error.message}');
        },
        onDiscovered: (tag) async {
          try {
            String? uid;
            String platform;

            final iosTag = MiFareIos.from(tag);
            if (iosTag != null) {
              uid = _hex(iosTag.identifier);
              platform = 'iOS';
            } else {
              final androidTag = NfcTagAndroid.from(tag);
              if (androidTag != null) {
                uid = _hex(androidTag.id);
                platform = 'Android';
              } else {
                onError('Type de badge NFC non reconnu.');
                await stop();
                return;
              }
            }

            await stop();
            onRead(NfcReadResult(uid, platform));
          } catch (e) {
            await stop();
            onError('Impossible de lire ce badge : $e');
          }
        },
      );
    } catch (e) {
      _running = false;
      onError('Impossible de démarrer le NFC : $e');
    }
  }

  String _hex(Uint8List bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(':')
      .toUpperCase();
}
