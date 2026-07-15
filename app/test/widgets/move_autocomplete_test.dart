import 'package:compendium_app/src/widgets/move_autocomplete.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dialect that renames the canonical `swing` move to "buzz", exercising the
/// editor's requirement that the move picker both displays and matches dialect
/// vocabulary (not just canonical taxonomy names).
final _buzzDialect = Dialect(name: 'Custom', moves: const {'swing': 'buzz'});

Future<void> _pump(WidgetTester tester, {Dialect? dialect}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MoveAutocomplete(
          taxonomy: contraTaxonomy,
          dialect: dialect,
          initialText: '',
          fieldKey: 'move',
          onSelected: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('matches and displays a dialect move substitution', (
    tester,
  ) async {
    await _pump(tester, dialect: _buzzDialect);
    // Typing the dialect term surfaces the underlying move as "buzz".
    await tester.enterText(find.byKey(const ValueKey('move-input')), 'buzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('move-option-swing')), findsOneWidget);
    expect(find.text('buzz'), findsWidgets);
    expect(find.text('swing'), findsNothing);
  });

  testWidgets('shows canonical names under the canonical dialect', (
    tester,
  ) async {
    await _pump(tester, dialect: Dialect.canonical);
    await tester.enterText(find.byKey(const ValueKey('move-input')), 'swing');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('move-option-swing')), findsOneWidget);
    expect(find.text('swing'), findsWidgets);
    // The dialect term isn't shown when the active dialect is canonical.
    expect(find.text('buzz'), findsNothing);
  });
}
