import '../models/cloud_models.dart';
import 'cloud_storage_provider.dart';

/// One entry returned by listing a Drive folder.
class DriveEntry {
  final String id;
  final String name;
  final bool isFolder;
  final int? sizeBytes;
  final DateTime? modifiedAt;

  const DriveEntry({
    required this.id,
    required this.name,
    required this.isFolder,
    this.sizeBytes,
    this.modifiedAt,
  });
}

/// Thin seam over the real Drive backend.
///
/// GoogleDriveProvider owns all path/overwrite logic and talks to Drive only
/// through this interface, so that logic is testable without a live account.
abstract class DriveGateway {
  /// Id of the folder named [name] under [parentId] (null = root), or null.
  Future<String?> findFolder({required String name, String? parentId});

  /// Creates a folder named [name] under [parentId] (null = root) and returns
  /// its id.
  Future<String> createFolder({required String name, String? parentId});

  /// Id of the file named [name] directly inside [parentId], or null.
  Future<String?> findFile({required String name, required String parentId});

  /// Uploads [localPath] as a new file named [name] inside [parentId].
  Future<void> uploadNew({
    required String parentId,
    required String name,
    required String localPath,
  });

  /// Replaces the content of the existing file [fileId] with [localPath].
  Future<void> overwrite({
    required String fileId,
    required String localPath,
  });

  /// Downloads the file [fileId] to [localPath].
  Future<void> downloadToFile({
    required String fileId,
    required String localPath,
  });

  /// Lists the entries directly inside [folderId].
  Future<List<DriveEntry>> listChildren({required String folderId});

  /// Deletes the entry [fileId]. No-op if it no longer exists.
  Future<void> deleteById({required String fileId});
}

/// Thin seam over the sign-in/token machinery, so auth state can be faked.
abstract class AuthGateway {
  Future<void> authenticate();
  Future<bool> isAuthenticated();
  Future<void> signOut();
}

/// CloudStorageProvider implementation for Google Drive.
///
/// Remote paths are relative to the app folder root (e.g.
/// "conversations/abc123/result.json"). Intermediate folders are created on
/// demand; re-uploading a path whose file already exists overwrites that file
/// rather than creating a duplicate.
class GoogleDriveProvider implements CloudStorageProvider {
  GoogleDriveProvider({
    required this.gateway,
    required this.auth,
    // No apostrophe: Drive `q` queries can't escape a quote inside a name
    // search, so "Look Who's Talking" would break every folder lookup (400).
    this.appFolderName = "Look Whos Talking",
  });

  final DriveGateway gateway;
  final AuthGateway auth;
  final String appFolderName;

  String? appFolderId;

  @override
  String get displayName => 'Google Drive';

  @override
  Future<void> authenticate() => auth.authenticate();

  @override
  Future<bool> isAuthenticated() => auth.isAuthenticated();

  @override
  Future<void> signOut() => auth.signOut();

  // Resolves (creating as needed) the folder named [name] directly under
  // [parentId], returning its id. Always asks the gateway — never relies on a
  // stale cached id.
  Future<String> _ensureFolder({required String name, String? parentId}) async {
    final existing =
        await gateway.findFolder(name: name, parentId: parentId);
    if (existing != null) return existing;
    return gateway.createFolder(name: name, parentId: parentId);
  }

  Future<String> _appFolder() async {
    final cached = appFolderId;
    if (cached != null) {
      // Verify the cached id still exists so a sign-out/re-auth on a new
      // account does not upload into a stale folder.
      final fresh =
          await gateway.findFolder(name: appFolderName, parentId: null);
      if (fresh != null) {
        if (fresh != cached) appFolderId = fresh;
        return fresh;
      }
    }
    final id = await _ensureFolder(name: appFolderName, parentId: null);
    appFolderId = id;
    return id;
  }

  // Walks [relativePath] (no leading/trailing slash, "" = app folder root),
  // creating folders as needed. Returns (folderId, fileName).
  Future<(String, String?)> _resolveOrCreate(String relativePath) async {
    final app = await _appFolder();
    final segments = _splitPath(relativePath);
    if (segments.isEmpty) return (app, null);

    String current = app;
    for (final segment in segments.take(segments.length - 1)) {
      current = await _ensureFolder(name: segment, parentId: current);
    }
    return (current, segments.last);
  }

  // Walks [relativePath] without creating anything. Returns the file entry id
  // (or folder id if [wantFolder] is set and the path names a folder), or null.
  Future<String?> _resolveExisting(
    String relativePath, {
    bool folderOnly = false,
  }) async {
    final app = await _appFolder();
    final segments = _splitPath(relativePath);
    if (segments.isEmpty) {
      return folderOnly ? app : null;
    }

    String? current = app;
    for (var i = 0; i < segments.length - 1; i++) {
      current = await gateway.findFolder(
        name: segments[i],
        parentId: current,
      );
      if (current == null) return null;
    }
    final last = segments.last;
    if (folderOnly) {
      return gateway.findFolder(name: last, parentId: current);
    }
    return gateway.findFile(name: last, parentId: current!);
  }

  @override
  Future<void> upload(String localPath, String remotePath) async {
    final normalized = _normalisePath(remotePath);
    final (folderId, fileName) = await _resolveOrCreate(normalized);
    if (fileName == null) {
      throw StorageException('remotePath is a folder, not a file: $remotePath');
    }

    final existing = await gateway.findFile(
      name: fileName,
      parentId: folderId,
    );
    if (existing != null) {
      await gateway.overwrite(fileId: existing, localPath: localPath);
    } else {
      await gateway.uploadNew(
        parentId: folderId,
        name: fileName,
        localPath: localPath,
      );
    }
  }

  @override
  Future<void> download(String remotePath, String localPath) async {
    final fileId = await _resolveExisting(_normalisePath(remotePath));
    if (fileId == null) {
      throw StorageException('remote file not found: $remotePath');
    }
    await gateway.downloadToFile(fileId: fileId, localPath: localPath);
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String folder) async {
    final folderId =
        await _resolveExisting(_normalisePath(folder), folderOnly: true);
    if (folderId == null) return const [];

    final children = await gateway.listChildren(folderId: folderId);
    return children
        .map(
          (e) => RemoteFileInfo(
            remotePath: '${_normalisePath(folder)}/${e.name}',
            filename: e.name,
            sizeBytes: e.sizeBytes ?? 0,
            modifiedAt: e.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList();
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    final normalized = _normalisePath(remotePath);
    // Files are the common case.
    final fileId = await _resolveExisting(normalized);
    if (fileId != null) {
      await gateway.deleteById(fileId: fileId);
      return;
    }
    // Otherwise the path may name a folder (e.g. an emptied conversation
    // folder being pruned after its files were deleted).
    final folderId = await _resolveExisting(normalized, folderOnly: true);
    if (folderId == null) return; // idempotent — nothing to delete
    await gateway.deleteById(fileId: folderId);
  }

  /// Splits a normalised relative path into segments.
  static List<String> _splitPath(String path) {
    if (path.isEmpty) return const [];
    return path.split('/');
  }

  // Strips leading/trailing slashes and collapses empty segments.
  static String _normalisePath(String path) {
    return path
        .split('/')
        .where((s) => s.isNotEmpty)
        .join('/');
  }
}
