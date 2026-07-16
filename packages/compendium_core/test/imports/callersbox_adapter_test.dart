import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Fixtures + tests for [CallersBoxAdapter].
///
/// Most fixtures are **synthetic** — hand-built to the documented TCB schema
/// (`docs/research/callersbox.md`) — plus one **real** id=1 example
/// ("The Nice Combination", Gene Hubert) captured verbatim from
/// `dance.php?id=1&format=JSON` (trimmed to the fields the adapter reads).

/// Builds a TCB dance map. Any field left null is omitted.
Map<String, Object?> _dance({
  Object? id = '42',
  String? name = 'Test Dance',
  List<String>? authors,
  List<String>? interpretedBy,
  String? permission = 'full',
  String? formationBase,
  String? formationDetail,
  String? progression,
  String? phraseStructure,
  List<String>? callingNotes,
  List<String>? otherNames,
  List<String>? music,
  List<String>? tunes,
  List<Map<String, Object?>>? appearances,
  List<Map<String, Object?>>? phrases,
}) {
  final map = <String, Object?>{};
  if (id != null) map['ID'] = id;
  if (name != null) map['Name'] = name;
  if (authors != null) map['Authors'] = authors;
  if (interpretedBy != null) map['InterpretedBy'] = interpretedBy;
  if (permission != null) map['Permission'] = permission;
  if (formationBase != null) map['FormationBase'] = formationBase;
  if (formationDetail != null) map['FormationDetail'] = formationDetail;
  if (progression != null) map['Progression'] = progression;
  if (phraseStructure != null) map['PhraseStructure'] = phraseStructure;
  if (callingNotes != null) map['CallingNotes'] = callingNotes;
  if (otherNames != null) map['OtherNames'] = otherNames;
  if (music != null) map['Music'] = music;
  if (tunes != null) map['Tunes'] = tunes;
  if (appearances != null) map['Appearances'] = appearances;
  if (phrases != null) map['phrases'] = phrases;
  return map;
}

Map<String, Object?> _phrase(String name, List<String> figures) => {
  'name': name,
  'figures': figures,
};

