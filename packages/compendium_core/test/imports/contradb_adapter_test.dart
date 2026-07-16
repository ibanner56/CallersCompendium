import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/test_database.dart';

/// Fixtures + tests for [ContraDbAdapter].
///
/// ContraDB is grey-code with **no committed real export**, so these fixtures
/// are **synthetic** — hand-built to the documented schema
/// (`docs/research/contradb.md`, `docs/design/imports.md` §ContraDB) and the
/// adapter's assumed positional `parameter_values` orders. They should be
/// revisited against a real dump when one becomes available.

/// Builds a ContraDB dance map. Any field left null is omitted.
Map<String, Object?> _dance({
  Object? id,
  String? title = 'Test Dance',
  Object? choreographer,
  String? startType,
  String? hook,
  String? preamble,
  String? notes,
  List<Map<String, Object?>>? figures,
}) {
  final map = <String, Object?>{'figures_json': figures ?? const []};
  if (id != null) map['id'] = id;
  if (title != null) map['title'] = title;
  if (choreographer != null) map['choreographer'] = choreographer;
  if (startType != null) map['start_type'] = startType;
  if (hook != null) map['hook'] = hook;
  if (preamble != null) map['preamble'] = preamble;
  if (notes != null) map['notes'] = notes;
  return map;
}

Map<String, Object?> _fig(
  String move,
  List<Object?> params, {
  String? note,
  Object? progression,
  String? customFigure,
  Object? beats,
}) {
  final map = <String, Object?>{'move': move, 'parameter_values': params};
  if (note != null) map['note'] = note;
  if (progression != null) map['progression'] = progression;
  if (customFigure != null) map['custom_figure'] = customFigure;
  if (beats != null) map['beats'] = beats;
  return map;
}

