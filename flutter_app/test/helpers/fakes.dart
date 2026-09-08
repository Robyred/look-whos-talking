// Shared fakes for widget tests: an in-memory ConversationStore and an inert
// CloudStorageProvider. Real sqflite I/O cannot run inside the fake-async
// testWidgets zone, and store/cloud behaviour is covered by their own unit
// tests — these fakes only let widgets drive the UI wiring.
import 'package:look_whos_talking/models/cloud_models.dart';
import 'package:look_whos_talking/models/conversation_record.dart';
import 'package:look_whos_talking/services/cloud_storage_provider.dart';
import 'package:look_whos_talking/services/conversation_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeCloud implements CloudStorageProvider {
  FakeCloud({this.authenticated = false});
  bool authenticated;

  @override
  Future<void> authenticate() async => authenticated = true;
  @override
  Future<bool> isAuthenticated() async => authenticated;
  @override
  Future<void> signOut() async => authenticated = false;
  @override
  Future<void> upload(String localPath, String remotePath) async {}
  @override
  Future<void> download(String remotePath, String localPath) async {
    throw const StorageException('nope');
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String folder) async => const [];
  @override
  Future<void> deleteFile(String remotePath) async {}
}

class MemoryStore extends ConversationStore {
  MemoryStore() : super(factory: databaseFactoryFfi);

  final Map<String, ConversationRecord> _records = {};

  @override
  Future<void> save(ConversationRecord record) async {
    _records[record.id] = record;
  }

  @override
  Future<List<ConversationRecord>> list() async {
    final values = _records.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return values;
  }

  @override
  Future<ConversationRecord?> get(String id) async => _records[id];

  @override
  Future<void> deleteAudio(String id) async {
    final record = _records[id];
    if (record == null) return;
    _records[id] = ConversationRecord(
      id: record.id,
      filename: record.filename,
      createdAt: record.createdAt,
      durationSec: record.durationSec,
      speakerCount: record.speakerCount,
      resultJson: record.resultJson,
      // audioPath deliberately omitted — audio is gone.
    );
  }

  @override
  Future<void> delete(String id) async {
    _records.remove(id);
  }

  @override
  Future<void> markSynced(String id) async {
    final record = _records[id];
    if (record == null) return;
    _records[id] = ConversationRecord(
      id: record.id,
      filename: record.filename,
      createdAt: record.createdAt,
      durationSec: record.durationSec,
      speakerCount: record.speakerCount,
      resultJson: record.resultJson,
      audioPath: record.audioPath,
      isSynced: true,
    );
  }
}
