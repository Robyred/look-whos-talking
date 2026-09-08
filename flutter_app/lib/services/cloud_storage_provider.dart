import '../models/cloud_models.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}

class StorageException implements Exception {
  final String message;
  const StorageException(this.message);
  @override
  String toString() => 'StorageException: $message';
}

/// Abstract cloud backend for conversation backups.
///
/// Google Drive is the first implementation; Dropbox or others can plug in by
/// implementing this same interface.
abstract class CloudStorageProvider {
  // Triggers the OAuth2 flow and stores the token securely.
  // Throws [AuthException] if the user cancels or auth fails.
  Future<void> authenticate();

  // True when a valid (non-expired) token exists.
  Future<bool> isAuthenticated();

  // Revokes the token and clears local credentials.
  Future<void> signOut();

  // Uploads the file at [localPath] to [remotePath] inside the app folder.
  // Overwrites if the remote file already exists.
  // Throws [StorageException] on failure.
  Future<void> upload(String localPath, String remotePath);

  // Downloads the remote file at [remotePath] to [localPath].
  // Throws [StorageException] if the remote file is not found.
  Future<void> download(String remotePath, String localPath);

  // Metadata for all entries (files and folders) directly inside [folder].
  // Returns an empty list when the folder does not exist.
  Future<List<RemoteFileInfo>> listFiles(String folder);

  // Deletes the entry at [remotePath]. No-op when it does not exist.
  Future<void> deleteFile(String remotePath);
}
