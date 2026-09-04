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
        expect(draft.dance.figures.map((figure) => figure.move), [
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
      expect(draft.dance.figures.any((figure) => figure.progression), isFalse);
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
      // about the choreography. Six of the seven placements must fail — and the
      // one that succeeds must be the one the rule picks.
      final dance = (await _draft()).dance;
      final outcomes = <int, DanceOutcome>{};
      for (var index = 0; index < dance.figures.length; index++) {
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
        [6],
        reason:
            'only the final petronella — the line the source annotates '
            '"face next" — leaves the set progressed; got $outcomes',
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

  group('which figure the import assumes progresses', () {
    // The rule itself, stated over shapes rather than over choreography. These
    // are not golden dances and are never compiled: they exist to pin the
    // branch selection, which is positional by design.
    core.Figure figure(String move, [Map<String, Object?> params = const {}]) =>
        core.Figure(move: move, params: params);

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
        core.Figure(move: move, params: params);

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

    test('accepts the singular spelling upstream also allows', () {
      final dance = _shapedLike(
        shape: core.FormationShape.dupleImproper,
        figures: [
          figure('circle'),
          figure('swing', {'who': 'nextNeighbor'}),
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
