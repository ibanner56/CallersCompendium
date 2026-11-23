import 'package:compendium_app/src/widgets/app_dropdown_field.dart';
import 'package:compendium_app/src/widgets/user_figure_argument_editor.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// The groups of dancers a figure of the user's own offers are its form's
/// (#2294): English's for an English figure, contra's for any other.
void main() {
  /// The values the picker for `who` offers, in order, `null` being "no
  /// default" (or "not stated"), when the editor is for a figure of [form].
  Future<List<Object?>> offered(
    WidgetTester tester, {
    required String form,
    required bool asDefault,
    ParamKind kind = ParamKind.dancerSet,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Center(
            child: UserFigureArgumentEditor(
              keyPrefix: 'use',
              param: UserFigureParam(key: 'who', kind: kind),
              form: form,
              value: null,
              onChanged: (_) {},
              dialect: Dialect.canonical,
              allowNone: asDefault,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<AppDropdownField<dynamic>>(
      find.byWidgetPredicate(
        (w) => w is AppDropdownField && w.key == const ValueKey('use-who'),
      ),
    );
    return [for (final entry in field.entries) entry.value];
  }

  const englishOnly = ['ends', 'top', 'corners', 'fives'];
  const contraOnly = ['thirdCorners', 'opposites'];

  for (final asDefault in [true, false]) {
    final picker = asDefault ? 'default' : 'dance';

    testWidgets('the $picker picker of an English figure offers English\'s '
        'groups, and none only contra has', (tester) async {
      final values = await offered(tester, form: 'ecd', asDefault: asDefault);
      expect(values, containsAll(englishOnly));
      expect(values, isNot(contains('thirdCorners')));
      expect(values, isNot(contains('opposites')));
    });

    testWidgets('the $picker picker of a contra figure offers contra\'s '
        'groups, and none only English has', (tester) async {
      final values = await offered(
        tester,
        form: 'contra',
        asDefault: asDefault,
      );
      expect(values, containsAll(contraOnly));
      for (final group in englishOnly) {
        expect(values, isNot(contains(group)), reason: group);
      }
    });

    testWidgets('the $picker picker never offers "not stated" as a value', (
      tester,
    ) async {
      final values = await offered(tester, form: 'ecd', asDefault: asDefault);
      expect(values, isNot(contains(ParamVocab.unspecified)));
    });
  }

  testWidgets('a pair of dancers offers the form\'s groups too', (
    tester,
  ) async {
    final english = await offered(
      tester,
      form: 'ecd',
      asDefault: true,
      kind: ParamKind.dancerPair,
    );
    expect(english, containsAll(englishOnly));
    expect(english, isNot(contains('thirdCorners')));
    final contra = await offered(
      tester,
      form: 'contra',
      asDefault: true,
      kind: ParamKind.dancerPair,
    );
    expect(contra, containsAll(contraOnly));
    expect(contra, isNot(contains('ends')));
  });

  testWidgets('a dance\'s argument has no button that would store "not '
      'stated"', (tester) async {
    for (final form in ['ecd', 'contra']) {
      await offered(tester, form: form, asDefault: false);
      expect(
        find.byKey(const ValueKey('use-who-clear')),
        findsNothing,
        reason: form,
      );
    }
  });

  testWidgets('a default can be left as "no default"', (tester) async {
    final values = await offered(tester, form: 'ecd', asDefault: true);
    expect(values, contains(null));
  });
}
