import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/screens/dialect_editor_screen.dart';

import '../support/l10n_harness.dart';

/// Conditional wording in the dialect editor: shown in words, stored by
/// meaning, and refused with a message that says how to fix it.
void main() {
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

  Future<Dialect? Function()> open(WidgetTester tester, Dialect initial) async {
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
                  builder: (_) => DialectEditorScreen(initial: initial),
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
    final toggle = find.byKey(const ValueKey('dialect-wordings-toggle'));
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    return () => popped;
  }

  /// Saves, confirming the wording leaves out a slot if asked.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('dialect-wording-confirm'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }
  }

  Finder field() => find.byKey(const ValueKey('dialect-wording-swing'));
  Finder error() => find.byKey(const ValueKey('dialect-wording-error-swing'));
  String preview(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('dialect-wording-preview-swing')))
      .data!;

  testWidgets('a stored condition shows in this dialect\'s words, and saves '
      'back by meaning', (tester) async {
    const stored = "[{?if who is 'role2s'}robin swing{?else}{who} swing]";
    final popped = await open(
      tester,
      Dialect.larksRobins.copyWith(
        name: 'Mine',
        moveWordings: const {'swing': stored},
      ),
    );
    expect(
      tester.widget<TextField>(field()).controller!.text,
      '[if who is robins then robin swing else {who} swing]',
    );
    expect(error(), findsNothing);
    expect(find.textContaining('A condition can test:'), findsOneWidget);

    await tester.enterText(
      field(),
      '[if who is partners then partner swing else {who} swing]',
    );
    await tester.pump();
    // The sample is an ordinary swing: partners.
    expect(preview(tester), contains('partner swing'));

    await save(tester);
    expect(
      popped()?.moveWordings['swing'],
      "[{?if who is 'partners'}partner swing{?else}{who} swing]",
    );
  });

  testWidgets('a mistake is explained under its field, and blocks the save', (
    tester,
  ) async {
    final popped = await open(
      tester,
      Dialect.larksRobins.copyWith(
        name: 'Mine',
        moveWordings: const {'swing': '{who} {move}'},
      ),
    );
    await tester.enterText(
      field(),
      '[if who is robbins then robin swing else {who} swing]',
    );
    await tester.pump();
    final message = tester.widget<Text>(error()).data!;
    expect(message, contains('“robbins” isn’t one of the values who can have'));
    expect(message, contains('Did you mean “robins”?'));
    expect(message, contains('who can be: everyone, larks, robins'));

    await tester.tap(find.byKey(const ValueKey('dialect-editor-save')));
    await tester.pumpAndSettle();
    expect(popped(), isNull);
    final banner = find.byKey(const ValueKey('dialect-validation-error'));
    await reveal(tester, banner);
    expect(tester.widget<Text>(banner).data, contains('swing'));
    await reveal(tester, field());

    await tester.enterText(field(), "[if who isn't robins then x else y]");
    await tester.pump();
    expect(
      tester.widget<Text>(error()).data,
      'Write “is not” instead of “isn\'t”: “who is not robins”.',
    );

    await tester.enterText(field(), '[if who is not robins then x else y]');
    await tester.pump();
    expect(error(), findsNothing);
    await save(tester);
    expect(
      popped()?.moveWordings['swing'],
      "[{?if who is not 'role2s'}x{?else}y]",
    );
  });

  testWidgets('a warning shows, and does not block the save', (tester) async {
    final popped = await open(
      tester,
      Dialect.larksRobins.copyWith(
        name: 'Mine',
        moveWordings: const {'swing': '{who} {move}'},
      ),
    );
    await tester.enterText(
      field(),
      '[if who is ones then everyone else swing]',
    );
    await tester.pump();
    expect(error(), findsNothing);
    expect(
      find.textContaining('If you meant the words “everyone else”'),
      findsOneWidget,
    );
    await save(tester);
    expect(popped()?.moveWordings['swing'], isNotNull);
  });
}
