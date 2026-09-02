import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/widgets/nav_button.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('NavButton', () {
    testWidgets('renders its icon and label', (tester) async {
      await tester.pumpWidget(_wrap(
        NavButton(
          icon: Icons.bar_chart,
          label: 'Overview',
          selected: false,
          onTap: () {},
        ),
      ));
      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
    });

    testWidgets('tapping calls onTap', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(
        NavButton(
          icon: Icons.bar_chart,
          label: 'Overview',
          selected: false,
          onTap: () => called = true,
        ),
      ));
      await tester.tap(find.byType(NavButton));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('selected=true uses primaryContainer background', (tester) async {
      await tester.pumpWidget(_wrap(
        NavButton(
          icon: Icons.bar_chart,
          label: 'Overview',
          selected: true,
          onTap: () {},
        ),
      ));
      await tester.pump();

      final context = tester.element(find.byType(NavButton));
      final cs = Theme.of(context).colorScheme;

      final material = tester.widget<Material>(
        find.descendant(of: find.byType(NavButton), matching: find.byType(Material)).first,
      );
      expect(material.color, equals(cs.primaryContainer));
    });

    testWidgets('selected=false uses surfaceContainerHighest background', (tester) async {
      await tester.pumpWidget(_wrap(
        NavButton(
          icon: Icons.bar_chart,
          label: 'Overview',
          selected: false,
          onTap: () {},
        ),
      ));
      await tester.pump();

      final context = tester.element(find.byType(NavButton));
      final cs = Theme.of(context).colorScheme;

      final material = tester.widget<Material>(
        find.descendant(of: find.byType(NavButton), matching: find.byType(Material)).first,
      );
      expect(material.color, equals(cs.surfaceContainerHighest));
    });

    testWidgets('selected=true and selected=false produce different colors', (tester) async {
      // Pump both variants and compare
      await tester.pumpWidget(_wrap(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NavButton(
              key: const Key('selected'),
              icon: Icons.bar_chart,
              label: 'A',
              selected: true,
              onTap: () {},
            ),
            NavButton(
              key: const Key('unselected'),
              icon: Icons.bar_chart,
              label: 'B',
              selected: false,
              onTap: () {},
            ),
          ],
        ),
      ));
      await tester.pump();

      final selectedMaterial = tester.widget<Material>(
        find
            .descendant(
                of: find.byKey(const Key('selected')),
                matching: find.byType(Material))
            .first,
      );
      final unselectedMaterial = tester.widget<Material>(
        find
            .descendant(
                of: find.byKey(const Key('unselected')),
                matching: find.byType(Material))
            .first,
      );
      expect(selectedMaterial.color, isNot(equals(unselectedMaterial.color)));
    });
  });
}
