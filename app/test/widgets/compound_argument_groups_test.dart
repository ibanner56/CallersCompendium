import 'package:compendium_app/src/widgets/compound_argument_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dropdown.dart';
import '../support/l10n_harness.dart';

/// A combination's group-of-dancers parameter that fills no slot offers the
/// groups of the combination's own form (#2294), so one made for English
/// offers the ends and the top and not the groups only contra has.
void main() {
  CompoundDefinition unused(String form) => CompoundDefinition(
    params: const [CompoundParam(key: 'who', kind: ParamKind.dancerSet)],
    figures: [
      testFigure(move: 'pull_by', params: {'who': 'neighbors', 'beats': 2}),
    ],
    bindings: const [],
    form: form,
  );

  Future<void> openPicker(WidgetTester tester, CompoundDefinition def) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Center(
            child: CompoundArgumentEditor(
              keyPrefix: 'arg',
              definition: def,
              param: def.params.single,
              value: 'everyone',
              onChanged: (_) {},
              dialect: Dialect.canonical,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await press(tester, find.byKey(const ValueKey('arg-who')));
    await tester.pumpAndSettle();
  }

  /// Whether the open menu has an entry labelled [label].
  bool offers(String label) => find
      .descendant(
        of: find.byType(MenuItemButton, skipOffstage: false),
        matching: find.text(label, skipOffstage: false),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('a combination made for English offers the ends and the top, '
      'and not third corners', (tester) async {
    await openPicker(tester, unused('ecd'));
    expect(offers('ends'), isTrue);
    expect(offers('top'), isTrue);
    expect(offers('third corners'), isFalse);
  });

  testWidgets('a combination made for contra offers third corners, and not '
      'the ends', (tester) async {
    await openPicker(tester, unused('contra'));
    expect(offers('third corners'), isTrue);
    expect(offers('ends'), isFalse);
  });
}
