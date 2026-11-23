import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

/// The `sequence` container: figures danced in order and shown on one line.
/// Model caps and nesting, the tolerant codec, display and canonical renders,
/// the one-phrase warning, and ordered search rows.
void main() {
  Figure balance({String who = 'ones', int beats = 4}) =>
      testFigure(move: 'balance', params: {'who': who, 'beats': beats});
  Figure swing({String who = 'ones', int beats = 12}) =>
      testFigure(move: 'swing', params: {'who': who, 'beats': beats});
  final balanceAndSwing = Figure.sequence(
    figures: [balance(), swing()],
    beats: 16,
  );
  final gnatPullOrbit = Figure.sequence(
    figures: [
      Figure(move: 'box_the_gnat', params: const {'who': 'twos', 'beats': 4}),
      Figure(move: 'pull_by', params: const {'who': 'twos', 'beats': 4}),
      Figure(
        move: 'orbit',
        params: const {
          'who': 'twos',
          'direction': 'clockwise',
          'travel': 0.5,
          'beats': 8,
        },
      ),
    ],
    beats: 16,
  );

  group('Figure.sequence', () {
    test('builds a container of its ordered steps', () {
      expect(balanceAndSwing.isSequence, isTrue);
      expect(balanceAndSwing.isContainer, isTrue);
      expect(balanceAndSwing.move, sequenceMove);
      expect(balanceAndSwing.beats, 16);
      expect(balanceAndSwing.subFigures, [balance(), swing()]);
    });

    test('holds two to four steps', () {
      final steps = [for (var i = 0; i < 5; i++) balance(beats: 2)];
      expect(
        Figure.sequence(figures: steps.sublist(0, 4), beats: 8).subFigures,
        hasLength(kMaxSequenceFigures),
      );
      expect(
        () => Figure.sequence(figures: steps, beats: 10),
        throwsArgumentError,
      );
      expect(
        () => Figure.sequence(figures: [balance()], beats: 4),
        throwsArgumentError,
      );
    });

    test('nests one level inside and around the other two kinds', () {
      final meanwhile = Figure.meanwhile(
        figures: [balanceAndSwing, gnatPullOrbit],
        beats: 16,
      );
      expect(meanwhile.subFigures.every((f) => f.isSequence), isTrue);
      final modifier = Figure.modifier(
        figures: [swing(), balanceAndSwing],
        beats: 16,
      );
      expect(modifier.subFigures.last.isSequence, isTrue);
      final around = Figure.sequence(
        figures: [
          Figure.meanwhile(figures: [balance(), swing()], beats: 8),
          swing(beats: 8),
        ],
        beats: 16,
      );
      expect(around.subFigures.first.isMeanwhile, isTrue);
    });

    test('rejects a sequence directly inside a sequence', () {
      expect(
        () => Figure.sequence(figures: [balanceAndSwing, swing()], beats: 16),
        throwsArgumentError,
      );
    });

    test('rejects a third container level', () {
      final meanwhile = Figure.meanwhile(
        figures: [balanceAndSwing, swing()],
        beats: 16,
      );
      expect(
        () => Figure.modifier(figures: [swing(), meanwhile], beats: 16),
        throwsArgumentError,
      );
    });
  });

  group('codec', () {
    test('round-trips a sequence nested in a meanwhile', () {
      final figure = Figure.meanwhile(
        figures: [balanceAndSwing, gnatPullOrbit],
        beats: 16,
      );
      expect(decodeFigures(encodeFigures([figure])), [figure]);
    });

    test('clamps an untrusted sequence to four steps', () {
      final json = figureToJson(balanceAndSwing);
      final step = figureToJson(balance(beats: 2));
      (json['params']! as Map)['figures'] = List.filled(9, step);
      final decoded = figureFromJson(json);
      expect(decoded.subFigures, hasLength(kMaxSequenceFigures));
    });

    test('drops a same-kind child rather than nesting it', () {
      final json = figureToJson(balanceAndSwing);
      (json['params']! as Map)['figures'] = [
        figureToJson(swing()),
        figureToJson(balanceAndSwing),
        figureToJson(balance()),
      ];
      expect(figureFromJson(json).subFigures, [swing(), balance()]);
    });

    test('unsupportedFigurePath looks inside a sequence', () {
      final json = figureToJson(balanceAndSwing);
      ((json['params']! as Map)['figures'] as List).add({
        'move': 'swing',
        'fromTheFuture': true,
      });
      expect(
        unsupportedFigurePath(jsonDecode(jsonEncode([json]))),
        'figures.params.figures.fromTheFuture',
      );
    });
  });

  group('rendering', () {
    final renderer = FigureRenderer(contraTaxonomy);
    final d = Dialect.larksRobins;

    test('two steps read "X and Y", saying a repeated subject once', () {
      expect(renderer.render(balanceAndSwing, d), 'ones balance and swing');
      expect(
        renderer.renderSummary(balanceAndSwing, d),
        'ones balance and swing',
      );
    });

    test('three steps read as a serial-comma list', () {
      expect(
        renderer.render(gnatPullOrbit, d),
        'twos box the gnat, pull by right, and orbit clockwise ½',
      );
    });

    test('a meanwhile of two sequences reads as one line', () {
      final figure = Figure.meanwhile(
        figures: [balanceAndSwing, gnatPullOrbit],
        beats: 16,
      );
      expect(
        renderer.render(figure, d),
        'ones balance and swing while twos box the gnat, pull by right, and '
        'orbit clockwise ½',
      );
    });

    test('a different subject is kept', () {
      final figure = Figure.sequence(
        figures: [
          balance(),
          swing(who: 'twos'),
        ],
        beats: 16,
      );
      expect(renderer.render(figure, d), 'ones balance and twos swing');
    });

    test('canonical text joins every step in full with the structural id', () {
      expect(
        renderer.renderCanonical(balanceAndSwing),
        'ones balance sequence ones swing',
      );
    });

    test('a step note follows its own step', () {
      final figure = Figure.sequence(
        figures: [
          balance().copyWith(note: 'right'),
          swing(),
        ],
        beats: 16,
      );
      expect(renderer.render(figure, d), 'ones balance (right) and swing');
    });

    test('as a modifier, each step is a gerund', () {
      final figure = Figure.modifier(
        figures: [
          Figure(move: 'circle', params: const {'beats': 8}),
          Figure.sequence(
            figures: [
              Figure(move: 'balance'),
              Figure(move: 'roll_away'),
            ],
            beats: 8,
          ),
        ],
        beats: 8,
      );
      expect(
        renderer.renderSummary(figure, d),
        'circle left 3 places, neighbor balancing and larks rolling away '
        'partner',
      );
    });
  });

  group('phrase sections', () {
    test('a sequence counts its own beats once', () {
      final sections = deriveSections([
        balanceAndSwing,
        swing(beats: 16),
      ], PhraseStructure.standard);
      expect(sections.map((s) => s.label), ['A1', 'A2']);
    });

    test('warns when a sequence is longer than one phrase', () {
      final long = Figure.sequence(
        figures: [balance(beats: 8), swing(beats: 12)],
        beats: 20,
      );
      final issues = <ValidationIssue>[];
      deriveSections([long], PhraseStructure.standard, issues: issues);
      final warning = issues.singleWhere(
        (i) => i.code == 'sequence_exceeds_phrase',
      );
      expect(warning.data, {
        'position': 1,
        'actual': 20,
        'limit': 16,
        'startBeat': 0,
        'limitStart': 0,
      });
      expect(warning.message, startsWith('a sequence in figure 1 is 20 beats'));
    });

    test('warns for a long sequence nested in a meanwhile', () {
      final long = Figure.sequence(
        figures: [balance(beats: 8), swing(beats: 12)],
        beats: 20,
      );
      final issues = <ValidationIssue>[];
      deriveSections(
        [
          swing(),
          Figure.meanwhile(figures: [long, swing()], beats: 16),
        ],
        PhraseStructure.standard,
        issues: issues,
      );
      expect(
        issues.where((i) => i.code == 'sequence_exceeds_phrase').single.data,
        {
          'position': 2,
          'actual': 20,
          'limit': 16,
          // The meanwhile starts after the first figure, and so does the
          // sequence inside it.
          'startBeat': 12,
          'limitStart': 0,
        },
      );
    });

    test('a sequence that fills a phrase exactly is not flagged', () {
      final issues = <ValidationIssue>[];
      deriveSections(
        [balanceAndSwing],
        PhraseStructure.standard,
        issues: issues,
      );
      expect(issues.where((i) => i.code == 'sequence_exceeds_phrase'), isEmpty);
    });

    test('an uneven structure measures a sequence by the phrase it sits in '
        '(23 November 2026)', () {
      // Two phrases of 16 beats, then two of 24.
      final structure = PhraseStructure.parse('2*8*2 + 2*12*2');
      expect(structure.beatsPerPhrase, isNull);
      final twenty = Figure.sequence(
        figures: [balance(beats: 8), swing(beats: 12)],
        beats: 20,
      );
      expect(
        sequenceExceedsPhrase(balanceAndSwing, structure, startBeat: 0),
        isFalse,
      );
      expect(sequenceExceedsPhrase(twenty, structure, startBeat: 0), isTrue);
      // Halfway through the second 16-beat phrase: still that phrase.
      expect(sequenceExceedsPhrase(twenty, structure, startBeat: 24), isTrue);
      expect(sequenceExceedsPhrase(twenty, structure, startBeat: 32), isFalse);
      // Past the end, the structure plays again from its first phrase.
      expect(
        sequenceExceedsPhrase(twenty, structure, startBeat: 80 + 4),
        isTrue,
      );
    });

    test('a sequence longer than the short phrase it sits in is flagged, '
        'against that phrase', () {
      // A1 and A2 are 8 beats each, B is 16.
      final structure = PhraseStructure.parse('2*4*2 + 1*8*2');
      final twelve = Figure.sequence(
        figures: [balance(beats: 4), swing(beats: 8)],
        beats: 12,
      );
      final inA = <ValidationIssue>[];
      deriveSections(
        [twelve, swing(beats: 4), swing(beats: 16)],
        structure,
        issues: inA,
      );
      expect(inA.singleWhere((i) => i.code == 'sequence_exceeds_phrase').data, {
        'position': 1,
        'actual': 12,
        'limit': 8,
        'startBeat': 0,
        'limitStart': 0,
      });
      final inB = <ValidationIssue>[];
      deriveSections(
        [swing(beats: 8), swing(beats: 8), twelve, swing(beats: 4)],
        structure,
        issues: inB,
      );
      expect(inB.where((i) => i.code == 'sequence_exceeds_phrase'), isEmpty);
    });

    test('a sequence may start partway through its phrase and run past its '
        'line, as long as it is no longer than the phrase', () {
      final issues = <ValidationIssue>[];
      deriveSections(
        [swing(beats: 8), balanceAndSwing, swing(beats: 8)],
        PhraseStructure.standard,
        issues: issues,
      );
      expect(issues.where((i) => i.code == 'sequence_exceeds_phrase'), isEmpty);
    });

    test('a nested sequence is measured by the phrase its own start is in', () {
      // A1 and A2 are 8 beats each, B is 16. The meanwhile starts at 16, in
      // B, so a 12-beat sequence inside it fits.
      final structure = PhraseStructure.parse('2*4*2 + 1*8*2');
      final twelve = Figure.sequence(
        figures: [balance(beats: 4), swing(beats: 8)],
        beats: 12,
      );
      final issues = <ValidationIssue>[];
      deriveSections(
        [
          swing(beats: 16),
          Figure.meanwhile(figures: [twelve, swing(beats: 12)], beats: 12),
          swing(beats: 4),
        ],
        structure,
        issues: issues,
      );
      expect(issues.where((i) => i.code == 'sequence_exceeds_phrase'), isEmpty);
    });
  });

  test('a shorthand count is not put on a sequence', () {
    final shorthands = ShorthandMappings([
      ShorthandMapping(token: 'bs', figures: [balanceAndSwing]),
    ]);
    for (final line in ['bs (20)', '20 bs']) {
      final figures = parseFreeTextFigureEntry(line, shorthands: shorthands);
      expect(figures, [balanceAndSwing], reason: line);
    }
  });

  group('search rows', () {
    late CompendiumDatabase db;
    late DanceRepository dances;

    setUp(() {
      db = openTestDatabase();
      dances = DanceRepository(db, contraTaxonomy);
    });

    tearDown(() => db.close());

    Future<List<({String move, int groupIdx, String? section})>> rowsOf(
      String id,
    ) async {
      final rows = await (db.select(
        db.danceFigures,
      )..where((t) => t.danceId.equals(id))).get();
      rows.sort((a, b) => a.idx.compareTo(b.idx));
      return [
        for (final r in rows)
          (move: r.move, groupIdx: r.groupIdx, section: r.section),
      ];
    }

    test('a top-level sequence gives each step its own group', () async {
      final dance = sampleDance(
        id: 'seq',
        figures: [swing(beats: 16), balanceAndSwing, swing(beats: 16)],
      );
      await dances.create(dance);
      final rows = await rowsOf('seq');
      expect(rows.map((r) => r.move), ['swing', 'balance', 'swing', 'swing']);
      expect(rows.map((r) => r.groupIdx), [0, 1, 2, 3]);
      // Each step's section is the sequence's.
      expect(rows.map((r) => r.section), ['A1', 'A2', 'A2', 'B1']);
    });

    test('a step takes the section it starts in', () async {
      final dance = sampleDance(
        id: 'cross',
        figures: [
          swing(beats: 12),
          Figure.sequence(figures: [balance(), swing(beats: 8)], beats: 12),
        ],
      );
      await dances.create(dance);
      expect((await rowsOf('cross')).map((r) => r.section), ['A1', 'A1', 'A2']);
      expect(await dances.search(FigureFilter.leaf('swing', section: 'A2')), [
        'cross',
      ]);
    });

    test('Then matches the steps of a sequence in order, and a wrap', () async {
      await dances.create(sampleDance(id: 'seq', figures: [balanceAndSwing]));
      expect(
        await dances.search(
          ThenFilter(FigureLeaf('balance'), FigureLeaf('swing')),
        ),
        ['seq'],
      );
      // A dance of just these two steps is a loop: swing is last, balance
      // first, so the reverse order matches across the wrap.
      expect(
        await dances.search(
          ThenFilter(FigureLeaf('swing'), FigureLeaf('balance')),
        ),
        ['seq'],
      );
    });

    test(
      'Then reads a sequence step by step, not step to later step',
      () async {
        await dances.create(
          sampleDance(
            id: 'three',
            figures: [
              Figure.sequence(
                figures: [
                  Figure(move: 'balance', params: const {'beats': 4}),
                  Figure(move: 'swing', params: const {'beats': 4}),
                  Figure(move: 'chain', params: const {'beats': 4}),
                ],
                beats: 12,
              ),
            ],
          ),
        );
        expect(
          await dances.search(
            ThenFilter(FigureLeaf('balance'), FigureLeaf('swing')),
          ),
          ['three'],
        );
        // swing sits between balance and chain.
        expect(
          await dances.search(
            ThenFilter(FigureLeaf('balance'), FigureLeaf('chain')),
          ),
          isEmpty,
        );
      },
    );

    test('a sequence inside a meanwhile shares the meanwhile group', () async {
      await dances.create(
        sampleDance(
          id: 'mw',
          figures: [
            Figure.meanwhile(
              figures: [balanceAndSwing, gnatPullOrbit],
              beats: 16,
            ),
          ],
        ),
      );
      final rows = await rowsOf('mw');
      expect(rows, hasLength(5));
      expect(rows.map((r) => r.groupIdx).toSet(), {0});
    });
  });
}
