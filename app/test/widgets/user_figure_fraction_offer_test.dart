import 'package:compendium_app/src/widgets/compound_argument_editor.dart';
import 'package:compendium_app/src/widgets/user_figure_argument_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// A figure of the user's own does not offer a fraction of `other` (#2120,
/// maintainer decision 4): its argument cannot carry the amount through to
/// the move it fills. One already chosen is still shown, and still valid.
void main() {
  Future<void> pump(WidgetTester tester, Object? value) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Center(
            child: UserFigureArgumentEditor(
              keyPrefix: 'use',
              param: UserFigureParam(key: 'part', kind: ParamKind.fraction),
              value: value,
              onChanged: (_) {},
              dialect: Dialect.canonical,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('use-part')));
    await tester.pumpAndSettle();
  }

  testWidgets('other is not offered', (tester) async {
    await pump(tester, 'half');
    expect(find.text('three quarter'), findsWidgets);
    expect(find.textContaining('other amount'), findsNothing);
  });

  testWidgets('an other already chosen is still offered and shown', (
    tester,
  ) async {
    await pump(tester, 'other');
    expect(find.textContaining('other amount'), findsWidgets);
  });

  test('an other already chosen still validates', () {
    final param = UserFigureParam(key: 'part', kind: ParamKind.fraction);
    expect(param.spec.validate('other'), isTrue);
  });

  testWidgets('a rotation of your own named amount is an ordinary turn', (
    tester,
  ) async {
    Object? reported;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Center(
            child: UserFigureArgumentEditor(
              keyPrefix: 'use',
              param: UserFigureParam(key: 'amount', kind: ParamKind.rotation),
              value: 0.5,
              onChanged: (v) => reported = v,
              dialect: Dialect.canonical,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Turns, not the fraction amount's "×", and it steps below 1¼.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('use-amount-value'))).data,
      contains('turn'),
    );
    await tester.tap(find.byKey(const ValueKey('use-amount-dec')));
    await tester.pumpAndSettle();
    expect(reported, 0.25);
  });

  group('a compound argument (#2120)', () {
    Future<void> pumpCompound(WidgetTester tester, Object? value) async {
      final definition = CompoundDefinition(
        params: const [CompoundParam(key: 'frac', kind: ParamKind.fraction)],
        figures: [Figure(move: 'figure_8')],
        bindings: const [
          CompoundSlotBinding(
            figureIndex: 0,
            slotKey: 'fraction',
            paramKey: 'frac',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Scaffold(
            body: Center(
              child: CompoundArgumentEditor(
                keyPrefix: 'arg',
                definition: definition,
                param: definition.params.single,
                value: value,
                onChanged: (_) {},
                dialect: Dialect.canonical,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('arg-frac')).last);
      await tester.pumpAndSettle();
    }

    testWidgets('does not offer other', (tester) async {
      await pumpCompound(tester, 'half');
      expect(find.text('three quarter'), findsWidgets);
      expect(find.textContaining('other amount'), findsNothing);
    });

    testWidgets('still shows an other already chosen', (tester) async {
      await pumpCompound(tester, 'other');
      expect(find.text('other amount'), findsWidgets);
    });
  });
}
