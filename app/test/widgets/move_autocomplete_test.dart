import 'package:compendium_app/src/widgets/move_autocomplete.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dialect that renames the canonical `swing` move to "buzz", exercising the
/// editor's requirement that the move picker both displays and matches dialect
/// vocabulary (not just canonical taxonomy names).
final _buzzDialect = Dialect(name: 'Custom', moves: const {'swing': 'buzz'});

Future<void> _pump(
  WidgetTester tester, {
  Dialect? dialect,
  ValueChanged<MoveOption>? onSelected,
  ValueChanged<String>? onCustomSubmitted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MoveAutocomplete(
          taxonomy: contraTaxonomy,
          dialect: dialect,
          initialText: '',
          fieldKey: 'move',
          onSelected: onSelected ?? (_) {},
          onCustomSubmitted: onCustomSubmitted,
        ),
      ),
    ),
  );
}

/// Sets both the render surface size and the [MediaQuery] physical size to
/// [size]. `setSurfaceSize` alone only affects layout constraints —
/// `MediaQuery.sizeOf`, which `ResponsiveAutocomplete` uses for its
/// breakpoints, reads `FlutterView.physicalSize` instead (see
/// `responsive_autocomplete_test.dart`), so both must be set to faithfully
/// simulate a phone-sized screen in tests.
Future<void> _setScreenSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
}

void main() {
  testWidgets('matches and displays a dialect move substitution', (
    tester,
  ) async {
    await _pump(tester, dialect: _buzzDialect);
    // Typing the dialect term surfaces the underlying move as "buzz".
    await tester.enterText(find.byKey(const ValueKey('move-input')), 'buzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('move-option-swing')), findsOneWidget);
    expect(find.text('buzz'), findsWidgets);
    expect(find.text('swing'), findsNothing);
  });

  testWidgets('shows canonical names under the canonical dialect', (
    tester,
  ) async {
    await _pump(tester, dialect: Dialect.canonical);
    await tester.enterText(find.byKey(const ValueKey('move-input')), 'swing');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('move-option-swing')), findsOneWidget);
    expect(find.text('swing'), findsWidgets);
    // The dialect term isn't shown when the active dialect is canonical.
    expect(find.text('buzz'), findsNothing);
  });

  group('narrow layout (issue #716)', () {
    testWidgets('tapping the field opens a sheet and picking an option above a '
        'simulated keyboard still selects the move', (tester) async {
      MoveOption? picked;
      await _setScreenSize(tester, const Size(360, 720));
      await _pump(tester, onSelected: (o) => picked = o);

      await tester.tap(
        find.byKey(const ValueKey('move-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Simulate a software keyboard inset, as issue #716 describes.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('move-input')), 'swing');
      await tester.pumpAndSettle();

      final optionFinder = find.byKey(const ValueKey('move-option-swing'));
      expect(optionFinder, findsOneWidget);
      // The option sits above the simulated keyboard inset, not hidden
      // underneath it.
      final optionRect = tester.getRect(optionFinder);
      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

      await tester.tap(optionFinder);
      await tester.pumpAndSettle();

      expect(picked?.id, 'swing');
      // The sheet closes after the pick.
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('free-text submission of an unmatched move still fires '
        'onCustomSubmitted from inside the sheet', (tester) async {
      String? custom;
      await _setScreenSize(tester, const Size(360, 720));
      await _pump(tester, onCustomSubmitted: (v) => custom = v);

      await tester.tap(
        find.byKey(const ValueKey('move-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('move-input')),
        'a brand new move',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(custom, 'a brand new move');
      expect(find.byType(BottomSheet), findsNothing);
    });
  });
}
