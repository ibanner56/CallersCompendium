// The desktop keyboard map, mouse Back and right-click on list rows (PLAT-7;
// `docs/user/accessibility.md` "Using the keyboard"). The macOS menu bar,
// which invokes the same intents, is covered in `app_menu_bar_test.dart`.
import 'package:compendium_app/main.dart';
import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/screens/dance_detail_screen.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_app/src/screens/perform_program_screen.dart';
import 'package:compendium_app/src/screens/program_editor_screen.dart';
import 'package:compendium_app/src/screens/settings_screen.dart';
import 'package:compendium_app/src/widgets/app_shortcuts.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/full_app_harness.dart';

const _palette = ValueKey('command-palette');
const _searchField = ValueKey('collection-search-field');

/// Wide enough for the dance editor's form, which overflows a narrow window
/// under the test font.
const _wide = Size(1200, 1600);

Future<AppData> _pump(
  WidgetTester tester, {
  Size size = const Size(500, 900),
}) async {
  // Narrow by default, so the dance detail is a pushed route rather than the
  // inline pane.
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final appData = openTestAppData();
  final repos = appData.repositories;
  final stamp = DateTime.utc(2026, 1, 1);
  await repos.choreographers.upsert(
    Choreographer(id: 'c1', name: 'Gene Hubert'),
  );
  await repos.dances.create(
    Dance(id: 'd1', title: 'Petronella', createdAt: stamp, updatedAt: stamp),
  );
  await repos.programs.create(
    Program(
      id: 'p1',
      title: 'Autumn Ball',
      slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
      createdAt: stamp,
      updatedAt: stamp,
    ),
  );
  await tester.pumpWidget(
    CompendiumApp(
      appData: appData,
      windowService: NoopWindowService(repos.settings),
      integrityCheck: () async => true,
    ),
  );
  await tester.pumpAndSettle();
  return appData;
}

