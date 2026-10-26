import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Accès kDrive en lecture seule. Jeton API saisi sur le téléphone et
/// conservé dans le stockage sécurisé Android, jamais embarqué dans l’APK.
class InfomaniakKdriveService {
  static const clientId = 'b26bf66d-f586-43fb-b70c-120b1f98c58c';
  static const redirectUri = 'fr.montchanin.clubnage:/oauth2redirect';
  static const driveId = 3455819;
  static const folderCandidateId = 215;
  static const membersName = 'ClubNage_Base_licencies_26-27_V4.xlsx';
  static const scheduleName = 'ClubNage_Suivi_activite_26-27_V4.xlsx';

  static const _authorizationEndpoint = 'https://login.infomaniak.com/authorize';
  static const _tokenEndpoint = 'https://login.infomaniak.com/token';
  final FlutterAppAuth _auth = const FlutterAppAuth();
  static const _secureStorage = FlutterSecureStorage();
  static const _apiTokenKey = 'clubnage_kdrive_api_token_v72';
  String? _accessToken;

  /// Le jeton est lu uniquement dans le stockage chiffré du téléphone.
  Future<bool> restoreSavedApiToken() async {
    final token = await _secureStorage.read(key: _apiTokenKey);
    if (token == null || token.isEmpty) return false;
    _accessToken = token;
    return true;
  }

  /// Valide le jeton AVANT de le sauvegarder. Aucun secret dans l'APK.
  Future<Map<String, dynamic>> connectWithApiToken(String input) async {
    final token = input.trim();
    if (token.isEmpty || token.contains(RegExp(r'\s'))) {
      throw ArgumentError('Jeton API vide ou invalide.');
    }
    final previous = _accessToken;
    _accessToken = token;
    try {
      final folder = await verifyFolder();
      await _secureStorage.write(key: _apiTokenKey, value: token);
      return folder;
    } catch (_) {
      _accessToken = previous;
      rethrow;
    }
  }

  Future<void> forgetApiToken() async {
    await _secureStorage.delete(key: _apiTokenKey);
    _accessToken = null;
  }


  bool get isConnected => _accessToken != null;

