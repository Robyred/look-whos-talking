// Basic app smoke test: home screen renders with the shared dependencies.
import 'package:flutter_test/flutter_test.dart';

import 'package:look_whos_talking/main.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('App smoke test — home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      LookWhosTalkingApp(store: MemoryStore(), cloud: FakeCloud()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Look Who\'s Talking'), findsOneWidget);
  });
}
