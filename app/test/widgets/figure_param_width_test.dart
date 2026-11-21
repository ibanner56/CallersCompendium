// The figure-parameter dropdown is as wide as its longest choice needs, so a
// closed value is never cut off: the closed field of a DropdownMenu scrolls
// rather than ellipsizing, so a field narrower than its value silently clips
// it. Measured on the render with the real fonts; the Ahem test font would
// make every glyph a full em and the check meaningless.
import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_app/src/theme/app_theme.dart';
import 'package:compendium_app/src/widgets/figure_param_editors.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dropdown.dart';
import '../support/l10n_harness.dart';
import '../support/real_fonts.dart';
import '../support/screen_size.dart';

const _phone = Size(360, 780);

/// One parameter editor in a [Wrap], the way the figure editor lays them out.
Future<void> _pump(
  WidgetTester tester, {
  required ParamSpec spec,
  required Object? value,
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  final notifier = ValueNotifier<Dialect>(Dialect.larksRobins);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      theme: AppTheme.light,
      builder: (context, child) => ActiveDialectScope(
        notifier: notifier,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FigureParamEditor(
                keyPrefix: 'f',
                paramKey: 'p',
                spec: spec,
                value: value,
                dialect: Dialect.larksRobins,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _field = ValueKey('f-p');

/// Every fixed vocabulary the dropdown offers, with "not stated" admitted so
/// the hint and the clear button are measured too.
final _specs = <String, ParamSpec>{
  'spin direction': const ParamSpec(
    ParamKind.spinDirection,
    defaultValue: 'clockwise',
  ),
  'hand': const ParamSpec(ParamKind.handedness, defaultValue: 'right'),
  'direction': const ParamSpec(ParamKind.direction, defaultValue: 'along'),
  'fraction': const ParamSpec(ParamKind.fraction, defaultValue: 'half'),
  'dancers': const ParamSpec(ParamKind.dancerSet, defaultValue: 'larks'),
  'dancers, or not stated': const ParamSpec(
    ParamKind.dancerSet,
    defaultValue: ParamVocab.unspecified,
    choices: [...ParamVocab.dancerSets, ParamVocab.unspecified],
  ),
};

void main() {
  setUpAll(loadBundledFonts);

  testWidgets('"counterclockwise" is shown in full at 1x', (tester) async {
    await setScreenSize(tester, _phone);
    await _pump(
      tester,
      spec: const ParamSpec(ParamKind.spinDirection, defaultValue: 'clockwise'),
      value: 'counterclockwise',
    );
    final field = find.byKey(_field);
    expect(dropdownShown(tester, field), 'counterclockwise');
    expectClosedValueFits(tester, field);
  });

  testWidgets('the field keeps one width whether a value is picked or '
      'cleared to "not stated"', (tester) async {
    await setScreenSize(tester, _phone);
    const spec = ParamSpec(
      ParamKind.handedness,
      defaultValue: ParamVocab.unspecified,
      choices: ['right', 'left', ParamVocab.unspecified],
    );
    await _pump(tester, spec: spec, value: 'left');
    final picked = tester.getSize(find.byKey(_field)).width;
    await _pump(tester, spec: spec, value: ParamVocab.unspecified);
    expect(dropdownShown(tester, find.byKey(_field)), '');
    expect(tester.getSize(find.byKey(_field)).width, picked);
  });

  for (final locale in const [Locale('en'), Locale('de'), Locale('fr')]) {
    for (final MapEntry(key: name, value: spec) in _specs.entries) {
      testWidgets('every $name choice is shown in full at 1x in $locale', (
        tester,
      ) async {
        await setScreenSize(tester, _phone);
        final choices = figureParamChoices(spec)!;
        for (final choice in choices) {
          await _pump(tester, spec: spec, value: choice, locale: locale);
          final field = find.byKey(_field);
          expect(tester.takeException(), isNull, reason: choice);
          expectClosedValueFits(tester, field);
        }
      });
    }
  }

  // At twice the text size a phone's row is too narrow for some fields: the
  // field then takes the whole row, never more, and the row is not
  // overflowed.
  for (final MapEntry(key: name, value: spec) in _specs.entries) {
    testWidgets('at 2x on a phone, every $name choice stays within the row', (
      tester,
    ) async {
      await setScreenSize(tester, _phone);
      final choices = figureParamChoices(spec)!;
      for (final choice in choices) {
        await _pump(tester, spec: spec, value: choice, scale: 2);
        expect(tester.takeException(), isNull, reason: choice);
        final field = find.byKey(_field);
        final box = tester.getRect(field);
        expect(box.left, greaterThanOrEqualTo(16), reason: choice);
        expect(box.right, lessThanOrEqualTo(_phone.width - 16), reason: choice);
        expectClosedValueFits(tester, field);
      }
    });
  }
}
