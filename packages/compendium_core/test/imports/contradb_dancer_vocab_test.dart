// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/src/imports/contradb_dancer_vocab.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// JSON↔HTML parity (#1545): every dancer-set phrase the JSON adapter maps
/// through `contradbDancerVocab` and that ContraDB's rendered HTML spells
/// (`contradbRenderedOnlyDancerKeys`) must structure to the same token from a
/// rendered-HTML line, not fall to a custom figure.
///
/// `swing` admits only some subjects, so a subject it rejects is tried with
/// `allemande left once`, which takes any pair-dancer set.
void main() {
  group('HTML dialect reads every rendered dancer-set phrase', () {
    for (final key in contradbRenderedOnlyDancerKeys) {
      final token = contradbDancerVocab[key]!;
      test('"$key" → $token', () {
        // The HTML page renders the default dialect (gentlespoon/ladle).
        final candidates = ['$key swing', '$key allemande left once'];
        final parsed = [
          for (final line in candidates)
            parseFigureLine(line, frontEnd: contraDbHtmlFigureFrontEnd),
        ];
        final hit = parsed.where(
          (f) => f != null && !f.isCustom && f.params['who'] == token,
        );
        expect(
          hit,
          isNotEmpty,
          reason:
              'none of $candidates structured with who=$token '
              '(got ${parsed.map((f) => f == null ? null : '${f.move}/${f.params['who']}').toList()})',
        );
      });
    }
  });

  group('every multi-word table key reaches the HTML dialect (#1555)', () {
    // `contradbRenderedOnlyDancerKeys` is a second hand-maintained list: a
    // multi-word key added to the table would reach the JSON adapter and be
    // silently absent from the HTML dialect. Every multi-word key must be
    // projected, or listed here — with the spelling ContraDB's HTML renders —
    // as one the dialect's own ordinal-aware subject list already reads; the
    // parse test below proves that claim for each entry.
    const readByDialectOwnList = {
      'second shadows': '2nd shadows',
      'previous neighbors': 'previous neighbors',
      'next neighbors': 'next neighbors',
      'third neighbors': '3rd neighbors',
      'fourth neighbors': '4th neighbors',
    };
    final multiWord = [
      for (final key in contradbDancerVocab.keys)
        if (key.contains(' ')) key,
    ];

    test('is projected or allow-listed', () {
      final unaccounted = [
        for (final key in multiWord)
          if (!contradbRenderedOnlyDancerKeys.contains(key) &&
              !readByDialectOwnList.containsKey(key))
            key,
      ];
      expect(
        unaccounted,
        isEmpty,
        reason:
            'add each to contradbRenderedOnlyDancerKeys (so the HTML dialect '
            'reads it), or to readByDialectOwnList once its HTML parse is '
            'proven below',
      );
    });

    test('the allow-list names only live, unprojected keys', () {
      for (final key in readByDialectOwnList.keys) {
        expect(contradbDancerVocab, contains(key), reason: 'stale: $key');
        expect(
          contradbRenderedOnlyDancerKeys,
          isNot(contains(key)),
          reason: '$key is projected; drop it from the allow-list',
        );
      }
    });

    for (final entry in readByDialectOwnList.entries) {
      final token = contradbDancerVocab[entry.key]!;
      test('"${entry.value}" → $token already parses from an HTML line', () {
        final candidates = [
          '${entry.value} swing',
          '${entry.value} allemande left once',
        ];
        final parsed = [
          for (final line in candidates)
            parseFigureLine(line, frontEnd: contraDbHtmlFigureFrontEnd),
        ];
        expect(
          parsed.any(
            (f) => f != null && !f.isCustom && f.params['who'] == token,
          ),
          isTrue,
          reason:
              'none of $candidates structured with who=$token '
              '(got ${parsed.map((f) => f == null ? null : '${f.move}/${f.params['who']}').toList()})',
        );
      });
    }
  });

  test('the HTML-only keys are all JSON vocabulary keys', () {
    for (final key in contradbRenderedOnlyDancerKeys) {
      expect(contradbDancerVocab, contains(key));
    }
  });

  test('the JSON adapter maps every table phrase to the same token', () async {
    final adapter = ContraDbAdapter();
    for (final entry in contradbDancerVocab.entries) {
      final payload = jsonEncode({
        'id': 'd',
        'title': 'T',
        'start_type': 'improper',
        'figures_json': [
          {
            'move': 'allemande',
            'parameter_values': [entry.key, 'right', 360, 8],
          },
        ],
      });
      final discovered = await adapter.discover(
        ImportRequest(payload: payload),
      );
      final draft = adapter.parse(await adapter.fetch(discovered.single));
      final f = figuresOf(draft.dance).firstWhere((f) => f.move == 'allemande');
      expect(f.params['who'], entry.value, reason: entry.key);
    }
  });
}
