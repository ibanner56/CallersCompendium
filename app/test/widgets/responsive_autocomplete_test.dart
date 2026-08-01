import 'package:compendium_app/src/widgets/responsive_autocomplete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal in-memory [ResponsiveAutocomplete] harness: options are plain
/// strings, matched by substring, with no free-text/create affordance beyond
/// an `onCustomSubmitted` fallback (mirroring `MoveAutocomplete`'s contract)
/// so tests can exercise every hook the real call sites rely on.
class _TestPicker extends StatefulWidget {
  const _TestPicker({
    required this.options,
    required this.onSelected,
    this.onCustomSubmitted,
    this.compactWidthBreakpoint = 600,
    this.compactHeightBreakpoint = 480,
    this.autofocus = false,
  });

  final List<String> options;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onCustomSubmitted;
  final double compactWidthBreakpoint;
  final double compactHeightBreakpoint;
  final bool autofocus;

  @override
  State<_TestPicker> createState() => _TestPickerState();
}

class _TestPickerState extends State<_TestPicker> {
  Iterable<String> _optionsFor(TextEditingValue value) {
    final q = value.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return widget.options.where((o) => o.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAutocomplete<String>(
      sheetSemanticLabel: 'Search options',
      autofocus: widget.autofocus,
      compactWidthBreakpoint: widget.compactWidthBreakpoint,
      compactHeightBreakpoint: widget.compactHeightBreakpoint,
      displayStringForOption: (o) => o,
      optionsBuilder: _optionsFor,
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          key: const ValueKey('test-input'),
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(labelText: 'Test field'),
          onSubmitted: (text) {
            final q = text.trim();
            final matches = _optionsFor(TextEditingValue(text: q));
            if (matches.isNotEmpty) {
              widget.onSelected(matches.first);
            } else if (q.isNotEmpty) {
              widget.onCustomSubmitted?.call(q);
            }
            onSubmit();
          },
        );
      },
      optionTileBuilder: (context, option, onSelected) {
        return ListTile(
          key: ValueKey('test-option-$option'),
          dense: true,
          title: Text(option),
          onTap: onSelected,
        );
      },
    );
  }
}

