import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for [buildContraDbSearchBody] and [parseContraDbSearchResults].
///
/// The happy-path fixture mirrors the live ContraDB search API
/// (`POST https://contradb.com/api/v1/dances`, captured 2026-07-17 for
/// `["title","petronella"]`): `{ numberSearched, numberMatching, dances: [ {
/// id, title, choreographer_name, formation, … }, … ] }`. No live network is
/// used.
void main() {
  group('buildContraDbSearchBody', () {
    test('builds the title filter body with defaults', () {
      final decoded = jsonDecode(buildContraDbSearchBody('petronella'));
      expect(decoded, {
        'filter': ['title', 'petronella'],
        'count': contraDbSearchCount,
        'offset': 0,
        'sort_by': 'titleA',
      });
    });

    test('honors count, offset, and sortBy overrides', () {
      final decoded = jsonDecode(
        buildContraDbSearchBody('star', count: 5, offset: 10, sortBy: 'titleD'),
      );
      expect(decoded, {
        'filter': ['title', 'star'],
        'count': 5,
        'offset': 10,
        'sort_by': 'titleD',
      });
    });

    test(
      'passes the query through verbatim (server lower-cases the match)',
      () {
        final decoded =
            jsonDecode(buildContraDbSearchBody('Money Musk'))
                as Map<String, Object?>;
        expect(decoded['filter'], ['title', 'Money Musk']);
      },
    );
  });

  group('parseContraDbSearchResults', () {
    const petronella = '''
{
  "numberSearched": 2324,
  "numberMatching": 2,
  "dances": [
    {
      "id": 2984,
      "title": "Festival Petronella #3",
      "choreographer_id": 59,
      "choreographer_name": "Will Mentor",
      "formation": "becket",
      "hook": "",
      "user_id": 5267,
      "user_name": "Koren A Wake",
      "created_at": "2025-09-01T06:09:01.915Z",
      "updated_at": "2025-09-01T06:09:01.915Z",
      "publish": "everywhere",
      "matching_figures_html": ""
    },
    {
      "id": 778,
      "title": "Greenfield Petronella",
      "choreographer_id": 95,
      "choreographer_name": "Chris Ricciotti",
      "formation": "improper - double progression",
      "hook": "",
      "user_id": 67,
      "user_name": "Karl Senseman",
      "publish": "everywhere",
      "matching_figures_html": ""
    }
  ]
}
''';

    test('parses the dances array into result rows', () {
      final results = parseContraDbSearchResults(petronella);
      expect(results, [
        const ContraDbSearchResult(
          id: '2984',
          name: 'Festival Petronella #3',
          author: 'Will Mentor',
          formation: 'becket',
        ),
        const ContraDbSearchResult(
          id: '778',
          name: 'Greenfield Petronella',
          author: 'Chris Ricciotti',
          formation: 'improper - double progression',
        ),
      ]);
    });

    test('empty dances list yields no results', () {
      expect(
        parseContraDbSearchResults(
          '{"numberSearched":2324,"numberMatching":0,"dances":[]}',
        ),
        isEmpty,
      );
    });

    test('malformed JSON yields no results (does not throw)', () {
      expect(parseContraDbSearchResults('{not valid json'), isEmpty);
      expect(parseContraDbSearchResults(''), isEmpty);
    });

    test('non-object payload yields no results', () {
      expect(parseContraDbSearchResults('[1,2,3]'), isEmpty);
      expect(parseContraDbSearchResults('"petronella"'), isEmpty);
      expect(parseContraDbSearchResults('null'), isEmpty);
    });

    test('missing or non-list dances yields no results', () {
      expect(parseContraDbSearchResults('{"numberSearched":1}'), isEmpty);
      expect(parseContraDbSearchResults('{"dances":"nope"}'), isEmpty);
    });

    test(
      'tolerates partial rows: missing optional fields default to empty',
      () {
        final results = parseContraDbSearchResults(
          '{"dances":[{"id":42,"title":"Bare Bones"}]}',
        );
        expect(results, [
          const ContraDbSearchResult(
            id: '42',
            name: 'Bare Bones',
            author: '',
            formation: '',
          ),
        ]);
      },
    );

    test(
      'skips unusable rows (missing id or title) and non-object entries',
      () {
        final results = parseContraDbSearchResults('''
{
  "dances": [
    {"title": "No Id Here", "choreographer_name": "X"},
    {"id": 7, "choreographer_name": "Y"},
    "not an object",
    42,
    {"id": 9, "title": "Keeper", "choreographer_name": "Z", "formation": "improper"}
  ]
}
''');
        expect(results, [
          const ContraDbSearchResult(
            id: '9',
            name: 'Keeper',
            author: 'Z',
            formation: 'improper',
          ),
        ]);
      },
    );

    test('coerces a string id and trims string fields', () {
      final results = parseContraDbSearchResults(
        '{"dances":[{"id":"55","title":"  Spacey  ","choreographer_name":"  A  ","formation":"  becket  "}]}',
      );
      expect(results, [
        const ContraDbSearchResult(
          id: '55',
          name: 'Spacey',
          author: 'A',
          formation: 'becket',
        ),
      ]);
    });
  });
}
