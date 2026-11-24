/// Integration: The Caller's Box → `compendium_core`'s adapter → this compiler.
///
/// The committed corpus is deliberately **one dance**. What this test proves is
/// that the seam between the two packages holds — a foreign payload becomes a
/// [core.Dance], a [core.Dance] becomes a record, and a record compiles — and
/// that is a property of the seam, not of the sample. Sample size is what
/// `bin/callersbox_harness.dart` is for, pointed at a local mirror; committing
/// thousands of source files to raise it would buy nothing this file does not
/// already establish.
///
/// The same harness runs here. Set `RUBRIC_TCB_CORPUS` to a directory of
/// Caller's Box JSON and the last group in this file sweeps it:
///
/// ```
/// $env:RUBRIC_TCB_CORPUS = 'C:\corpus\dances'; fvm dart test test/io/callersbox_integration_test.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:compendium_core/compendium_core.dart' as core;
import 'package:compendium_core/testing.dart' as core_test;
import 'package:compendium_rubric/compendium_rubric.dart';
import 'package:test/test.dart';

/// `test/io/callersbox/once_more_with_feeling.json` — The Caller's Box #14948,
/// fetched verbatim from
/// `https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=14948&format=JSON`.
///
/// Chosen because its permission tier is `full` (so the figures are actually in
/// the payload), it structures with nothing left as free text, and its
/// progression sits on the last figure — where the import rule assumes it —
/// with the source note `face next` independently saying so.
File get _fixture => File('test/io/callersbox/once_more_with_feeling.json');

String _payload() => _fixture.readAsStringSync().replaceFirst('\uFEFF', '');

Future<core.StructuredDraft> _draft() async {
  final adapter = core.CallersBoxAdapter();
  final discovered = await adapter.discover(
    core.ImportRequest(payload: _payload()),
  );
  return adapter.parse(await adapter.fetch(discovered.single));
}

