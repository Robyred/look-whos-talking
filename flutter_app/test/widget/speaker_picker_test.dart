import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:look_whos_talking/widgets/speaker_picker.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('SpeakerPicker', () {
    testWidgets('renders all 6 option labels', (tester) async {
      await tester.pumpWidget(_wrap(
        SpeakerPicker(selected: null, onChanged: (_) {}),
      ));
      expect(find.text("Don't know"), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('6+'), findsOneWidget);
    });

    testWidgets('tapping "3" calls onChanged with 3', (tester) async {
      int? received = -1;
      await tester.pumpWidget(_wrap(
        SpeakerPicker(selected: null, onChanged: (v) => received = v),
      ));
      await tester.tap(find.text('3'));
      await tester.pump();
      expect(received, equals(3));
    });

    testWidgets('tapping "2" calls onChanged with 2', (tester) async {
      int? received = -1;
      await tester.pumpWidget(_wrap(
        SpeakerPicker(selected: null, onChanged: (v) => received = v),
      ));
      await tester.tap(find.text('2'));
      await tester.pump();
      expect(received, equals(2));
    });

    testWidgets('tapping "6+" calls onChanged with 6', (tester) async {
      int? received = -1;
      await tester.pumpWidget(_wrap(
        SpeakerPicker(selected: null, onChanged: (v) => received = v),
      ));
      await tester.tap(find.text('6+'));
      await tester.pump();
      expect(received, equals(6));
    });

    testWidgets('tapping "Don\'t know" calls onChanged with null', (tester) async {
      int? received = 99;
      await tester.pumpWidget(_wrap(
        SpeakerPicker(selected: 3, onChanged: (v) => received = v),
      ));
      await tester.tap(find.text("Don't know"));
      await tester.pump();
      expect(received, isNull);
    });

    testWidgets('selected pill has different Material color than unselected', (tester) async {
      await tester.pumpWidget(_wrap(
        SpeakerPicker(selected: 3, onChanged: (_) {}),
      ));
      await tester.pump();

      // Find all Material widgets that are direct parents of InkWell (the pill materials)
      // We compare the color of the selected ('3') pill vs an unselected ('2') pill.
      final context = tester.element(find.text('3'));
      final selectedCs = Theme.of(context).colorScheme;

      // The selected Material should use primaryContainer
      final selectedMaterial = tester.widget<Material>(
        find.ancestor(of: find.text('3'), matching: find.byType(Material)).first,
      );
      final unselectedMaterial = tester.widget<Material>(
        find.ancestor(of: find.text('2'), matching: find.byType(Material)).first,
      );

      expect(selectedMaterial.color, equals(selectedCs.primaryContainer));
      expect(unselectedMaterial.color, equals(selectedCs.surfaceContainerHighest));
    });
  });
}
