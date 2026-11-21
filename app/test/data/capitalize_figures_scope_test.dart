import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/capitalize_figures_scope.dart';

void main() {
  group('capitalizeFirstLetter', () {
    test('upper-cases the first letter only when enabled', () {
      expect(
        capitalizeFirstLetter('neighbors allemande left', capitalize: true),
        'Neighbors allemande left',
      );
      expect(
        capitalizeFirstLetter('neighbors allemande left', capitalize: false),
        'neighbors allemande left',
      );
    });

    test('leaves already-capitalized, empty and non-letter starts alone', () {
      expect(capitalizeFirstLetter('Swing', capitalize: true), 'Swing');
      expect(capitalizeFirstLetter('', capitalize: true), '');
      expect(capitalizeFirstLetter('½ turn', capitalize: true), '½ turn');
      expect(
        capitalizeFirstLetter('(ones) swing', capitalize: true),
        '(ones) swing',
      );
    });

    test('is not fooled by a multi-code-unit first character', () {
      // U+10428 DESERET SMALL LETTER LONG I is a surrogate pair whose capital
      // form is U+10400; slicing by UTF-16 unit would corrupt it.
      expect(
        capitalizeFirstLetter('\u{10428}x', capitalize: true),
        '\u{10400}x',
      );
    });
  });

  group('CapitalizeFiguresScope', () {
    testWidgets('defaults to false with no ancestor', (tester) async {
      late bool value;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            value = CapitalizeFiguresScope.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(value, isFalse);
    });

    testWidgets('changing the notifier rebuilds dependents', (tester) async {
      final notifier = ValueNotifier<bool>(false);
      addTearDown(notifier.dispose);
      final observed = <bool>[];
      await tester.pumpWidget(
        CapitalizeFiguresScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              observed.add(CapitalizeFiguresScope.of(context));
              return const SizedBox();
            },
          ),
        ),
      );
      notifier.value = true;
      await tester.pump();
      expect(observed, [false, true]);
    });

    testWidgets('notifierOf throws without an ancestor', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            expect(
              () => CapitalizeFiguresScope.notifierOf(context),
              throwsFlutterError,
            );
            return const SizedBox();
          },
        ),
      );
    });
  });
}
