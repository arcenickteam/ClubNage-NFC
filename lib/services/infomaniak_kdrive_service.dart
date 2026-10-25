import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

/// Connexion OAuth2 mobile (PKCE via AppAuth), sans secret embarqué.
/// Les appels kDrive sont exclusivement des GET (lecture seule).
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
  String? _accessToken;

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
        scopes: const ['drive'],
      ),
    );
    if (response?.accessToken == null) {
      throw StateError('Connexion annulée ou jeton non reçu.');
    }
    _accessToken = response!.accessToken;
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
          'Vérifier les droits du dossier partagé et le scope drive.');
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

  Future<int> _findFileId(String name) async {
    final result = await _jsonGet(Uri.https('api.infomaniak.com',
        '/3/drive/$driveId/files/$folderCandidateId/name', {'name': name}));
    final data = result['data'];
    if (data is! Map<String, dynamic> || data['name'] != name || data['id'] is! num) {
      throw StateError('Fichier introuvable ou nom différent : $name');
    }
    return (data['id'] as num).toInt();
  }

  Future<Uint8List> downloadWorkbook(String name) async {
    if (name != membersName && name != scheduleName) {
      throw ArgumentError('Fichier non autorisé : $name');
    }
    await verifyFolder();
    final id = await _findFileId(name);
    // Route binaire kDrive v2. Le test sur le compte réel doit confirmer
    // qu'elle est accessible aux bénéficiaires du partage externe.
    final url = Uri.https('api.infomaniak.com',
        '/2/drive/$driveId/files/$id/download');
    final response = await _get(url);
    final bytes = response.bodyBytes;
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
      throw StateError('Le téléchargement ne contient pas un classeur XLSX valide.');
    }
    return bytes;
  }
}
