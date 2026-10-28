import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/fixtures.dart';
import '../storage/test_database.dart';

/// The `sequence` container: figures danced in order and shown on one line.
/// Model caps and nesting, the tolerant codec, display and canonical renders,
/// the one-phrase warning, and ordered search rows.
void main() {
  Figure balance({String who = 'ones', int beats = 4}) =>
      Figure(move: 'balance', params: {'who': who, 'beats': beats});
  Figure swing({String who = 'ones', int beats = 12}) =>
      Figure(move: 'swing', params: {'who': who, 'beats': beats});
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
      expect(warning.data, {'position': 1, 'actual': 20, 'limit': 16});
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
        {'position': 2, 'actual': 20, 'limit': 16},
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

    test('an uneven structure allows its longest phrase', () {
      final structure = PhraseStructure.parse('2*8*2 + 2*12*2');
      expect(structure.beatsPerPhrase, isNull);
      expect(structure.longestPhraseBeats, 24);
      expect(sequenceExceedsPhrase(balanceAndSwing, structure), isFalse);
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

    test('Then matches the steps of a sequence in order only', () async {
      await dances.create(sampleDance(id: 'seq', figures: [balanceAndSwing]));
      expect(
        await dances.search(
          ThenFilter(FigureLeaf('balance'), FigureLeaf('swing')),
        ),
        ['seq'],
      );
      expect(
        await dances.search(
          ThenFilter(FigureLeaf('swing'), FigureLeaf('balance')),
        ),
        isEmpty,
      );
    });

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
