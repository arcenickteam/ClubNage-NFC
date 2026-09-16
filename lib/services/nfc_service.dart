import 'dart:io';
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
      if (Platform.isAndroid) {
        await NfcManagerAndroid.instance.disableReaderMode();
      } else {
        await NfcManager.instance.stopSession();
      }
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
      if (Platform.isAndroid) {
        // Reader Mode prend la main sur le traitement NFC système d'Android.
        // skipNdefCheck est volontaire : nos NTAG213 peuvent être vierges et
        // Club MN NFC utilise leur UID matériel, pas leur contenu NDEF.
        await NfcManagerAndroid.instance.enableReaderMode(
          flags: {
            NfcReaderFlagAndroid.nfcA,
            NfcReaderFlagAndroid.nfcB,
            NfcReaderFlagAndroid.skipNdefCheck,
            NfcReaderFlagAndroid.noPlatformSounds,
          },
          onTagDiscovered: (tag) async {
            try {
              final androidTag = NfcTagAndroid.from(tag);
              if (androidTag == null) {
                onError('Tag NFC Android non reconnu.');
                await stop();
                return;
              }
              final uid = _hex(androidTag.id);
              await stop();
              onRead(NfcReadResult(uid, 'Android'));
            } catch (e) {
              await stop();
              onError('Impossible de lire ce badge : $e');
            }
          },
        );
        return;
      }

      // iOS : session NFC native via nfc_manager.
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        alertMessageIos: 'Approchez le porte-clé Club MN NFC',
        invalidateAfterFirstReadIos: true,
        noPlatformSoundsAndroid: false,
        onSessionErrorIos: (error) {
          _running = false;
          onError('Lecture NFC interrompue : ${error.message}');
        },
        onDiscovered: (tag) async {
          try {
            final iosTag = MiFareIos.from(tag);
            if (iosTag == null) {
              onError('Tag NFC iOS non reconnu.');
              await stop();
              return;
            }
            final uid = _hex(iosTag.identifier);
            await stop();
            onRead(NfcReadResult(uid, 'iOS'));
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
