import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/show_glossary_scope.dart';

void main() {
  group('ShowGlossaryScope', () {
    testWidgets('defaults to false with no ancestor', (tester) async {
      late bool value;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            value = ShowGlossaryScope.of(context);
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
        ShowGlossaryScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              observed.add(ShowGlossaryScope.of(context));
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
              () => ShowGlossaryScope.notifierOf(context),
              throwsFlutterError,
            );
            return const SizedBox();
          },
        ),
      );
    });
  });
}