Future<StructuredDraft> _importOne(String payload) async {
  final adapter = ContraDbAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

Figure _figureFor(StructuredDraft d, String move) =>
    d.dance.figures.firstWhere((f) => f.move == move);

void main() {
  group('ContraDbAdapter', () {
    test('source is ProvenanceSource.contradb', () {
      expect(ContraDbAdapter().source, ProvenanceSource.contradb);
    });

    group('structured mapping', () {
      test('mapped moves round-trip to named params', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              id: 'd1',
              title: 'Structured',
              startType: 'improper',
              figures: [
                _fig('swing', ['partners', 16]),
                _fig('allemande', ['neighbors', 'right', 360, 8]),
                _fig('circle', ['left', 4, 8]),
                _fig('right left through', ['across', 8]),
              ],
            ),
          ),
        );

        expect(draft.dance.title, 'Structured');
        expect(draft.dance.formation.shape, FormationShape.dupleImproper);

        final swing = _figureFor(draft, 'swing');
        expect(swing.params['who'], 'partners');
        expect(swing.params['beats'], 16);

        final allemande = _figureFor(draft, 'allemande');
        expect(allemande.params['who'], 'neighbors');
        expect(allemande.params['hand'], 'right');
        expect(allemande.params['turn'], 1.0); // 360° → 1 turn
        expect(allemande.params['beats'], 8);

        final circle = _figureFor(draft, 'circle');
        expect(circle.params['turn'], 'left');
        expect(circle.params['places'], 4);

        // Nothing fell back to custom.
        expect(draft.quality.isFullyCustom, isFalse);
        expect(draft.quality.customFigures, 0);
        expect(draft.quality.structuredFigures, 4);
      });

      test(
        'role vocabulary migrates gentlespoons/ladles → role1s/role2s',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                figures: [
                  _fig('chain', ['ladles', 'across', 8]),
                  _fig('star promenade', ['gentlespoons', 'right', 540, 4]),
                ],
              ),
            ),
          );
          expect(_figureFor(draft, 'chain').params['who'], 'role2s');
          final sp = _figureFor(draft, 'star_promenade');
          expect(sp.params['who'], 'role1s');
          expect(sp.params['turn'], 1.5); // 540° → 1.5 turns
        },
      );

      test('figure note and progression flag are preserved', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig(
                  'swing',
                  ['partners', 16],
                  note: 'scoop them up',
                  progression: 1,
                ),
              ],
            ),
          ),
        );
        final swing = _figureFor(draft, 'swing');
        expect(swing.note, 'scoop them up');
        expect(swing.progression, isTrue);
      });

      test('choice params match separator-insensitively', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('down the hall', [
                  'everyone',
                  'forward_then_backward',
                  'turn_couple',
                  8,
                ]),
              ],
            ),
          ),
        );
        final dth = _figureFor(draft, 'down_the_hall');
        expect(dth.params['facing'], 'forwardThenBackward');
        expect(dth.params['ender'], 'turnCouple');
      });
    });

    group('term migration & aliases', () {
      test('gyre → shoulder_round', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('gyre', ['neighbors', 'right', 360, 8]),
              ],
            ),
          ),
        );
        final sr = _figureFor(draft, 'shoulder_round');
        expect(sr.params['who'], 'neighbors');
        expect(sr.params['shoulder'], 'right');
        expect(sr.params['turn'], 1.0);
        expect(draft.quality.customFigures, 0);
      });

      test('see saw → do si do with pinned left shoulder', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('see saw', ['neighbors', 360, 8]),
              ],
            ),
          ),
        );
        final dsd = _figureFor(draft, 'do_si_do');
        expect(dsd.params['who'], 'neighbors');
        expect(dsd.params['shoulder'], 'left');
      });

      test('swat the flea → box the gnat with pinned left hand', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('swat the flea', ['partners', 4]),
              ],
            ),
          ),
        );
        final btg = _figureFor(draft, 'box_the_gnat');
        expect(btg.params['who'], 'partners');
        expect(btg.params['hand'], 'left');
      });

      test('meltdown swing → swing with pinned prefix', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('meltdown swing', ['partners', 8]),
              ],
            ),
          ),
        );
        expect(_figureFor(draft, 'swing').params['prefix'], 'meltdown');
      });
    });

    group('parse-never-fails', () {
      test('unknown move falls back to custom with an issue', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('floop de doo', ['partners'], note: 'wat', beats: 8),
              ],
            ),
          ),
        );
        final fig = draft.dance.figures.single;
        expect(fig.isCustom, isTrue);
        expect(fig.params['text'], contains('floop de doo'));
        expect(fig.params['beats'], 8);
        expect(
          draft.issues.any((i) => i.code == 'contradb_move_fallback'),
          isTrue,
        );
      });

      test(
        'ContraDB custom move preserves custom_figure text + beats',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                figures: [
                  _fig(
                    'custom',
                    const [],
                    customFigure: 'do a thing',
                    beats: 6,
                  ),
                ],
              ),
            ),
          );
          final fig = draft.dance.figures.single;
          expect(fig.isCustom, isTrue);
          expect(fig.params['text'], 'do a thing');
          expect(fig.params['beats'], 6);
        },
      );

      test(
        'custom move takes beats from a trailing positional value',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                figures: [
                  _fig('custom', const [8], customFigure: 'do a thing'),
                ],
              ),
            ),
          );
          final fig = draft.dance.figures.single;
          expect(fig.params['text'], 'do a thing');
          expect(fig.params['beats'], 8);
        },
      );

      test('a fully-unmapped dance is a valid, committable draft', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              title: 'All Custom',
              figures: [
                _fig('flibber', ['x'], beats: 8),
                _fig('flubber', ['y'], beats: 8),
              ],
            ),
          ),
        );
        expect(draft.quality.isFullyCustom, isTrue);
        expect(draft.dance.figures.every((f) => f.isCustom), isTrue);
        expect(draft.dance.title, 'All Custom');
      });

      test(
        'contra corners custom_figure sub-field maps to custom param',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                figures: [
                  _fig(
                    'contra corners',
                    ['ones'],
                    customFigure: 'allemande left the corners',
                    beats: 16,
                  ),
                ],
              ),
            ),
          );
          final cc = _figureFor(draft, 'contra_corners');
          expect(cc.params['who'], 'ones');
          expect(cc.params['custom'], 'allemande left the corners');
        },
      );
    });

    group('positional param edge cases', () {
      test('too-few parameter_values are tolerated (defaults apply)', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('swing', ['partners']), // no beats
              ],
            ),
          ),
        );
        final swing = _figureFor(draft, 'swing');
        expect(swing.params['who'], 'partners');
        expect(swing.params.containsKey('beats'), isFalse);
      });

      test('extra parameter_values are ignored with an issue', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('swing', ['partners', 16, 'extra', 'more']),
              ],
            ),
          ),
        );
        final swing = _figureFor(draft, 'swing');
        expect(swing.params['who'], 'partners');
        expect(swing.params['beats'], 16);
        expect(
          draft.issues.any((i) => i.code == 'contradb_param_unmapped'),
          isTrue,
        );
      });

      test(
        'an unconvertible param is dropped with an issue, not a crash',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                figures: [
                  _fig('allemande', ['neighbors', 'sideways', 360, 8]),
                ],
              ),
            ),
          );
          final allemande = _figureFor(draft, 'allemande');
          expect(allemande.params.containsKey('hand'), isFalse);
          expect(allemande.params['who'], 'neighbors');
          expect(
            draft.issues.any((i) => i.code == 'contradb_param_unmapped'),
            isTrue,
          );
        },
      );

      test('a (0)-beat figure is preserved', () async {
        final draft = await _importOne(
          jsonEncode(
            _dance(
              figures: [
                _fig('form long waves', ['role1s', 0]),
              ],
            ),
          ),
        );
        final flw = _figureFor(draft, 'form_long_waves');
        expect(flw.params['beats'], 0);
        expect(flw.beats, 0);
      });
    });

    group('start_type classification', () {
      Future<Formation> formationFor(String startType) async {
        final draft = await _importOne(
          jsonEncode(_dance(startType: startType)),
        );
        return draft.dance.formation;
      }

      test('improper', () async {
        expect(
          (await formationFor('improper')).shape,
          FormationShape.dupleImproper,
        );
      });

      test('Becket ccw and cw', () async {
        expect(
          (await formationFor('Becket ccw')).shape,
          FormationShape.becketCcw,
        );
        expect((await formationFor('Becket')).shape, FormationShape.becketCw);
      });

      test('proper', () async {
        expect(
          (await formationFor('proper')).shape,
          FormationShape.dupleProper,
        );
      });

      test('an odd string → other with a warning, detail preserved', () async {
        final draft = await _importOne(
          jsonEncode(_dance(startType: 'spiral galaxy')),
        );
        expect(draft.dance.formation.shape, FormationShape.other);
        expect(draft.dance.formation.detail, 'spiral galaxy');
        expect(
          draft.issues.any((i) => i.code == 'contradb_formation_unclassified'),
          isTrue,
        );
      });
    });

    group('metadata', () {
      test(
        'hook maps to hook; preamble/notes/choreographer fold into notes',
        () async {
          final draft = await _importOne(
            jsonEncode(
              _dance(
                hook: 'A joyful chestnut',
                preamble: 'Careful of the ends.',
                notes: 'First published 1990.',
                choreographer: 'Cary Ravitz',
              ),
            ),
          );
          expect(draft.dance.hook, 'A joyful chestnut');
          expect(draft.dance.callingNotes, contains('Cary Ravitz'));
          expect(draft.dance.callingNotes, contains('Careful of the ends.'));
          expect(draft.dance.callingNotes, contains('First published 1990.'));
          expect(draft.dance.authorIds, isEmpty);
          expect(
            draft.issues.any(
              (i) => i.code == 'contradb_choreographer_unresolved',
            ),
            isTrue,
          );
        },
      );

      test('choreographer object with a name is read', () async {
        final draft = await _importOne(
          jsonEncode(_dance(choreographer: {'id': 7, 'name': 'Bob Isaacs'})),
        );
        expect(draft.dance.callingNotes, contains('Bob Isaacs'));
      });
    });

    group('discovery & batch shapes', () {
      test('object with a dances array → N records', () async {
        final adapter = ContraDbAdapter();
        final discovered = await adapter.discover(
          ImportRequest(
            payload: jsonEncode({
              'dances': [
                _dance(id: 'a', title: 'Alpha'),
                _dance(id: 'b', title: 'Beta'),
              ],
            }),
          ),
        );
        expect(discovered.map((r) => r.label), ['Alpha', 'Beta']);
        expect(discovered.map((r) => r.externalId), ['a', 'b']);
        expect(
          discovered.every((r) => r.source == ProvenanceSource.contradb),
          isTrue,
        );
      });

      test('a bare array of dances → N records', () async {
        final adapter = ContraDbAdapter();
        final discovered = await adapter.discover(
          ImportRequest(
            payload: jsonEncode([_dance(title: 'One'), _dance(title: 'Two')]),
          ),
        );
        expect(discovered.map((r) => r.label), ['One', 'Two']);
      });

      test('a single bare dance object → one record', () async {
        final adapter = ContraDbAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: jsonEncode(_dance(title: 'Solo'))),
        );
        expect(discovered.single.label, 'Solo');
      });

      test('externalId derives from title when id is absent', () async {
        final adapter = ContraDbAdapter();
        final discovered = await adapter.discover(
          ImportRequest(payload: jsonEncode(_dance(title: 'No Id Dance'))),
        );
        expect(discovered.single.externalId, 'title:no id dance');
      });
    });

    group('pipeline integration', () {
      ImportPipeline buildPipeline(CompendiumDatabase db) => ImportPipeline(
        DanceRepository(db, contraTaxonomy),
        ChoreographerRepository(db),
      );

      test('malformed top-level JSON → structured discover failure', () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final result = await buildPipeline(
          db,
        ).plan(ContraDbAdapter(), const ImportRequest(payload: 'not json {'));
        expect(result.errors, hasLength(1));
        expect(result.errors.single.stage, ImportStage.discover);
        expect(result.plannedCount, 0);
      });

      test('missing payload fails discover', () async {
        expect(
          () => ContraDbAdapter().discover(const ImportRequest()),
          throwsA(isA<ImportError>()),
        );
      });

      test(
        'one bad record among good ones is tolerated (partial batch)',
        () async {
          final db = openTestDatabase();
          addTearDown(db.close);
          final result = await buildPipeline(db).plan(
            ContraDbAdapter(),
            ImportRequest(
              payload: jsonEncode([
                _dance(id: 'good1', title: 'Good One'),
                42, // not a dance object
                _dance(id: 'good2', title: 'Good Two'),
              ]),
            ),
          );
          expect(result.plannedCount, 2);
          expect(result.errors, hasLength(1));
          expect(result.errors.single.stage, ImportStage.parse);
        },
      );

      test('a record with no title fails parse but not the batch', () async {
        final db = openTestDatabase();
        addTearDown(db.close);
        final result = await buildPipeline(db).plan(
          ContraDbAdapter(),
          ImportRequest(
            payload: jsonEncode([
              _dance(id: 'ok', title: 'Has Title'),
              _dance(id: 'notitle', title: null),
            ]),
          ),
        );
        expect(result.plannedCount, 1);
        expect(result.errors, hasLength(1));
        expect(result.errors.single.stage, ImportStage.parse);
      });
    });

    group('dedupe', () {
      test(
        'exact (contradb, externalId) re-import resolves to reimport',
        () async {
          final adapter = ContraDbAdapter();
          final discovered = await adapter.discover(
            ImportRequest(
              payload: jsonEncode(_dance(id: 'cdb-1', title: 'X')),
            ),
          );
          final record = discovered.single;

          final index = DedupeIndex([
            DedupeEntry(
              danceId: 'existing',
              title: 'X',
              source: ProvenanceSource.contradb,
              externalId: 'cdb-1',
            ),
          ]);
          final verdict = index.verdictFor(
            source: record.source,
            externalId: record.externalId,
            title: 'X',
          );
          expect(verdict.kind, DedupeKind.reimport);
          expect(verdict.targetDanceId, 'existing');
        },
      );
    });
  });
}
