// Large-text guard for the fraction amount editing added by #2120: the
// fraction dropdown showing "other amount…" and the amount stepper beside it,
// at phone width with the system text scale raised, in every locale. Same
// harness as dropdown_large_text_test.dart (#2182): bundled fonts, 360 dp,
// and a RenderFlex overflow surfaces as a framework exception.
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/figure_param_editors.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';
import '../support/real_fonts.dart';
import '../support/screen_size.dart';

void main() {
  final def = contraTaxonomy.resolve('poussette')!;

  Future<void> pump(WidgetTester tester, double scale, Locale locale) async {
    await loadBundledFonts();
    await setScreenSize(tester, const Size(360, 780));
    Widget editor(String key, Object? value) => FigureParamEditor(
      keyPrefix: 'p',
      paramKey: key,
      spec: def.params[key]!,
      value: value,
      dialect: Dialect.larksRobins,
      moveId: 'poussette',
      fractionAmountFollows: true,
      onChanged: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            // As the dance editor lays its params out.
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                editor('fraction', 'other'),
                editor(fractionAmountParam, 2.25),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in [1.5, 2.0]) {
    for (final locale in testSupportedLocales) {
      testWidgets('fraction and amount at ${scale}x in $locale', (
        tester,
      ) async {
        await pump(tester, scale, locale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('p-amount-value')), findsOneWidget);
        // The open menu, with its "other amount…" item, lays out too.
        await tester.tap(find.byKey(const ValueKey('p-fraction')).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
