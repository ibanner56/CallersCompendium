import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/dialect_editor_screen.dart';

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

  testWidgets('typing a colliding substitution surfaces the collision live', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: DialectEditorScreen(initial: Dialect.canonical)),
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
      MaterialApp(home: DialectEditorScreen(initial: Dialect.canonical)),
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
      MaterialApp(home: DialectEditorScreen(initial: Dialect.canonical)),
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
    await tester.scrollUntilVisible(
      preview(),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // The sample figures + free text render the new plural role term, and no
    // longer show the bare canonical token.
    final text = previewText(tester).toLowerCase();
    expect(text, contains('larks'));
    expect(text, isNot(contains('role1s')));
  });

  testWidgets('Save is still guarded: an invalid dialect is not returned', (
    tester,
  ) async {
    Dialect? popped;
    var didPop = false;
    await tester.pumpWidget(
      MaterialApp(
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
        MaterialApp(home: DialectEditorScreen(initial: dialect)),
      );

      // Reveal both collapsed substitution editors.
      final movesToggle = find.byKey(const ValueKey('dialect-moves-toggle'));
      await tester.ensureVisible(movesToggle);
      await tester.tap(movesToggle);
      await tester.pumpAndSettle();

      final dancersToggle = find.byKey(
        const ValueKey('dialect-dancers-toggle'),
      );
      await tester.ensureVisible(dancersToggle);
      await tester.tap(dancersToggle);
      await tester.pumpAndSettle();

      Future<void> expectFieldLabel(String key, String term) async {
        final field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
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
}
