import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/cloud_models.dart';
import 'package:look_whos_talking/models/conversation_record.dart';
import 'package:look_whos_talking/screens/history_screen.dart';
import 'package:look_whos_talking/screens/results_screen.dart';
import 'package:look_whos_talking/services/cloud_storage_provider.dart';
import 'package:look_whos_talking/services/conversation_store.dart';
import 'package:look_whos_talking/services/sync_service.dart';
import 'package:look_whos_talking/view_models/history_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Cloud implements CloudStorageProvider {
  @override
  String get displayName => 'Test Cloud';
  _Cloud({this.authenticated = true});
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

/// In-memory ConversationStore for widget tests. Real sqflite I/O cannot run
/// inside the fake-async test zone, and store behaviour is already covered by
/// its own unit tests — here we only exercise how the UI drives the store.
class _MemoryStore extends ConversationStore {
  _MemoryStore() : super(factory: databaseFactoryFfi);
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
      isSynced: record.isSynced,
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

  @override
  Future<void> close() async {}
}

String _minimalResultJson(String id) => jsonEncode({
      'filename': 'call $id',
      'total_duration_sec': 65.0,
      'speaker_count': 2,
      'speakers': [
        {'speaker_id': 'SPEAKER_00', 'duration_sec': 30.0, 'percentage': 46.0},
        {'speaker_id': 'SPEAKER_01', 'duration_sec': 35.0, 'percentage': 54.0},
      ],
      'overlap_sec': 0,
      'speech_sec': 65,
      'silence_sec': 0,
      'transcript': <Map<String, dynamic>>[],
    });

ConversationRecord rec(
  String id, {
  String? audioPath,
  bool isSynced = false,
  DateTime? createdAt,
}) =>
    ConversationRecord(
      id: id,
      filename: 'Team call $id',
      createdAt: createdAt ?? DateTime(2026, 9, 7, 10, 30),
      durationSec: 65.25,
      speakerCount: 2,
      resultJson: _minimalResultJson(id),
      audioPath: audioPath,
      isSynced: isSynced,
    );

