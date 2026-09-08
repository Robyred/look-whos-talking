import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'google_drive_provider.dart';

/// Real [DriveGateway] over Google's generated Drive v3 client.
///
/// Wire format and media handling belong to googleapis; this adapter only maps
/// our narrow operations onto it. Needs a live authenticated client (see
/// google_drive_services.dart) — verify on a device, not in unit tests.
class GoogleDriveGatewayImpl implements DriveGateway {
  GoogleDriveGatewayImpl(this._api);

  static const _folderMimeType = 'application/vnd.google-apps.folder';

  final drive.DriveApi _api;

  String _parentClause(String? parentId) =>
      "'${parentId ?? 'root'}' in parents";

  @override
  Future<String?> findFolder({required String name, String? parentId}) async {
    final q = "name = '$name' and mimeType = '$_folderMimeType' "
        "and ${_parentClause(parentId)} and trashed = false";
    final result = await _api.files.list(q: q, spaces: 'drive');
    final files = result.files ?? const [];
    if (files.isEmpty) return null;
    return files.first.id;
  }

  @override
  Future<String> createFolder({required String name, String? parentId}) async {
    final file = await _api.files.create(
      drive.File(
        name: name,
        mimeType: _folderMimeType,
        parents: [parentId ?? 'root'],
      ),
    );
    return file.id!;
  }

  @override
  Future<String?> findFile({required String name, required String parentId}) async {
    final q = "name = '$name' and '$parentId' in parents and trashed = false";
    final result = await _api.files.list(
      q: q,
      spaces: 'drive',
    );
    final files = result.files ?? const [];
    if (files.isEmpty) return null;
    return files.first.id;
  }

  @override
  Future<void> uploadNew({
    required String parentId,
    required String name,
    required String localPath,
  }) async {
    final bytes = await File(localPath).readAsBytes();
    await _api.files.create(
      drive.File(name: name, parents: [parentId]),
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
    );
  }

  @override
  Future<void> overwrite({
    required String fileId,
    required String localPath,
  }) async {
    final bytes = await File(localPath).readAsBytes();
    await _api.files.update(
      drive.File(),
      fileId,
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
    );
  }

  @override
  Future<void> downloadToFile({
    required String fileId,
    required String localPath,
  }) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final sink = File(localPath).openWrite();
    try {
      await sink.addStream(media.stream);
    } finally {
      await sink.close();
    }
  }

  @override
  Future<List<DriveEntry>> listChildren({required String folderId}) async {
    final result = await _api.files.list(
      q: "'$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    final files = result.files ?? const [];
    return files
        .map(
          (f) => DriveEntry(
            id: f.id!,
            name: f.name ?? '',
            isFolder: f.mimeType == _folderMimeType,
            sizeBytes: f.size == null ? null : int.tryParse(f.size!),
            modifiedAt: f.modifiedTime,
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteById({required String fileId}) async {
    await _api.files.delete(fileId);
  }
}

/// Adds the Authorization header from [headersProvider] to every request.
///
/// googleapis has no auth layer of its own — the authenticated http.Client is
/// the standard seam.
class AuthHeaderClient extends http.BaseClient {
  AuthHeaderClient(this._inner, this._headersProvider);

  final http.Client _inner;
  final Future<Map<String, String>?> Function() _headersProvider;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await _headersProvider();
    if (headers != null) {
      request.headers.addAll(headers);
    }
    return _inner.send(request);
  }
}
