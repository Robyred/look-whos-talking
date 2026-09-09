import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/screens/settings_screen.dart';
import 'package:look_whos_talking/services/cloud_storage_provider.dart';

import '../helpers/fakes.dart';

void main() {
  List<FakeCloud> threeProviders() => [
        FakeCloud(displayName: 'Google Drive'),
        FakeCloud(displayName: 'OneDrive'),
        FakeCloud(displayName: 'Dropbox'),
      ];

  Widget screen(List<FakeCloud> providers) => MaterialApp(
        home: SettingsScreen(providers: providers),
      );

  Finder connectIn(String displayName) => find.descendant(
        of: find.widgetWithText(ListTile, displayName),
        matching: find.text('Connect'),
      );

  Finder row(String displayName) => find.widgetWithText(ListTile, displayName);

  testWidgets('renders one row per provider, all not connected',
      (tester) async {
    await tester.pumpWidget(screen(threeProviders()));
    await tester.pumpAndSettle();

    expect(find.text('Cloud storage'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('OneDrive'), findsOneWidget);
    expect(find.text('Dropbox'), findsOneWidget);
    expect(find.text('Not connected'), findsNWidgets(3));
    expect(find.text('Connect'), findsNWidgets(3));
  });

  testWidgets('Connect authenticates that provider only', (tester) async {
    final providers = threeProviders();
    await tester.pumpWidget(screen(providers));
    await tester.pumpAndSettle();

    await tester.tap(connectIn('OneDrive'));
    await tester.pumpAndSettle();

    expect(find.descendant(of: row('OneDrive'), matching: find.text('Connected')),
        findsOneWidget);
    expect(providers[1].authenticated, isTrue);
    expect(providers[0].authenticated, isFalse);
    expect(providers[2].authenticated, isFalse);
    // Other rows untouched.
    expect(find.descendant(of: row('Google Drive'), matching: find.text('Not connected')),
        findsOneWidget);
    expect(find.descendant(of: row('Dropbox'), matching: find.text('Not connected')),
        findsOneWidget);
  });

  testWidgets('Disconnect asks for confirmation, then signs out',
      (tester) async {
    final providers = [
      FakeCloud(displayName: 'Dropbox', authenticated: true),
    ];
    await tester.pumpWidget(screen(providers));
    await tester.pumpAndSettle();

    // Cancel keeps the connection.
    await tester.tap(find.descendant(of: row('Dropbox'), matching: find.text('Disconnect')));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect Dropbox?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(providers.single.authenticated, isTrue);

    // Confirming disconnects.
    await tester.tap(find.descendant(of: row('Dropbox'), matching: find.text('Disconnect')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Disconnect')));
    await tester.pumpAndSettle();

    expect(providers.single.authenticated, isFalse);
    expect(find.descendant(of: row('Dropbox'), matching: find.text('Not connected')),
        findsOneWidget);
  });

  testWidgets('an AuthException during connect shows no snackbar',
      (tester) async {
    final providers = [
      FakeCloud(displayName: 'OneDrive', authError: const AuthException('cancelled')),
    ];
    await tester.pumpWidget(screen(providers));
    await tester.pumpAndSettle();

    await tester.tap(connectIn('OneDrive'));
    await tester.pumpAndSettle();

    expect(providers.single.authenticated, isFalse);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.descendant(of: row('OneDrive'), matching: find.text('Not connected')),
        findsOneWidget);
  });

  testWidgets('a generic failure during connect shows a snackbar',
      (tester) async {
    final providers = [
      FakeCloud(displayName: 'Dropbox', authError: Exception('network down')),
    ];
    await tester.pumpWidget(screen(providers));
    await tester.pumpAndSettle();

    await tester.tap(connectIn('Dropbox'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not connect'), findsOneWidget);
  });
}
