import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/cloud_models.dart';
import 'cloud_storage_provider.dart';
import 'oauth2.dart';

// ── App registration constants ────────────────────────────────────────────────
const _dbAppKey = 'ypxmmh1ye0mzpby';
const _dbRedirectUrl = 'db-ypxmmh1ye0mzpby://2/token';
const _dbScopes = [
  'files.content.write',
  'files.content.read',
  'account_info.read',
];
const _dbTokenKey = 'dropbox_refresh_token';
const _dbAuthEndpoint = 'https://www.dropbox.com/oauth2/authorize';
const _dbTokenEndpoint = 'https://api.dropboxapi.com/oauth2/token';
const _dbUploadUrl = 'https://content.dropboxapi.com/2/files/upload';
const _dbDownloadUrl = 'https://content.dropboxapi.com/2/files/download';
const _dbListUrl = 'https://api.dropboxapi.com/2/files/list_folder';
const _dbDeleteUrl = 'https://api.dropboxapi.com/2/files/delete_v2';

/// CloudStorageProvider for Dropbox (App folder access).
///
/// With app-folder access type the app's folder root is the API root: every
/// path here is relative to /Apps/Look Who's Talking/ in the user's Dropbox.
class DropboxProvider implements CloudStorageProvider {
  DropboxProvider({
    http.Client? client,
    TokenBroker? broker,
    TokenStore? tokenStore,
  })  : _client = client ?? http.Client(),
        _broker = broker ?? const FlutterAppAuthBroker(),
        _tokens = tokenStore ?? const SecureTokenStore();

  final http.Client _client;
  final TokenBroker _broker;
  final TokenStore _tokens;
  String? _accessToken;

  @override
  String get displayName => 'Dropbox';

  Map<String, String> _authHeaders({String? contentType}) => {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': ?contentType,
      };

  @override
  Future<void> authenticate() async {
    // Dropbox only issues a refresh token when token_access_type=offline is
    // requested at authorization time.
    final result = await _broker.exchangeCode(
      clientId: _dbAppKey,
      redirectUrl: _dbRedirectUrl,
      authorizationEndpoint: _dbAuthEndpoint,
      tokenEndpoint: _dbTokenEndpoint,
      scopes: _dbScopes,
      additionalParameters: const {'token_access_type': 'offline'},
    );
    _accessToken = result.accessToken;
    final refresh = result.refreshToken;
    if (refresh != null) {
      await _tokens.write(key: _dbTokenKey, value: refresh);
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    if (_accessToken != null) return true;
    final refresh = await _tokens.read(key: _dbTokenKey);
    if (refresh == null) return false;
    return _silentRefresh(refresh);
  }

  Future<bool> _silentRefresh(String refreshToken) async {
    try {
      final result = await _broker.refreshToken(
        clientId: _dbAppKey,
        redirectUrl: _dbRedirectUrl,
        tokenEndpoint: _dbTokenEndpoint,
        scopes: _dbScopes,
        refreshToken: refreshToken,
      );
      _accessToken = result.accessToken;
      final refresh = result.refreshToken;
      if (refresh != null) {
        await _tokens.write(key: _dbTokenKey, value: refresh);
      }
      return _accessToken != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    _accessToken = null;
    await _tokens.delete(key: _dbTokenKey);
  }

  @override
  Future<void> upload(String localPath, String remotePath) async {
    final filename = remotePath.split('/').last;
    final arg = jsonEncode({
      'path': '/$filename',
      'mode': 'overwrite', // same semantics as GoogleDriveProvider
      'autorename': false,
      'mute': true,
    });
    final bytes = await File(localPath).readAsBytes();
    final resp = await _client.post(
      Uri.parse(_dbUploadUrl),
      headers: {
        ..._authHeaders(contentType: 'application/octet-stream'),
        'Dropbox-API-Arg': arg,
      },
      body: bytes,
    );
    _checkDropbox(resp);
  }

  @override
  Future<void> download(String remotePath, String localPath) async {
    final filename = remotePath.split('/').last;
    final arg = jsonEncode({'path': '/$filename'});
    final resp = await _client.post(
      Uri.parse(_dbDownloadUrl),
      headers: {
        ..._authHeaders(),
        'Dropbox-API-Arg': arg,
      },
    );
    if (resp.statusCode != 200) {
      throw StorageException('Dropbox download failed: ${resp.statusCode}');
    }
    await File(localPath).writeAsBytes(resp.bodyBytes);
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String folder) async {
    final resp = await _client.post(
      Uri.parse(_dbListUrl),
      headers: _authHeaders(contentType: 'application/json'),
      body: jsonEncode({'path': '', 'recursive': false}),
    );
    _checkDropbox(resp);
    final entries = (jsonDecode(resp.body)['entries'] as List)
        .cast<Map<String, dynamic>>();
    return entries
        .where((e) => e['.tag'] == 'file')
        .map(
          (e) => RemoteFileInfo(
            remotePath: e['path_lower'] as String,
            filename: e['name'] as String,
            sizeBytes: e['size'] as int? ?? 0,
            modifiedAt: DateTime.parse(e['server_modified'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    final filename = remotePath.split('/').last;
    final resp = await _client.post(
      Uri.parse(_dbDeleteUrl),
      headers: _authHeaders(contentType: 'application/json'),
      body: jsonEncode({'path': '/$filename'}),
    );
    // 409 path_not_found → already deleted → idempotent no-op.
    if (resp.statusCode != 200 && resp.statusCode != 409) {
      _checkDropbox(resp);
    }
  }

  void _checkDropbox(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StorageException('Dropbox API ${r.statusCode}: ${r.body}');
    }
  }
}
