import 'package:compendium_app/src/widgets/responsive_autocomplete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/screen_size.dart';

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
    this.initialText = '',
    this.initialValue,
    this.focusNode,
    this.refocusAfterSelect = false,
  });

  final List<String> options;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onCustomSubmitted;
  final double compactWidthBreakpoint;
  final double compactHeightBreakpoint;
  final bool autofocus;
  final String initialText;
  final TextEditingValue? initialValue;
  final FocusNode? focusNode;

  /// Mirrors `name_picker.dart`'s `_AddAutocomplete.onSelected`
  /// (`:162-163`): clears the field and re-requests focus after every pick,
  /// which is what turns a successful selection into "reopen the sheet" on
  /// a phone. Requires [focusNode] to be non-null (the test needs a handle
  /// on the same node the widget refocuses to assert on it).
  final bool refocusAfterSelect;

  @override
  State<_TestPicker> createState() => _TestPickerState();
}

class _TestPickerState extends State<_TestPicker> {
  // Owned only so `refocusAfterSelect` has something to clear — mirrors
  // `_AddAutocompleteState._controller` in name_picker.dart.
  TextEditingController? _ownedController;
  TextEditingController get _controller =>
      _ownedController ??= TextEditingController();

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  Iterable<String> _optionsFor(TextEditingValue value) {
    final q = value.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return widget.options.where((o) => o.toLowerCase().contains(q));
  }

