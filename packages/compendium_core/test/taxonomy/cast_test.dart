import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_core/testing.dart';
import 'package:test/test.dart';

/// Contra's `cast` move and the `hand_cast` alias of `gate` (taxonomy v40,
/// issue #770), with The Caller's Box readings that fill them.
///
/// The maintainer's rulings these pin (2026-11-19):
/// - `direction` is `left`/`right` (the shoulder), `up`/`down`, or unstated;
///   "clockwise" is the right shoulder and "counterclockwise" the left.
/// - an unstated direction shows as "cast back", a shoulder as "cast back
///   left/right", up/down bare;
/// - "cast off" is `down` with `places` 1 unless the line states a number;
/// - The Caller's Box import assumes women cast back over the right shoulder
///   and men over the left when no shoulder is stated; nothing else assumes
///   it (typed text, a re-check, other sources); the display always shows the
///   shoulder;
/// - `(past …)` counts into `places` and is kept as a note; `[with N1]` is a
///   note, as on other moves;
/// - "Hand cast" is an alias of `gate`, listed as a move like `long_lines`.
///
/// Corpus figures in comments come from the 1,563 public Caller's Box dances
/// whose figures mention "cast", fetched 2026-11-19 (`docs/research/
/// callersbox.md`).
/// The figures [CallersBoxAdapter] imports from one phrase of [lines].
Future<List<Figure>> imported(List<String> lines) async {
  final adapter = CallersBoxAdapter();
  final payload = jsonEncode({
    'ID': '770',
    'Name': 'Cast test',
    'Permission': 'full',
    'phrases': [
      {'name': 'A1', 'figures': lines},
    ],
  });
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final draft = adapter.parse(await adapter.fetch(discovered.single));
  return switch (draft.dance.figuresSource) {
    DecodedFigures(:final figures) => figures,
    UnreadableFigures() => const [],
  };
}

MoveDef? contraOrEcd(String id) =>
    contraTaxonomy.resolve(id) ?? ecdTaxonomy.resolve(id);