/// A [core.Dance] built only to exercise [assumedProgressionIndex]'s branch
/// selection. It is never compiled, and it is not choreography: the rule under
/// test is positional and does not read what the figures do, so the figures
/// here are placeholders that make the *shape* of the dance legible.
core.Dance _shapedLike({
  required core.FormationShape shape,
  required List<core.Figure> figures,
  core.Progression progression = core.Progression.single,
}) {
  final now = DateTime.utc(2020);
  return core.Dance(
    id: 'rule-under-test',
    title: 'rule under test',
    formation: core.Formation(shape),
    progression: progression,
    figures: figures,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('the fixture survives the adapter', () {
    test(
      'it is a real Caller\'s Box payload and structures completely',
      () async {
        final draft = await _draft();
        expect(draft.raw.source, core.ProvenanceSource.callersbox);
        expect(draft.raw.externalId, '14948');
        expect(draft.dance.title, 'Once More With Feeling');
        expect(draft.dance.form, core.DanceForm.contra);
        expect(draft.dance.formation.shape, core.FormationShape.dupleImproper);
        expect(draft.dance.progression, core.Progression.single);

        // The fixture earns its place by being fully structured: a `custom`
        // figure is text the compiler has no reading of, and a fixture holding
        // one could never test a compile at all.
        expect(draft.quality.customFigures, 0);
        expect(draft.quality.totalFigures, 7);
        expect(decodedFigures(draft.dance)!.map((figure) => figure.move), [
          'box_the_gnat',
          'allemande',
          'swing',
          'circle',
          'swing',
          'petronella',
          'petronella',
        ]);
      },
    );

    test('the source flags no figure as the progression', () async {
      // The premise of the whole import rule. The Caller's Box figure lines are
      // prose with nowhere to put this, so the adapter never sets it — unlike
      // the ContraDB adapter, whose source markup carries an explicit marker.
      // If this ever starts failing, the assumption below has become
      // unnecessary and should be deleted rather than kept as a fallback.
      final draft = await _draft();
      expect(
        decodedFigures(draft.dance)!.any((figure) => figure.progression),
        isFalse,
      );
    });
  });

  group('bridging a core dance into a record', () {
    test('it assumes the last figure progresses, and says so', () async {
      final bridged = bridgeCoreDance((await _draft()).dance);

      expect(bridged.assumedProgressionAt, 6);
      expect(bridged.warnings, hasLength(1));
      expect(bridged.warnings.single.kind, WarningKind.assumedProgression);
      expect(bridged.warnings.single.opIndex, 6);

      final figures = bridged.record['figures']! as List<Object?>;
      final flagged = [
        for (var i = 0; i < figures.length; i++)
          if ((figures[i]! as Map<String, Object?>)['progression'] == true) i,
      ];
      expect(flagged, [6], reason: 'exactly one figure carries the flag');
    });

    test('it carries the four fields the parser reads', () async {
      final record = bridgeCoreDance((await _draft()).dance).record;
      expect(record['title'], 'Once More With Feeling');
      expect(record['form'], 'contra');
      expect(record['formation'], {'shape': 'dupleImproper'});
      expect(record['progression'], 'single');
      expect(record['figures'], hasLength(7));
    });
  });

  group('the imported dance compiles', () {
    test('it compiles, and the warning survives into the result', () async {
      final run = runCoreDance(await _draft(), label: 'fixture');

      expect(
        run.outcome,
        DanceOutcome.compiled,
        reason: run.detail ?? 'no detail',
      );
      expect(run.sourceId, '14948');
      expect(run.assumedProgressionAt, 6);
      // The ruling that makes this test worth writing: a compile resting on an
      // assumption must not read like one resting on the record.
      expect(
        run.warnings.map((warning) => warning.kind),
        contains(WarningKind.assumedProgression),
      );
    });

    test('the compile is discriminating, not a rubber stamp', () async {
      // The mutation this whole file exists to catch: if the compiler accepted
      // any progression placement, "it compiled" would assert nothing at all
      // about the choreography. Five of the seven placements must fail. The
      // two that succeed are the final petronella, which the rule picks, and
      // the first one: a flag there finds nobody whole at an end, so it is
      // held and finishes on the second petronella (user-ruled 2026-11-23:
      // holding applies in every formation).
      final dance = (await _draft()).dance;
      final outcomes = <int, DanceOutcome>{};
      for (var index = 0; index < decodedFigures(dance)!.length; index++) {
        final record = bridgeCoreDance(dance).record;
        final figures = record['figures']! as List<Object?>;
        for (var i = 0; i < figures.length; i++) {
          final figure = figures[i]! as Map<String, Object?>;
          if (i == index) {
            figure['progression'] = true;
          } else {
            figure.remove('progression');
          }
        }
        final parsed = parseDance(record);
        outcomes[index] = switch (parsed) {
          Err() => DanceOutcome.unsupported,
          Ok(:final value) => switch (compile(value)) {
            Compiled() => DanceOutcome.compiled,
            Mismatch() => DanceOutcome.mismatch,
            CompileError() => DanceOutcome.figureRefused,
          },
        };
      }

      final compiling = outcomes.entries
          .where((entry) => entry.value == DanceOutcome.compiled)
          .map((entry) => entry.key)
          .toList();
      expect(
        compiling,
        [5, 6],
        reason:
            'only the petronellas leave the set progressed: the final one, '
            'the line the source annotates "face next", and the first, whose '
            'held change-over the second finishes; got $outcomes',
      );
    });

    test('a run reports the moves the source named', () async {
      final run = runCoreDance(await _draft(), label: 'fixture');
      expect(run.moves, {
        'box_the_gnat',
        'allemande',
        'swing',
        'circle',
        'petronella',
      });
      expect(run.totalFigures, 7);
      expect(run.customFigures, 0);
    });
  });

  group('the payload entry point', () {
    test('an undecodable transcription is the adapter\'s failure, not an '
        'empty dance', () async {
      // compendium_core holds a transcription as a sealed FigureSource so that
      // an undecodable one cannot pass for an empty list; this is the one
      // place the compiler meets that case, and it must keep it apart.
      final draft = await _draft();
      final now = DateTime.utc(2020);
      final unreadable = core.StructuredDraft(
        dance: core.Dance(
          id: 'unreadable',
          title: draft.dance.title,
          formation: draft.dance.formation,
          figuresSource: const core.UnreadableFigures('not json'),
          createdAt: now,
          updatedAt: now,
        ),
        raw: draft.raw,
      );

      final run = runCoreDance(unreadable);

      expect(run.outcome, DanceOutcome.adapterFailed);
      expect(decodedFigures(unreadable.dance), isNull);
    });

    test('it runs a raw payload end to end', () async {
      final runs = await runCallersBoxPayload(_payload(), label: _fixture.path);
      expect(runs, hasLength(1));
      expect(runs.single.outcome, DanceOutcome.compiled);
      expect(runs.single.label, _fixture.path);
    });

    test('an unreadable payload becomes a run, not an exception', () async {
      // A corpus sweep must not unwind on one bad file; the local mirror
      // contains at least one that is not valid JSON.
      final runs = await runCallersBoxPayload('{ not json', label: 'broken');
      expect(runs, hasLength(1));
      expect(runs.single.outcome, DanceOutcome.adapterFailed);
      expect(runs.single.detail, isNotNull);
    });

    test('a report divides by what the compiler was actually handed', () async {
      final runs = await runCallersBoxPayload(_payload(), label: 'fixture');
      final report = CorpusReport([
        ...runs,
        // Neither of these was ever compiled, so neither may count against the
        // compile rate — they measure the source's coverage, not ours.
        const DanceRun(
          title: 'withheld',
          outcome: DanceOutcome.empty,
          sourceId: null,
          label: 'x',
        ),
        const DanceRun(
          title: 'free text',
          outcome: DanceOutcome.unstructured,
          sourceId: null,
          label: 'x',
        ),
      ]);

      expect(report.total, 3);
      expect(report.attempted, 1);
      expect(report.compiled, 1);
      expect(report.compileRate, 1.0);
      expect(report.count(DanceOutcome.empty), 1);
      expect(report.movesMissing, isEmpty);
      expect(report.movesCovered, hasLength(5));
    });

    test('an empty report scores nothing rather than everything', () {
      final report = CorpusReport(const []);
      expect(report.compileRate, 0.0);
      expect(report.corpusCoverage, 0.0);
      expect(report.vocabularyCoverage, 0.0);
      expect(report.inScopeRate, 0.0);
    });

    test('the in-scope rate divides by what we are actually aiming at', () {
      // *(User-ruled scope.)* The headline number excludes the dances nobody
      // could compile today -- free text, and anything deferred -- so that it
      // measures the model rather than the size of the backlog. Everything
      // that could compile and did not stays in, including a plain mismatch.
      final report = CorpusReport(const [
        DanceRun(
          title: 'lands',
          outcome: DanceOutcome.compiled,
          sourceId: null,
          label: 'x',
        ),
        DanceRun(
          title: 'ran and landed wrong',
          outcome: DanceOutcome.mismatch,
          sourceId: null,
          label: 'x',
        ),
        DanceRun(
          title: 'names a move we have not written',
          outcome: DanceOutcome.unsupported,
          sourceId: null,
          label: 'x',
          blockedByDeferral: true,
        ),
        DanceRun(
          title: 'a deferred param inside a figure we do implement',
          outcome: DanceOutcome.figureRefused,
          sourceId: null,
          label: 'x',
          blockedByDeferral: true,
        ),
        DanceRun(
          title: 'a figure that genuinely disagreed with the floor',
          outcome: DanceOutcome.figureRefused,
          sourceId: null,
          label: 'x',
        ),
        DanceRun(
          title: 'free text',
          outcome: DanceOutcome.unstructured,
          sourceId: null,
          label: 'x',
        ),
        DanceRun(
          title: 'withheld',
          outcome: DanceOutcome.empty,
          sourceId: null,
          label: 'x',
        ),
      ]);

      expect(report.deferred, 2);
      // The compile, the mismatch, and the honest refusal. Not the two
      // deferrals, the free text, or the withheld record.
      expect(report.inScope, 3);
      expect(report.inScopeRate, closeTo(1 / 3, 1e-9));
      // The older rate still counts both deferred figure refusals, because it
      // answers a different question: how much of the corpus can be read at
      // all. The two numbers are meant to disagree.
      expect(report.attempted, 4);
      expect(report.compileRate, 0.25);
    });

    test(
      'a crash is in scope, so a defect here cannot hide in the backlog',
      () {
        final report = CorpusReport(const [
          DanceRun(
            title: 'threw',
            outcome: DanceOutcome.crashed,
            sourceId: null,
            label: 'x',
          ),
        ]);

        expect(report.inScope, 1);
        expect(report.inScopeRate, 0.0);
      },
    );
  });

  group('a slide after a balanced long wave is a Rory O\'More '
      '(user-ruled 2026-11-23)', () {
    core.Figure figure(String move, [Map<String, Object?> params = const {}]) =>
        core_test.testFigure(move: move, params: params);
    core.Figure wave({String whom = 'neighbors', bool balance = true}) =>
        figure('form_long_waves', {
          'whom': whom,
          'whomHand': 'right',
          'who': 'role1s',
          'balance': balance,
          'beats': 4,
        });
    Map<String, Object?> bridgedAt(List<core.Figure> figures, int index) =>
        (bridgeCoreDance(
                  _shapedLike(
                    shape: core.FormationShape.dupleImproper,
                    figures: figures,
                  ),
                ).record['figures']!
                as List<Object?>)[index]!
            as Map<String, Object?>;

    test('"Balance long wave; Slide left (past N2)" slides the wave', () {
      final slide = bridgedAt([
        wave(),
        figure('slide_along_set', {'slide': 'left', 'beats': 4}),
      ], 1);
      expect(slide['move'], 'rory_o_more');
      expect(slide['params'], {'balance': false, 'slide': 'left', 'beats': 4});
    });

    test('a wave formed with a later neighbour set slides among them', () {
      final slide = bridgedAt([
        wave(whom: 'nextNeighbors'),
        figure('slide_along_set', {'slide': 'right', 'beats': 4}),
      ], 1);
      expect(slide['move'], 'rory_o_more');
      expect((slide['params']! as Map)['who'], 'nextNeighbors');
    });

    test('a slide that states no direction slides left, as it would have', () {
      final slide = bridgedAt([wave(), figure('slide_along_set')], 1);
      expect(slide['move'], 'rory_o_more');
      expect((slide['params']! as Map)['slide'], 'left');
    });

    test('the wave itself is left as it was imported', () {
      final first = bridgedAt([
        wave(),
        figure('slide_along_set', {'slide': 'right', 'beats': 4}),
      ], 0);
      expect(first['move'], 'form_long_waves');
      expect((first['params']! as Map)['balance'], isTrue);
    });

    test('a slide with no balanced wave just before it stays a slide', () {
      expect(
        bridgedAt([
          wave(balance: false),
          figure('slide_along_set', {'slide': 'left'}),
        ], 1)['move'],
        'slide_along_set',
      );
      expect(
        bridgedAt([
          figure('swing'),
          figure('slide_along_set', {'slide': 'left'}),
        ], 1)['move'],
        'slide_along_set',
      );
      expect(
        bridgedAt([
          figure('slide_along_set', {'slide': 'left'}),
        ], 0)['move'],
        'slide_along_set',
      );
    });
  });

  group('a sequence container is danced as its children', () {
    // `compendium_core` puts a run of figures written on one line ("pass
    // through and California twirl") in a `sequence` container. It defines no
    // new motion: the children are danced in order, exactly as if they had
    // been written as separate figures. The fixture is the control here,
    // because it compiles as plain figures, so the same figures inside a
    // container must compile too.
    Future<core.StructuredDraft> withSequence(
      int start,
      int end, {
      bool progression = false,
    }) async {
      final draft = await _draft();
      final figures = decodedFigures(draft.dance)!;
      final children = figures.sublist(start, end);
      final wrapped = [
        ...figures.sublist(0, start),
        core.Figure.sequence(
          figures: children,
          beats: children.fold(0, (sum, figure) => sum + figure.beats),
          progression: progression,
        ),
        ...figures.sublist(end),
      ];
      return core.StructuredDraft(
        dance: draft.dance.copyWith(figures: wrapped),
        raw: draft.raw,
      );
    }

    test('a sequence mid-dance compiles as the figures it holds', () async {
      final draft = await withSequence(3, 5);
      expect(
        decodedFigures(draft.dance)!.map((figure) => figure.move),
        contains('sequence'),
        reason: 'the container really is in the transcription',
      );

      final figures =
          bridgeCoreDance(draft.dance).record['figures']! as List<Object?>;
      expect(
        [for (final f in figures) (f! as Map<String, Object?>)['move']],
        [
          'box_the_gnat',
          'allemande',
          'swing',
          'circle',
          'swing',
          'petronella',
          'petronella',
        ],
      );
      expect(runCoreDance(draft).outcome, DanceOutcome.compiled);
    });

    test('the assumed progression reaches inside a closing sequence', () async {
      // The positional rule takes the last figure danced, which is the last
      // child, not the container.
      final draft = await withSequence(5, 7);
      final bridged = bridgeCoreDance(draft.dance);
      expect(bridged.assumedProgressionAt, 6);
      expect(runCoreDance(draft).outcome, DanceOutcome.compiled);
    });

    test('a sequence flagged as the progression hands it to its last '
        'child', () async {
      final draft = await withSequence(5, 7, progression: true);
      final danced = dancedFigures(draft.dance)!;
      expect(
        [for (final f in danced) f.progression],
        [false, false, false, false, false, false, true],
      );
      final run = runCoreDance(draft);
      expect(run.outcome, DanceOutcome.compiled);
      expect(run.assumedProgressionAt, isNull, reason: 'the source said');
    });

    group('an open chain', () {
      // Hudson's report note on Every Second Counts (10417, 2026-11-24): the
      // courtesy allemande Caller's Box writes "3/4" is a full allemande.
      // Reading every open chain that way was ratified by the user 2026-11-24.
      core.Figure allemande(String who, num travel, {String hand = 'left'}) =>
          core_test.testFigure(
            move: 'allemande',
            params: {'who': who, 'hand': hand, 'travel': travel, 'beats': 4},
          );
      core.Dance withChain(
        String? title,
        List<core.Figure> children, {
        bool progression = false,
      }) {
        final now = DateTime.utc(2020);
        return core.Dance(
          id: 'open-chain',
          title: 'open chain',
          formation: const core.Formation(core.FormationShape.dupleImproper),
          figures: [
            core.Figure.sequence(
              figures: children,
              beats: 8,
              title: title,
              progression: progression,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        );
      }

      List<Object?> travels(core.Dance dance) => [
        for (final f in dancedFigures(dance)!) f.params['travel'],
      ];

      test('closes with a full allemande', () {
        for (final who in ['role1s', 'role2s']) {
          final dance = withChain('Open $who chain to neighbor', [
            allemande(who, 0.5, hand: 'right'),
            allemande('neighbors', 0.75),
          ]);
          expect(travels(dance), [0.5, 1.0], reason: who);
        }
      });

      test('keeps the rest of the turn and takes a flag to it', () {
        final flagged = withChain('OPEN ROLE2S CHAIN', [
          allemande('role2s', 0.5, hand: 'right'),
          allemande('neighbors', 0.75),
        ], progression: true);
        final courtesy = dancedFigures(flagged)!.last;
        expect(courtesy.params, {
          'who': 'neighbors',
          'hand': 'left',
          'travel': 1.0,
          'beats': 4,
        });
        expect(courtesy.progression, isTrue);
      });

      test('leaves a courtesy turn that is not an allemande', () {
        // "Men allemande left 1/2 / Neighbor right shoulder round 3/4".
        final dance = withChain('Modified open role1s chain', [
          allemande('role1s', 0.5),
          core_test.testFigure(
            move: 'shoulder_round',
            params: {'who': 'neighbors', 'travel': 0.75, 'beats': 4},
          ),
        ]);
        expect(travels(dance), [0.5, 0.75]);
      });

      test('is danced as written without a chain title', () {
        final dance = withChain('Allemandes', [
          allemande('role2s', 0.5, hand: 'right'),
          allemande('neighbors', 0.75),
        ]);
        expect(travels(dance), [0.5, 0.75]);
      });

      test('is danced as written when the turns differ', () {
        for (final children in [
          [allemande('neighbors', 0.5), allemande('neighbors', 0.75)],
          [allemande('role2s', 0.75), allemande('neighbors', 0.75)],
          [allemande('role2s', 0.5), allemande('neighbors', 0.5)],
          [
            core_test.testFigure(
              move: 'shoulder_round',
              params: {'who': 'role2s', 'travel': 0.5, 'beats': 4},
            ),
            allemande('neighbors', 0.75),
          ],
          [
            allemande('role2s', 0.5),
            allemande('neighbors', 0.75),
            allemande('partners', 0.75),
          ],
        ]) {
          final dance = withChain('Open role2s chain to neighbor', children);
          expect(travels(dance), [
            for (final c in children) c.params['travel'],
          ], reason: '$children');
        }
      });
    });

    test('a sequence inside another container is left inside it', () {
      // Only a top-level sequence is spliced; a meanwhile stays a meanwhile,
      // whatever it holds, and the parser builds it as one.
      final meanwhile = core.Figure.meanwhile(
        figures: [
          core_test.testFigure(move: 'swing'),
          core.Figure.sequence(
            figures: [
              core_test.testFigure(move: 'circle'),
              core_test.testFigure(move: 'star'),
            ],
            beats: 8,
          ),
        ],
        beats: 8,
      );
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [meanwhile],
      );
      final danced = dancedFigures(dance)!;
      expect(danced.single.move, 'meanwhile');
      expect(
        [for (final f in danced.single.subFigures) f.move],
        ['swing', 'sequence'],
        reason: 'the inner sequence is not spliced into the meanwhile',
      );
    });

    test('a container inside a sequence comes up to the top level', () {
      // The splice is one level deep: a meanwhile the sequence held is danced
      // in its place, as a meanwhile.
      final meanwhile = core.Figure.meanwhile(
        figures: [
          core_test.testFigure(move: 'swing'),
          core_test.testFigure(move: 'circle'),
        ],
        beats: 8,
      );
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          core.Figure.sequence(
            figures: [
              core_test.testFigure(move: 'star'),
              meanwhile,
            ],
            beats: 16,
          ),
        ],
      );
      expect(
        [for (final f in dancedFigures(dance)!) f.move],
        ['star', 'meanwhile'],
      );
    });
  });

  group('a Caller\'s Box promenade that states no where', () {
    // Caller's Box writes every promenade across with `where: across`; the
    // lines it imports with no `where` are whole-set, counter-rotating,
    // around-a-dancer and mixer promenades. The parser's `across` default
    // would dance them as a promenade across, so this path reports them as an
    // import problem, before the compiler is asked. *(User-ruled.)*
    Future<core.StructuredDraft> withPromenadeAt(
      int index,
      Map<String, Object?> params, {
      bool inSequence = false,
      bool inMeanwhile = false,
    }) async {
      final draft = await _draft();
      final figures = [...decodedFigures(draft.dance)!];
      final promenade = core_test.testFigure(move: 'promenade', params: params);
      final partner = core_test.testFigure(move: 'swing');
      figures[index] = inSequence
          ? core.Figure.sequence(figures: [partner, promenade], beats: 8)
          : inMeanwhile
          ? core.Figure.meanwhile(figures: [partner, promenade], beats: 8)
          : promenade;
      return core.StructuredDraft(
        dance: draft.dance.copyWith(figures: figures),
        raw: draft.raw,
      );
    }

    for (final params in <Map<String, Object?>>[
      {'who': 'partners', 'direction': 'counterclockwise'},
      {'who': 'partners'},
    ]) {
      test('$params is an import problem, not a compiler one', () async {
        final run = runCoreDance(await withPromenadeAt(2, params));
        expect(run.outcome, DanceOutcome.unstructured);
        expect(run.blockedByDeferral, isFalse);
        expect(run.inScope, isFalse);
        expect(run.attempted, isFalse);
        expect(
          run.detail,
          startsWith('figure 3 (promenade) imported with no where'),
        );
      });
    }

    test('one inside a sequence is found among the danced figures', () async {
      final run = runCoreDance(
        await withPromenadeAt(2, {'who': 'partners'}, inSequence: true),
      );
      expect(run.outcome, DanceOutcome.unstructured);
      expect(run.blockedByDeferral, isFalse);
      expect(
        run.detail,
        startsWith('figure 4 (promenade) imported with no where'),
      );
    });

    test('one inside a meanwhile is found in its slot', () async {
      // The bridge does not splice a meanwhile, but the promenade inside it is
      // still danced, so compiling it as `across` would be the same guess.
      final run = runCoreDance(
        await withPromenadeAt(2, {'who': 'partners'}, inMeanwhile: true),
      );
      expect(run.outcome, DanceOutcome.unstructured);
      expect(
        run.detail,
        startsWith('figure 3 (promenade) imported with no where'),
      );
      expect(run.moves, containsAll(<String>['meanwhile', 'promenade']));
    });

    for (final params in <Map<String, Object?>>[
      {'who': 'partners', 'where': 'across'},
      {'who': 'partners', 'where': 'across', 'direction': 'clockwise'},
    ]) {
      test('$params reaches the compiler', () async {
        final run = runCoreDance(await withPromenadeAt(2, params));
        // Every figure dances, the promenade included; the set then lands
        // where the fixture's own figure 3 would not have taken it.
        expect(run.outcome, DanceOutcome.mismatch);
      });
    }

    test('it is reported before any compiler blocker', () async {
      // As a free-text figure is: an earlier unimplemented move does not take
      // the blame for a dance the import could not structure.
      final draft = await withPromenadeAt(4, {'who': 'partners'});
      final figures = [...decodedFigures(draft.dance)!];
      figures[1] = core_test.testFigure(move: 'dolphin_hey');
      final run = runCoreDance(
        core.StructuredDraft(
          dance: draft.dance.copyWith(figures: figures),
          raw: draft.raw,
        ),
      );
      expect(run.outcome, DanceOutcome.unstructured);
      expect(run.blockedByDeferral, isFalse);
      expect(
        run.detail,
        startsWith('figure 5 (promenade) imported with no where'),
      );
    });

    test('a free-text figure still speaks first', () async {
      final draft = await withPromenadeAt(4, {'who': 'partners'});
      final figures = [...decodedFigures(draft.dance)!];
      figures[1] = core_test.testFigure(
        move: core.customMoveId,
        params: const {'text': 'something nobody structured'},
      );
      final dance = draft.dance.copyWith(figures: figures);
      final run = runCoreDance(
        core.StructuredDraft(dance: dance, raw: draft.raw),
      );
      expect(run.outcome, DanceOutcome.unstructured);
      expect(run.detail, isNot(contains('promenade')));
    });

    test('the corpus report counts it out of scope, not as deferred', () async {
      final run = runCoreDance(await withPromenadeAt(2, {'who': 'partners'}));
      final report = CorpusReport([run]);
      expect(report.deferred, 0);
      expect(report.inScope, 0);
      expect(report.attempted, 0);
      expect(report.count(DanceOutcome.unstructured), 1);
    });
  });

  group('a hey whose last pass is marked "~" is the last-resort progression '
      '(user-ruled 2026-11-24)', () {
    /// A Caller's Box payload for a Becket dance, from its figure lines.
    String payload(String id, String direction, List<List<String>> phrases) =>
        jsonEncode({
          'ID': id,
          'Name': 'Caller\'s Box #$id',
          'Authors': ['Test'],
          'Permission': 'full',
          'FormationBase': 'Duple Minor - Becket',
          'FormationDetail': '',
          'Progression': 'Single',
          'Direction': direction,
          'Mixer?': '',
          'phrases': [
            for (final (i, lines) in phrases.indexed)
              {
                'name': ['A1', 'A2', 'B1', 'B2'][i],
                'figures': lines,
              },
          ],
          'CallingNotes': <Object?>[],
        });

    /// Rowdy Rendezvous (Caller's Box #18981, permission `full`). It flags no
    /// progression, and neither the positional nor the next-neighbours
    /// reading compiles it.
    String rowdy({bool tilde = true}) => payload('18981', 'CCW', [
      ['(6) Circle left 3/4', '(10) Neighbor swing'],
      [
        '(8) In long lines, go forward and back',
        '(8) On right diagonal, right and left through with neighbor',
      ],
      [
        '(8) On right diagonal, ladies chain to shadow',
        '(8) Hey 1/2 (WR;NL;MR${tilde ? '~' : ''})',
      ],
      ['(4) Partner balance', '(12) Partner swing'],
    ]);

    test('it compiles a dance progressing on its marked hey', () async {
      final runs = await runCallersBoxPayload(rowdy(), label: '18981');
      expect(runs.single.outcome, DanceOutcome.compiled, reason: '$runs');
      expect(runs.single.assumedProgressionAt, 5);
      expect(
        runs.single.warnings.map((w) => w.detail),
        contains(contains('marks partial ("~")')),
      );
    });

    test('without the "~" the same dance does not compile', () async {
      final runs = await runCallersBoxPayload(
        rowdy(tilde: false),
        label: '18981',
      );
      expect(runs.single.outcome, isNot(DanceOutcome.compiled));
    });

    test(
      "Haven't We Met Before? compiles once its waiting couple swings",
      () async {
        // Caller's Box #10129, permission `full`. The next-neighbours reading
        // places its progression on the second hey; the N0 swing of the
        // couple waiting at the top is what lets it compile.
        final runs = await runCallersBoxPayload(
          payload('10129', 'CW', [
            [
              '(6) Star left 3/4; men turn around',
              '(10) N1 neighbor do-si-do 1 & 1/2',
            ],
            ['(4) N0 neighbor balance', '(12) N0 neighbor swing'],
            ['(8) Hey 1/2 (ML;PR;WL;N0R~)', '(8) Hey 1/2 (MR;PL;WR;N1L~)'],
            [
              '(6) N2 neighbor allemande right 1',
              '(2) Men cross by right',
              '(8) Partner swing',
            ],
          ]),
          label: '10129',
        );
        expect(runs.single.outcome, DanceOutcome.compiled, reason: '$runs');
        expect(runs.single.assumedProgressionAt, 4);
      },
    );

    test('the last marked hey is the one, and a flag in the source wins', () {
      core.Figure hey(String? note) => core_test.testFigure(
        move: 'hey',
        params: const {'length': 'half'},
        note: note,
      );
      core.Figure figure(String move) => core_test.testFigure(move: move);
      core.Dance shaped(List<core.Figure> figures) =>
          _shapedLike(shape: core.FormationShape.becketCw, figures: figures);
      expect(
        partialPassProgressionIndex(
          shaped([
            hey('last pass partial'),
            hey('with hands; last pass partial'),
            hey(null),
            figure('swing'),
          ]),
        ),
        1,
      );
      expect(
        partialPassProgressionIndex(shaped([hey(null), figure('swing')])),
        isNull,
      );
      expect(
        partialPassProgressionIndex(
          shaped([
            hey('last pass partial'),
            core_test.testFigure(move: 'swing', progression: true),
          ]),
        ),
        isNull,
      );
    });
  });

  group('which figure the import assumes progresses', () {
    // The rule itself, stated over shapes rather than over choreography. These
    // are not golden dances and are never compiled: they exist to pin the
    // branch selection, which is positional by design.
    core.Figure figure(String move, [Map<String, Object?> params = const {}]) =>
        core_test.testFigure(move: move, params: params);

    test('the last figure, in the ordinary case', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [figure('circle'), figure('swing'), figure('star')],
      );
      expect(assumedProgressionIndex(dance), 2);
    });

    test(
      'a Becket dance opening with a slide left progresses on the slide',
      () {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            figure('slide_along_set', {'slide': 'left'}),
            figure('circle'),
            figure('swing'),
          ],
        );
        expect(assumedProgressionIndex(dance), 0);
      },
    );

    test(
      'an unparameterised slide is a slide left, as upstream defines it',
      () {
        // `slide_along_set.slide` defaults to `left` in the taxonomy, so a bare
        // slide must take the same branch as an explicit one.
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [figure('slide_along_set'), figure('swing')],
        );
        expect(assumedProgressionIndex(dance), 0);
      },
    );

    test(
      'a Becket dance opening with a slice left progresses on the slice',
      () {
        // A slice lands like a slide (user-ruled 2026-11-22), and a bare slice
        // is a slice left: `slice.slice` defaults to `left` upstream.
        for (final opener in [
          figure('slice', {'slice': 'left'}),
          figure('slice'),
        ]) {
          final dance = _shapedLike(
            shape: core.FormationShape.becketCw,
            figures: [opener, figure('circle'), figure('swing')],
          );
          expect(assumedProgressionIndex(dance), 0, reason: '$opener');
        }
      },
    );

    test('a modifier opening a Becket dance is read by its main figure', () {
      // User-ruled 2026-11-23: a modifier carrying the progression carries it
      // for its main figure, so "slice left while partner roll away" opens the
      // dance with a slice left. Its modifier (a roll away) does not count.
      for (final (children, expected) in [
        ([figure('slice'), figure('roll_away')], 0),
        ([figure('long_lines'), figure('slice')], 2),
      ]) {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            core.Figure.modifier(figures: children, beats: 8),
            figure('circle'),
            figure('swing'),
          ],
        );
        expect(
          assumedProgressionIndex(dance),
          expected,
          reason: children.map((child) => child.move).join(' while '),
        );
      }
    });

    test('a hall figure noted "backwards" backs along the hall', () {
      // Caller's Box "go up the hall (backwards)" arrives as a note.
      // Agent's call 2026-11-24.
      core.Figure hall(
        String? note, [
        Map<String, Object?> params = const {},
      ]) =>
          core_test.testFigure(move: 'up_the_hall', params: params, note: note);
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          hall('backwards'),
          hall('backwards; with nextNeighbors'),
          hall('backwards', {'facing': 'forward'}),
          hall(null),
          hall('ones follow twos'),
          hall('backwards', {'who': 'ones'}),
        ],
      );
      final facings = [
        for (final record
            in bridgeCoreDance(dance).record['figures']! as List<Object?>)
          ((record! as Map<String, Object?>)['params']!
              as Map<String, Object?>)['facing'],
      ];
      expect(facings, ['backward', 'backward', 'forward', null, null, null]);
    });

    test('a swing noted "face up" or "finish proper" finishes facing up', () {
      // Caller's Box "Ones swing; face up" arrives as a note on the swing.
      // Agent's call 2026-11-24: "face down" is not read (see
      // `_swingNoteFacing`).
      core.Figure swing(
        String? note, [
        String move = 'swing',
        Map<String, Object?> params = const {},
      ]) => core_test.testFigure(move: move, params: params, note: note);
      final dance = _shapedLike(
        shape: core.FormationShape.dupleProper,
        figures: [
          swing('face up'),
          swing('finish proper'),
          swing('with nextNeighbors; face up'),
          swing('face down'),
          swing('face up [with n0]'),
          swing('face up', 'swing', {'endFacing': 'down'}),
          swing('face up', 'allemande'),
          swing(null),
        ],
      );
      final facings = [
        for (final record
            in bridgeCoreDance(dance).record['figures']! as List<Object?>)
          ((record! as Map<String, Object?>)['params']!
              as Map<String, Object?>)['endFacing'],
      ];
      expect(facings, ['up', 'up', 'up', null, null, 'down', null, null]);
    });

    test('inside a container too', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          core.Figure.modifier(
            figures: [
              core_test.testFigure(move: 'up_the_hall', note: 'backwards'),
              figure('turn_alone'),
            ],
            beats: 8,
          ),
        ],
      );
      final container =
          (bridgeCoreDance(dance).record['figures']! as List<Object?>).first!
              as Map<String, Object?>;
      final children =
          (container['params']! as Map<String, Object?>)['figures']!
              as List<Object?>;
      expect(
        ((children.first! as Map<String, Object?>)['params']!
            as Map<String, Object?>)['facing'],
        'backward',
      );
    });

    test('a swing inside a container reads its facing too', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleProper,
        figures: [
          core.Figure.modifier(
            figures: [
              core_test.testFigure(move: 'swing', note: 'face up'),
              figure('turn_alone'),
            ],
            beats: 8,
          ),
        ],
      );
      final container =
          (bridgeCoreDance(dance).record['figures']! as List<Object?>).first!
              as Map<String, Object?>;
      final children =
          (container['params']! as Map<String, Object?>)['figures']!
              as List<Object?>;
      expect(
        ((children.first! as Map<String, Object?>)['params']!
            as Map<String, Object?>)['endFacing'],
        'up',
      );
    });

    test('a modifier carries a container child to the record as a figure', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          core.Figure.modifier(
            figures: [
              figure('long_lines'),
              figure('roll_away', {'whom': 'neighbors'}),
            ],
            beats: 8,
          ),
          figure('swing'),
        ],
      );
      final record = bridgeCoreDance(dance).record;
      final container =
          (record['figures']! as List<Object?>).first! as Map<String, Object?>;
      final children =
          (container['params']! as Map<String, Object?>)['figures']!
              as List<Object?>;
      expect(children, [
        {'move': 'long_lines', 'params': <String, Object?>{}},
        {
          'move': 'roll_away',
          'params': {'whom': 'neighbors'},
        },
      ]);
      expect(parseDance(record), isA<Ok<Dance, DanceParseError>>());
    });

    test('a Becket dance opening with a double slice does not', () {
      // A diagonal return flagged is two progressions, and single-progression
      // dances open with one too, so (agent's call) the
      // bridge does not assume one there.
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('slice', {'slice': 'left', 'return': 'diagonal'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    test('a Becket dance progresses on its first diagonal chain', () {
      // User-ruled 2026-11-23: a Becket progression is the obvious move.
      for (final where in ['leftDiagonal', 'rightDiagonal']) {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            figure('circle'),
            figure('chain', {'who': 'role2s', 'where': 'across'}),
            figure('chain', {'who': 'role2s', 'where': where}),
            figure('petronella'),
            figure('swing'),
          ],
        );
        expect(assumedProgressionIndex(dance), 2, reason: where);
      }
    });

    test('a Becket dance progresses on its first diagonal right and left '
        'through', () {
      // Agent's call 2026-11-24, by analogy with the diagonal chain.
      for (final where in ['leftDiagonal', 'rightDiagonal']) {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            figure('circle'),
            figure('right_left_through', {'where': 'across'}),
            figure('right_left_through', {'where': where}),
            figure('swing'),
          ],
        );
        expect(assumedProgressionIndex(dance), 2, reason: where);
      }
    });

    test('a Becket dance progresses on a pass through along the set', () {
      for (final params in [
        {'where': 'along'},
        <String, Object?>{},
      ]) {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCcw,
          figures: [
            figure('pass_through', {'where': 'across'}),
            figure('circle'),
            figure('pass_through', params),
            figure('swing'),
          ],
        );
        expect(assumedProgressionIndex(dance), 2, reason: '$params');
      }
    });

    test('a Duple Improper dance still progresses on its last figure', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('chain', {'who': 'role2s', 'where': 'leftDiagonal'}),
          figure('pass_through', {'where': 'along'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 2);
    });

    test('an arch and dive straight after a hall figure progresses', () {
      // User-ruled 2026-11-24: the line bends into a ring and the arch and
      // dive carries the couples on.
      for (final hall in ['up_the_hall', 'down_the_hall']) {
        final dance = _shapedLike(
          shape: core.FormationShape.dupleImproper,
          figures: [
            figure('down_the_hall'),
            figure(hall),
            figure('arch_and_dive', {'who': 'ones'}),
            figure('swing'),
            figure('long_lines'),
          ],
        );
        expect(assumedProgressionIndex(dance), 2, reason: hall);
      }
    });

    test('the first arch and dive after a hall figure is the one taken', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('down_the_hall'),
          figure('arch_and_dive'),
          figure('up_the_hall'),
          figure('arch_and_dive'),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    test('a Becket dance does not progress on an arch after a hall figure', () {
      // The rule is ruled for the line of four in an improper set; a Becket
      // dance with no move along the set keeps its last figure.
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('down_the_hall'),
          figure('arch_and_dive'),
          figure('swing'),
          figure('long_lines'),
        ],
      );
      expect(assumedProgressionIndex(dance), 4);
    });

    test('an arch and dive after anything else does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [figure('circle'), figure('arch_and_dive'), figure('swing')],
      );
      expect(assumedProgressionIndex(dance), 2);
    });

    test('a sole slide or slice right progresses', () {
      // Hudson's Apogee note (2026-11-24): "the slide_along_set right is the
      // progression". Reading every single-progression dance's only slide
      // that way was ratified by the user 2026-11-24.
      for (final slide in [
        figure('slice', {'slice': 'right'}),
        figure('slide_along_set', {'slide': 'right'}),
      ]) {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCcw,
          figures: [slide, figure('swing')],
        );
        expect(assumedProgressionIndex(dance), 0, reason: '$slide');
      }
    });

    test('a sole slide progresses wherever it falls', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('slide_along_set', {'slide': 'right'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    test('an earlier diagonal chain still comes first', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('chain', {'who': 'role2s', 'where': 'leftDiagonal'}),
          figure('slide_along_set', {'slide': 'right'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 0);
    });

    test('a slide right in a dance with two slides does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCcw,
        figures: [
          figure('slide_along_set', {'slide': 'right'}),
          figure('swing'),
          figure('slice', {'slice': 'right'}),
          figure('circle'),
        ],
      );
      expect(assumedProgressionIndex(dance), 3);
    });

    test('a sole slide right in a double-progression dance does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        progression: core.Progression.double,
        figures: [
          figure('circle'),
          figure('slide_along_set', {'slide': 'right'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 2);
    });

    test('a sole slide left later in the dance progresses too', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('slide_along_set', {'slide': 'left'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    test('a sole slide is read through a modifier as its main figure', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          core.Figure.modifier(
            figures: [
              figure('slide_along_set', {'slide': 'right'}),
              figure('roll_away'),
            ],
            beats: 8,
          ),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    test('a second slide inside a container counts against the first', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('slide_along_set', {'slide': 'right'}),
          figure('circle'),
          core.Figure.modifier(
            figures: [
              figure('swing'),
              figure('slide_along_set', {'slide': 'right'}),
            ],
            beats: 8,
          ),
        ],
      );
      expect(assumedProgressionIndex(dance), 2);
    });

    test("a Rory O'More's slide is not a sole slide", () {
      // The bridge reads a slide straight after a balance in a long wave as
      // a Rory O'More, which is not its own progression (agent's call).
      final rory = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('form_long_waves', {'balance': true}),
          figure('slide_along_set', {'slide': 'right'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(rory), 3);
      // Nor does it count against a plain slide elsewhere.
      final both = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('form_long_waves', {'balance': true}),
          figure('slide_along_set', {'slide': 'right'}),
          figure('circle'),
          figure('slide_along_set', {'slide': 'right'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(both), 3);
    });

    test('a sole slice by dancer does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('slice', {'slice': 'right', 'by': 'dancer'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 2);
    });

    test('a sole double slice later in the dance does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('slice', {'slice': 'right', 'return': 'diagonal'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 2);
    });

    test('a slide left outside Becket does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('slide_along_set', {'slide': 'left'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    group('a single-file promenade around the major set to N2', () {
      // Hudson ruled 2026-11-24 that this is a promenade along the set, single
      // file, which carries every dancer on to the next neighbours. The
      // import reads it as a single-file circle with the phrase as its note.
      core.Figure around(String direction, {String? tail}) =>
          core_test.testFigure(
            move: 'circle',
            params: {'direction': direction, 'singleFile': true, 'beats': 2},
            note: 'around the major set to N2${tail ?? ''}',
          );

      test('is bridged as a promenade along the set', () {
        for (final (direction, rotation) in [
          ('left', 'clockwise'),
          ('right', 'counterclockwise'),
        ]) {
          final dance = _shapedLike(
            shape: core.FormationShape.dupleImproper,
            figures: [figure('star'), around(direction), figure('circle')],
          );
          final record =
              (bridgeCoreDance(dance).record['figures']! as List<Object?>)[1]!
                  as Map<String, Object?>;
          expect(record['move'], 'promenade', reason: direction);
          expect(record['params'], {
            'where': 'along',
            'singleFile': true,
            'direction': rotation,
            'beats': 2,
          }, reason: direction);
        }
      });

      test('is where the progression is assumed, in any formation', () {
        // Agent's call: the promenade ends facing the next neighbours, so it
        // is the progression, as a Becket slide is.
        for (final shape in [
          core.FormationShape.dupleImproper,
          core.FormationShape.becketCw,
        ]) {
          final dance = _shapedLike(
            shape: shape,
            figures: [
              figure('chain', {'who': 'role2s', 'where': 'leftDiagonal'}),
              around('left'),
              figure('swing'),
            ],
          );
          expect(assumedProgressionIndex(dance), 1, reason: '$shape');
        }
      });

      test('a counter-rotating one is left as the import read it', () {
        final dance = _shapedLike(
          shape: core.FormationShape.dupleImproper,
          figures: [
            around('left', tail: ' (women ccw in center, men cw on outside)'),
            figure('swing'),
          ],
        );
        final record =
            (bridgeCoreDance(dance).record['figures']! as List<Object?>)[0]!
                as Map<String, Object?>;
        expect(record['move'], 'circle');
        expect(assumedProgressionIndex(dance), 1);
      });

      test('a single-file circle without the phrase is a circle', () {
        final dance = _shapedLike(
          shape: core.FormationShape.dupleImproper,
          figures: [
            core_test.testFigure(
              move: 'circle',
              params: {'direction': 'left', 'singleFile': true, 'beats': 4},
              note: '[with N2]',
            ),
            figure('swing'),
          ],
        );
        final record =
            (bridgeCoreDance(dance).record['figures']! as List<Object?>)[0]!
                as Map<String, Object?>;
        expect(record['move'], 'circle');
      });
    });

    test('a dance with no figures has nothing to assume', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: const [],
      );
      expect(assumedProgressionIndex(dance), isNull);
      expect(bridgeCoreDance(dance).warnings, isEmpty);
    });

    test('a source that does flag a figure is taken at its word', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          core.Figure(move: 'circle', progression: true),
          figure('swing'),
        ],
      );
      final bridged = bridgeCoreDance(dance);
      expect(bridged.assumedProgressionAt, isNull);
      expect(bridged.warnings, isEmpty);
      final figures = bridged.record['figures']! as List<Object?>;
      expect((figures[0]! as Map<String, Object?>)['progression'], true);
      expect(
        (figures[1]! as Map<String, Object?>).containsKey('progression'),
        isFalse,
      );
    });
  });

  group('the nextNeighbors fallback placement', () {
    core.Figure figure(String move, [Map<String, Object?> params = const {}]) =>
        core_test.testFigure(move: move, params: params);

    test('lands on the figure before the first nextNeighbors reach', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('circle'),
          figure('swing'),
          figure('do_si_do', {'who': 'nextNeighbors'}),
          figure('swing', {'who': 'partners'}),
        ],
      );
      expect(nextNeighborsProgressionIndex(dance), 1);
    });

    test('reads only the first reach, not the last', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('circle'),
          figure('do_si_do', {'who': 'nextNeighbors'}),
          figure('star'),
          figure('swing', {'who': 'nextNeighbors'}),
        ],
      );
      expect(nextNeighborsProgressionIndex(dance), 0);
    });

    test('accepts the singular spelling the source may emit', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('circle'),
          core_test.invalidTestFigure(
            move: 'swing',
            params: const {'who': 'nextNeighbor'},
            reason:
                'exercises the legacy singular source spelling before normalization',
          ),
        ],
      );
      expect(nextNeighborsProgressionIndex(dance), 0);
    });

    test('has nowhere to go when the opening figure is the first reach', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('swing', {'who': 'nextNeighbors'}),
          figure('circle'),
        ],
      );
      expect(nextNeighborsProgressionIndex(dance), isNull);
    });

    test('finds a reach inside a container', () {
      // Agent's call, 2026-11-23: a container's children are danced in its
      // slot, so a roll away with the next neighbours inside a modifier reaches
      // for them as surely as one on its own line.
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('swing'),
          core.Figure.modifier(
            figures: [
              figure('long_lines'),
              figure('roll_away', {'whom': 'nextNeighbors'}),
            ],
            beats: 8,
          ),
        ],
      );
      expect(nextNeighborsProgressionIndex(dance), 1);
    });

    test('declines a dance that never reaches for the next couple', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('circle'),
          figure('swing', {'who': 'partners'}),
        ],
      );
      expect(nextNeighborsProgressionIndex(dance), isNull);
    });

    group('N2 in a note (user-ruled 2026-11-23)', () {
      core.Figure noted(String move, String note) =>
          core_test.testFigure(move: move, note: note);
      core.Dance becket(List<core.Figure> figures) =>
          _shapedLike(shape: core.FormationShape.becketCw, figures: figures);

      test('a note dancing with the next neighbours is a reach', () {
        // Songbird: "Partner poussette ... [with N2]" is imported as a note.
        final dance = becket([
          figure('circle'),
          figure('poussette'),
          noted('poussette', 'with nextNeighbors'),
          figure('swing', {'who': 'partners'}),
        ]);
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      test('the source spelling and company in the note still count', () {
        final dance = becket([
          figure('circle'),
          figure('swing'),
          noted('balance', 'with N2, shadow'),
        ]);
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      test('others listed before N2 still count', () {
        final dance = becket([
          figure('circle'),
          figure('swing'),
          noted('balance', 'with shadow and N2'),
        ]);
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      test('ending face N2 places the progression on that figure', () {
        final dance = becket([
          figure('circle'),
          noted('swing', 'face N2'),
          figure('do_si_do'),
        ]);
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      test('a note reach in the opening figure has nowhere to go', () {
        final dance = becket([noted('balance', 'with N2'), figure('swing')]);
        expect(nextNeighborsProgressionIndex(dance), isNull);
      });

      test('a note inside a container counts', () {
        final dance = becket([
          figure('circle'),
          figure('swing'),
          core.Figure.modifier(
            figures: [figure('long_lines'), noted('roll_away', 'with N2')],
            beats: 8,
          ),
        ]);
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      group('an excursion', () {
        test('N2 and then plain neighbours again is skipped', () {
          final dance = becket([
            figure('circle'),
            noted('balance', 'with nextNeighbors'),
            figure('swing', {'who': 'neighbors'}),
          ]);
          expect(nextNeighborsProgressionIndex(dance), isNull);
        });

        test('the singular spelling also marks the return', () {
          final dance = becket([
            figure('circle'),
            noted('balance', 'with nextNeighbors'),
            core_test.invalidTestFigure(
              move: 'swing',
              params: const {'who': 'neighbor'},
              reason: 'exercises the legacy singular source spelling',
            ),
          ]);
          expect(nextNeighborsProgressionIndex(dance), isNull);
        });

        test('a face N2 note is skipped the same way', () {
          final dance = becket([
            figure('circle'),
            noted('swing', 'face N2'),
            figure('swing', {'who': 'neighbors'}),
          ]);
          expect(nextNeighborsProgressionIndex(dance), isNull);
        });

        test('and the scan goes on to the next mention', () {
          final dance = becket([
            figure('circle'),
            noted('balance', 'with N2'),
            figure('swing', {'who': 'neighbors'}),
            figure('star'),
            noted('balance', 'with N2'),
          ]);
          expect(nextNeighborsProgressionIndex(dance), 3);
        });

        test('a param mention is never skipped', () {
          final dance = becket([
            figure('circle'),
            figure('do_si_do', {'who': 'nextNeighbors'}),
            figure('swing', {'who': 'neighbors'}),
          ]);
          expect(nextNeighborsProgressionIndex(dance), 0);
        });
      });

      group('notes that are not a mention of the whole hands four', () {
        for (final note in const [
          'finish proper; face up',
          'pass N2 by right shoulder',
          'to N2',
          'with partner; to N2',
          'with partner, to N2',
          'with shadow, pass N2',
          'M1 with N2, W1 with N1',
          'Heads with N2, sides with N1',
          'with N2 phantoms',
          'face N2 M2, on diagonal',
        ]) {
          test('"$note"', () {
            final dance = becket([figure('circle'), noted('swing', note)]);
            expect(nextNeighborsProgressionIndex(dance), isNull);
          });
        }
      });

      test('the retry warning names the next neighbours', () {
        final dance = becket([
          figure('circle'),
          figure('swing'),
          noted('balance', 'with nextNeighbors'),
        ]);
        final bridged = bridgeCoreDance(dance, useNextNeighborsFallback: true);
        expect(bridged.assumedProgressionAt, 1);
        expect(bridged.warnings.single.detail, contains('N2'));
      });
    });

    group('N3 and N4 mark later progressions (user-ruled 2026-11-23)', () {
      core.Figure noted(String move, String note) =>
          core_test.testFigure(move: move, note: note);
      core.Dance dance(
        List<core.Figure> figures, {
        core.Progression progression = core.Progression.double,
      }) => _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: figures,
      ).copyWith(progression: progression);
      List<int> flagged(BridgedDance bridged) => [
        for (final (i, f) in (bridged.record['figures']! as List).indexed)
          if ((f as Map)['progression'] == true) i,
      ];

      test('a double progression flags the figure before the first N3', () {
        final bridged = bridgeCoreDance(
          dance([
            figure('circle'),
            figure('swing', {'who': 'nextNeighbors'}),
            figure('long_lines'),
            figure('do_si_do', {'who': 'thirdNeighbors'}),
          ]),
          useNextNeighborsFallback: true,
        );
        expect(flagged(bridged), [0, 2]);
        expect(bridged.warnings.map((w) => w.detail), contains(contains('N3')));
      });

      test('a note dancing with N3 is a reach; facing N3 is the figure', () {
        expect(
          laterNeighborsProgressionIndex(
            dance([
              figure('circle'),
              figure('swing'),
              noted('balance', 'with thirdNeighbors'),
            ]),
            n: 3,
            after: 0,
          ),
          1,
        );
        expect(
          laterNeighborsProgressionIndex(
            dance([
              figure('circle'),
              figure('swing'),
              noted('allemande', 'face N3'),
            ]),
            n: 3,
            after: 0,
          ),
          2,
        );
      });

      test('a single progression places no second', () {
        final bridged = bridgeCoreDance(
          dance([
            figure('circle'),
            figure('swing', {'who': 'nextNeighbors'}),
            figure('long_lines'),
            figure('do_si_do', {'who': 'thirdNeighbors'}),
          ], progression: core.Progression.single),
          useNextNeighborsFallback: true,
        );
        expect(flagged(bridged), [0]);
      });

      test('the positional rule places no second', () {
        // A Becket dance opening with a slide left progresses there by the
        // positional rule; only the N2 retry goes on to read N3.
        final bridged = bridgeCoreDance(
          _shapedLike(
            shape: core.FormationShape.becketCw,
            figures: [
              figure('slide_along_set', {'slide': 'left'}),
              figure('swing'),
              figure('do_si_do', {'who': 'thirdNeighbors'}),
            ],
          ).copyWith(progression: core.Progression.double),
        );
        expect(flagged(bridged), [0]);
      });

      test(
        'a triple flags the third before the first N4; a double does not',
        () {
          final figures = [
            figure('circle'),
            figure('swing', {'who': 'nextNeighbors'}),
            figure('long_lines'),
            figure('do_si_do', {'who': 'thirdNeighbors'}),
            figure('star'),
            figure('swing', {'who': 'fourthNeighbors'}),
          ];
          expect(
            flagged(
              bridgeCoreDance(
                dance(figures, progression: core.Progression.triple),
                useNextNeighborsFallback: true,
              ),
            ),
            [0, 2, 4],
          );
          expect(
            flagged(
              bridgeCoreDance(dance(figures), useNextNeighborsFallback: true),
            ),
            [0, 2],
          );
        },
      );

      test('a later progression must come after the one before it', () {
        // N3 named right after the N2 reach would put the second progression
        // on the first one's figure: that is not a second progression.
        expect(
          laterNeighborsProgressionIndex(
            dance([
              figure('circle'),
              figure('swing', {'who': 'nextNeighbors'}),
              figure('do_si_do', {'who': 'thirdNeighbors'}),
            ]),
            n: 3,
            after: 1,
          ),
          isNull,
        );
      });

      test('a note-only N3 followed by N2 again is an excursion', () {
        expect(
          laterNeighborsProgressionIndex(
            dance([
              figure('circle'),
              figure('swing'),
              noted('balance', 'with N3'),
              figure('swing', {'who': 'nextNeighbors'}),
              noted('allemande', 'face N3'),
            ]),
            n: 3,
            after: 0,
          ),
          4,
        );
      });

      test('a note-only N3 followed by plain neighbours is an excursion', () {
        expect(
          laterNeighborsProgressionIndex(
            dance([
              figure('circle'),
              figure('swing'),
              noted('balance', 'with N3'),
              figure('swing', {'who': 'neighbors'}),
            ]),
            n: 3,
            after: 0,
          ),
          isNull,
        );
      });

      test('a note inside a container counts', () {
        expect(
          laterNeighborsProgressionIndex(
            dance([
              figure('circle'),
              figure('swing'),
              core.Figure.modifier(
                figures: [figure('long_lines'), noted('swing', 'face N3')],
                beats: 8,
              ),
            ]),
            n: 3,
            after: 0,
          ),
          2,
        );
      });

      test('the retry is compiled when it only adds a later progression', () {
        // A Becket double opening with a slide left: both rules put the first
        // progression on the slide, and only the retry adds the N3 one.
        final source = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            figure('slide_along_set', {'slide': 'left'}),
            figure('swing', {'who': 'nextNeighbors'}),
            figure('long_lines'),
            figure('do_si_do', {'who': 'thirdNeighbors'}),
          ],
        ).copyWith(progression: core.Progression.double);
        final positional = bridgeCoreDance(source);
        final fallback = bridgeCoreDance(
          source,
          useNextNeighborsFallback: true,
        );
        expect(positional.assumedProgressionAt, 0);
        expect(fallback.assumedProgressionAt, 0);
        expect(fallback.laterProgressionsAt, [2]);
        expect(retryPlacesDifferently(positional, fallback), isTrue);
        expect(retryPlacesDifferently(positional, positional), isFalse);
      });

      test('the first progression is warned about first', () {
        final bridged = bridgeCoreDance(
          dance([
            figure('circle'),
            figure('swing', {'who': 'nextNeighbors'}),
            figure('long_lines'),
            figure('do_si_do', {'who': 'thirdNeighbors'}),
          ]),
          useNextNeighborsFallback: true,
        );
        expect(bridged.warnings.map((w) => w.opIndex), [0, 2]);
      });

      group('clauses that are not a mention of the whole hands four', () {
        for (final note in const [
          'M1 with N3, W1 with N2',
          'Heads with N3',
          'with N3 phantoms',
          'face N3 M2',
          'with partner, to N3',
          'face N2',
          'with N4',
        ]) {
          test('"$note"', () {
            expect(
              laterNeighborsProgressionIndex(
                dance([
                  figure('circle'),
                  figure('swing'),
                  noted('balance', note),
                ]),
                n: 3,
                after: 0,
              ),
              isNull,
            );
          });
        }
      });
    });

    test('a flagged source is never second-guessed', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          core.Figure(move: 'circle', progression: true),
          figure('swing', {'who': 'nextNeighbors'}),
        ],
      );
      final bridged = bridgeCoreDance(dance, useNextNeighborsFallback: true);
      expect(bridged.assumedProgressionAt, isNull);
      expect(bridged.warnings, isEmpty);
    });

    test('the retry still warns, and says why it was needed', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('circle'),
          figure('swing'),
          figure('do_si_do', {'who': 'nextNeighbors'}),
        ],
      );
      final bridged = bridgeCoreDance(dance, useNextNeighborsFallback: true);
      expect(bridged.assumedProgressionAt, 1);
      expect(bridged.warnings.single.kind, WarningKind.assumedProgression);
      expect(bridged.warnings.single.detail, contains('nextNeighbors'));
    });
  });

  group('local corpus sweep', () {
    final corpus = Platform.environment['RUBRIC_TCB_CORPUS'];

    test(
      'every dance in RUBRIC_TCB_CORPUS is read without unwinding',
      () async {
        final directory = Directory(corpus!);
        expect(
          directory.existsSync(),
          isTrue,
          reason: 'RUBRIC_TCB_CORPUS is not a directory: $corpus',
        );

        final files = directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.json'))
            .toList();
        final runs = <DanceRun>[];
        for (final file in files) {
          runs.addAll(
            await runCallersBoxPayload(
              file.readAsStringSync().replaceFirst('\uFEFF', ''),
              label: file.path,
            ),
          );
        }

        final report = CorpusReport(runs);
        printOnFailure('${report.total} dances, ${report.attempted} attempted');
        // The sweep asserts robustness, not a pass rate: a corpus of real
        // choreography is expected to contain dances this compiler cannot yet
        // read, and pinning a number here would turn every new import into a
        // failing test.
        expect(runs, hasLength(greaterThan(0)));
        expect(report.count(DanceOutcome.adapterFailed), lessThan(runs.length));
      },
      skip: corpus == null
          ? 'set RUBRIC_TCB_CORPUS to sweep a local mirror'
          : null,
    );
  });
}
