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

/// The error text the token field is showing, or null.
String? _tokenFieldError(WidgetTester tester) => tester
    .widget<TextField>(
      find.byKey(const ValueKey('shorthand-token-field'), skipOffstage: false),
    )
    .decoration
    ?.errorText;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rejects an empty token and stays open', (tester) async {
    final read = await _pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();

    // On the token field, not in a banner at the top of the page.
    expect(_tokenFieldError(tester), 'Enter a shorthand token.');
    expect(
      find.byKey(const ValueKey('shorthand-validation-error')),
      findsNothing,
    );
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

    expect(_tokenFieldError(tester), isNotNull);
    expect(read(), isNull);
  });

  testWidgets('editing the token clears its error', (tester) async {
    await _pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();
    expect(_tokenFieldError(tester), isNotNull);

    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'b',
    );
    await tester.pump();

    expect(_tokenFieldError(tester), isNull);
  });

  testWidgets('a token with no target figures says so beside the figure list, '
      'in view', (tester) async {
    // A short window so the figure list's error is below the fold unless the
    // editor scrolls to it.
    await tester.binding.setSurfaceSize(const Size(600, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'bns',
    );
    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();

    final error = find.byKey(const ValueKey('shorthand-validation-error'));
    expect(error, findsOneWidget);
    expect(_tokenFieldError(tester), isNull);
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester.getRect(error);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(view.height));
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

  testWidgets('offers meanwhile and modifier targets', (tester) async {
    await _pumpEditor(
      tester,
      initial: ShorthandMapping(token: 'combo', figures: [_swing()]),
    );

    await tester.tap(find.byKey(const ValueKey('figure-add')));
    await tester.pump();

    expect(find.byKey(const ValueKey('figure-add-meanwhile')), findsOneWidget);
    expect(find.byKey(const ValueKey('figure-add-modifier')), findsOneWidget);
  });

  testWidgets('warns, without blocking, when the token already reads as a '
      'figure (#1827)', (tester) async {
    final read = await _pumpEditor(
      tester,
      initial: ShorthandMapping(token: 'bns', figures: [_swing()]),
    );
    const warning = ValueKey('shorthand-shadow-warning');
    expect(find.byKey(warning), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'swing',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(warning), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'zzqx',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(warning), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('shorthand-token-field')),
      'swing',
    );
    await tester.tap(find.byKey(const ValueKey('shorthand-editor-save')));
    await tester.pumpAndSettle();
    expect(read()?.token, 'swing');
  });

  // #1830: a shorthand expands to a snippet, not a whole dance, so the phrase
  // labels and the beat total ("Under by N beats") belong to dances only.
  testWidgets('does not show phrase labels or a beat total for a snippet', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      initial: ShorthandMapping(token: 'sw', figures: [_swing()]),
    );

    expect(find.byKey(const ValueKey('figure-0-summary')), findsOneWidget);
    // The row keeps an empty label slot; no phrase label such as "A1" reads in it.
    final label = find.byKey(const ValueKey('figure-0-label'));
    if (label.evaluate().isNotEmpty) {
      expect(tester.widget<Text>(label).data, isEmpty);
    }
    expect(find.byKey(const ValueKey('figure-beats-total')), findsNothing);
    expect(find.byKey(const ValueKey('figure-beats-warning')), findsNothing);
    expect(find.textContaining('Under by'), findsNothing);
  });
}