  void _handleSelected(String option) {
    widget.onSelected(option);
    if (widget.refocusAfterSelect) {
      assert(
        widget.focusNode != null,
        'refocusAfterSelect requires an explicit focusNode to refocus',
      );
      _controller.clear();
      widget.focusNode!.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAutocomplete<String>(
      sheetSemanticLabel: 'Search options',
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      textEditingController: widget.refocusAfterSelect ? _controller : null,
      compactWidthBreakpoint: widget.compactWidthBreakpoint,
      compactHeightBreakpoint: widget.compactHeightBreakpoint,
      initialValue: widget.refocusAfterSelect
          ? null
          : widget.initialValue ?? TextEditingValue(text: widget.initialText),
      displayStringForOption: (o) => o,
      optionsBuilder: _optionsFor,
      onSelected: _handleSelected,
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

Future<void> _pump(
  WidgetTester tester, {
  required List<String> options,
  required ValueChanged<String> onSelected,
  ValueChanged<String>? onCustomSubmitted,
  double compactWidthBreakpoint = 600,
  double compactHeightBreakpoint = 480,
  bool autofocus = false,
  String initialText = '',
  TextEditingValue? initialValue,
  TextDirection textDirection = TextDirection.ltr,
  FocusNode? focusNode,
  bool refocusAfterSelect = false,
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
            initialText: initialText,
            initialValue: initialValue,
            focusNode: focusNode,
            refocusAfterSelect: refocusAfterSelect,
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

    testWidgets('updates an owned field when initial text changes', (
      tester,
    ) async {
      await _pump(
        tester,
        options: const ['swing'],
        onSelected: (_) {},
        initialValue: const TextEditingValue(
          text: 'do si do',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('test-input')))
            .controller
            ?.text,
        'do si do',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('test-input')))
            .controller
            ?.selection
            .baseOffset,
        3,
      );

      await _pump(
        tester,
        options: const ['swing'],
        onSelected: (_) {},
        initialValue: const TextEditingValue(
          text: 'see saw',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('test-input')))
            .controller
            ?.text,
        'see saw',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('test-input')))
            .controller
            ?.selection
            .baseOffset,
        2,
      );
    });

    testWidgets('updates the sheet field when initial text changes', (
      tester,
    ) async {
      await setScreenSize(tester, const Size(360, 720));
      final initialText = ValueNotifier('do si do');
      addTearDown(initialText.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<String>(
                valueListenable: initialText,
                builder: (context, text, child) {
                  return _TestPicker(
                    options: const ['swing'],
                    onSelected: (_) {},
                    initialText: text,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('test-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      initialText.value = 'see saw';
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('test-input')))
            .controller
            ?.text,
        'see saw',
      );
    });
  });

  group('narrow layout (compact width)', () {
    Future<void> pumpNarrow(
      WidgetTester tester, {
      required List<String> options,
      required ValueChanged<String> onSelected,
      bool autofocus = false,
      TextDirection textDirection = TextDirection.ltr,
      FocusNode? focusNode,
      bool refocusAfterSelect = false,
    }) async {
      await setScreenSize(tester, const Size(360, 720));
      await _pump(
        tester,
        options: options,
        onSelected: onSelected,
        autofocus: autofocus,
        textDirection: textDirection,
        focusNode: focusNode,
        refocusAfterSelect: refocusAfterSelect,
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
      // The launcher's field is updated to show the picked option's display
      // string (mirrors `Autocomplete`'s own post-selection behavior) rather
      // than staying on whatever text was typed while searching.
      final launcherField = tester.widget<TextField>(
        find.byKey(const ValueKey('test-input')),
      );
      expect(launcherField.controller?.text, 'balance');
    });

    testWidgets(
      'a tap-driven open does not swallow a later genuine Tab/AT focus '
      'arrival',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        await pumpNarrow(
          tester,
          options: const ['swing'],
          onSelected: (_) {},
          focusNode: focusNode,
        );

        // Open (and close, via a pick) the sheet purely by tapping — the
        // launcher's FocusNode never gains focus in this path, since
        // AbsorbPointer blocks the tap from reaching the field itself.
        await tester.tap(
          find.byKey(const ValueKey('test-input')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('test-input')),
          'swing',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('test-option-swing')));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(focusNode.hasFocus, isFalse);

        // A later, unrelated, genuine Tab/AT-driven focus arrival must still
        // open the sheet — it must not be swallowed by a stale
        // "ignore next focus gain" guard left over from the tap-driven open
        // above (see PR review discussion on responsive_autocomplete.dart).
        focusNode.requestFocus();
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
      },
    );

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

    testWidgets(
      'repeated selections keep reopening the sheet, not just the first '
      '(#894)',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        final picked = <String>[];
        await pumpNarrow(
          tester,
          options: const ['alpha', 'bravo', 'charlie', 'delta'],
          onSelected: picked.add,
          focusNode: focusNode,
          refocusAfterSelect: true,
        );

        // The first open is tap-driven — `AbsorbPointer` means the tap
        // never reaches the launcher, so `openedViaFocus == false` here.
        // Every reopen after that is itself focus-driven (the refocus below
        // is what opens it), which is the branch #894 actually broke.
        await tester.tap(
          find.byKey(const ValueKey('test-input')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        for (final name in ['alpha', 'bravo', 'charlie']) {
          expect(
            find.byType(BottomSheet),
            findsOneWidget,
            reason: 'sheet must still be open before picking "$name"',
          );
          await tester.enterText(
            find.byKey(const ValueKey('test-input')),
            name,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('test-option-$name')));
          await tester.pumpAndSettle();
        }

        expect(picked, ['alpha', 'bravo', 'charlie']);
        // The count matters — issue #894's own acceptance criterion is
        // "three or more", since a fix that only reopens after every other
        // addition passes a two-addition test for the wrong reason (it
        // would still fail on the third, as this assertion establishes).
        expect(
          find.byType(BottomSheet),
          findsOneWidget,
          reason: 'sheet must still be open after the third pick',
        );
      },
    );

    testWidgets(
      'a focus-driven open that is dismissed without picking does not '
      'permanently swallow a later genuine Tab/AT focus arrival (#894)',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        await pumpNarrow(
          tester,
          options: const ['swing'],
          onSelected: (_) {},
          focusNode: focusNode,
        );

        // Open via a genuine focus gain (Tab/AT traversal) — the
        // `openedViaFocus == true` branch that arms the guard.
        focusNode.requestFocus();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);

        // Dismiss WITHOUT picking (back/drag-down) — tap the modal barrier,
        // well above the sheet's own content (`initialChildSize: 0.6`).
        await tester.tapAt(const Offset(180, 10));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);

        // A later, unrelated, genuine Tab/AT-driven focus arrival must
        // still open the sheet. Before the fix this stays swallowed
        // forever: the guard, once armed by the dismiss above, is never
        // consumed — the launcher is unmounted while the sheet is open, so
        // no automatic focus-restoration ever arrives to consume it.
        focusNode.requestFocus();
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsOneWidget);
      },
    );

    testWidgets(
      'a focus-driven open that is dismissed without picking does not '
      'immediately reopen (the boomerang the guard exists to prevent)',
      (tester) async {
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);
        await pumpNarrow(
          tester,
          options: const ['swing'],
          onSelected: (_) {},
          focusNode: focusNode,
        );

        focusNode.requestFocus();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);

        await tester.tapAt(const Offset(180, 10));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
      },
    );

    testWidgets(
      'dismissing without selecting after a tap-driven open also leaves it '
      'closed',
      (tester) async {
        await pumpNarrow(tester, options: const ['swing'], onSelected: (_) {});

        await tester.tap(
          find.byKey(const ValueKey('test-input')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);

        await tester.tapAt(const Offset(180, 10));
        await tester.pumpAndSettle();

        expect(find.byType(BottomSheet), findsNothing);
      },
    );
  });

  group('compact-height heuristic', () {
    testWidgets('a wide-but-short (landscape phone) surface uses the sheet', (
      tester,
    ) async {
      await setScreenSize(tester, const Size(800, 400));
      await _pump(tester, options: const ['swing'], onSelected: (_) {});

      await tester.tap(
        find.byKey(const ValueKey('test-input')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a tall-enough wide surface stays inline', (tester) async {
      await setScreenSize(tester, const Size(800, 700));
      await _pump(tester, options: const ['swing'], onSelected: (_) {});

      await tester.enterText(find.byKey(const ValueKey('test-input')), 'sw');
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const ValueKey('test-option-swing')), findsOneWidget);
    });
  });
}
