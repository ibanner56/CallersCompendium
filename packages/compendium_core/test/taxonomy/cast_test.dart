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
/// - in The Caller's Box, women cast back over the right shoulder and men
///   over the left; any other named dancers casting back stay custom;
/// - `(past …)` counts into `places` and is kept as a note; `[with N1]` is a
///   note, as on other moves;
/// - "Hand cast" is an alias of `gate`.
///
/// Corpus figures in comments come from the 1,563 public Caller's Box dances
/// whose figures mention "cast", fetched 2026-11-19 (`docs/research/
/// callersbox.md`).
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

    test('hand cast is an alias of gate that pins nothing', () {
      final alias = contraTaxonomy.aliases['hand_cast']!;
      expect(alias.targetMove, 'gate');
      expect(alias.pinnedParams, isEmpty);
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

    test('women cast back over the right shoulder, men over the left', () {
      expect(castParams('Women cast back')['direction'], 'right');
      expect(castParams('Men cast back')['direction'], 'left');
      // The mixer form: the next partner is a note, not a place.
      final toP2 = tcb('Women cast back to P2');
      expect(toP2.params['direction'], 'right');
      expect(toP2.note, 'to P2');
    });

    test('a cast back naming no dancers states no shoulder', () {
      expect(castParams('Cast back'), isEmpty);
    });

    test('a cast back by any other named dancers stays custom', () {
      // The maintainer asked for this group to stay custom for now.
      expect(tcb('Ones cast back').isCustom, isTrue);
      expect(tcb('Partner cast back').isCustom, isTrue);
    });

    test('(past …) counts into places and is kept as a note', () {
      final figure = tcb('Ones cast down (past twos; threes)');
      expect(figure.params['places'], 2);
      expect(figure.note, 'past twos; threes');
      expect(tcb('Ones cast up (past N2;N1)').params['places'], 2);
      expect(tcb('Ones cast up (past threes)').params['places'], 1);
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
