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
  bool _processingTag = false;
  String? _lastUid;
  DateTime? _lastReadAt;

  static const Duration _sameBadgeCooldown = Duration(seconds: 3);

  bool get isRunning => _running;

  Future<bool> isAvailable() async {
    final availability = await NfcManager.instance.checkAvailability();
    return availability == NfcAvailability.enabled;
  }

  /// Arrête explicitement la session NFC.
  ///
  /// Sur Android, Reader Mode reste volontairement actif après la lecture
  /// d'un badge. Cela évite de rendre immédiatement un NTAG213 vierge au
  /// système Android alors qu'il est encore posé contre le téléphone.
  Future<void> stop() async {
    if (!_running) return;

    try {
      if (Platform.isAndroid) {
        await NfcManagerAndroid.instance.disableReaderMode();
      } else {
        await NfcManager.instance.stopSession();
      }
    } catch (_) {
      // Une session peut déjà avoir été arrêtée par le système.
    } finally {
      _running = false;
      _processingTag = false;
      _lastUid = null;
      _lastReadAt = null;
    }
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
    _processingTag = false;
    _lastUid = null;
    _lastReadAt = null;

    try {
      if (Platform.isAndroid) {
        await _startAndroidReader(onRead: onRead, onError: onError);
        return;
      }

      await _startIosSession(onRead: onRead, onError: onError);
    } catch (e) {
      _running = false;
      _processingTag = false;
      _lastUid = null;
      onError('Impossible de démarrer le NFC : $e');
    }
  }

  Future<void> _startAndroidReader({
    required void Function(NfcReadResult result) onRead,
    required void Function(String message) onError,
  }) async {
    await NfcManagerAndroid.instance.enableReaderMode(
      flags: {
        NfcReaderFlagAndroid.nfcA,
        NfcReaderFlagAndroid.nfcB,

        // Les badges Club MN NFC sont des NTAG213 qui peuvent être vierges.
        // Nous utilisons uniquement leur UID matériel.
        NfcReaderFlagAndroid.skipNdefCheck,

        // Pas de son système Android : l'application gère son propre retour.
        NfcReaderFlagAndroid.noPlatformSounds,
      },
      onTagDiscovered: (tag) async {
        if (!_running || _processingTag) return;

        try {
          final androidTag = NfcTagAndroid.from(tag);

          if (androidTag == null) {
            onError('Tag NFC Android non reconnu.');
            return;
          }

          final uid = _hex(androidTag.id);

          // Protection anti-double lecture :
          // le même badge est ignoré pendant quelques secondes,
          // mais un autre badge peut être lu immédiatement.
          final now = DateTime.now();
          if (_lastUid == uid &&
              _lastReadAt != null &&
              now.difference(_lastReadAt!) < _sameBadgeCooldown) {
            return;
          }

          _processingTag = true;
          _lastUid = uid;
          _lastReadAt = now;

          // Reader Mode reste actif : on peut enchaîner les badges
          // sans fermer l'écran et sans rendre le NTAG213 à Android.
          try {
            onRead(NfcReadResult(uid, 'Android'));
          } finally {
            // Très important : réarme immédiatement le lecteur
            // pour accepter le badge suivant.
            _processingTag = false;
          }
        } catch (e) {
          _processingTag = false;
          onError('Impossible de lire ce badge : $e');
        }
      },
    );
  }

  Future<void> _startIosSession({
    required void Function(NfcReadResult result) onRead,
    required void Function(String message) onError,
  }) async {
    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      alertMessageIos: 'Approchez le porte-clé Club MN NFC',
      invalidateAfterFirstReadIos: true,
      noPlatformSoundsAndroid: false,
      onSessionErrorIos: (error) {
        _running = false;
        _processingTag = false;
        _lastUid = null;

        onError('Lecture NFC interrompue : ${error.message}');
      },
      onDiscovered: (tag) async {
        if (_processingTag) return;

        try {
          final iosTag = MiFareIos.from(tag);

          if (iosTag == null) {
            await stop();
            onError('Tag NFC iOS non reconnu.');
            return;
          }

          _processingTag = true;

          final uid = _hex(iosTag.identifier);

          // iOS utilise sa propre session NFC système.
          await stop();

          onRead(NfcReadResult(uid, 'iOS'));
        } catch (e) {
          await stop();
          onError('Impossible de lire ce badge : $e');
        }
      },
    );
  }

  String _hex(Uint8List bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(':')
      .toUpperCase();
}