/// Sets both the render surface size and the [MediaQuery] physical size to
/// [size]. `setSurfaceSize` alone only affects layout constraints (what a
/// [LayoutBuilder] would see) — `MediaQuery.sizeOf`, which
/// [ResponsiveAutocomplete] uses for its breakpoints (matching real-device
/// keyboard-obscuring geometry rather than a possibly-unbounded local layout
/// box), reads `FlutterView.physicalSize` instead, so both must be set to
/// faithfully simulate a given screen size in tests.
Future<void> _setScreenSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    return tester.binding.setSurfaceSize(null);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<String> options,
  required ValueChanged<String> onSelected,
  ValueChanged<String>? onCustomSubmitted,
  double compactWidthBreakpoint = 600,
  double compactHeightBreakpoint = 480,
  bool autofocus = false,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: textDirection,
      child: MaterialApp(
        home: Scaffold(
          body: _TestPicker(
            options: options,
            onSelected: onSelected,
            onCustomSubmitted: onCustomSubmitted,
            compactWidthBreakpoint: compactWidthBreakpoint,
            compactHeightBreakpoint: compactHeightBreakpoint,
            autofocus: autofocus,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('wide layout (>= breakpoints)', () {
    testWidgets('renders an inline overlay and selects an option', (
      tester,
    ) async {
      String? picked;
      await _pump(
        tester,
        options: const ['swing', 'balance', 'allemande'],
        onSelected: (v) => picked = v,
      );

      await tester.enterText(find.byKey(const ValueKey('test-input')), 'sw');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('test-option-swing')), findsOneWidget);
      // The overlay renders inline, not inside a modal route.
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byKey(const ValueKey('test-option-swing')));
      await tester.pumpAndSettle();
      expect(picked, 'swing');
    });

    testWidgets('free-text fallback fires when nothing matches', (
      tester,
    ) async {
      String? custom;
      await _pump(
        tester,
        options: const ['swing'],
        onSelected: (_) {},
        onCustomSubmitted: (v) => custom = v,
      );

      await tester.enterText(
        find.byKey(const ValueKey('test-input')),
        'a brand new figure',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(custom, 'a brand new figure');
    });
  });

  group('narrow layout (compact width)', () {
    Future<void> pumpNarrow(
      WidgetTester tester, {
      required List<String> options,
      required ValueChanged<String> onSelected,
      bool autofocus = false,
      TextDirection textDirection = TextDirection.ltr,
    }) async {
      await _setScreenSize(tester, const Size(360, 720));
      await _pump(
        tester,
        options: options,
        onSelected: onSelected,
        autofocus: autofocus,
        textDirection: textDirection,
      );
    }

    testWidgets('tapping the field opens a keyboard-safe sheet', (
      tester,
    ) async {
      String? picked;
      await pumpNarrow(
        tester,
        options: const ['swing', 'balance', 'allemande'],
        onSelected: (v) => picked = v,
      );

      await tester.tap(
        find.byKey(const ValueKey('test-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      // The sheet has its own live field; typing filters and shows options.
      await tester.enterText(find.byKey(const ValueKey('test-input')), 'bal');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('test-option-balance')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('test-option-balance')));
      await tester.pumpAndSettle();

      expect(picked, 'balance');
      // Closes after the pick.
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('autofocus opens the sheet immediately on mount', (
      tester,
    ) async {
      await pumpNarrow(
        tester,
        options: const ['swing'],
        onSelected: (_) {},
        autofocus: true,
      );
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('remains usable with an ambient RTL directionality', (
      tester,
    ) async {
      String? picked;
      await pumpNarrow(
        tester,
        options: const ['swing'],
        onSelected: (v) => picked = v,
        textDirection: TextDirection.rtl,
      );

      await tester.tap(
        find.byKey(const ValueKey('test-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('test-input')), 'sw');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('test-option-swing')));
      await tester.pumpAndSettle();
      expect(picked, 'swing');
    });

    testWidgets(
      'options remain visible and hit-testable above a simulated keyboard',
      (tester) async {
        String? picked;
        await pumpNarrow(
          tester,
          options: const ['swing', 'balance'],
          onSelected: (v) => picked = v,
        );

        await tester.tap(
          find.byKey(const ValueKey('test-input')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Simulate a 300px software keyboard inset, as issue #716 describes.
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const ValueKey('test-input')), 'sw');
        await tester.pumpAndSettle();

        final optionFinder = find.byKey(const ValueKey('test-option-swing'));
        expect(optionFinder, findsOneWidget);
        // The option's top must sit above the simulated keyboard inset (i.e.
        // it is not rendered underneath it) and is genuinely tappable.
        final optionRect = tester.getRect(optionFinder);
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(optionRect.bottom, lessThanOrEqualTo(screenHeight - 300));

        await tester.tap(optionFinder);
        await tester.pumpAndSettle();
        expect(picked, 'swing');
      },
    );

    testWidgets(
      'a drag starting on empty sheet space scrolls without dismissing',
      (tester) async {
        final many = [for (var i = 0; i < 40; i++) 'option-$i'];
        await pumpNarrow(tester, options: many, onSelected: (_) {});

        await tester.tap(
          find.byKey(const ValueKey('test-input')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('test-input')),
          'option',
        );
        await tester.pumpAndSettle();

        // A far-down option isn't visible until we scroll.
        expect(
          find.byKey(const ValueKey('test-option-option-39')),
          findsNothing,
        );

        // Drag starting well inside the sheet's list area (not on the field,
        // not on the modal scrim) upward to scroll the list, repeating until
        // the far-down option comes into view (mirrors a real drag-to-scroll
        // gesture; anchoring on the `ListView` itself — rather than a tile
        // that would scroll out from under the anchor — keeps every
        // iteration's drag start point stable and within the list).
        await tester.dragUntilVisible(
          find.byKey(const ValueKey('test-option-option-39')),
          find.byType(ListView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();

        // The sheet is still open (the drag didn't dismiss it) and the list
        // scrolled far enough to reveal a later option.
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.byKey(const ValueKey('test-option-option-39')),
          findsOneWidget,
        );
      },
    );
  });

  group('compact-height heuristic', () {
    testWidgets('a wide-but-short (landscape phone) surface uses the sheet', (
      tester,
    ) async {
      await _setScreenSize(tester, const Size(800, 400));
      await _pump(tester, options: const ['swing'], onSelected: (_) {});

      await tester.tap(
        find.byKey(const ValueKey('test-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a tall-enough wide surface stays inline', (tester) async {
      await _setScreenSize(tester, const Size(800, 700));
      await _pump(tester, options: const ['swing'], onSelected: (_) {});

      await tester.enterText(find.byKey(const ValueKey('test-input')), 'sw');
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const ValueKey('test-option-swing')), findsOneWidget);
    });
  });
}
