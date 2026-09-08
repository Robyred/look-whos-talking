import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/models/conversation_record.dart';
import 'package:look_whos_talking/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

void main() {
  MemoryStore storeWithOldRecording() {
    final store = MemoryStore();
    // Body runs synchronously (no awaits) — record is present immediately.
    store.save(
      ConversationRecord(
        id: 'job_old',
        filename: 'board meeting.m4a',
        createdAt: DateTime.now().subtract(const Duration(days: 100)),
        durationSec: 300,
        speakerCount: 3,
        resultJson: '{"speaker_count":3}',
        audioPath: '/tmp/board-meeting.m4a',
      ),
    );
    return store;
  }

  Widget home(MemoryStore store, {FakeCloud? cloud}) =>
      MaterialApp(home: HomeScreen(store: store, cloud: cloud ?? FakeCloud()));

  // The cleanup check and the dialog actions touch shared_preferences, whose
  // mock still resolves through real-async platform channels. Run those turns
  // inside tester.runAsync (real event loop), then settle the UI normally.
  Future<void> pumpHome(WidgetTester tester, Widget widget) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  // Simulates a fresh app launch: unmount everything first (pumping the same
  // widget type would otherwise reuse the existing HomeScreen state and never
  // re-run its initState cleanup check).
  Future<void> relaunch(WidgetTester tester, MemoryStore store) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await pumpHome(tester, home(store));
  }

  testWidgets('renders the record and upload actions plus a History entry',
      (tester) async {
    await pumpHome(tester, home(MemoryStore()));

    expect(find.text('Record Audio'), findsOneWidget);
    expect(find.text('Upload File'), findsOneWidget);
    expect(find.byIcon(Icons.history), findsOneWidget);
  });

  testWidgets('History icon pushes the History screen', (tester) async {
    await pumpHome(tester, home(MemoryStore()));

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget); // History screen AppBar
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('cleanup prompt appears when an old recording has audio',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = storeWithOldRecording();

    await pumpHome(tester, home(store));

    expect(find.text('Free up storage?'), findsOneWidget);
    expect(
      find.textContaining('recording(s) older than 90 days'),
      findsOneWidget,
    );
    expect(find.text('Delete audio'), findsOneWidget);
    expect(find.text('Keep for now'), findsOneWidget);
    expect(find.text('Remind me later'), findsOneWidget);
  });

  testWidgets('no prompt when every recording is recent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = MemoryStore();
    store.save(
      ConversationRecord(
        id: 'job_new',
        filename: 'today.m4a',
        createdAt: DateTime.now(),
        durationSec: 10,
        speakerCount: 1,
        resultJson: '{}',
        audioPath: '/tmp/today.m4a',
      ),
    );

    await pumpHome(tester, home(store));

    expect(find.text('Free up storage?'), findsNothing);
  });

  testWidgets('"Keep for now" closes the dialog and suppresses the next '
      'launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = storeWithOldRecording();

    await pumpHome(tester, home(store));
    expect(find.text('Free up storage?'), findsOneWidget);

    await tapAndSettle(tester, find.text('Keep for now'));
    expect(find.text('Free up storage?'), findsNothing);

    // Relaunch: same store, same prefs — should stay quiet for 30 days.
    await relaunch(tester, store);
    expect(find.text('Free up storage?'), findsNothing);
    // Audio untouched.
    final saved = await store.get('job_old');
    expect(saved!.audioPath, isNotNull);
  });

  testWidgets('"Remind me later" does not suppress the next launch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = storeWithOldRecording();

    await pumpHome(tester, home(store));
    expect(find.text('Free up storage?'), findsOneWidget);

    await tapAndSettle(tester, find.text('Remind me later'));
    expect(find.text('Free up storage?'), findsNothing);

    await relaunch(tester, store);
    expect(find.text('Free up storage?'), findsOneWidget);
  });

  testWidgets('"Delete audio" removes only the audio path and suppresses '
      'future prompts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = storeWithOldRecording();

    await pumpHome(tester, home(store));
    expect(find.text('Free up storage?'), findsOneWidget);

    await tapAndSettle(tester, find.text('Delete audio'));

    final saved = await store.get('job_old');
    expect(saved, isNotNull);
    expect(saved!.audioPath, isNull); // transcript/record survives
    expect(saved.filename, 'board meeting.m4a');

    await relaunch(tester, store);
    expect(find.text('Free up storage?'), findsNothing);
  });
}
