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
