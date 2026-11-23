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
}) {
  final now = DateTime.utc(2020);
  return core.Dance(
    id: 'rule-under-test',
    title: 'rule under test',
    formation: core.Formation(shape),
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

    test('a Becket dance slicing right does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('slice', {'slice': 'right'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    test('a Becket dance sliding right does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCcw,
        figures: [
          figure('slide_along_set', {'slide': 'right'}),
          figure('swing'),
        ],
      );
      expect(assumedProgressionIndex(dance), 1);
    });

    test('a Becket dance that does not open with a slide does not', () {
      final dance = _shapedLike(
        shape: core.FormationShape.becketCw,
        figures: [
          figure('circle'),
          figure('slide_along_set', {'slide': 'left'}),
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

      test('a note dancing with the next neighbours is a reach', () {
        // Songbird: "Partner poussette ... [with N2]" is imported as a note.
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            figure('circle'),
            figure('poussette'),
            noted('poussette', 'with nextNeighbors'),
            figure('swing', {'who': 'partners'}),
          ],
        );
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      test('the source spelling and company in the note still count', () {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            figure('circle'),
            figure('swing'),
            noted('balance', 'with N2, shadow'),
          ],
        );
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      test('ending face N2 places the progression on that figure', () {
        final dance = _shapedLike(
          shape: core.FormationShape.dupleImproper,
          figures: [
            figure('circle'),
            noted('swing', 'face N2'),
            figure('do_si_do'),
          ],
        );
        expect(nextNeighborsProgressionIndex(dance), 1);
      });

      test('N2 and then plain neighbours again is an excursion', () {
        final dance = _shapedLike(
          shape: core.FormationShape.becketCw,
          figures: [
            figure('circle'),
            noted('balance', 'with nextNeighbors'),
            figure('swing', {'who': 'neighbors'}),
          ],
        );
        expect(nextNeighborsProgressionIndex(dance), isNull);
      });

      test('a note on another figure is not read as a reach', () {
        final dance = _shapedLike(
          shape: core.FormationShape.dupleImproper,
          figures: [figure('circle'), noted('swing', 'finish proper; face up')],
        );
        expect(nextNeighborsProgressionIndex(dance), isNull);
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
