// The dance editor's "Add figures from text" sheet (#2326): several figure
// lines at once, each read as the Move box reads a typed line.
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/repositories_scope.dart';
import 'package:compendium_app/src/data/settings_keys.dart';
import 'package:compendium_app/src/data/shorthand_mappings_controller.dart';
import 'package:compendium_app/src/data/shorthand_mappings_scope.dart';
import 'package:compendium_app/src/screens/dance_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'figures_support.dart';
import 'support/announcements.dart';
import 'support/l10n_harness.dart';
import 'support/test_repositories.dart';

final _now = DateTime.utc(2026, 1, 1);

/// Lines a caller might paste: a shorthand of their own (typed in another
/// case), a figure named in the active dialect, and ordinary figure lines.
const _lines = [
  'NS',
  '(8) long lines forward and back',
  '(8) follows chain',
  '(8) half hey',
  '(16) partner balance and swing',
  'circle left 3/4; turn alone',
];

Future<CompendiumRepositories> _repos({
  required bool freeText,
  DanceForm form = DanceForm.contra,
  List<Figure> figures = const [],
}) async {
  final repos = openTestRepositories();
  await repos.settings.set(kFreeTextEntryKey, freeText);
  await repos.dances.create(
    Dance(
      id: 'd1',
      title: 'Test',
      form: form,
      figures: figures,
      createdAt: _now,
      updatedAt: _now,
    ),
  );
  return repos;
}

