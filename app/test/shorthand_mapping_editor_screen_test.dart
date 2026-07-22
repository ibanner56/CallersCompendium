import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/screens/shorthand_mapping_editor_screen.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';

Figure _swing() =>
    Figure(move: 'swing', params: {'who': 'neighbors', 'beats': 16});

/// Pumps a launcher that pushes [ShorthandMappingEditorScreen] and records the
/// value it pops, so tests can assert what the editor returns (or that it stays
/// open on a validation failure).
Future<ShorthandMapping? Function()> _pumpEditor(
  WidgetTester tester, {
  ShorthandMapping? initial,
  Set<String> existingTokens = const {},
}) async {
  ShorthandMapping? result;
  var popped = false;
  final dialect = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(dialect.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      builder: (context, child) =>
          ActiveDialectScope(notifier: dialect, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<ShorthandMapping>(
                  MaterialPageRoute(
                    builder: (_) => ShorthandMappingEditorScreen(
                      initial: initial,
                      existingTokens: existingTokens,
                    ),
                  ),
                );
                popped = true;
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
  return () => popped ? result : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rejects an empty token and stays open', (tester) async {
    final read = await _pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shorthand-validation-error')),
      findsOneWidget,
    );
    expect(find.text('Enter a shorthand token.'), findsOneWidget);
    // Editor did not pop.
    expect(read(), isNull);
    expect(find.byKey(const ValueKey('shorthand-token-field')), findsOneWidget);
  });

  testWidgets('rejects a case-insensitive duplicate token', (tester) async {
    final read = await _pumpEditor(tester, existingTokens: {'sw'});

    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'SW',
    );
    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shorthand-validation-error')),
      findsOneWidget,
    );
    expect(read(), isNull);
  });

  testWidgets('rejects a token with no target figures', (tester) async {
    final read = await _pumpEditor(tester);

    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'bns',
    );
    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shorthand-validation-error')),
      findsOneWidget,
    );
    expect(read(), isNull);
  });

  testWidgets('saving an edited mapping returns token + figures', (
    tester,
  ) async {
    final read = await _pumpEditor(
      tester,
      initial: ShorthandMapping(token: 'bns', figures: [_swing()]),
    );

    // Re-case the token; the seeded figure is left untouched.
    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'BnS',
    );
    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();

    final mapping = read();
    expect(mapping, isNotNull);
    expect(mapping!.token, 'BnS');
    expect(mapping.figures.single.move, 'swing');
  });
}
