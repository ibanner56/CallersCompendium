import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/widgets/event_rule_text.dart';
import 'package:compendium_app/src/widgets/picker_suggestions.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_harness.dart';

/// How a "Would break" or slot marker names a rule (#2530, #2535): shown by
/// its nickname, else its sentence; read to a screen reader as its nickname
/// and sentence, else its sentence.
void main() {
  EventRule rule(String id, {String? nickname}) => EventRule.of(
    id: id,
    savedSearchId: 'ss-$id',
    quantifier: EventRuleQuantifier.atMost,
    count: 1,
    scope: EventRuleScope.wholeProgram,
    nickname: nickname,
  );

  const petronella =
      'At most 1 dance matching "Petronella" in the whole program';
  const becket = 'At most 1 dance matching "Becket" in the whole program';

  group('eventRuleName', () {
    final en = lookupAppLocalizations(const Locale('en'));

    test('a rule without a nickname is shown and read as its sentence', () {
      final name = eventRuleName(en, rule('r1'), 'Petronella');
      expect(name.title, petronella);
      expect(name.spoken, petronella);
    });

    test(
      'a rule with a nickname is shown by it and read with its sentence',
      () {
        final name = eventRuleName(
          en,
          rule('r1', nickname: 'Family petronella'),
          'Petronella',
        );
        expect(name.title, 'Family petronella');
        expect(name.spoken, 'Family petronella ($petronella)');
      },
    );

    test('the join is the locale\'s own: Japanese uses full-width '
        'parentheses', () {
      final ja = lookupAppLocalizations(const Locale('ja'));
      final sentence = eventRuleSentence(ja, rule('r1'), 'Petronella');
      final name = eventRuleName(
        ja,
        rule('r1', nickname: 'Family petronella'),
        'Petronella',
      );
      expect(name.title, 'Family petronella');
      expect(name.spoken, 'Family petronella（$sentence）');
    });
  });

  testWidgets('several rules: the text names each by its title, the label '
      'reads each nicknamed one with its sentence, once counted', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final en = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: SuggestionRuleMarker(
            key: const ValueKey('marker'),
            rules: [
              eventRuleName(
                en,
                rule('r1', nickname: 'Family petronella'),
                'Petronella',
              ),
              eventRuleName(en, rule('r2'), 'Becket'),
            ],
          ),
        ),
      ),
    );
    final marker = find.byKey(const ValueKey('marker'));
    expect(
      find.descendant(
        of: marker,
        matching: find.text('Would break 2 rules: Family petronella; $becket'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(marker),
      matchesSemantics(
        label:
            'Would break 2 event rules: Family petronella ($petronella); '
            '$becket',
      ),
    );
    semantics.dispose();
  });
}