Future<void> _pumpEditor(
  WidgetTester tester,
  CompendiumRepositories repos, {
  bool withShorthand = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 3600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final dialect = ValueNotifier<Dialect>(Dialect.leadsFollows);
  addTearDown(dialect.dispose);
  final shorthands = ShorthandMappingsController(repos.settings);
  addTearDown(shorthands.dispose);
  if (withShorthand) {
    await shorthands.upsert(
      ShorthandMapping(
        token: 'ns',
        figures: [
          Figure(
            move: 'swing',
            params: const {'who': 'neighbors', 'beats': 16},
          ),
        ],
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) => RepositoriesScope(
        repositories: repos,
        child: ActiveDialectScope(
          notifier: dialect,
          child: ShorthandMappingsScope(controller: shorthands, child: child!),
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-editor'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<String>(
                builder: (_) => const DanceEditorScreen(danceId: 'd1'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-editor')));
  await tester.pumpAndSettle();
}

Future<void> _openAddMenu(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('figure-add')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('figure-add')));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await _openAddMenu(tester);
  await tester.tap(find.byKey(const ValueKey('figure-add-from-text')));
  await tester.pumpAndSettle();
}

Future<void> _enterSheetText(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('figure-text-sheet-field')),
    text,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapAdd(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('figure-text-sheet-add')),
  );
  await tester.tap(find.byKey(const ValueKey('figure-text-sheet-add')));
  await tester.pumpAndSettle();
}

Future<List<Figure>> _saveAndRead(
  WidgetTester tester,
  CompendiumRepositories repos,
) async {
  await tester.tap(find.byKey(const ValueKey('save-dance')));
  await tester.pumpAndSettle();
  return figuresOf((await repos.dances.getById('d1'))!);
}

/// The figures typing [lines] one at a time into the Move box with Free-text
/// entry on gives.
Future<List<Figure>> _typedOneByOne(
  WidgetTester tester,
  List<String> lines, {
  DanceForm form = DanceForm.contra,
}) async {
  final repos = await _repos(freeText: true, form: form);
  await _pumpEditor(tester, repos);
  await _openAddMenu(tester);
  await tester.tap(find.byKey(const ValueKey('figure-add-figure')));
  await tester.pumpAndSettle();
  for (final line in lines) {
    await tester.enterText(
      find.byKey(const ValueKey('figure-free-text-field')),
      line,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('figure-free-text-submit')),
    );
    await tester.tap(find.byKey(const ValueKey('figure-free-text-submit')));
    await tester.pumpAndSettle();
  }
  final figures = await _saveAndRead(tester, repos);
  await tester.pumpWidget(const SizedBox());
  return figures;
}

/// The figures pasting [text] into the sheet and choosing Add figures gives.
Future<List<Figure>> _pasted(
  WidgetTester tester,
  String text, {
  required bool freeText,
  DanceForm form = DanceForm.contra,
}) async {
  final repos = await _repos(freeText: freeText, form: form);
  await _pumpEditor(tester, repos);
  await _openSheet(tester);
  await _enterSheetText(tester, text);
  await _tapAdd(tester);
  final figures = await _saveAndRead(tester, repos);
  await tester.pumpWidget(const SizedBox());
  return figures;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pasting six lines adds their figures, each as typing that line '
      'in the Move box adds it', (tester) async {
    final typed = await _typedOneByOne(tester, _lines);
    // One figure a line, and two for the `;` line.
    expect(typed, hasLength(7));
    // The shorthand and the dialect's name were read, not kept as text.
    expect(typed.first.move, 'swing');
    expect(typed.first.params['who'], 'neighbors');
    expect(typed.where((f) => f.isCustom), isEmpty);

    final pasted = await _pasted(tester, _lines.join('\n'), freeText: true);
    expect(pasted, typed);
  });

  testWidgets('it works the same with Free-text entry off', (tester) async {
    final typed = await _typedOneByOne(tester, _lines);
    final pasted = await _pasted(tester, _lines.join('\n'), freeText: false);
    expect(pasted, typed);
  });

  testWidgets('a contra line with a leading A1..C2 label reads as the line '
      'without it', (tester) async {
    final bare = await _pasted(tester, _lines.join('\n'), freeText: false);
    final labelled = await _pasted(
      tester,
      [
        'A1 ${_lines[0]}',
        'a1: ${_lines[1]}',
        'A2',
        'A2 ${_lines[2]}',
        'B1. ${_lines[3]}',
        'B2) ${_lines[4]}',
        'B2 ${_lines[5]}',
      ].join('\r\n'),
      freeText: false,
    );
    expect(labelled, bare);
  });

  testWidgets('an English "A1 1-8 lead up" reads as it does when typed', (
    tester,
  ) async {
    const line = 'A1 1-8 lead up';
    final typed = await _typedOneByOne(tester, [line], form: DanceForm.ecd);
    final pasted = await _pasted(
      tester,
      line,
      freeText: false,
      form: DanceForm.ecd,
    );
    expect(pasted, typed);
    expect(pasted.single.isCustom, isFalse);
  });

  testWidgets('the preview counts figures and marks unrecognized lines', (
    tester,
  ) async {
    final repos = await _repos(freeText: false);
    await _pumpEditor(tester, repos);
    await _openSheet(tester);
    expect(find.text('No figures to add yet'), findsOneWidget);
    await _enterSheetText(
      tester,
      '(16) partner balance and swing\nzorbulate the frobnicator',
    );
    final first = find.byKey(const ValueKey('figure-text-sheet-line-0'));
    final second = find.byKey(const ValueKey('figure-text-sheet-line-1'));
    expect(
      find.descendant(of: first, matching: find.textContaining('figure')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: first,
        matching: find.textContaining('Not recognized'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: second,
        matching: find.text('Not recognized: added as an unrecognized figure'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('figure-text-sheet-unrecognized')),
      findsOneWidget,
    );
    await _tapAdd(tester);
    final figures = await _saveAndRead(tester, repos);
    // The unrecognized line is kept as a figure carrying its text.
    expect(figures.last.isCustom, isTrue);
    expect(figures.last.customOrigin, CustomOrigin.importGap);
  });

  testWidgets('cancelling inserts nothing and leaves the dance unchanged', (
    tester,
  ) async {
    final existing = [
      Figure(move: 'swing', params: const {'beats': 16}),
    ];
    final repos = await _repos(freeText: false, figures: existing);
    await _pumpEditor(tester, repos);
    await _openSheet(tester);
    await _enterSheetText(tester, _lines.join('\n'));
    await tester.tap(find.byKey(const ValueKey('figure-text-sheet-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-text-sheet-field')), findsNothing);
    // Nothing was added: the list still holds only the existing row.
    expect(find.byKey(const ValueKey('figure-0-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-1-summary')), findsNothing);
    expect(await _saveAndRead(tester, repos), existing);
  });

  group('typed text is kept (pre-release audit finding F-02)', () {
    const field = ValueKey('figure-text-sheet-field');

    String sheetText(WidgetTester tester) =>
        tester.widget<TextField>(find.byKey(field)).controller!.text;

    testWidgets('a tap above the sheet asks first, and Keep editing keeps '
        'every line', (tester) async {
      final repos = await _repos(freeText: false);
      await _pumpEditor(tester, repos);
      await _openSheet(tester);
      await _enterSheetText(tester, _lines.join('\n'));
      await tester.tapAt(const Offset(600, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-cancel')));
      await tester.pumpAndSettle();
      expect(sheetText(tester), _lines.join('\n'));
    });

    testWidgets('Back asks first, and Discard closes it adding nothing', (
      tester,
    ) async {
      final existing = [
        Figure(move: 'swing', params: const {'beats': 16}),
      ];
      final repos = await _repos(freeText: false, figures: existing);
      await _pumpEditor(tester, repos);
      await _openSheet(tester);
      await _enterSheetText(tester, _lines.join('\n'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(field), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discard-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(field), findsNothing);
      expect(await _saveAndRead(tester, repos), existing);
    });

    testWidgets('Escape asks first too', (tester) async {
      final repos = await _repos(freeText: false);
      await _pumpEditor(tester, repos);
      await _openSheet(tester);
      await _enterSheetText(tester, _lines.join('\n'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('discard-confirm')), findsOneWidget);
      expect(find.byKey(field), findsOneWidget);
    });

    testWidgets('a swipe down does not close it', (tester) async {
      final repos = await _repos(freeText: false);
      await _pumpEditor(tester, repos);
      await _openSheet(tester);
      await _enterSheetText(tester, _lines.join('\n'));
      // From the button row, which is outside the sheet's scrolling body.
      await tester.drag(
        find.byKey(const ValueKey('figure-text-sheet-cancel')),
        const Offset(0, 1500),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(field), findsOneWidget);
      expect(sheetText(tester), _lines.join('\n'));
    });

    testWidgets('an empty sheet still closes on a tap above it', (
      tester,
    ) async {
      final repos = await _repos(freeText: false);
      await _pumpEditor(tester, repos);
      await _openSheet(tester);
      await tester.tapAt(const Offset(600, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(field), findsNothing);
      expect(find.byKey(const ValueKey('discard-confirm')), findsNothing);
    });
  });

  testWidgets('one Undo takes out every figure the sheet added', (
    tester,
  ) async {
    final existing = [
      Figure(move: 'swing', params: const {'beats': 16}),
    ];
    final repos = await _repos(freeText: false, figures: existing);
    await _pumpEditor(tester, repos);
    await _openSheet(tester);
    await _enterSheetText(tester, _lines.join('\n'));
    await _tapAdd(tester);
    expect(find.byKey(const ValueKey('figure-5-summary')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('undo-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('figure-0-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-1-summary')), findsNothing);
  });

  testWidgets('after Add figures, focus is on the last added row and the '
      'count is announced', (tester) async {
    final announcements = recordAnnouncements();
    final repos = await _repos(
      freeText: false,
      figures: [
        Figure(move: 'swing', params: const {'beats': 16}),
      ],
    );
    await _pumpEditor(tester, repos);
    await _openSheet(tester);
    await _enterSheetText(tester, _lines.join('\n'));
    await _tapAdd(tester);
    expect(find.byKey(const ValueKey('figure-7-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-8-summary')), findsNothing);

    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    bool holdsFocus(String key) {
      var found = false;
      tester.element(find.byKey(ValueKey(key))).visitAncestorElements((e) {
        if (e == focused) found = true;
        return !found;
      });
      return found;
    }

    expect(holdsFocus('figure-7-summary'), isTrue);
    expect(holdsFocus('figure-6-summary'), isFalse);
    expect(announcements, contains('Added 7 figures.'));
  });

  group('input over a cap is refused and inserts nothing', () {
    Future<void> expectRefused(
      WidgetTester tester,
      String text,
      String message,
    ) async {
      final repos = await _repos(freeText: false);
      await _pumpEditor(tester, repos);
      await _openSheet(tester);
      await _enterSheetText(tester, text);
      expect(find.textContaining(message), findsOneWidget);
      final add = tester.widget<FilledButton>(
        find.byKey(const ValueKey('figure-text-sheet-add')),
      );
      expect(add.onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('figure-text-sheet-add')));
      await tester.pumpAndSettle();
      // Still open, and the dance has no figures.
      expect(
        find.byKey(const ValueKey('figure-text-sheet-field')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('figure-text-sheet-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('figure-0-summary')), findsNothing);
    }

    testWidgets('too many lines', (tester) async {
      await expectRefused(
        tester,
        List.filled(maxFigureTextLines + 1, 'swing').join('\n'),
        'more than $maxFigureTextLines lines',
      );
    });

    testWidgets('a line too long to read as one figure line', (tester) async {
      await expectRefused(
        tester,
        'swing\n${'x' * (maxFreeTextEntryLength + 1)}',
        'longer than',
      );
    });

    testWidgets('too much text', (tester) async {
      await expectRefused(
        tester,
        'swing\n' * (maxFigureTextLength ~/ 6 + 1),
        'characters',
      );
    });
  });
}
