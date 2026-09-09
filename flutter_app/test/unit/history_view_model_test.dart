import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/cloud_models.dart';
import 'package:look_whos_talking/models/conversation_record.dart';
import 'package:look_whos_talking/models/sync_summary.dart';
import 'package:look_whos_talking/services/cloud_storage_provider.dart';
import 'package:look_whos_talking/services/conversation_store.dart';
import 'package:look_whos_talking/services/sync_service.dart';
import 'package:look_whos_talking/view_models/history_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeCloud implements CloudStorageProvider {
  @override
  String get displayName => 'VM Cloud';
  bool authenticated = true;

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
    throw UnimplementedError();
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String folder) async => const [];

  @override
  Future<void> deleteFile(String remotePath) async {}
}

/// SyncService whose index + downloads are scripted and recorded.
class _ScriptedSync extends SyncService {
  _ScriptedSync(ConversationStore store, Directory docs, Directory tmp)
      : super(
          store: store,
          provider: _FakeCloud(),
          documentsDirProvider: () async => docs,
          tempDirProvider: () => tmp,
        );

  final List<String> downloadedIds = [];
  List<String> remoteIds = const [];

  @override
  Future<List<RemoteConversationMeta>> fetchRemoteIndex() async {
    return remoteIds
        .map(
          (id) => RemoteConversationMeta(
            id: id,
            filename: 'restored $id',
            createdAt: DateTime(2026, 9, 1),
            hasAudio: false,
          ),
        )
        .toList();
  }

  @override
  Future<void> downloadConversation(String remoteId) async {
    downloadedIds.add(remoteId);
    await store.save(
      ConversationRecord(
        id: remoteId,
        filename: 'restored $remoteId',
        createdAt: DateTime(2026, 9, 1),
        durationSec: 30,
        speakerCount: 2,
        resultJson: jsonEncode({'id': remoteId}),
        isSynced: true,
      ),
    );
  }
}

ConversationRecord rec(String id, {String? audioPath, DateTime? createdAt}) =>
    ConversationRecord(
      id: id,
      filename: 'call $id',
      createdAt: createdAt ?? DateTime(2026, 9, 1, 8),
      durationSec: 60,
      speakerCount: 2,
      resultJson: '{"id":"$id"}',
      audioPath: audioPath,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  late ConversationStore store;
  late Directory tempDir;
  late Directory docsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lwt_vm_test');
    docsDir = await Directory.systemTemp.createTemp('lwt_vm_docs');
    await Directory('${tempDir.path}/tmp').create();
    store = ConversationStore(
      factory: databaseFactoryFfi,
      dbPath: '${tempDir.path}/test.db',
    );
  });

  tearDown(() async {
    await store.close();
    await tempDir.delete(recursive: true);
    await docsDir.delete(recursive: true);
  });

  SyncService defaultSync() => SyncService(
        store: store,
        provider: _FakeCloud(),
        documentsDirProvider: () async => docsDir,
        tempDirProvider: () => Directory('${tempDir.path}/tmp'),
      );

  HistoryViewModel makeVm({SyncService? sync}) => HistoryViewModel(
        store: store,
        syncService: sync ?? defaultSync(),
      );

  group('load', () {
    test('empty store loads as loaded with no records', () async {
      final vm = makeVm();
      await vm.load();
      expect(vm.state, HistoryLoadState.loaded);
      expect(vm.records, isEmpty);
      expect(vm.error, isNull);
    });

    test('loads all records into state', () async {
      await store.save(rec('a'));
      await store.save(rec('b'));
      final vm = makeVm();
      await vm.load();
      expect(vm.records.map((r) => r.id).toSet(), {'a', 'b'});
      expect(vm.state, HistoryLoadState.loaded);
    });

    test('sets error state when the store throws', () async {
      final broken = ConversationStore(
        factory: databaseFactoryFfi,
        dbPath: '/nonexistent_dir_xyz/test.db',
      );
      final vm2 = HistoryViewModel(
        store: broken,
        syncService: SyncService(store: broken, provider: _FakeCloud()),
      );
      await vm2.load();
      expect(vm2.state, HistoryLoadState.error);
      expect(vm2.error, isNotNull);
      await broken.close();
    });
  });

  group('delete', () {
    test('deletes from store and removes from state', () async {
      final audio = File('${tempDir.path}/a.aac');
      await audio.writeAsBytes([1]);
      await store.save(rec('a', audioPath: audio.path));
      final vm = makeVm();
      await vm.load();

      await vm.delete('a');

      expect(vm.records, isEmpty);
      expect(await store.get('a'), isNull);
      expect(await audio.exists(), isFalse);
    });
  });

  group('deleteAudio', () {
    test('deletes file, nulls path in store, keeps record in state', () async {
      final audio = File('${tempDir.path}/a.aac');
      await audio.writeAsBytes([1, 2]);
      await store.save(rec('a', audioPath: audio.path));
      final vm = makeVm();
      await vm.load();

      await vm.deleteAudio('a');

      final fromStore = await store.get('a');
      expect(fromStore, isNotNull);
      expect(fromStore!.audioPath, isNull);
      expect(fromStore.resultJson, '{"id":"a"}');
      expect(await audio.exists(), isFalse);
      final inState = vm.records.singleWhere((r) => r.id == 'a');
      expect(inState.audioPath, isNull);
    });
  });

  group('syncAll', () {
    test('delegates to SyncService, stores summary, refreshes', () async {
      await store.save(rec('a'));
      final scripted = _ScriptedSync(
        store,
        docsDir,
        Directory('${tempDir.path}/tmp'),
      );
      final vm = HistoryViewModel(
        store: store,
        syncService: scripted,
      );

      final summary = await vm.syncAll();

      expect(summary, isA<SyncSummary>());
      expect(vm.lastSyncSummary, same(summary));
    });
  });

  group('restoreFromCloud', () {
    test('downloads only conversations missing locally', () async {
      await store.save(rec('local_only'));
      final scripted = _ScriptedSync(
        store,
        docsDir,
        Directory('${tempDir.path}/tmp'),
      )..remoteIds = const ['remote_1', 'remote_2'];
      final vm = HistoryViewModel(
        store: store,
        syncService: scripted,
      );

      await vm.restoreFromCloud();

      expect(scripted.downloadedIds, ['remote_1', 'remote_2']);
      expect(await store.get('remote_1'), isNotNull);
      expect(await store.get('remote_2'), isNotNull);
      expect(await store.get('local_only'), isNotNull);
    });

    test('does not re-download a conversation that exists locally', () async {
      await store.save(rec('both'));
      final scripted = _ScriptedSync(
        store,
        docsDir,
        Directory('${tempDir.path}/tmp'),
      )..remoteIds = const ['both', 'other'];
      final vm = HistoryViewModel(
        store: store,
        syncService: scripted,
      );

      await vm.restoreFromCloud();

      expect(scripted.downloadedIds, ['other']);
    });

    test('handles an empty remote index', () async {
      final vm = makeVm();
      await vm.restoreFromCloud();
      expect(await store.list(), isEmpty);
    });
  });
}
