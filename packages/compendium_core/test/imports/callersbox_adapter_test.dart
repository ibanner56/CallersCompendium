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
  String? direction,
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
  if (direction != null) map['Direction'] = direction;
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

      test('filters non-dance elements out of a mixed array', () async {
        final adapter = CallersBoxAdapter();
        final records = await adapter.discover(
          ImportRequest(
            payload: jsonEncode([
              {'not': 'a dance'},
              _dance(id: '5', name: 'Real'),
              'junk',
            ]),
          ),
        );
        expect(records, hasLength(1));
        expect(records.single.externalId, '5');
        expect(records.single.label, 'Real');
      });

      test('throws when an array has no dance-like elements', () {
        expect(
          () => CallersBoxAdapter().discover(
            ImportRequest(
              payload: jsonEncode([
                {'not': 'a dance'},
                'junk',
              ]),
            ),
          ),
          throwsA(isA<ImportError>()),
        );
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

      test('resolves Becket direction from the Direction field', () async {
        final ccw = await _importOne(
          jsonEncode(
            _dance(formationBase: 'Duple Minor - Becket', direction: 'CCW'),
          ),
        );
        expect(ccw.dance.formation.shape, FormationShape.becketCcw);

        final cw = await _importOne(
          jsonEncode(
            _dance(formationBase: 'Duple Minor - Becket', direction: 'CW'),
          ),
        );
        expect(cw.dance.formation.shape, FormationShape.becketCw);

        final blank = await _importOne(
          jsonEncode(
            _dance(formationBase: 'Duple Minor - Becket', direction: ''),
          ),
        );
        expect(blank.dance.formation.shape, FormationShape.becketCw);

        final weird = await _importOne(
          jsonEncode(
            _dance(
              formationBase: 'Duple Minor - Becket',
              direction: 'sideways',
            ),
          ),
        );
        expect(weird.dance.formation.shape, FormationShape.becketCw);
        expect(
          weird.issues.any((i) => i.code == 'callersbox_direction_unmapped'),
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

      test(
        'Authors → authorNames; not folded into notes; no info issue',
        () async {
          final draft = await _importOne(
            jsonEncode(_dance(authors: ['Gene Hubert', 'Cary Ravitz'])),
          );
          expect(draft.dance.authorIds, isEmpty);
          expect(draft.authorNames, ['Gene Hubert', 'Cary Ravitz']);
          expect(draft.dance.callingNotes, isNot(contains('Gene Hubert')));
          expect(draft.dance.callingNotes, isNot(contains('Cary Ravitz')));
          expect(
            draft.issues.any((i) => i.code == 'callersbox_author_unresolved'),
            isFalse,
          );
        },
      );

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
        'full permission: a balance line folds into the following swing',
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
          // PR3b cross-line merge: the preceding balance line folds into the
          // swing as its `balance` prefix, so the two source lines become one
          // structured figure carrying the summed beats (4 + 12 = 16).
          expect(draft.dance.figures, hasLength(1));
          expect(draft.dance.figures.single.isCustom, isFalse);
          expect(draft.dance.figures.single.move, 'swing');
          expect(draft.dance.figures.single.params['who'], 'neighbors');
          expect(draft.dance.figures.single.params['prefix'], 'balance');
          expect(draft.dance.figures.single.params['beats'], 16);
        },
      );

      test('stores clean custom text with no phrase-label prefix on '
          'fallback', () async {
        // Unrecognised lines fall back to custom. The TCB phrase name is NOT
        // prefixed onto the text — section grouping derives from beats, so
        // embedding it would duplicate a structured field.
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('A2', ['(6) In a big ring, go forward and back']),
                _phrase('B2', ['(2) Bend the line', '(8) Star left 1']),
              ],
            ),
          ),
        );
        expect(draft.dance.figures[0].isCustom, isTrue);
        expect(
          _text(draft.dance.figures[0]),
          'In a big ring, go forward and back',
        );
        expect(draft.dance.figures[1].isCustom, isTrue);
        expect(_text(draft.dance.figures[1]), 'Bend the line');
        // "Star left 1" is recognised → structured.
        expect(draft.dance.figures[2].move, 'star');
      });

      test('stores clean custom text when a phrase has no name', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('', ['(2) Bend the line']),
              ],
            ),
          ),
        );
        expect(_text(draft.dance.figures.single), 'Bend the line');
      });

      test('scrubs gendered role terms before parsing', () async {
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
        // "Ladies chain to neighbor" now structures (PR2 D3): the chain is
        // recognised and the "to neighbor" target is preserved as a Figure
        // note. The scrub still ran (who is the canonical role token).
        expect(draft.dance.figures[0].isCustom, isFalse);
        expect(draft.dance.figures[0].move, 'chain');
        expect(draft.dance.figures[0].params['who'], 'role2s');
        expect(draft.dance.figures[0].note, 'to neighbor');
        // "Gents allemande left" structures; the scrub still ran, so who is the
        // canonical role token (proof scrub happens before parsing).
        expect(draft.dance.figures[1].move, 'allemande');
        expect(draft.dance.figures[1].params['who'], 'role1s');
        expect(draft.dance.figures[1].params['hand'], 'left');
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
        // "Neighbor gypsy right" → shoulder_round structured (gypsy scrubbed).
        expect(draft.dance.figures[0].move, 'shoulder_round');
        expect(draft.dance.figures[0].params['who'], 'neighbors');
        expect(draft.dance.figures[0].params['shoulder'], 'right');
        // "gypsies once" scrubs to "shoulder rounds once" but has no dancer set
        // and stays custom — the scrub is still visible in the text.
        expect(draft.dance.figures[1].isCustom, isTrue);
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
        // "Neighbor swing" is recognised → structured with source beats.
        expect(draft.dance.figures[2].move, 'swing');
        expect(draft.dance.figures[2].params['beats'], 4);
      });
    });

    group('parse — cross-line balance + bend merge (PR3b)', () {
      Future<List<Figure>> figuresFor(List<String> lines) async {
        final draft = await _importOne(
          jsonEncode(_dance(phrases: [_phrase('A1', lines)])),
        );
        return draft.dance.figures;
      }

      test('balance → swing folds into a balance-prefixed swing', () async {
        final figures = await figuresFor([
          '(4) Neighbor balance',
          '(12) Neighbor swing',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'swing');
        expect(figures.single.params['prefix'], 'balance');
        expect(figures.single.params['who'], 'neighbors');
        expect(figures.single.params['beats'], 16); // 4 + 12
      });

      test('matching who folds (neighbor balance → neighbor swing)', () async {
        final figures = await figuresFor([
          '(4) Neighbor balance',
          '(12) Neighbor swing',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'swing');
        expect(figures.single.params['who'], 'neighbors');
        expect(figures.single.params['prefix'], 'balance');
      });

      test('a who conflict blocks the fold (neighbor balance / partner '
          'swing stay separate)', () async {
        final figures = await figuresFor([
          '(4) Neighbor balance',
          '(12) Partner swing',
        ]);
        // The balance names a different dancer than the swing, so folding would
        // drop the neighbor balance — leave both as their own figures.
        expect(figures, hasLength(2));
        expect(figures[0].move, 'balance');
        expect(figures[0].params['who'], 'neighbors');
        expect(figures[1].move, 'swing');
        expect(figures[1].params['who'], 'partners');
        expect(figures[1].params['prefix'], isNull);
      });

      test(
        'balance → petronella sets balance true with summed beats',
        () async {
          final figures = await figuresFor(['(4) Balance', '(4) Petronella']);
          expect(figures, hasLength(1));
          expect(figures.single.move, 'petronella');
          expect(figures.single.params['balance'], isTrue);
          expect(figures.single.params['beats'], 8); // 4 + 4
        },
      );

      test('balance → rory_o_more flips the neutral false to true', () async {
        final figures = await figuresFor(['(4) Balance', '(4) Rory O\'More']);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'rory_o_more');
        expect(figures.single.params['balance'], isTrue);
        expect(figures.single.params['beats'], 8);
      });

      test('balance → box_the_gnat sets the new balance flag', () async {
        final figures = await figuresFor([
          '(4) Partner balance',
          '(4) Box the gnat',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'box_the_gnat');
        expect(figures.single.params['balance'], isTrue);
        expect(figures.single.params['beats'], 8);
      });

      test('balance → swat_the_flea sets the inherited balance flag', () async {
        final figures = await figuresFor([
          '(4) Partner balance',
          '(4) Swat the flea',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'swat_the_flea');
        expect(figures.single.params['balance'], isTrue);
        expect(figures.single.params['beats'], 8);
      });

      test('balance → box_circulate sets the balance flag (v11)', () async {
        final figures = await figuresFor([
          '(4) Partner balance',
          '(4) Box circulate',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'box_circulate');
        expect(figures.single.params['balance'], isTrue);
        expect(figures.single.params['beats'], 8); // 4 + 4
      });

      test(
        'balance + star_through do NOT fold (v12: no balance param)',
        () async {
          final figures = await figuresFor([
            '(4) Partner balance',
            '(4) Star through',
          ]);
          // star_through was removed from the balance-merge set to mirror
          // california_twirl, so the balance line stays a separate figure rather
          // than folding in, and star_through carries no balance param.
          expect(figures, hasLength(2));
          final star = figures.firstWhere((f) => f.move == 'star_through');
          expect(star.params.containsKey('balance'), isFalse);
        },
      );

      test(
        'a varied custom balance form (long wave) folds into a swing',
        () async {
          final figures = await figuresFor([
            '(4) Balance the long wave',
            '(12) Partner swing',
          ]);
          expect(figures, hasLength(1));
          expect(figures.single.move, 'swing');
          expect(figures.single.params['prefix'], 'balance');
          expect(figures.single.params['beats'], 16);
        },
      );

      test('a "wave of four" custom balance folds into a swing', () async {
        final figures = await figuresFor([
          '(4) Balance the wave of four',
          '(12) Neighbor swing',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'swing');
        expect(figures.single.params['prefix'], 'balance');
      });

      test('bend the line → down_the_hall upgrades the ender', () async {
        final figures = await figuresFor([
          '(8) Go down the hall',
          '(4) Bend the line',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'down_the_hall');
        expect(figures.single.params['ender'], 'bendTheLine');
        expect(figures.single.params['beats'], 12); // 8 + 4
      });

      test('bend the line → up_the_hall upgrades the ender', () async {
        final figures = await figuresFor([
          '(8) Go up the hall',
          '(4) Bend the line',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'up_the_hall');
        expect(figures.single.params['ender'], 'bendTheLine');
        expect(figures.single.params['beats'], 12);
      });

      test('a non-adjacent balance is NOT merged into a later swing', () async {
        final figures = await figuresFor([
          '(4) Neighbor balance',
          '(8) Circle left 3/4',
          '(12) Neighbor swing',
        ]);
        expect(figures, hasLength(3));
        expect(figures[0].move, 'balance');
        expect(figures[1].move, 'circle');
        expect(figures[2].move, 'swing');
        expect(figures[2].params['prefix'], isNull);
      });

      test(
        'a balance with no following mergeable move stays separate',
        () async {
          final figures = await figuresFor([
            '(4) Neighbor balance',
            '(8) Circle left 3/4',
          ]);
          expect(figures, hasLength(2));
          expect(figures[0].move, 'balance');
          expect(figures[0].params['beats'], 4);
          expect(figures[1].move, 'circle');
        },
      );

      test('a bend the line not adjacent to a hall stays custom', () async {
        final figures = await figuresFor([
          '(12) Neighbor swing',
          '(4) Bend the line',
        ]);
        expect(figures, hasLength(2));
        expect(figures[0].move, 'swing');
        expect(figures[1].isCustom, isTrue);
        expect(_text(figures[1]), 'Bend the line');
      });

      test('a bend never folds into a custom (unrecognised) hall', () async {
        final figures = await figuresFor([
          '(6) Go down the hall and back',
          '(2) Bend the line',
        ]);
        expect(figures, hasLength(2));
        expect(figures[0].isCustom, isTrue);
        expect(figures[1].isCustom, isTrue);
        expect(_text(figures[1]), 'Bend the line');
      });

      test('a fold never crosses a phrase (section) boundary', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              phrases: [
                _phrase('A1', ['(4) Neighbor balance']),
                _phrase('A2', ['(12) Neighbor swing']),
              ],
            ),
          ),
        );
        // Balance ends A1 and the swing opens A2 — different sections, so they
        // are left as two separate figures.
        expect(draft.dance.figures, hasLength(2));
        expect(draft.dance.figures[0].move, 'balance');
        expect(draft.dance.figures[1].move, 'swing');
        expect(draft.dance.figures[1].params['prefix'], isNull);
      });

      test('a single-line "balance and swing" is not double-folded', () async {
        final figures = await figuresFor([
          '(4) Neighbor balance',
          '(16) Neighbor balance and swing',
        ]);
        // The second line already structures as a balance-prefixed swing; the
        // preceding standalone balance line has no *unbalanced* move to fold
        // into, so both survive (the swing keeps its own 16 beats).
        expect(figures, hasLength(2));
        expect(figures[0].move, 'balance');
        expect(figures[1].move, 'swing');
        expect(figures[1].params['prefix'], 'balance');
        expect(figures[1].params['beats'], 16);
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
        expect(draft.authorNames, ['Gene Hubert']);
        expect(draft.dance.callingNotes, isNot(contains('Gene Hubert')));
        // 8 figures: A1's balance folds into the following swing (PR3b), and in
        // A2 both "in a line of four" halls now structure (PR3) with the
        // trailing "Bend the line" folding into the up-the-hall (PR3b), so the
        // 10 source lines across A1/A2/B1/B2 collapse to 8.
        expect(draft.dance.figures, hasLength(8));
        // Recognised lines structure (the balance-and-swing, swings, circle,
        // star, chain-to-neighbor, and both A2 halls with their "in a line of
        // four" prefix). Only A2's "Neighbor turn as couples" stays custom.
        expect(draft.dance.figures.where((f) => f.isCustom), hasLength(1));
        // "Ladies chain to neighbor" (phrase B2) now structures as a chain with
        // the "to neighbor" target preserved as a Figure note.
        final chain = draft.dance.figures.firstWhere((f) => f.move == 'chain');
        expect(chain.params['who'], 'role2s');
        expect(chain.note, 'to neighbor');
        // The first figure is A1's balance-and-swing: the balance line folded
        // into the swing as its prefix, carrying the summed beats (4 + 12).
        expect(draft.dance.figures.first.move, 'swing');
        expect(draft.dance.figures.first.params['prefix'], 'balance');
        expect(draft.dance.figures.first.params['beats'], 16);
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
