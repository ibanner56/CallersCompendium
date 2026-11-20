import 'dart:async';

import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:compendium_app/src/widgets/app_shortcuts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dropdown.dart';
import '../support/real_fonts.dart';
import '../support/screen_size.dart';

const _fieldKey = ValueKey('field');

const _entries = [
  AppDropdownEntry<String?>(value: null, label: 'None'),
  AppDropdownEntry<String?>(value: 'a', label: 'Alpha'),
  AppDropdownEntry<String?>(value: 'b', label: 'Bravo'),
  AppDropdownEntry<String?>(value: 'c', label: 'Charlie', enabled: false),
];

/// Pumps one field under [Form] [formKey], with its value held by the test.
Future<void> _pump(
  WidgetTester tester, {
  required String? value,
  ValueChanged<String?>? onChanged,
  bool filterable = false,
  GlobalKey<FormState>? formKey,
  FormFieldValidator<String?>? validator,
  FormFieldSetter<String?>? onSaved,
  AutovalidateMode? autovalidateMode,
  double textScale = 1,
  List<AppDropdownEntry<String?>> entries = _entries,
  bool compact = false,
  bool clearsAfterPick = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: formKey,
            child: Column(
              children: [
                AppDropdownField<String?>(
                  key: _fieldKey,
                  value: value,
                  entries: entries,
                  filterable: filterable,
                  compact: compact,
                  fillWidth: !compact,
                  clearsAfterPick: clearsAfterPick,
                  decoration: compact
                      ? const InputDecoration(hintText: 'Pick')
                      : const InputDecoration(labelText: 'Pick'),
                  validator: validator,
                  onSaved: onSaved,
                  autovalidateMode: autovalidateMode,
                  onChanged: onChanged,
                ),
                const TextField(key: ValueKey('after')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _shown(WidgetTester tester) =>
    dropdownShown(tester, find.byKey(_fieldKey));

/// Pumps the field inside a [Focus] that stands for whatever around it
/// answers Esc (an inline editor that closes, or the app's go-back), and
/// returns how many times Esc reached it.
Future<int Function()> _pumpWithPageEsc(
  WidgetTester tester, {
  ValueChanged<String?>? onChanged,
}) async {
  var pageEsc = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              pageEsc++;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              AppDropdownField<String?>(
                key: _fieldKey,
                value: 'a',
                entries: _entries,
                decoration: const InputDecoration(labelText: 'Pick'),
                onChanged: onChanged ?? (_) {},
              ),
              const Expanded(child: SizedBox.expand(key: ValueKey('blank'))),
            ],
          ),
        ),
      ),
    ),
  );
  return () => pageEsc;
}