void main() {
  final renderer = FigureRenderer(contraTaxonomy);
  final canonical = Dialect.canonical;

  Figure tcb(String line) {
    final figures = parseFigureLines(
      line,
      beats: 4,
      frontEnd: tcbFigureFrontEnd,
    );
    expect(figures, hasLength(1), reason: line);
    return figures.single;
  }

  Map<String, Object?> castParams(String line) {
    final figure = tcb(line);
    expect(figure.move, 'cast', reason: line);
    return {...figure.params}..remove('beats');
  }

  String show(Map<String, Object?> params) => renderer.renderSummary(
    testFigure(move: 'cast', params: params),
    canonical,
  );

  group('taxonomy', () {
    test('cast states nothing by default', () {
      final def = contraTaxonomy.resolve('cast')!;
      for (final name in [
        'who',
        'direction',
        'places',
        'whom',
        'destination',
      ]) {
        expect(
          def.params[name]?.defaultValue,
          ParamVocab.unspecified,
          reason: name,
        );
      }
      expect(def.params['direction']?.choices, [
        'left',
        'right',
        'up',
        'down',
        ParamVocab.unspecified,
      ]);
    });

    test('its destinations include every ECD destination, plus top and '
        'bottom', () {
      // The maintainer's decision: contra's and ECD's casts share one shape.
      final ecd = ecdDestinations.where((d) => d != ParamVocab.unspecified);
      expect(castDestinations, containsAll(ecd));
      expect(castDestinations, containsAll(['top', 'bottom']));
    });

    test('ECD has not yet taken the shared shape', () {
      // The maintainer decided contra's `cast` and ECD's `ecd_cast` share one
      // shape; the ECD side is the ECD taxonomy's to change. This records
      // where it stands, so the change shows up here: when `ecd_cast` takes
      // the shape, replace this with a test that the two moves' param names,
      // `direction` choices and `destination` choices agree.
      final ecd = contraOrEcd('ecd_cast')!;
      expect(ecd.params.keys.toSet(), {
        'who',
        'where',
        'direction',
        'whom',
        'destination',
        'beats',
      });
      expect(contraTaxonomy.resolve('cast')!.params.keys.toSet(), {
        'who',
        'direction',
        'places',
        'whom',
        'destination',
        'beats',
      });
    });

    test('hand cast is an alias of gate that pins nothing', () {
      final alias = contraTaxonomy.aliases['hand_cast']!;
      expect(alias.targetMove, 'gate');
      expect(alias.pinnedParams, isEmpty);
      expect(alias.listedAsMove, isTrue);
      expect(contraTaxonomy.resolve('hand_cast')?.id, 'gate');
    });
  });

  group('display', () {
    test('an unstated direction reads "cast back"', () {
      expect(show({}), 'cast back');
      expect(show({'who': 'ones'}), 'ones cast back');
    });

    test('a shoulder reads "cast back left/right"; up and down read bare', () {
      expect(show({'direction': 'right'}), 'cast back right');
      expect(show({'direction': 'left'}), 'cast back left');
      expect(show({'direction': 'up'}), 'cast up');
      expect(show({'direction': 'down'}), 'cast down');
    });

    test("a role's own shoulder is still shown", () {
      // The maintainer's ruling: unlike a chain's role-implied hand, a cast's
      // shoulder is shown even when it is the role's usual one.
      expect(
        show({'who': 'role2s', 'direction': 'right'}),
        'role2s cast back right',
      );
      expect(
        show({'who': 'role1s', 'direction': 'left'}),
        'role1s cast back left',
      );
      expect(
        show({'who': 'role2s', 'direction': 'left'}),
        'role2s cast back left',
      );
      expect(
        show({'who': 'ones', 'direction': 'right'}),
        'ones cast back right',
      );
    });

    test('places, whom and destination follow in that order', () {
      expect(
        show({
          'who': 'ones',
          'direction': 'down',
          'places': 2,
          'whom': 'twos',
          'destination': 'partnersPlace',
        }),
        "ones cast down 2 places around twos to partner's place",
      );
      expect(show({'direction': 'down', 'places': 1}), 'cast down 1 place');
      expect(
        show({'direction': 'down', 'destination': 'bottom'}),
        'cast down to the bottom',
      );
    });

    test('the canonical line keeps the stored token, not the wording', () {
      expect(
        renderer.renderCanonical(
          testFigure(
            move: 'cast',
            params: {'who': 'role2s', 'direction': 'right'},
          ),
        ),
        'role2s cast right',
      );
    });

    test('a hand cast shows under its own name', () {
      expect(
        renderer.renderSummary(testFigure(move: 'hand_cast'), canonical),
        'hand cast',
      );
    });

    test("a hand cast keeps a gate's wording around its own name", () {
      expect(
        renderer.renderSummary(
          testFigure(
            move: 'hand_cast',
            params: {'pair': 'neighbors', 'travel': 0.5, 'endFacing': 'up'},
          ),
          canonical,
        ),
        allOf(startsWith('neighbor hand cast'), contains('to face up')),
      );
    });

    test("a dialect's name for gate never renames a hand cast", () {
      final rotate = Dialect(name: 'Rotate', moves: {'gate': 'rotate'});
      expect(
        renderer.renderSummary(testFigure(move: 'hand_cast'), rotate),
        'hand cast',
      );
      final named = Dialect(name: 'Named', moves: {'hand_cast': 'pivot'});
      expect(
        renderer.renderSummary(testFigure(move: 'hand_cast'), named),
        'pivot',
      );
    });
  });

  group("The Caller's Box", () {
    test('cast off is down one place unless a number is stated', () {
      expect(castParams('Ones cast off'), {
        'who': 'ones',
        'direction': 'down',
        'places': 1,
      });
      expect(castParams('Ones cast off 2'), {
        'who': 'ones',
        'direction': 'down',
        'places': 2,
      });
    });

    test('clockwise is the right shoulder, counterclockwise the left', () {
      expect(castParams('Men cast clockwise')['direction'], 'right');
      expect(castParams('Men cast counterclockwise')['direction'], 'left');
      expect(castParams('Women cast right')['direction'], 'right');
      expect(castParams('Women cast left')['direction'], 'left');
    });

    test('the import assumes women cast back over the right shoulder, '
        'men over the left', () async {
      final figures = await imported([
        '(2) Women cast back',
        '(2) Men cast back',
        '(2) Women cast back to P2',
        '(2) Women cast back || Men go forward',
        '(2) Women cast down',
        '(2) Women cast counterclockwise',
      ]);
      expect(
        [for (final f in figures.take(3)) f.params['direction']],
        ['right', 'left', 'right'],
      );
      // The mixer form: the next partner is a note, not a place.
      expect(figures[2].note, 'to P2');
      // A `||` side is covered too.
      expect(figures[3].subFigures.first.params['direction'], 'right');
      // A stated direction is never replaced.
      expect(figures[4].params['direction'], 'down');
      expect(figures[5].params['direction'], 'left');
    });

    test('outside the import, an unstated shoulder stays unstated', () {
      // The maintainer limited the assumption to the Caller's Box adapter:
      // the front end alone, a re-check of stored lines (the fan-out across
      // every front end) and typed text all leave it out.
      expect(castParams('Women cast back'), {'who': 'role2s'});
      expect(
        parseFigureLinesFanOut('Women cast back', beats: 4).single.params,
        isNot(contains('direction')),
      );
      final reparsed = reparseImportGapFigures([
        testFigure(
          move: customMove,
          params: {'text': 'Women cast back', 'beats': 2},
          customOrigin: CustomOrigin.importGap,
        ),
      ]);
      expect(reparsed.figures.single.move, 'cast');
      expect(reparsed.figures.single.params, isNot(contains('direction')));
      expect(
        parseFreeTextFigureEntry('robins cast back').single.params,
        isNot(contains('direction')),
      );
    });

    test('a cast back naming no dancers states no shoulder', () {
      expect(castParams('Cast back'), isEmpty);
    });

    test('a cast back by other named dancers states no shoulder', () {
      expect(castParams('Ones cast back'), {'who': 'ones'});
    });

    test('the groups the maintainer kept custom stay custom', () {
      expect(
        tcb(
          'Ones lead down through twos; separate; cast back to place',
        ).isCustom,
        isTrue,
      );
      final ends = parseFigureLines(
        'Ends cast back to P2 || Centers walk forward to P2',
        beats: 2,
        frontEnd: tcbFigureFrontEnd,
      ).single;
      expect(ends.subFigures.first.isCustom, isTrue);
    });

    test("a re-check reads a cast as the front end does", () {
      // The re-check of an older import, Caller's Companion import and
      // free-text entry read through the fan-out across every front end.
      for (final line in [
        'Women cast back',
        'Men cast back to P2',
        'Ones cast back',
        'Ones cast down (past twos; threes)',
      ]) {
        expect(
          encodeFigures(parseFigureLinesFanOut(line, beats: 4)),
          encodeFigures([tcb(line)]),
          reason: line,
        );
      }
    });

    test('(past …) counts into places and is kept as a note', () {
      final figure = tcb('Ones cast down (past twos; threes)');
      expect(figure.params['places'], 2);
      expect(figure.note, 'past twos; threes');
      expect(tcb('Ones cast up (past N2;N1)').params['places'], 2);
      expect(tcb('Ones cast up (past threes)').params['places'], 1);
    });

    test('a (past …) list that is not a list of dancers stays custom', () {
      for (final line in [
        'Twos cast up (past ones and threes)',
        'Women cast up (past S; to partner)',
        'Ones cast down (past twos, threes)',
        'Ones cast down (past 2 couples)',
        'Ones cast down (past top couple)',
        'Ones cast down (past twos) (past threes)',
      ]) {
        expect(tcb(line).isCustom, isTrue, reason: line);
      }
      expect(
        tcb('Ones cast down (past N2 twos; N1 threes)').params['places'],
        2,
      );
      expect(tcb('role2s cast down (past W2;W3)').params['places'], 2);
      expect(tcb('Ones cast down (past shadow S1)').params['places'], 1);
    });

    test('a (past …) count that disagrees with the line stays custom', () {
      expect(
        tcb('Ones cast down 1 place (past twos; threes)').isCustom,
        isTrue,
      );
      expect(tcb('Ones cast off (past twos; threes)').isCustom, isTrue);
    });

    test('[with N1] becomes a note, as on other moves', () {
      final figure = tcb('Ones cast off [with N1]');
      expect(figure.move, 'cast');
      expect(figure.note, 'with neighbors');
    });

    test('a bare hand cast is the hand_cast alias', () {
      final figure = tcb('Hand cast');
      expect(figure.move, 'hand_cast');
      expect({...figure.params}..remove('beats'), isEmpty);
    });

    test('wordings the move cannot hold stay custom', () {
      for (final line in [
        // Which gate slot "ones" fills is not stated.
        'Ones hand cast',
        'Men cast clockwise behind partner',
        'Women cast counterclockwise around the major set',
        'Twos cast up to ends of line of four',
        'Ones cast down to bottom, inverting lines. Others follow',
        // Two directions.
        'Ones cast down and to the left',
        'Ones cast up down',
      ]) {
        expect(tcb(line).isCustom, isTrue, reason: line);
      }
    });
  });

  group('display read-back', () {
    test('every destination reads back as itself', () {
      for (final destination in castDestinations) {
        final figure = testFigure(
          move: 'cast',
          params: {
            'who': 'ones',
            'direction': 'down',
            'destination': destination,
          },
        );
        final text = renderer.renderSummary(figure, canonical);
        final read = parseFreeTextFigureEntry(text);
        expect(read, hasLength(1), reason: text);
        expect(read.single.params['destination'], destination, reason: text);
      }
    });
  });
}
