import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/widgets/compound_argument_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// A compound's places argument bound to a circle's places (taxonomy v39)
/// may be "not stated", as the circle's own field may.
void main() {
  // The template's own places: unstated where the move admits it, else a
  // count (a facing star's template cannot hold the sentinel).
  CompoundDefinition definition(String move, {Object places = 3}) =>
      CompoundDefinition(
        params: const [CompoundParam(key: 'n', kind: ParamKind.places)],
        figures: [
          testFigure(move: move, params: {'places': places}),
        ],
        bindings: const [
          CompoundSlotBinding(figureIndex: 0, slotKey: 'places', paramKey: 'n'),
        ],
      );

  Future<Object? Function()> pump(
    WidgetTester tester,
    CompoundDefinition def,
    Object? value,
  ) async {
    Object? reported;
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
              value: value,
              onChanged: (v) => reported = v,
              dialect: Dialect.canonical,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => reported;
  }

  String fieldText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('arg-n')))
      .controller!
      .text;

  testWidgets('bound to a circle: an unstated argument shows empty, and can '
      'be emptied again', (tester) async {
    final def = definition('circle', places: ParamVocab.unspecified);
    expect(
      allowedValues(def, 'n', contraTaxonomy),
      contains(ParamVocab.unspecified),
    );
    var read = await pump(tester, def, ParamVocab.unspecified);
    expect(fieldText(tester), isEmpty, reason: 'not a made-up count');
    expect(find.byKey(const ValueKey('arg-n-choose')), findsNothing);

    read = await pump(tester, def, 3);
    await tester.enterText(find.byKey(const ValueKey('arg-n')), '');
    await tester.pump();
    expect(read(), ParamVocab.unspecified);
    expect(find.text('Enter a whole number from 1 to 10'), findsNothing);
  });

  testWidgets('bound to a facing star: emptying the field is still an error', (
    tester,
  ) async {
    final def = definition('facing_star');
    expect(
      allowedValues(def, 'n', contraTaxonomy),
      isNot(contains(ParamVocab.unspecified)),
    );
    final read = await pump(tester, def, 3);
    await tester.enterText(find.byKey(const ValueKey('arg-n')), '');
    await tester.pump();
    expect(read(), isNull);
    expect(find.text('Enter a whole number from 1 to 10'), findsOneWidget);
  });

  test('the summary reads "not stated", not the sentinel token', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      compoundArgumentsText(
        l10n,
        definition('circle', places: ParamVocab.unspecified),
        const {'n': ParamVocab.unspecified},
        Dialect.canonical,
      ),
      'not stated',
    );
  });
}