  Future<void> connect() async {
    final response = await _auth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        redirectUri,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: _authorizationEndpoint,
          tokenEndpoint: _tokenEndpoint,
        ),
        scopes: const ['openid', 'profile'],
      ),
    );
    if (response.accessToken == null) {
      throw StateError('Connexion annulée ou jeton non reçu.');
    }
    _accessToken = response.accessToken;
  }

  void disconnect() => _accessToken = null;

  Future<http.Response> _get(Uri url) async {
    final token = _accessToken;
    if (token == null) throw StateError('Connectez-vous d’abord à Infomaniak.');
    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('API kDrive : HTTP ${response.statusCode} sur ${url.path}. '
          'Vérifier le jeton API et ses autorisations kDrive.');
    }
    return response;
  }

  Future<Map<String, dynamic>> _jsonGet(Uri uri) async {
    final response = await _get(uri);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['result'] != 'success') {
      throw StateError('Réponse inattendue de l’API kDrive.');
    }
    return decoded;
  }

  /// Vérifie l'identifiant de dossier issu de l'URL web, sans le supposer valide.
  Future<Map<String, dynamic>> verifyFolder() async {
    final result = await _jsonGet(Uri.https('api.infomaniak.com',
        '/3/drive/$driveId/files/$folderCandidateId'));
    final folder = result['data'];
    if (folder is! Map<String, dynamic> ||
        folder['name'] != 'Saison 2026-2027') {
      throw StateError('Le dossier 215 ne correspond pas à « Saison 2026-2027 ». '
          'Il faut récupérer son identifiant API réel.');
    }
    return folder;
  }

  /// Recherche d'abord le nom officiel du classeur, puis les variantes
  /// courantes ajoutées lors d'un doublon. Le suffixe (1) observé dans
  /// les Téléchargements macOS ne signifie PAS qu'il existe sur kDrive.
  /// La variante n'est essayée que si l'API confirme une absence (404).
  Future<int> _findFileId(String name) async {
    final dot = name.lastIndexOf('.');
    final variants = <String>[
      name,
      if (dot > 0) '${name.substring(0, dot)}(1)${name.substring(dot)}',
      if (dot > 0) '${name.substring(0, dot)} (1)${name.substring(dot)}',
    ];
    for (final candidate in variants) {
      final url = Uri.https('api.infomaniak.com',
          '/3/drive/$driveId/files/$folderCandidateId/name',
          {'name': candidate});
      final token = _accessToken;
      if (token == null) {
        throw StateError('Connectez-vous d’abord à Infomaniak.');
      }
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) continue;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Recherche kDrive : HTTP ${response.statusCode} '
            'pour $candidate. Vérifiez le jeton et les droits.');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['result'] != 'success') {
        throw StateError('Réponse inattendue lors de la recherche de $candidate.');
      }
      final data = decoded['data'];
      if (data is Map<String, dynamic> &&
          data['name'] == candidate && data['id'] is num) {
        return (data['id'] as num).toInt();
      }
      throw StateError('Réponse kDrive sans identifiant valide pour $candidate.');
    }
    throw StateError('Classeur absent du dossier kDrive : $name '
        '(noms officiels et variantes (1) vérifiés).');
  }

  /// Liste uniquement les noms des entrées ZIP (pas le contenu des licenciés).
  /// Permet de distinguer un vrai XLSX d'un ZIP contenant des XLSX.
  static List<String> zipEntryNames(Uint8List bytes) {
    final names = <String>[];
    int u16(int i) => bytes[i] | (bytes[i + 1] << 8);
    int u32(int i) => u16(i) | (u16(i + 2) << 16);
    var i = 0;
    while (i + 46 <= bytes.length) {
      if (bytes[i] == 0x50 && bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02) {
        final nameLength = u16(i + 28);
        final extraLength = u16(i + 30);
        final commentLength = u16(i + 32);
        final end = i + 46 + nameLength + extraLength + commentLength;
        if (end > bytes.length) break;
        try {
          names.add(utf8.decode(bytes.sublist(i + 46, i + 46 + nameLength)));
        } on FormatException {
          names.add('<nom ZIP non UTF-8>');
        }
        i = end;
      } else {
        i++;
      }
    }
    return names;
  }

  static String describeWorkbookPayload(Uint8List bytes, String contentType) {
    final zip = bytes.length >= 4 && bytes[0] == 0x50 &&
        bytes[1] == 0x4b && bytes[2] == 0x03 && bytes[3] == 0x04;
    if (!zip) {
      final looksJson = contentType.contains('json') ||
          (bytes.isNotEmpty && (bytes[0] == 0x7b || bytes[0] == 0x5b));
      return 'Réponse non XLSX : ${bytes.length} octets, type $contentType'
          '${looksJson ? ' (réponse JSON possible)' : ''}.';
    }
    final names = zipEntryNames(bytes);
    if (names.contains('[Content_Types].xml') &&
        names.contains('xl/workbook.xml')) {
      return 'XLSX reconnu : ${bytes.length} octets, type $contentType.';
    }
    final workbooks = names.where((n) => n.toLowerCase().endsWith('.xlsx')).toList();
    if (workbooks.isNotEmpty) {
      return 'Archive ZIP contenant ${workbooks.length} fichier(s) XLSX, '
          'pas un classeur XLSX direct (type $contentType).';
    }
    return 'Archive ZIP sans structure XLSX reconnue : '
        '${bytes.length} octets, type $contentType.';
  }

  Future<Uint8List> downloadWorkbook(String name, {
    void Function(String stage)? onProgress,
  }) async {
    if (name != membersName && name != scheduleName) {
      throw ArgumentError('Fichier non autorisé : $name');
    }
    onProgress?.call('1/4 Vérification du dossier kDrive');
    await verifyFolder();
    onProgress?.call('2/4 Recherche du fichier $name');
    final id = await _findFileId(name);
    onProgress?.call('3/4 Téléchargement du fichier $name (ID $id)');
    final url = Uri.https('api.infomaniak.com',
        '/2/drive/$driveId/files/$id/download');
    final response = await _get(url);
    final bytes = response.bodyBytes;
    final contentType = response.headers['content-type'] ?? 'non renseigné';
    final description = describeWorkbookPayload(bytes, contentType);
    onProgress?.call('4/4 Contrôle du format : $description');
    final names = zipEntryNames(bytes);
    if (!names.contains('[Content_Types].xml') ||
        !names.contains('xl/workbook.xml')) {
      throw FormatException('Téléchargement $name (ID $id) : $description');
    }
    return bytes;
  }
}