Future<StructuredDraft> _importOne(String payload) async {
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

/// The custom-figure text ([customFigure] stores it in `params['text']`).
String _text(Figure f) => f.params['text'] as String;

/// The real id=1 record, trimmed to the fields the adapter reads.
const String _realId1 = '''
{
  "request": "http://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1&format=JSON",
  "download_date": "2026-07-16T05:47:04+00:00",
  "ID": "1",
  "Name": "The Nice Combination",
  "Authors": ["Gene Hubert"],
  "InterpretedBy": [],
  "Permission": "full",
  "Status": "",
  "BasedOn": [],
  "FormationBase": "Duple Minor - Improper",
  "FormationDetail": "",
  "Progression": "Single",
  "Direction": "",
  "PhraseStructure": "",
  "Music": [],
  "Tunes": [],
  "phrases": [
    {"name": "A1", "figures": ["(4) Neighbor balance", "(12) Neighbor swing"]},
    {"name": "A2", "figures": ["(6) In a line of four, go down the hall (M1-W2-M2-W1)", "(2) Neighbor turn as couples", "(6) In a line of four, go up the hall (W2-M1-W1-M2)", "(2) Bend the line"]},
    {"name": "B1", "figures": ["(6) Circle left 3/4", "(10) Partner swing"]},
    {"name": "B2", "figures": ["(8) Ladies chain to neighbor", "(8) Star left 1"]}
  ],
  "CallingNotes": [],
  "Appearances": [{"source": "Dizzy Dances, Volume II", "p": "6"}],
  "OtherNames": []
}
''';

void main() {
  group('CallersBoxAdapter', () {
    test('source is ProvenanceSource.callersbox', () {
      expect(CallersBoxAdapter().source, ProvenanceSource.callersbox);
    });

    group('discover', () {
      test('throws on null payload', () {
        expect(
          () => CallersBoxAdapter().discover(const ImportRequest()),
          throwsA(
            isA<ImportError>().having(
              (e) => e.stage,
              'stage',
              ImportStage.discover,
            ),
          ),
        );
      });

      test('throws on blank payload', () {
        expect(
          () =>
              CallersBoxAdapter().discover(const ImportRequest(payload: '  ')),
          throwsA(isA<ImportError>()),
        );
      });

      test('throws on undecodable JSON', () {
        expect(
          () => CallersBoxAdapter().discover(
            const ImportRequest(payload: '{not json'),
          ),
          throwsA(
            isA<ImportError>().having(
              (e) => e.stage,
              'stage',
              ImportStage.discover,
            ),
          ),
        );
      });

      test('throws when payload is not a TCB dance', () {
        expect(
          () => CallersBoxAdapter().discover(
            const ImportRequest(payload: '{"foo": "bar"}'),
          ),
          throwsA(isA<ImportError>()),
        );
      });

      test('throws on an empty array', () {
        expect(
          () =>
              CallersBoxAdapter().discover(const ImportRequest(payload: '[]')),
          throwsA(isA<ImportError>()),
        );
      });

      test('discovers a single dance (externalId=ID, label=Name)', () async {
        final adapter = CallersBoxAdapter();
        final records = await adapter.discover(
          ImportRequest(
            payload: jsonEncode(_dance(id: '7', name: 'Solo')),
          ),
        );
        expect(records, hasLength(1));
        expect(records.single.externalId, '7');
        expect(records.single.label, 'Solo');
      });

      test('discovers an array of dances', () async {
        final adapter = CallersBoxAdapter();
        final records = await adapter.discover(
          ImportRequest(
            payload: jsonEncode([
              _dance(id: '1', name: 'One'),
              _dance(id: '2', name: 'Two'),
            ]),
          ),
        );
        expect(records.map((r) => r.externalId), ['1', '2']);
        expect(records.map((r) => r.label), ['One', 'Two']);
      });

      test('discovers a {dances:[...]} wrapper', () async {
        final adapter = CallersBoxAdapter();
        final records = await adapter.discover(
          ImportRequest(
            payload: jsonEncode({
              'dances': [_dance(id: '9', name: 'Wrapped')],
            }),
          ),
        );
        expect(records.single.externalId, '9');
      });

      test('a failed discover clears prior state', () async {
        final adapter = CallersBoxAdapter();
        await adapter.discover(
          ImportRequest(payload: jsonEncode(_dance(id: '1'))),
        );
        await expectLater(
          adapter.discover(const ImportRequest(payload: '{bad')),
          throwsA(isA<ImportError>()),
        );
        // The stale record must not be fetchable after a failed discover.
        await expectLater(
          adapter.fetch(
            const DiscoveredRecord(
              source: ProvenanceSource.callersbox,
              locator: {'index': 0},
            ),
          ),
          throwsA(isA<ImportError>()),
        );
      });
    });

    group('fetch', () {
      test('re-serializes a self-contained record with permission', () async {
        final adapter = CallersBoxAdapter();
        final discovered = await adapter.discover(
          ImportRequest(
            payload: jsonEncode(_dance(id: '3', permission: 'search')),
          ),
        );
        final raw = await adapter.fetch(discovered.single);
        expect(raw.source, ProvenanceSource.callersbox);
        expect(raw.externalId, '3');
        expect(raw.permission, 'search');
        expect(raw.contentType, 'application/json');
        expect(jsonDecode(raw.payload), isA<Map<String, dynamic>>());
      });

      test('throws on a bad locator', () {
        expect(
          () => CallersBoxAdapter().fetch(
            const DiscoveredRecord(source: ProvenanceSource.callersbox),
          ),
          throwsA(
            isA<ImportError>().having(
              (e) => e.stage,
              'stage',
              ImportStage.fetch,
            ),
          ),
        );
      });
    });

    group('parse — metadata', () {
      test('maps Name → title', () async {
        final draft = await _importOne(
          jsonEncode(_dance(name: 'The Nice Combination')),
        );
        expect(draft.dance.title, 'The Nice Combination');
      });

      test(
        'classifies FormationBase best-effort, keeps original detail',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                formationBase: 'Duple Minor - Improper',
                formationDetail: 'chestnut',
              ),
            ),
          );
          expect(draft.dance.formation.shape, FormationShape.dupleImproper);
          expect(draft.dance.formation.detail, contains('Improper'));
          expect(draft.dance.formation.detail, contains('chestnut'));
        },
      );

      test('classifies Becket, and unknown → other + warning', () async {
        final becket = await _importOne(
          jsonEncode(_dance(formationBase: 'Duple Minor - Becket')),
        );
        expect(becket.dance.formation.shape, FormationShape.becketCw);

        final weird = await _importOne(
          jsonEncode(_dance(formationBase: 'Zia')),
        );
        expect(weird.dance.formation.shape, FormationShape.other);
        expect(
          weird.issues.any(
            (i) => i.code == 'callersbox_formation_unclassified',
          ),
          isTrue,
        );
      });

      test('maps Progression best-effort', () async {
        final d = await _importOne(jsonEncode(_dance(progression: 'Double')));
        expect(d.dance.progression, Progression.double);

        final weird = await _importOne(
          jsonEncode(_dance(progression: 'Other-Weird')),
        );
        expect(weird.dance.progression, Progression.other);
        expect(
          weird.issues.any((i) => i.code == 'callersbox_progression_unmapped'),
          isTrue,
        );
      });

      test(
        'empty PhraseStructure → default; valid preserved; bad → warn',
        () async {
          final def = await _importOne(jsonEncode(_dance(phraseStructure: '')));
          expect(def.dance.phraseStructure.raw, '');

          final valid = await _importOne(
            jsonEncode(_dance(phraseStructure: '6*8*2')),
          );
          expect(valid.dance.phraseStructure.raw, '6*8*2');

          final bad = await _importOne(
            jsonEncode(_dance(phraseStructure: 'garbage')),
          );
          expect(bad.dance.phraseStructure.raw, '');
          expect(
            bad.issues.any(
              (i) => i.code == 'callersbox_phrase_structure_unreadable',
            ),
            isTrue,
          );
        },
      );

      test('Authors → notes + one info issue each; authorIds empty', () async {
        final draft = await _importOne(
          jsonEncode(_dance(authors: ['Gene Hubert', 'Cary Ravitz'])),
        );
        expect(draft.dance.authorIds, isEmpty);
        expect(draft.dance.callingNotes, contains('Gene Hubert'));
        expect(draft.dance.callingNotes, contains('Cary Ravitz'));
        final authorIssues = draft.issues
            .where((i) => i.code == 'callersbox_author_unresolved')
            .toList();
        expect(authorIssues, hasLength(2));
      });

      test('OtherNames, Music, Tunes, Appearances fold as expected', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              otherNames: ['Nice Combo'],
              music: ['reels'],
              tunes: ['Tune A', 'Tune B'],
              appearances: [
                {'source': 'Dizzy Dances', 'p': '6'},
              ],
            ),
          ),
        );
        expect(draft.dance.callingNotes, contains('Nice Combo'));
        expect(draft.dance.callingNotes, contains('reels'));
        expect(draft.dance.callingNotes, contains('Dizzy Dances (p. 6)'));
        expect(draft.dance.tunes, ['Tune A', 'Tune B']);
      });

      test('id but no Name is still importable as a stub', () async {
        final draft = await _importOne(
          jsonEncode(_dance(id: '55', name: null)),
        );
        expect(draft.dance.title, contains('55'));
      });
    });

    group('parse — figures + dialect scrubbing', () {
      test(
        'full permission: (beats) text → custom figures with beats',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                phrases: [
                  _phrase('A1', [
                    '(4) Neighbor balance',
                    '(12) Neighbor swing',
                  ]),
                ],
              ),
            ),
          );
          expect(draft.dance.figures, hasLength(2));
          expect(draft.dance.figures.every((f) => f.isCustom), isTrue);
          expect(_text(draft.dance.figures[0]), 'Neighbor balance');
          expect(draft.dance.figures[0].params['beats'], 4);
          expect(_text(draft.dance.figures[1]), 'Neighbor swing');
          expect(draft.dance.figures[1].params['beats'], 12);
        },
      );

      test('scrubs gendered role terms to canonical role tokens', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('B2', [
                  '(8) Ladies chain to neighbor',
                  '(8) Gents allemande left',
                ]),
              ],
            ),
          ),
        );
        final texts = draft.dance.figures.map(_text).toList();
        expect(texts[0], 'role2s chain to neighbor');
        expect(texts[1], 'role1s allemande left');
        expect(texts.join(' '), isNot(contains('Ladies')));
        expect(texts.join(' '), isNot(contains('Gents')));
      });

      test('substitutes gypsy → shoulder round (safety net)', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('A1', ['(8) Neighbor gypsy right', '(8) gypsies once']),
              ],
            ),
          ),
        );
        expect(_text(draft.dance.figures[0]), 'Neighbor shoulder round right');
        expect(_text(draft.dance.figures[1]), 'shoulder rounds once');
      });

      test('parse never fails on odd figure lines', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('A1', [
                  '(0) Improper formation',
                  'No beats prefix here',
                  '',
                  '(4) Neighbor swing',
                ]),
              ],
            ),
          ),
        );
        // Empty line dropped; the other three kept.
        expect(draft.dance.figures, hasLength(3));
        expect(
          draft.dance.figures[0].params['beats'],
          isNull,
        ); // (0) → no beats
        expect(_text(draft.dance.figures[0]), 'Improper formation');
        expect(_text(draft.dance.figures[1]), 'No beats prefix here');
        expect(_text(draft.dance.figures[2]), 'Neighbor swing');
      });
    });

    group('parse — permission tiers', () {
      test('search tier → metadata-only, no figures + warning', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              permission: 'search',
              name: 'Hidden',
              phrases: [
                _phrase('A1', ['(4) Neighbor balance']),
              ],
            ),
          ),
        );
        expect(draft.dance.title, 'Hidden');
        expect(draft.dance.figures, isEmpty);
        expect(
          draft.issues.any((i) => i.code == 'callersbox_search_tier'),
          isTrue,
        );
      });

      test('missing permission → metadata-only + warning', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              permission: null,
              phrases: [
                _phrase('A1', ['(4) Neighbor balance']),
              ],
            ),
          ),
        );
        expect(draft.dance.figures, isEmpty);
        expect(
          draft.issues.any((i) => i.code == 'callersbox_search_tier'),
          isTrue,
        );
      });
    });

    group('real id=1 fixture', () {
      test('The Nice Combination parses end to end', () async {
        final draft = await _importOne(_realId1);
        expect(draft.dance.title, 'The Nice Combination');
        expect(draft.dance.formation.shape, FormationShape.dupleImproper);
        expect(draft.dance.progression, Progression.single);
        expect(draft.dance.authorIds, isEmpty);
        expect(draft.dance.callingNotes, contains('Gene Hubert'));
        // 10 figure lines across A1/A2/B1/B2.
        expect(draft.dance.figures, hasLength(10));
        expect(draft.dance.figures.every((f) => f.isCustom), isTrue);
        // "Ladies chain to neighbor" scrubbed to a canonical role token.
        final chain = draft.dance.figures
            .map(_text)
            .firstWhere((t) => t.contains('chain'));
        expect(chain, startsWith('role2s chain'));
        // Beats preserved from the (N) prefixes.
        expect(draft.dance.figures.first.params['beats'], 4);
      });

      test('sourceVersion carries the download_date', () async {
        final adapter = CallersBoxAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: _realId1),
        );
        final raw = await adapter.fetch(discovered.single);
        expect(raw.sourceVersion, '2026-07-16T05:47:04+00:00');
        expect(raw.permission, 'full');
      });
    });
  });
}