void main() {
  late _MemoryStore store;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    store = _MemoryStore();
  });

  Future<void> pumpHistory(
    WidgetTester tester, {
    _Cloud? cloud,
  }) async {
    final sync = SyncService(
      store: store,
      provider: cloud ?? _Cloud(),
      documentsDirProvider: () async => throw UnimplementedError(),
      tempDirProvider: () => throw UnimplementedError(),
    );
    final vm = HistoryViewModel(store: store, syncService: sync);
    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when no conversations exist',
      (tester) async {
    await pumpHistory(tester);
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('renders one row per record with metadata icons',
      (tester) async {
    await store.save(rec('a', audioPath: '/audio/a.aac'));
    await store.save(rec('b', isSynced: true));

    // Not authenticated so the action bar (which uses the same icons) is
    // hidden and only the row icons are in the tree.
    await pumpHistory(tester, cloud: _Cloud(authenticated: false));

    expect(find.text('Team call a'), findsOneWidget);
    expect(find.text('Team call b'), findsOneWidget);
    // a is unsynced → cloud_upload; b is synced → cloud_done.
    expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    // Only a has audio (graphic_eq); b shows music_off.
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expect(find.byIcon(Icons.music_off), findsOneWidget);
    // Subtitle includes duration + speaker count.
    expect(find.textContaining('1m 5s'), findsNWidgets(2));
    expect(find.textContaining('2 speakers'), findsNWidgets(2));
  });

  testWidgets('shows sync + restore buttons when authenticated and unsynced '
      'records exist', (tester) async {
    await store.save(rec('a'));
    await pumpHistory(tester, cloud: _Cloud(authenticated: true));

    expect(find.text('Sync all'), findsOneWidget);
    expect(find.text('Restore from cloud'), findsOneWidget);
  });

  testWidgets('hides sync/restore buttons when not authenticated',
      (tester) async {
    await store.save(rec('a'));
    await pumpHistory(tester, cloud: _Cloud(authenticated: false));

    expect(find.text('Sync all'), findsNothing);
    expect(find.text('Restore from cloud'), findsNothing);
  });

  testWidgets('shows Sync all even when everything is already synced '
      '(re-sync available)', (tester) async {
    await store.save(rec('a', isSynced: true));
    await pumpHistory(tester, cloud: _Cloud(authenticated: true));

    expect(find.text('Sync all'), findsOneWidget);
    expect(find.text('Restore from cloud'), findsOneWidget);
  });

  testWidgets('tapping a row navigates to Results screen', (tester) async {
    await store.save(rec('a'));
    await pumpHistory(tester);

    await tester.tap(find.text('Team call a'));
    await tester.pumpAndSettle();

    expect(find.byType(ResultsScreen), findsOneWidget);
  });

  testWidgets('swipe-to-delete asks for confirmation; cancel keeps the row',
      (tester) async {
    await store.save(rec('a'));
    await pumpHistory(tester);

    await tester.drag(find.text('Team call a'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete conversation?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Team call a'), findsOneWidget);
    expect(await store.get('a'), isNotNull);
  });

  testWidgets('swipe-to-delete removes the record when confirmed',
      (tester) async {
    await store.save(rec('a', audioPath: '/audio/a.aac'));
    await pumpHistory(tester);

    await tester.drag(find.text('Team call a'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Team call a'), findsNothing);
    expect(await store.get('a'), isNull);
  });

  testWidgets('long-press menu deletes audio only, keeping the record',
      (tester) async {
    await store.save(rec('a', audioPath: '/audio/a.aac'));
    await pumpHistory(tester);

    await tester.longPress(find.text('Team call a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete audio only'));
    await tester.pumpAndSettle();

    final stored = await store.get('a');
    expect(stored, isNotNull);
    expect(stored!.audioPath, isNull);
    // Row still present, now without the audio icon.
    expect(find.text('Team call a'), findsOneWidget);
    expect(find.byIcon(Icons.music_off), findsOneWidget);
  });

  testWidgets('select mode shows checkboxes and a live selected count',
      (tester) async {
    await store.save(rec('a'));
    await store.save(rec('b'));
    await pumpHistory(tester, cloud: _Cloud(authenticated: true));

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.text('Team call a'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Sync selected (1)'), findsOneWidget);
  });

  testWidgets('long-press delete offers remove-from-cloud for a synced row',
      (tester) async {
    await store.save(rec('a', isSynced: true));
    await pumpHistory(tester, cloud: _Cloud(authenticated: true));

    await tester.longPress(find.text('Team call a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();

    expect(find.text('Delete & remove from cloud'), findsOneWidget);
    expect(find.text('Delete (local)'), findsOneWidget);
  });

  testWidgets('delete selected removes exactly the selected conversations',
      (tester) async {
    await store.save(rec('a'));
    await store.save(rec('b'));
    await store.save(rec('c'));
    await pumpHistory(tester, cloud: _Cloud(authenticated: true));

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team call a'));
    await tester.tap(find.text('Team call b'));
    await tester.pumpAndSettle();
    expect(find.text('Delete selected (2)'), findsOneWidget);

    await tester.tap(find.text('Delete selected (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 conversation(s)?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await store.get('a'), isNull);
    expect(await store.get('b'), isNull);
    expect(await store.get('c'), isNotNull, reason: 'unselected row survives');
  });

  testWidgets('bulk delete offers the cloud option when a selected row is '
      'synced', (tester) async {
    await store.save(rec('a', isSynced: true));
    await store.save(rec('b'));
    await pumpHistory(tester, cloud: _Cloud(authenticated: true));

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team call a'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete selected (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Delete & remove from cloud'), findsOneWidget);
    expect(find.text('Delete (local)'), findsOneWidget);
  });
}