/// Presses [key], with [modifier] held when one is given.
Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? modifier,
}) async {
  if (modifier != null) await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  if (modifier != null) await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _openDanceDetail(WidgetTester tester) async {
  await tester.tap(find.text('Petronella'));
  await tester.pumpAndSettle();
  expect(find.byType(DanceDetailScreen), findsOneWidget);
}

Future<void> _openProgramSummary(WidgetTester tester) async {
  await tester.tap(find.text('Programs'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Autumn Ball'));
  await tester.pumpAndSettle();
}

Future<void> _openProgramEditor(WidgetTester tester) async {
  await _openProgramSummary(tester);
  await tester.tap(find.byKey(const ValueKey('open-builder')));
  await tester.pumpAndSettle();
  expect(find.byType(ProgramEditorScreen), findsOneWidget);
}

Future<void> _openPerform(WidgetTester tester) async {
  await _openProgramSummary(tester);
  await tester.tap(find.byKey(const ValueKey('summary-perform')));
  await tester.pumpAndSettle();
  expect(find.byType(PerformProgramScreen), findsOneWidget);
}

/// Opens the new-dance editor and types a title, so it has unsaved changes.
Future<void> _openDirtyDanceEditor(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('new-dance')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('title-field')), 'Rory');
  await tester.pump();
}

bool _settingsShowing(WidgetTester tester) =>
    find.byType(SettingsScreen).hitTestable().evaluate().isNotEmpty;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(rootBundle.clear);

  group('back: Esc, Ctrl/Cmd-W and mouse Back', () {
    testWidgets('Esc leaves a pushed page', (tester) async {
      await _pump(tester);
      await _openDanceDetail(tester);

      await _press(tester, LogicalKeyboardKey.escape);

      expect(find.byType(DanceDetailScreen), findsNothing);
      expect(find.text('Petronella'), findsOneWidget);
    });

    testWidgets('Ctrl-W and Cmd-W leave a pushed page', (tester) async {
      await _pump(tester);
      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await _openDanceDetail(tester);
        await _press(tester, LogicalKeyboardKey.keyW, modifier: modifier);
        expect(
          find.byType(DanceDetailScreen),
          findsNothing,
          reason: '$modifier',
        );
      }
    });

    testWidgets('the mouse Back button leaves a pushed page', (tester) async {
      await _pump(tester);
      await _openDanceDetail(tester);

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await gesture.down(tester.getCenter(find.byType(DanceDetailScreen)));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(DanceDetailScreen), findsNothing);
    });

    testWidgets('Esc in an editor with unsaved changes asks first', (
      tester,
    ) async {
      await _pump(tester, size: _wide);
      await _openDirtyDanceEditor(tester);

      await _press(tester, LogicalKeyboardKey.escape);

      expect(find.byKey(const ValueKey('discard-cancel')), findsOneWidget);
      // A second Esc closes the question, as a tap outside it would, and keeps
      // the edits.
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('discard-cancel')), findsNothing);
      expect(find.byType(DanceEditorScreen), findsOneWidget);
      expect(find.text('Rory'), findsOneWidget);
    });

    testWidgets('Esc in a text field leaves a page with nothing unsaved', (
      tester,
    ) async {
      await _pump(tester, size: _wide);
      await tester.tap(find.byKey(const ValueKey('new-dance')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('title-field')));
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isA<Focus>().having((f) => f.debugLabel, 'debugLabel', 'EditableText'),
      );

      await _press(tester, LogicalKeyboardKey.escape);

      expect(find.byType(DanceEditorScreen), findsNothing);
    });

    testWidgets('Esc closes an autocomplete\'s options before the page', (
      tester,
    ) async {
      await _pump(tester, size: _wide);
      await tester.tap(find.byKey(const ValueKey('new-dance')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('author-input')),
        'Gene',
      );
      await tester.pumpAndSettle();
      final option = find.byKey(const ValueKey('author-option-c1'));
      expect(option, findsOneWidget);

      await _press(tester, LogicalKeyboardKey.escape);

      expect(option, findsNothing);
      expect(find.byType(DanceEditorScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('discard-cancel')), findsNothing);
    });

    testWidgets('Esc closes an open menu and leaves the page under it', (
      tester,
    ) async {
      await _pump(tester);
      await _openDanceDetail(tester);
      await tester.tap(find.byKey(const ValueKey('dance-actions-overflow')));
      await tester.pumpAndSettle();
      final menu = find.byWidgetPredicate((w) => w is PopupMenuItem);
      expect(menu, findsWidgets);

      await _press(tester, LogicalKeyboardKey.escape);

      expect(menu, findsNothing);
      expect(find.byType(DanceDetailScreen), findsOneWidget);
    });

    testWidgets('Esc does not leave Perform', (tester) async {
      await _pump(tester);
      await _openPerform(tester);

      await _press(tester, LogicalKeyboardKey.escape);

      expect(find.byType(PerformProgramScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('perform-exit-dialog')), findsNothing);
    });

    testWidgets('Ctrl-W in Perform asks before it leaves', (tester) async {
      await _pump(tester);
      await _openPerform(tester);

      await _press(
        tester,
        LogicalKeyboardKey.keyW,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byKey(const ValueKey('perform-exit-dialog')), findsOneWidget);
      expect(find.byType(PerformProgramScreen), findsOneWidget);
    });

    testWidgets('Esc on the shell does nothing', (tester) async {
      await _pump(tester);

      await _press(tester, LogicalKeyboardKey.escape);

      expect(find.text('Petronella'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Ctrl/Cmd-S saves the open editor', () {
    testWidgets('in the dance editor', (tester) async {
      final appData = await _pump(tester, size: _wide);
      await _openDirtyDanceEditor(tester);

      await _press(
        tester,
        LogicalKeyboardKey.keyS,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byType(DanceEditorScreen), findsNothing);
      final titles = [
        for (final d in await appData.repositories.dances.listAll()) d.title,
      ];
      expect(titles, contains('Rory'));
    });

    testWidgets('in the program editor', (tester) async {
      final appData = await _pump(tester);
      await _openProgramEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('program-title')),
        'Winter Ball',
      );
      await tester.pump();

      await _press(
        tester,
        LogicalKeyboardKey.keyS,
        modifier: LogicalKeyboardKey.metaLeft,
      );

      final saved = await appData.repositories.programs.getById('p1');
      expect(saved?.title, 'Winter Ball');
    });

    testWidgets('the program editor holds the focus as soon as it opens', (
      tester,
    ) async {
      await _pump(tester);
      await _openProgramEditor(tester);

      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(Actions.maybeFind<SaveIntent>(focused), isNotNull);
    });

    testWidgets('a new program still puts the focus in its title', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-program')));
      await tester.pumpAndSettle();

      final title = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('program-title')),
          matching: find.byType(EditableText),
        ),
      );
      expect(title.focusNode.hasFocus, isTrue);
    });

    testWidgets('outside an editor it does nothing', (tester) async {
      await _pump(tester);
      await _openDanceDetail(tester);

      await _press(
        tester,
        LogicalKeyboardKey.keyS,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byType(DanceDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Ctrl/Cmd-N, Ctrl/Cmd-, and Ctrl/Cmd-F', () {
    testWidgets('Ctrl-N opens the new-dance editor from the Programs tab', (
      tester,
    ) async {
      await _pump(tester, size: _wide);
      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();

      await _press(
        tester,
        LogicalKeyboardKey.keyN,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byType(DanceEditorScreen), findsOneWidget);
    });

    testWidgets('Cmd-N leaves a pushed page first', (tester) async {
      await _pump(tester, size: _wide);
      await _openProgramEditor(tester);

      await _press(
        tester,
        LogicalKeyboardKey.keyN,
        modifier: LogicalKeyboardKey.metaLeft,
      );

      expect(find.byType(DanceEditorScreen), findsOneWidget);
      expect(find.byType(ProgramEditorScreen), findsNothing);
    });

    testWidgets('Cmd-, shows Settings from a pushed page', (tester) async {
      await _pump(tester);
      await _openDanceDetail(tester);
      expect(_settingsShowing(tester), isFalse);

      await _press(
        tester,
        LogicalKeyboardKey.comma,
        modifier: LogicalKeyboardKey.metaLeft,
      );

      expect(find.byType(DanceDetailScreen), findsNothing);
      expect(_settingsShowing(tester), isTrue);
    });

    testWidgets('Ctrl-, from an editor with unsaved changes asks, and stays', (
      tester,
    ) async {
      await _pump(tester, size: _wide);
      await _openDirtyDanceEditor(tester);

      await _press(
        tester,
        LogicalKeyboardKey.comma,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byKey(const ValueKey('discard-cancel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(DanceEditorScreen), findsOneWidget);
      expect(find.text('Rory'), findsOneWidget);
      expect(_settingsShowing(tester), isFalse);
    });

    testWidgets('a dialog keeps the app commands out until it closes', (
      tester,
    ) async {
      await _pump(tester);
      await _openDanceDetail(tester);
      // The search palette is a dialog over the page.
      await _press(
        tester,
        LogicalKeyboardKey.keyK,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(find.byKey(_palette), findsOneWidget);

      await _press(
        tester,
        LogicalKeyboardKey.comma,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byKey(_palette), findsOneWidget);
      expect(find.byType(DanceDetailScreen), findsOneWidget);
      expect(_settingsShowing(tester), isFalse);
    });

    testWidgets('Ctrl-N, Ctrl-F and Ctrl-, do nothing in Perform', (
      tester,
    ) async {
      await _pump(tester);
      await _openPerform(tester);

      for (final key in [
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.comma,
      ]) {
        await _press(tester, key, modifier: LogicalKeyboardKey.controlLeft);
      }

      expect(find.byType(PerformProgramScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('perform-exit-dialog')), findsNothing);
      expect(find.byType(DanceEditorScreen), findsNothing);
      expect(find.byKey(_palette), findsNothing);
    });

    testWidgets('Ctrl-F focuses the Collection search box', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byKey(_searchField), 'Pet');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await _press(
        tester,
        LogicalKeyboardKey.keyF,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      final field = tester.widget<TextField>(find.byKey(_searchField));
      expect(field.focusNode?.hasFocus, isTrue);
      expect(
        field.controller?.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      expect(find.byKey(_palette), findsNothing);
    });

    testWidgets('Ctrl-F opens global search away from the Collection', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();

      await _press(
        tester,
        LogicalKeyboardKey.keyF,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byKey(_palette), findsOneWidget);
    });
  });

  group('right-click on a list row opens its ⋮ menu', () {
    testWidgets('a dance row', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('Petronella'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('dance-action-delete')), findsOneWidget);
      expect(find.byType(DanceDetailScreen), findsNothing);
    });

    testWidgets('a program row', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Programs'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Autumn Ball'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('program-action-delete')),
        findsOneWidget,
      );
    });
  });
}
