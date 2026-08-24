import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/dialect_editor_screen.dart';

import '../support/l10n_harness.dart';

void main() {
  Finder validationError() =>
      find.byKey(const ValueKey('dialect-validation-error'));
  Finder preview() => find.byKey(const ValueKey('dialect-preview'));

  String previewText(WidgetTester tester) {
    final column = tester.widget<Column>(preview());
    final buffer = StringBuffer();
    for (final child in column.children) {
      if (child is Padding && child.child is Text) {
        buffer.writeln((child.child! as Text).data);
      }
    }
    return buffer.toString();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = find.byType(Scrollable).first;
    for (final delta in [-300.0, 300.0]) {
      for (var attempt = 0; attempt < 30; attempt++) {
        if (target.evaluate().isNotEmpty) break;
        await tester.drag(scrollable, Offset(0, delta));
        await tester.pumpAndSettle();
      }
      if (target.evaluate().isNotEmpty) break;
    }
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('typing a colliding substitution surfaces the collision live', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(initial: Dialect.canonical),
      ),
    );

    // No issues before any edit.
    expect(validationError(), findsNothing);

    // Two role terms mapping to the same word is a reversal collision.
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role1-singular')),
      'star',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role2-singular')),
      'star',
    );
    await tester.pump();

    // Surfaced live — before any Save tap.
    expect(validationError(), findsOneWidget);
    expect(tester.widget<Text>(validationError()).data, contains('ambiguous'));
  });

  testWidgets('a valid edit clears live validation issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(initial: Dialect.canonical),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('dialect-role1-singular')),
      'star',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role2-singular')),
      'star',
    );
    await tester.pump();
    expect(validationError(), findsOneWidget);

    // Fixing the second role term removes the collision.
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role2-singular')),
      'comet',
    );
    await tester.pump();
    expect(validationError(), findsNothing);
  });

  testWidgets('the preview reflects role-term edits live', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(initial: Dialect.canonical),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('dialect-role1-singular')),
      'lark',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role1-plural')),
      'larks',
    );
    await tester.pump();

    // Scroll the preview (at the bottom of the editor list) into view.
    await reveal(tester, preview());
    await tester.pumpAndSettle();

    // The sample figures + free text render the new plural role term, and no
    // longer show the bare canonical token.
    final text = previewText(tester).toLowerCase();
    expect(text, contains('larks'));
    expect(text, isNot(contains('role1s')));
  });

  testWidgets(
    'move wording templates show slots, warnings, and reset separately',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: DialectEditorScreen(
            initial: Dialect(
              name: 'Wording',
              moves: const {'swing': 'twirl'},
              moveWordings: const {'swing': '{who} {move} {future}'},
            ),
          ),
        ),
      );

      final toggle = find.byKey(const ValueKey('dialect-wordings-toggle'));
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dialect-wording-swing')),
        findsOneWidget,
      );
      expect(find.textContaining('Unknown slots are empty'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('dialect-wording-preview-swing')),
            )
            .data,
        contains('twirl'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('dialect-wording-swing')),
        '{who',
      );
      await tester.pump();
      expect(
        find.text(
          'This template is invalid, so the normal wording will be used.',
        ),
        findsOneWidget,
      );

      final restore = find.byKey(const ValueKey('dialect-wordings-restore'));
      await reveal(tester, restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dialect-wordings-reset-dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('dialect-wordings-reset-confirm')),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('dialect-wording-swing')), findsNothing);
      final movesToggle = find.byKey(const ValueKey('dialect-moves-toggle'));
      await reveal(tester, movesToggle);
      await tester.tap(movesToggle);
      await tester.pump();
      expect(find.byKey(const ValueKey('dialect-move-swing')), findsOneWidget);
    },
  );

  testWidgets('resetting wording templates requires confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(
          initial: Dialect(
            name: 'Wording',
            moveWordings: const {'swing': '{who} {move}'},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('dialect-wordings-toggle')));
    await tester.pumpAndSettle();
    final restore = find.byKey(const ValueKey('dialect-wordings-restore'));
    await reveal(tester, restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('dialect-wordings-reset-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('dialect-wording-swing')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('dialect-wordings-reset-confirm')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dialect-wording-swing')), findsNothing);
  });

  testWidgets('restoring discouraged terms requires confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(
          initial: Dialect(name: 'Terms', discouragedTerms: const ['avoid']),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('dialect-discouraged-toggle'));
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final restore = find.byKey(const ValueKey('dialect-discouraged-restore'));
    await reveal(tester, restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('dialect-discouraged-reset-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dialect-discouraged-chip-avoid')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('dialect-discouraged-reset-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dialect-discouraged-chip-avoid')),
      findsNothing,
    );
  });

  testWidgets('back navigation prompts to save or exit without saving', (
    tester,
  ) async {
    Dialect? popped;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<Dialect>(
                MaterialPageRoute(
                  builder: (_) =>
                      DialectEditorScreen(initial: Dialect.canonical),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role1-singular')),
      'star',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dialect-exit-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialect-exit-save')));
    await tester.pumpAndSettle();
    expect(popped?.roles['role1']?.singular, 'star');
  });

  testWidgets('back navigation can exit without saving', (tester) async {
    var didReturn = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await Navigator.of(context).push<Dialect>(
                MaterialPageRoute(
                  builder: (_) =>
                      DialectEditorScreen(initial: Dialect.canonical),
                ),
              );
              didReturn = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role1-singular')),
      'star',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dialect-exit-without-saving')));
    await tester.pumpAndSettle();

    expect(didReturn, isTrue);
  });

  testWidgets('sections use uppercase expansion headers and action colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(
          initial: Dialect(
            name: 'Sections',
            moves: const {'swing': 'twirl'},
            moveWordings: const {'swing': '{who} {move}'},
          ),
        ),
      ),
    );

    for (final entry in [
      ('dialect-roles-toggle', 'ROLE TERMS'),
      ('dialect-moves-toggle', 'MOVE SUBSTITUTIONS'),
      ('dialect-dancers-toggle', 'DANCER SUBSTITUTIONS'),
      ('dialect-wordings-toggle', 'MOVE WORDING TEMPLATES'),
      ('dialect-discouraged-toggle', 'DISCOURAGED TERMS'),
    ]) {
      expect(find.byKey(ValueKey(entry.$1)), findsOneWidget);
      expect(find.text(entry.$2), findsOneWidget);
    }
    expect(find.text('PREVIEW'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNWidgets(5));

    final wordingsToggle = find.byKey(
      const ValueKey('dialect-wordings-toggle'),
    );
    await reveal(tester, wordingsToggle);
    await tester.tap(wordingsToggle);
    await tester.pumpAndSettle();

    final context = tester.element(wordingsToggle);
    final theme = Theme.of(context);
    final reset = tester.widget<TextButton>(
      find.byKey(const ValueKey('dialect-wordings-restore')),
    );
    expect(reset.style!.foregroundColor!.resolve({}), theme.colorScheme.error);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const ValueKey('dialect-wording-delete-swing')),
              matching: find.byType(Icon),
            ),
          )
          .color,
      theme.colorScheme.error,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('dialect-add-move-wording')),
              matching: find.text('Add a move wording template…'),
            ),
          )
          .style!
          .color,
      theme.colorScheme.secondary,
    );

    final moveToggle = find.byKey(const ValueKey('dialect-moves-toggle'));
    await reveal(tester, moveToggle);
    await tester.tap(moveToggle);
    await tester.pumpAndSettle();
    final moves = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('dialect-add-move')),
    );
    moves.onChanged!(
      moves.items!
          .map((item) => item.value)
          .firstWhere((id) => id == 'balance'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('dialect-move-balance'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('dialect-move-swing'))).dy,
      ),
    );
  });

  testWidgets('adding a wording updates the main preview immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(
          initial: Dialect(name: 'Wording', moves: const {'swing': 'twirl'}),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('dialect-wordings-toggle'));
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final menu = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('dialect-add-move-wording')),
    );
    menu.onChanged!(
      menu.items!
          .map((item) => item.value)
          .firstWhere((value) => value == 'swing'),
    );
    await tester.pumpAndSettle();

    await reveal(tester, preview());
    expect(previewText(tester), contains('twirl'));
  });

  testWidgets('omitting only move shows an optional-slot notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(
          initial: Dialect(
            name: 'Wording',
            moveWordings: const {
              'hey':
                  '{who} {article} {dir} {length} {shoulder} {until} {ricochets}',
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('dialect-wordings-toggle')));
    await tester.pumpAndSettle();

    final notice = find.text('This template omits optional slots: {move}');
    expect(notice, findsOneWidget);
    expect(
      tester.widget<Text>(notice).style!.color,
      Theme.of(tester.element(notice)).colorScheme.tertiary,
    );

    await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dialect-wording-confirm-dialog')),
      findsNothing,
    );
  });

  testWidgets('saving omitted wording slots requires confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: DialectEditorScreen(
          initial: Dialect(
            name: 'Wording',
            moveWordings: const {'swing': '{move}'},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dialect-wording-confirm-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('Save anyway?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dialect-wording-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dialect-wording-confirm-dialog')),
      findsNothing,
    );
  });

  testWidgets('saving malformed wording templates keeps the editor open', (
    tester,
  ) async {
    final invalidTemplates = [
      '{who',
      '{first-name}',
      '[{who}',
      '}',
      List.filled(kMaxMoveWordingLength + 1, 'x').join(),
    ];

    for (final template in invalidTemplates) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: DialectEditorScreen(
            initial: Dialect(
              name: 'Invalid wording',
              moveWordings: {'swing': template},
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
      await tester.pumpAndSettle();

      expect(find.byType(DialectEditorScreen), findsOneWidget);
      expect(validationError(), findsOneWidget, reason: 'template: $template');
      expect(
        find.textContaining('Fix invalid move wording templates before saving'),
        findsOneWidget,
        reason: 'template: $template',
      );
      expect(
        find.byKey(const ValueKey('dialect-wording-confirm-dialog')),
        findsNothing,
        reason: 'template: $template',
      );
    }
  });

  testWidgets('Save is still guarded: an invalid dialect is not returned', (
    tester,
  ) async {
    Dialect? popped;
    var didPop = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<Dialect>(
                    MaterialPageRoute(
                      builder: (_) =>
                          DialectEditorScreen(initial: Dialect.canonical),
                    ),
                  );
                  didPop = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Introduce a collision, then attempt to Save.
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role1-singular')),
      'star',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dialect-role2-singular')),
      'star',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
    await tester.pumpAndSettle();

    // The editor stayed open (no pop) and the error is shown.
    expect(didPop, isFalse);
    expect(popped, isNull);
    expect(validationError(), findsOneWidget);
  });

  testWidgets(
    'substitution fields expose their canonical term via semantics (a11y)',
    (tester) async {
      // A dialect carrying two move and two dancer substitutions, so each
      // editor renders multiple rows that must be told apart by AT.
      final dialect = Dialect(
        name: 'A11y',
        moves: const {'swing': 'twirl', 'balance': 'rock'},
        dancers: const {
          'neighbors': 'buddies',
          'nextNeighbors': 'next buddies',
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: DialectEditorScreen(initial: dialect),
        ),
      );

      // Reveal both collapsed substitution editors.
      final movesToggle = find.byKey(const ValueKey('dialect-moves-toggle'));
      await reveal(tester, movesToggle);
      await tester.tap(movesToggle);
      await tester.pumpAndSettle();

      final dancersToggle = find.byKey(
        const ValueKey('dialect-dancers-toggle'),
      );
      await reveal(tester, dancersToggle);
      await tester.tap(dancersToggle);
      await tester.pumpAndSettle();

      Future<void> expectFieldLabel(String key, String term) async {
        final field = find.byKey(ValueKey(key));
        await reveal(tester, field);
        await tester.pumpAndSettle();
        // Target the field's editable node directly; the leading Text label
        // shares the same term, so we assert the term lands on the text field
        // itself (its programmatic name), not merely somewhere in the row.
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        expect(
          tester.getSemantics(editable),
          isSemantics(label: term, isTextField: true),
          reason: 'field "$key" should announce its canonical term "$term"',
        );
      }

      // Each field carries its own programmatic label (canonical move display
      // name / humanized dancer token), not a shared generic hint — so a
      // screen-reader user can tell the substitution rows apart.
      await expectFieldLabel('dialect-move-swing', 'swing');
      await expectFieldLabel('dialect-move-balance', 'balance');
      await expectFieldLabel('dialect-dancer-neighbors', 'neighbors');
      await expectFieldLabel('dialect-dancer-nextNeighbors', 'next neighbors');
    },
  );

  // Issue #832. `_substitutableTokens` iterated `ParamVocab.pairDancerSets`,
  // so the four single-dancer identities were absent from this screen entirely
  // — there was no way to express "robin two" instead of the default "second
  // robin", for exactly the tokens a caller most wants to reword. And the row
  // label humanized camelCase, so adding them naively would have shown the raw
  // `twos role2` this issue is about IN THE SCREEN THAT FIXES IT.
  group('single-dancer identities are substitutable (#832)', () {
    Future<void> openDancers(WidgetTester tester, Dialect initial) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: DialectEditorScreen(initial: initial),
        ),
      );
      final toggle = find.byKey(const ValueKey('dialect-dancers-toggle'));
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    /// The add menu's own items, read off the widget rather than the rendered
    /// overlay: the list is long enough that the lower entries are never laid
    /// out, so a `find.text` sweep would silently under-report.
    ({List<String?> values, List<String?> labels}) addMenu(
      WidgetTester tester,
    ) {
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(const ValueKey('dialect-add-dancer')),
      );
      return (
        values: [for (final i in dropdown.items!) i.value],
        labels: [for (final i in dropdown.items!) (i.child as Text).data],
      );
    }

    testWidgets('the add menu offers all four, labelled by dialect', (
      tester,
    ) async {
      await openDancers(tester, Dialect.larksRobins);
      final menu = addMenu(tester);

      expect(menu.values, containsAll(ParamVocab.singleDancers));
      // THE TRAP: labelled through the dialect, never as the raw token.
      expect(
        menu.labels,
        containsAll([
          'first lark',
          'first robin',
          'second lark',
          'second robin',
        ]),
      );
      for (final raw in [
        'ones role1',
        'ones role2',
        'twos role1',
        'twos role2',
      ]) {
        expect(
          menu.labels,
          isNot(contains(raw)),
          reason: 'the raw token "$raw" must never reach the settings UI',
        );
      }

      // The group dancer sets are still there, still humanized.
      expect(menu.values, containsAll(['neighbors', 'nextNeighbors']));
      expect(menu.labels, contains('next neighbors'));
      // Role-driven tokens stay excluded (role-term substitution owns them).
      expect(menu.values, isNot(contains('role1s')));
      expect(menu.values, isNot(contains('role2s')));
    });

    testWidgets('an existing identity row is labelled by dialect', (
      tester,
    ) async {
      await openDancers(
        tester,
        Dialect(
          name: 'Reworded',
          roles: Dialect.larksRobins.roles,
          dancers: const {'twosRole2': 'robin two'},
        ),
      );

      final field = find.byKey(const ValueKey('dialect-dancer-twosRole2'));
      await reveal(tester, field);
      await tester.pumpAndSettle();

      // The row names the token being overridden by its DEFAULT wording — not
      // the substitution in the adjacent field, which would be circular.
      expect(find.text('second robin'), findsWidgets);
      expect(find.text('twos role2'), findsNothing);
      expect(tester.widget<TextField>(field).controller!.text, 'robin two');
    });

    testWidgets('the row label tracks role terms as they are edited', (
      tester,
    ) async {
      // A viewport tall enough to lay the whole form out at once: the role
      // field and the dancer row must both be built simultaneously, and the
      // editor's list only builds what is on screen.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await openDancers(
        tester,
        Dialect(
          name: 'Editing',
          roles: Dialect.larksRobins.roles,
          dancers: const {'twosRole2': 'robin two'},
        ),
      );
      expect(find.text('second robin'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('dialect-role2-singular')),
        'raven',
      );
      await tester.pumpAndSettle();

      expect(find.text('second raven'), findsWidgets);
      expect(find.text('second robin'), findsNothing);
    });

    testWidgets('adding one round-trips into the saved dialect', (
      tester,
    ) async {
      Dialect? popped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<Dialect>(
                    MaterialPageRoute(
                      builder: (_) =>
                          DialectEditorScreen(initial: Dialect.larksRobins),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('dialect-dancers-toggle'));
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      // Drive the menu's own callback: the rendered overlay is long enough
      // that the entry is never laid out, so tapping it is not reachable.
      // The value comes FROM the menu, so this is red when the menu does not
      // offer the token rather than reaching a state the UI cannot produce.
      final menu = tester.widget<DropdownButton<String>>(
        find.byKey(const ValueKey('dialect-add-dancer')),
      );
      menu.onChanged!(
        menu.items!.map((i) => i.value).firstWhere((v) => v == 'twosRole2'),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('dialect-dancer-twosRole2'));
      await reveal(tester, field);
      await tester.enterText(field, 'robin two');
      await tester.pumpAndSettle();

      final save = find.byKey(const ValueKey('dialect-editor-save'));
      await reveal(tester, save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(popped?.dancers['twosRole2'], 'robin two');
    });
  });
}