void main() {
  testWidgets('fills the width it is given, as the text fields beside it do', (
    tester,
  ) async {
    await _pump(tester, value: 'a', onChanged: (_) {});
    expect(
      tester.getSize(find.byType(TextField).first).width,
      tester.getSize(find.byKey(const ValueKey('after'))).width,
    );
  });

  testWidgets('shows the value, and a pick reports the new one', (
    tester,
  ) async {
    String? picked = 'a';
    await _pump(tester, value: 'a', onChanged: (v) => picked = v);
    expect(_shown(tester), 'Alpha');
    await pickDropdownEntry(tester, find.byKey(_fieldKey), 'Bravo');
    expect(picked, 'b');
    expect(_shown(tester), 'Bravo');
  });

  testWidgets('a "None" entry is a choice like any other', (tester) async {
    String? picked = 'a';
    var calls = 0;
    await _pump(
      tester,
      value: 'a',
      onChanged: (v) {
        picked = v;
        calls++;
      },
    );
    await pickDropdownEntry(tester, find.byKey(_fieldKey), 'None');
    expect(calls, 1);
    expect(picked, isNull);
    expect(_shown(tester), 'None');
  });

  testWidgets('picking the current entry again reports nothing', (
    tester,
  ) async {
    var calls = 0;
    await _pump(tester, value: 'a', onChanged: (_) => calls++);
    await pickDropdownEntry(tester, find.byKey(_fieldKey), 'Alpha');
    expect(calls, 0);
    expect(_shown(tester), 'Alpha');
  });

  testWidgets('a disabled entry cannot be picked', (tester) async {
    var calls = 0;
    await _pump(tester, value: 'a', onChanged: (_) => calls++);
    await tester.tap(find.byKey(_fieldKey));
    await tester.pumpAndSettle();
    expect(dropdownEntry('Charlie'), findsOneWidget, reason: 'it is listed');
    await tester.tap(dropdownEntry('Charlie'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(_shown(tester), 'Alpha');
  });

  testWidgets('follows the parent when it rebuilds with a new value', (
    tester,
  ) async {
    await _pump(tester, value: 'a', onChanged: (_) {});
    expect(_shown(tester), 'Alpha');
    await _pump(tester, value: 'b', onChanged: (_) {});
    expect(_shown(tester), 'Bravo');
    expect(
      tester.state<FormFieldState<String?>>(find.byKey(_fieldKey)).value,
      'b',
    );
    // Cleared from outside: the "None" entry.
    await _pump(tester, value: null, onChanged: (_) {});
    expect(_shown(tester), 'None');
  });

  testWidgets('a value not among the entries shows an empty field', (
    tester,
  ) async {
    await _pump(
      tester,
      value: 'gone',
      onChanged: (_) {},
      entries: _entries.where((e) => e.value != null).toList(),
    );
    expect(_shown(tester), isEmpty);
  });

  testWidgets('with no onChanged the field is disabled and does not open', (
    tester,
  ) async {
    await _pump(tester, value: 'a');
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(_fieldKey),
        matching: find.byType(TextField),
      ),
    );
    expect(field.enabled, isFalse);
    await tester.tap(find.byKey(_fieldKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Bravo'), findsNothing);
  });

  testWidgets('validates, saves and resets inside a Form', (tester) async {
    final formKey = GlobalKey<FormState>();
    String? saved = 'unset';
    var value = 'a' as String?;
    await _pump(
      tester,
      value: value,
      formKey: formKey,
      onChanged: (v) => value = v,
      validator: (v) => v == null ? 'Choose one' : null,
      onSaved: (v) => saved = v,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
    expect(find.text('Choose one'), findsNothing);
    await pickDropdownEntry(tester, find.byKey(_fieldKey), 'None');
    // Validated as soon as the user changed it.
    expect(find.text('Choose one'), findsOneWidget);
    expect(formKey.currentState!.validate(), isFalse);

    await pickDropdownEntry(tester, find.byKey(_fieldKey), 'Bravo');
    expect(formKey.currentState!.validate(), isTrue);
    formKey.currentState!.save();
    expect(saved, 'b');

    formKey.currentState!.reset();
    await tester.pump();
    expect(_shown(tester), 'Alpha');
  });

  testWidgets('announces its label and its value', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, value: 'a', onChanged: (_) {});
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byKey(_fieldKey),
          matching: find.byType(TextField),
        ),
      ),
      isSemantics(label: 'Pick', value: 'Alpha'),
    );
    handle.dispose();
  });

  group('on touch, a select-only field', () {
    testWidgets('opens on tap without raising the keyboard', (tester) async {
      await _pump(tester, value: 'a', onChanged: (_) {});
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      expect(find.text('Bravo'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.testTextInput.hasAnyClients, isFalse);
    });

    testWidgets('a dense field is still at least 44 pt tall', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AppDropdownField<String?>(
              key: _fieldKey,
              value: 'a',
              entries: _entries,
              decoration: const InputDecoration(
                labelText: 'Pick',
                isDense: true,
              ),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(_fieldKey)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('with a hardware keyboard, Esc and go back on its arrow '
        'reach the page', (tester) async {
      final pageEsc = await _pumpWithPageEsc(tester);
      // The field itself never takes the focus on touch: Tab reaches the arrow.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final arrow = find.descendant(
        of: find.byKey(_fieldKey),
        matching: find.byType(IconButton),
      );
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.descendant(of: arrow, matching: find.byWidget(focused.widget)),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(pageEsc(), 1);

      // Go back as an intent (Ctrl/Cmd-W, the menu bar's Close): it carries on
      // from the page, with the focus off the field and its arrow.
      FocusNode? focusAtGoBack;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Actions(
            actions: {
              GoBackIntent: CallbackAction<GoBackIntent>(
                onInvoke: (_) {
                  focusAtGoBack = FocusManager.instance.primaryFocus;
                  return null;
                },
              ),
            },
            child: Scaffold(
              body: AppDropdownField<String?>(
                key: _fieldKey,
                value: 'a',
                entries: _entries,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final onArrow = FocusManager.instance.primaryFocus!;
      Actions.invoke(onArrow.context!, const GoBackIntent());
      await tester.pumpAndSettle();
      expect(focusAtGoBack, isNotNull);
      expect(focusAtGoBack, isNot(onArrow));
    });

    testWidgets('gives entries at least a 44 pt target', (tester) async {
      await _pump(tester, value: 'a', onChanged: (_) {});
      expect(
        tester.getSize(find.byKey(_fieldKey)).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      final entry = find.ancestor(
        of: find.text('Bravo'),
        matching: find.byType(MenuItemButton),
      );
      expect(tester.getSize(entry).height, greaterThanOrEqualTo(44));
    });
  });

  group('a filterable field', () {
    testWidgets('raises the keyboard on tap, and typing narrows the menu', (
      tester,
    ) async {
      String? picked = 'a';
      await _pump(
        tester,
        value: 'a',
        filterable: true,
        onChanged: (v) => picked = v,
      );
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(find.byKey(_fieldKey), 'rav');
      await tester.pumpAndSettle();
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('None'), findsNothing);
      await tester.tap(find.text('Bravo'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
      expect(_shown(tester), 'Bravo');
    });

    // On every platform a mouse press outside a focused text field takes its
    // focus, so a filterable field (focused while it filters) loses it to the
    // press on an entry even on a tablet with a mouse. The press must neither
    // close the menu nor put the filter back, which would move the entries
    // out from under the pointer.
    testWidgets('a mouse click picks from the filtered menu', (tester) async {
      String? picked = 'a';
      await _pump(
        tester,
        value: 'a',
        filterable: true,
        onChanged: (v) => picked = v,
      );
      await press(tester, find.byKey(_fieldKey), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'rav');
      await tester.pumpAndSettle();
      expect(find.text('None'), findsNothing, reason: 'the menu is filtered');
      await press(
        tester,
        dropdownEntry('Bravo'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(picked, 'b');
      expect(_shown(tester), 'Bravo');
    }, variant: TargetPlatformVariant.all());

    testWidgets('a scroll the user makes closes the menu for good', (
      tester,
    ) async {
      await setScreenSize(tester, const Size(400, 300));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppDropdownField<String?>(
                  key: _fieldKey,
                  value: 'a',
                  entries: _entries,
                  filterable: true,
                  decoration: const InputDecoration(labelText: 'Pick'),
                  onChanged: (_) {},
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsWidgets);
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // A later scroll of the page, not the one focus makes.
      unawaited(
        scroll.position.animateTo(
          40,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0), reason: 'it scrolled');
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('stays open when taking focus scrolls the page', (
      tester,
    ) async {
      // Half below the fold of a scrolling page: focusing the field scrolls
      // it into view, and any scroll under an open menu shuts it.
      await setScreenSize(tester, const Size(400, 300));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 250),
                AppDropdownField<String?>(
                  key: _fieldKey,
                  value: 'a',
                  entries: _entries,
                  filterable: true,
                  decoration: const InputDecoration(labelText: 'Pick'),
                  onChanged: (_) {},
                ),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      );
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0), reason: 'it scrolled');
      expect(find.byType(MenuItemButton), findsWidgets);
    });

    testWidgets('puts back the current choice when typing matched nothing', (
      tester,
    ) async {
      var calls = 0;
      await _pump(
        tester,
        value: 'a',
        filterable: true,
        onChanged: (_) => calls++,
      );
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), 'zzz');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(_shown(tester), 'Alpha');
    });
  });

  group('on desktop', () {
    testWidgets('after a pick through the arrow, Esc reaches the page', (
      tester,
    ) async {
      var pageEsc = 0;
      String? picked = 'a';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Focus(
              // Stands for whatever around the field answers Esc: an inline
              // editor that closes, or the app's go-back.
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  pageEsc++;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: AppDropdownField<String?>(
                key: _fieldKey,
                value: 'a',
                entries: _entries,
                decoration: const InputDecoration(labelText: 'Pick'),
                onChanged: (v) => picked = v,
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(_fieldKey),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(dropdownEntry('Bravo'));
      await tester.pumpAndSettle();
      expect(picked, 'b');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(pageEsc, 1);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a click outside that dismisses the menu leaves the focus '
        'where the click left it', (tester) async {
      await _pumpWithPageEsc(tester);
      await tester.tap(find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsWidgets);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('blank'))));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(_fieldKey),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.focusNode.hasFocus, isFalse);
    }, variant: TargetPlatformVariant.desktop());

    // The mouse press on an entry takes the focus off the field before the
    // release picks it (a text field drops its focus on a click anywhere
    // outside itself, the menu included). A menu that closed on that blur
    // was gone before the release, so no click picked anything (#2292).
    testWidgets('a mouse click picks an entry, and the focus comes back to '
        'the field', (tester) async {
      String? picked = 'a';
      await _pump(tester, value: 'a', onChanged: (v) => picked = v);
      await press(tester, find.byKey(_fieldKey));
      await tester.pumpAndSettle();
      await press(tester, dropdownEntry('Bravo'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
      expect(_shown(tester), 'Bravo');
      expect(find.byType(MenuItemButton), findsNothing);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(_fieldKey),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.focusNode.hasFocus, isTrue);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('Tab away closes an open menu', (tester) async {
      await _pump(tester, value: 'a', onChanged: (_) {});
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a parent rebuild keeps the keyboard highlight', (
      tester,
    ) async {
      String? picked = 'a';
      await _pump(tester, value: 'a', onChanged: (v) => picked = v);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      for (var i = 0; i < _entries.length && _shown(tester) != 'Bravo'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(_shown(tester), 'Bravo');
      // The parent rebuilds with equal entries in a new list, as an editor
      // does on any change of its own.
      await _pump(
        tester,
        value: 'a',
        onChanged: (v) => picked = v,
        entries: [..._entries],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, 'b');
    }, variant: TargetPlatformVariant.desktop());

    for (final compact in [false, true]) {
      testWidgets(
        'Tab reaches the ${compact ? 'compact ' : ''}field, the arrows '
        'and Enter pick, Esc closes without a pick',
        (tester) async {
          String? picked = 'a';
          await _pump(
            tester,
            value: 'a',
            compact: compact,
            onChanged: (v) => picked = v,
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final field = find.descendant(
            of: find.byKey(_fieldKey),
            matching: find.byType(EditableText),
          );
          expect(
            tester.widget<EditableText>(field).focusNode.hasFocus,
            isTrue,
            reason: 'the first Tab stop is the field itself',
          );

          // Enter opens; Down highlights an entry, which the field shows; Esc
          // closes and the field shows the current choice again.
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('Bravo'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(_shown(tester), isNot('Alpha'), reason: 'a highlight shows');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Bravo'), findsNothing);
          expect(picked, 'a');
          expect(_shown(tester), 'Alpha');

          // Enter opens; the arrows move the highlight, which the field shows;
          // Enter picks the highlighted entry.
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          for (
            var i = 0;
            i < _entries.length && _shown(tester) != 'Bravo';
            i++
          ) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await tester.pumpAndSettle();
          }
          expect(_shown(tester), 'Bravo');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('Charlie'), findsNothing, reason: 'the menu closed');
          expect(picked, 'b');
          expect(_shown(tester), 'Bravo');

          // The next Tab leaves the field for the next control, not the arrow.
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: find.byKey(const ValueKey('after')),
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode
                .hasFocus,
            isTrue,
          );
        },
        variant: TargetPlatformVariant.desktop(),
      );
    }
  });

  group('a compact field, a list row\'s trailing control', () {
    testWidgets('has no fill or box, only an underline, and keeps a 48 dp '
        'touch target', (tester) async {
      await _pump(tester, value: 'a', compact: true, onChanged: (_) {});
      final decorator = tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(_fieldKey),
          matching: find.byType(InputDecorator),
        ),
      );
      expect(decorator.decoration.filled, isFalse);
      expect(decorator.decoration.enabledBorder, isA<UnderlineInputBorder>());
      expect(decorator.decoration.border, isA<UnderlineInputBorder>());
      expect(
        tester.getSize(find.byKey(_fieldKey)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('is as wide as its widest entry, never cuts a value off, and '
        'starts its value where the field starts', (tester) async {
      await loadBundledFonts();
      for (final scale in [1.0, 2.0]) {
        // Enabled entries only, so the widest entry the field is sized by is
        // one of those measured.
        final entries = _entries.where((e) => e.enabled).toList();
        for (final entry in entries) {
          await _pump(
            tester,
            value: entry.value,
            entries: entries,
            compact: true,
            textScale: scale,
            onChanged: (_) {},
          );
          expect(_shown(tester), entry.label);
          expectClosedValueFits(tester, find.byKey(_fieldKey));
        }
      }
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(_fieldKey),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.textAlign, TextAlign.start);
      // Narrower than the page: sized to its entries, not filling the row.
      expect(tester.getSize(find.byKey(_fieldKey)).width, lessThan(400));
    });

    testWidgets('right to left, too, never cuts its widest value off', (
      tester,
    ) async {
      await loadBundledFonts();
      final entries = _entries.where((e) => e.enabled).toList();
      for (final entry in entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: Center(
                  child: AppDropdownField<String?>(
                    key: _fieldKey,
                    compact: true,
                    fillWidth: false,
                    value: entry.value,
                    entries: entries,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_shown(tester), entry.label);
        expectClosedValueFits(tester, find.byKey(_fieldKey));
      }
    });

    for (final density in [VisualDensity.standard, VisualDensity.compact]) {
      testWidgets('is 48 dp tall at 1x text at $density', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(visualDensity: density),
            home: Scaffold(
              body: Center(
                child: AppDropdownField<String?>(
                  key: _fieldKey,
                  compact: true,
                  fillWidth: false,
                  value: 'a',
                  entries: _entries,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byKey(_fieldKey)).height, 48);
      });
    }

    testWidgets('announces its value', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, value: 'b', compact: true, onChanged: (_) {});
      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byKey(_fieldKey),
            matching: find.byType(TextField),
          ),
        ),
        isSemantics(value: 'Bravo'),
      );
      handle.dispose();
    });
  });

  testWidgets('with clearsAfterPick, a pick is reported and the field goes '
      'back to its hint', (tester) async {
    final picks = <String?>[];
    await _pump(
      tester,
      value: null,
      entries: _entries.skip(1).toList(),
      compact: true,
      clearsAfterPick: true,
      onChanged: picks.add,
    );
    expect(_shown(tester), '');
    await pickDropdownEntry(tester, find.byKey(_fieldKey), 'Alpha');
    expect(picks, ['a']);
    expect(_shown(tester), '', reason: 'back to the hint');
    // The same entry again is a second action, not "no change".
    await pickDropdownEntry(tester, find.byKey(_fieldKey), 'Alpha');
    expect(picks, ['a', 'a']);
    expect(_shown(tester), '');
  });

  testWidgets('at 2x text on a phone, the field stays one line and the open '
      'entries wrap', (tester) async {
    await loadBundledFonts();
    await setScreenSize(tester, const Size(360, 780));
    const long = 'A long entry that a translation or a user might well write';
    await _pump(
      tester,
      value: 'a',
      onChanged: (_) {},
      textScale: 2,
      entries: const [
        AppDropdownEntry(value: 'a', label: long),
        AppDropdownEntry(value: 'b', label: 'Bravo'),
      ],
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_fieldKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The open entry wraps rather than clipping: it is taller than a
    // one-line entry, and no wider than the screen.
    final longEntry = tester.getSize(dropdownEntry(long));
    final shortEntry = tester.getSize(dropdownEntry('Bravo'));
    expect(longEntry.width, lessThanOrEqualTo(360));
    expect(longEntry.height, greaterThan(shortEntry.height));
  });
}
