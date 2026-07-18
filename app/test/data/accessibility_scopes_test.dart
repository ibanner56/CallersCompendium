import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart';
import 'package:compendium_app/src/data/set_list_color_coding_scope.dart';
import 'package:compendium_app/src/data/verbose_figure_rendering_scope.dart';

void main() {
  group('ReduceMotionScope', () {
    testWidgets('defaults to false with no ancestor', (tester) async {
      late bool value;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            value = ReduceMotionScope.of(context);
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
        ReduceMotionScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              observed.add(ReduceMotionScope.of(context));
              return const SizedBox();
            },
          ),
        ),
      );
      expect(observed, [false]);
      notifier.value = true;
      await tester.pump();
      expect(observed, [false, true]);
    });

    testWidgets('notifierOf throws without an ancestor', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            expect(
              () => ReduceMotionScope.notifierOf(context),
              throwsFlutterError,
            );
            return const SizedBox();
          },
        ),
      );
    });
  });

  group('VerboseFigureRenderingScope', () {
    testWidgets('defaults to false with no ancestor', (tester) async {
      late bool value;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            value = VerboseFigureRenderingScope.of(context);
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
        VerboseFigureRenderingScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              observed.add(VerboseFigureRenderingScope.of(context));
              return const SizedBox();
            },
          ),
        ),
      );
      expect(observed, [false]);
      notifier.value = true;
      await tester.pump();
      expect(observed, [false, true]);
    });
  });

  group('ConfirmBeforeDeleteScope', () {
    testWidgets('defaults to false with no ancestor', (tester) async {
      late bool value;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            value = ConfirmBeforeDeleteScope.of(context);
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
        ConfirmBeforeDeleteScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              observed.add(ConfirmBeforeDeleteScope.of(context));
              return const SizedBox();
            },
          ),
        ),
      );
      expect(observed, [false]);
      notifier.value = true;
      await tester.pump();
      expect(observed, [false, true]);
    });
  });

  group('SetListColorCodingScope', () {
    testWidgets('defaults to true (on) with no ancestor', (tester) async {
      late bool value;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            value = SetListColorCodingScope.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(value, isTrue);
    });

    testWidgets('changing the notifier rebuilds dependents', (tester) async {
      final notifier = ValueNotifier<bool>(true);
      addTearDown(notifier.dispose);
      final observed = <bool>[];
      await tester.pumpWidget(
        SetListColorCodingScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              observed.add(SetListColorCodingScope.of(context));
              return const SizedBox();
            },
          ),
        ),
      );
      expect(observed, [true]);
      notifier.value = false;
      await tester.pump();
      expect(observed, [true, false]);
    });

    testWidgets('notifierOf throws without an ancestor', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            expect(
              () => SetListColorCodingScope.notifierOf(context),
              throwsFlutterError,
            );
            return const SizedBox();
          },
        ),
      );
    });
  });
}
