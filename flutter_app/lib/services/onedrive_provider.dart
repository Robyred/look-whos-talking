import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/cloud_models.dart';
import 'cloud_storage_provider.dart';
import 'oauth2.dart';

// ── App registration constants ────────────────────────────────────────────────
const _odClientId = '85bd1269-8a45-47a1-93e5-6394edf7fd6b';
const _odRedirectUrl =
    'lookwhostalking://auth';
const _odScopes = ['Files.ReadWrite.AppFolder', 'offline_access'];
const _odAppFolder = 'Look Who\'s Talking';
const _odTokenKey = 'onedrive_refresh_token';
const _odAuthEndpoint =
    'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
const _odTokenEndpoint =
    'https://login.microsoftonline.com/common/oauth2/v2.0/token';
const _odGraphBase =
    'https://graph.microsoft.com/v1.0/me/drive/special/approot:/$_odAppFolder';

/// CloudStorageProvider for OneDrive (Microsoft Graph, Files.ReadWrite.AppFolder).
///
/// All paths are relative to the dedicated app-root folder that Graph creates
/// for this app. Uploads use createUploadSession so any file size works.
class OneDriveProvider implements CloudStorageProvider {
  OneDriveProvider({
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
  String get displayName => 'OneDrive';

  String _base(String filename) => '$_odGraphBase/$filename';

  Map<String, String> _authHeaders() =>
      {'Authorization': 'Bearer $_accessToken'};

  @override
  Future<void> authenticate() async {
    final result = await _broker.exchangeCode(
      clientId: _odClientId,
      redirectUrl: _odRedirectUrl,
      authorizationEndpoint: _odAuthEndpoint,
      tokenEndpoint: _odTokenEndpoint,
      scopes: _odScopes,
    );
    _accessToken = result.accessToken;
    final refresh = result.refreshToken;
    if (refresh != null) {
      await _tokens.write(key: _odTokenKey, value: refresh);
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    if (_accessToken != null) return true;
    final refresh = await _tokens.read(key: _odTokenKey);
    if (refresh == null) return false;
    return _silentRefresh(refresh);
  }

  Future<bool> _silentRefresh(String refreshToken) async {
    try {
      final result = await _broker.refreshToken(
        clientId: _odClientId,
        redirectUrl: _odRedirectUrl,
        tokenEndpoint: _odTokenEndpoint,
        scopes: _odScopes,
        refreshToken: refreshToken,
      );
      _accessToken = result.accessToken;
      final refresh = result.refreshToken;
      if (refresh != null) {
        await _tokens.write(key: _odTokenKey, value: refresh);
      }
      return _accessToken != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    _accessToken = null;
    await _tokens.delete(key: _odTokenKey);
  }

  @override
  Future<void> upload(String localPath, String remotePath) async {
    final filename = remotePath.split('/').last;
    final sessionResp = await _client.post(
      Uri.parse('$_odGraphBase/$filename:/createUploadSession'),
      headers: {
        ..._authHeaders(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'item': {'@microsoft.graph.conflictBehavior': 'replace'}
      }),
    );
    _checkGraph(sessionResp);
    final uploadUrl =
        (jsonDecode(sessionResp.body) as Map)['uploadUrl'] as String;

    final bytes = await File(localPath).readAsBytes();
    final uploadResp = await _client.put(
      Uri.parse(uploadUrl),
      headers: {
        'Content-Length': '${bytes.length}',
        'Content-Range': 'bytes 0-${bytes.length - 1}/${bytes.length}',
      },
      body: bytes,
    );
    if (uploadResp.statusCode != 200 && uploadResp.statusCode != 201) {
      throw StorageException(
          'OneDrive upload failed: ${uploadResp.statusCode}');
    }
  }

  @override
  Future<void> download(String remotePath, String localPath) async {
    final filename = remotePath.split('/').last;
    final metaResp = await _client.get(
      Uri.parse(_base(filename)),
      headers: _authHeaders(),
    );
    _checkGraph(metaResp);
    final downloadUrl =
        (jsonDecode(metaResp.body) as Map)['@microsoft.graph.downloadUrl']
            as String;
    final contentResp = await _client.get(Uri.parse(downloadUrl));
    if (contentResp.statusCode != 200) {
      throw StorageException(
          'OneDrive download failed: ${contentResp.statusCode}');
    }
    await File(localPath).writeAsBytes(contentResp.bodyBytes);
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String folder) async {
    final resp = await _client.get(
      Uri.parse('$_odGraphBase/children'),
      headers: _authHeaders(),
    );
    _checkGraph(resp);
    final items = (jsonDecode(resp.body)['value'] as List)
        .cast<Map<String, dynamic>>();
    return items
        .map(
          (item) => RemoteFileInfo(
            remotePath: '$_odAppFolder/${item['name']}',
            filename: item['name'] as String,
            sizeBytes: item['size'] as int? ?? 0,
            modifiedAt: DateTime.parse(item['lastModifiedDateTime'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    final filename = remotePath.split('/').last;
    final resp = await _client.delete(
      Uri.parse(_base(filename)),
      headers: _authHeaders(),
    );
    // 404 → already deleted → idempotent no-op.
    if (resp.statusCode != 204 && resp.statusCode != 404) {
      throw StorageException(
          'OneDrive delete failed: ${resp.statusCode}');
    }
  }

  void _checkGraph(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StorageException('Graph API ${r.statusCode}: ${r.body}');
    }
  }
}
