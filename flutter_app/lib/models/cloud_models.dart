// Metadata for a file stored in the user's cloud storage.

class RemoteFileInfo {
  final String remotePath;
  final String filename;
  final int sizeBytes;
  final DateTime modifiedAt;

  const RemoteFileInfo({
    required this.remotePath,
    required this.filename,
    required this.sizeBytes,
    required this.modifiedAt,
  });
}

// One conversation as seen in the remote app folder — used to restore history
// on a new device.
class RemoteConversationMeta {
  final String id;
  // The remote folder name (e.g. my-interview_<uuid>) — used to build cloud
  // paths. The id above may differ for legacy folders (uuid extracted).
  final String remoteDir;
  final String filename;
  final DateTime createdAt;
  final bool hasAudio;

  const RemoteConversationMeta({
    required this.id,
    required this.remoteDir,
    required this.filename,
    required this.createdAt,
    required this.hasAudio,
  });
}
