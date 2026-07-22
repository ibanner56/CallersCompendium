import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/confirm_before_delete_scope.dart';
import 'package:compendium_app/src/data/decimal_turns_scope.dart';
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
      final notifier = ValueNotifier<bool?>(false);
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

    testWidgets(
      'follows the OS Reduce Motion preference when unset (issue #447)',
      (tester) async {
        // No explicit in-app override (notifier == null): the scope must honor
        // the OS-level MediaQuery.disableAnimations by default (WCAG 2.3.3).
        final notifier = ValueNotifier<bool?>(null);
        addTearDown(notifier.dispose);
        late bool value;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: ReduceMotionScope(
              notifier: notifier,
              child: Builder(
                builder: (context) {
                  value = ReduceMotionScope.of(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        expect(value, isTrue);
      },
    );

    testWidgets('unset with OS animations enabled reports full motion', (
      tester,
    ) async {
      final notifier = ValueNotifier<bool?>(null);
      addTearDown(notifier.dispose);
      late bool value;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: ReduceMotionScope(
            notifier: notifier,
            child: Builder(
              builder: (context) {
                value = ReduceMotionScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(value, isFalse);
    });

    testWidgets(
      'explicit in-app override wins over the OS setting (issue #447)',
      (tester) async {
        // OS requests reduced motion, but an explicit in-app "off" override
        // must force full motion; and an explicit "on" override must force
        // reduced motion even when the OS wants full motion.
        final notifier = ValueNotifier<bool?>(false);
        addTearDown(notifier.dispose);
        final observed = <bool>[];
        Widget build(bool osDisableAnimations) => MediaQuery(
          data: MediaQueryData(disableAnimations: osDisableAnimations),
          child: ReduceMotionScope(
            notifier: notifier,
            child: Builder(
              builder: (context) {
                observed.add(ReduceMotionScope.of(context));
                return const SizedBox();
              },
            ),
          ),
        );

        // OS on, override off -> off wins.
        await tester.pumpWidget(build(true));
        expect(observed.last, isFalse);

        // OS off, override on -> on wins.
        notifier.value = true;
        await tester.pumpWidget(build(false));
        await tester.pump();
        expect(observed.last, isTrue);
      },
    );

    testWidgets(
      'rebuilds when the OS setting changes at runtime (issue #447)',
      (tester) async {
        final notifier = ValueNotifier<bool?>(null);
        addTearDown(notifier.dispose);
        final observed = <bool>[];
        Widget build(bool osDisableAnimations) => MediaQuery(
          data: MediaQueryData(disableAnimations: osDisableAnimations),
          child: ReduceMotionScope(
            notifier: notifier,
            child: Builder(
              builder: (context) {
                observed.add(ReduceMotionScope.of(context));
                return const SizedBox();
              },
            ),
          ),
        );

        await tester.pumpWidget(build(false));
        expect(observed, [false]);
        // Flipping the OS preference must rebuild dependents live because
        // of() registers a dependency on the disableAnimations aspect.
        await tester.pumpWidget(build(true));
        expect(observed, [false, true]);
      },
    );

    testWidgets('overrideOf reports the raw tri-state override', (
      tester,
    ) async {
      final notifier = ValueNotifier<bool?>(null);
      addTearDown(notifier.dispose);
      final observed = <bool?>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ReduceMotionScope(
            notifier: notifier,
            child: Builder(
              builder: (context) {
                observed.add(ReduceMotionScope.overrideOf(context));
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      // OS wants reduced motion, but the raw override is still unset (null).
      expect(observed, [null]);
      notifier.value = false;
      await tester.pump();
      expect(observed, [null, false]);
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

  group('DecimalTurnsScope', () {
    testWidgets('defaults to false with no ancestor', (tester) async {
      late bool value;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            value = DecimalTurnsScope.of(context);
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
        DecimalTurnsScope(
          notifier: notifier,
          child: Builder(
            builder: (context) {
              observed.add(DecimalTurnsScope.of(context));
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
              () => DecimalTurnsScope.notifierOf(context),
              throwsFlutterError,
            );
            return const SizedBox();
          },
        ),
      );
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
