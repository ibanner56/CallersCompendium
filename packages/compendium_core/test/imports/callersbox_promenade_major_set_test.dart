import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// Caller's Box whole-set promenades: `around the major set` anywhere on the
/// line, and the `to <dancer>` destination (`promenade.destination`, taxonomy
/// v29). See `_promenadeAnnotation` in `callersbox_figure_dialect.dart`.
List<Figure> _parse(String text) =>
    parseFigureLines(text, beats: 8, frontEnd: tcbFigureFrontEnd);

Figure _single(String text) => _parse(text).single;

void main() {
  group('around the major set followed by an annotation keeps every word', () {
    // Before the fix `around the major set` was recognised only at the END of
    // the line; followed by `(…)`/`[…]`, the normal path stripped the phrase
    // and the annotation for recognition and the figure carried no note.
    final cases = {
      'Partner promenade clockwise around the major set (to N2)':
          'to N2; around the major set',
      'Partner promenade clockwise around the major set [with N2]':
          'with N2; around the major set',
      'Neighbor promenade counterclockwise around the major set '
              '[men with women in front of him]':
          'role1s with role2s in front of him; around the major set',
      // Real corpus lines (dances 7448, 15457).
      'Neighbor promenade clockwise around the major set (backwards)':
          'backwards; around the major set',
      'Neighbor promenade counterclockwise around the major set (new partner)':
          'new partner; around the major set',
      // Already worked before the fix; pinned so the two orders agree.
      'Partner promenade clockwise (to N2) around the major set':
          'to N2; around the major set',
    };
    cases.forEach((line, note) {
      test(line, () {
        final f = _single(line);
        expect(f.move, 'promenade');
        expect(f.note, note);
      });
    });
  });

  group('destination', () {
    test('a bare "to N2" tail fills destination and keeps its words', () {
      final f = _single(
        'Partner promenade clockwise around the major set to N2',
      );
      expect(f.move, 'promenade');
      expect(f.params['who'], 'partners');
      expect(f.params['direction'], 'clockwise');
      expect(f.params['destination'], 'nextNeighbors');
      expect(f.note, 'around the major set; to N2');
    });

    test('"to partner", "to N3" and "to shadow" map onto the dancer set', () {
      expect(
        _single(
          'N1 neighbor promenade clockwise around the major set to partner',
        ).params,
        containsPair('destination', 'partners'),
      );
      expect(
        _single(
          'Partner promenade clockwise around the major set to N3',
        ).params,
        containsPair('destination', 'thirdNeighbors'),
      );
      expect(
        _single(
          'Neighbor promenade clockwise around the major set to shadow',
        ).params,
        containsPair('destination', 'shadows'),
      );
    });

    test('a "(to N2)" annotation fills destination too', () {
      final f = _single(
        'Partner promenade clockwise around the major set (to N2)',
      );
      expect(f.params['destination'], 'nextNeighbors');
    });

    test('an annotation between the phrase and the tail survives', () {
      final f = _single(
        'Partner promenade clockwise around the major set (backwards) to N2',
      );
      expect(f.params['destination'], 'nextNeighbors');
      expect(f.note, 'backwards; around the major set; to N2');
    });

    test('the destination stays visible when the renderer suppresses it', () {
      // TCB states no `where`, so the effective `where` is the `across`
      // default and the v30 gate (`where != 'across'`) hides the destination
      // clause. The words must then reach the reader through the note.
      final f = _single(
        'Partner promenade clockwise around the major set to N2',
      );
      final line = FigureRenderer(contraTaxonomy).render(f, Dialect.canonical);
      expect(line, isNot(contains('neighbors')));
      expect(f.note, contains('to N2'));
    });

    test('a stated non-across `where` renders the destination, so the words '
        'are consumed rather than printed twice', () {
      final f = _single('Partner promenade along to N2');
      expect(f.params['where'], 'along');
      expect(f.params['destination'], 'nextNeighbors');
      expect(f.note, isNull);
      expect(
        FigureRenderer(contraTaxonomy).render(f, Dialect.canonical),
        contains('to next neighbors'),
      );
    });

    test('an unstated subject is not written', () {
      final f = _single('Promenade clockwise around the major set to N2');
      expect(f.move, 'promenade');
      expect(f.params['destination'], 'nextNeighbors');
      expect(f.params.containsKey('who'), isFalse);
    });
  });

  group('lines that must stay custom', () {
    for (final line in [
      // Not a dancer set.
      'Shadow promenade counterclockwise around the major set to next',
      'Partner promenade to place',
      // Qualified destination / extra words.
      'Partner promenade clockwise around the major set to shadow S4',
      'Partner promenade clockwise around the major set two places to N2',
      // Counter-rotating two-ring single-file figure.
      'Single file promenade around the major set to N3 '
          '(men cw in center, women ccw on outside)',
      // Not corpus wording: a single-file whole-set line with no rotation
      // word names no direction to travel, annotation or not (#2331).
      'Single file promenade around the major set to N2',
    ]) {
      test(line, () => expect(_single(line).isCustom, isTrue));
    }
  });

  group('a single-file promenade around the major set is a promenade (#2331)', () {
    // Maintainer ruling: `Single file promenade counterclockwise around the
    // major set to N2` travels the whole set — a promenade around the major
    // set, not a single-file circle (whose unstated `places` read as a
    // three-place circle in the hands four). `where: along` and `who`
    // unwritten follow ContraDB's whole-set single-file promenade and TCB's
    // own unstated-subject rule; the spin word is the promenade's `direction`.
    Map<String, Object?> sf(String direction, [String? destination]) => {
      'singleFile': true,
      'where': 'along',
      'direction': direction,
      'destination': ?destination,
      'beats': 8,
    };

    final cases = <String, (Map<String, Object?>, String?)>{
      // Dances 18240, 18241, 18428 (beats prefix removed).
      'Single file promenade counterclockwise around the major set to N2': (
        sf('counterclockwise', 'nextNeighbors'),
        'around the major set',
      ),
      // Dance 7867.
      'Single file promenade clockwise around the major set to N2': (
        sf('clockwise', 'nextNeighbors'),
        'around the major set',
      ),
      // Dances 2592, 14473, 11935, 3073.
      'Single file promenade counterclockwise around the major set to partner':
          (sf('counterclockwise', 'partners'), 'around the major set'),
      'Single file promenade clockwise around the major set to N1': (
        sf('clockwise', 'neighbors'),
        'around the major set',
      ),
      'Single file promenade clockwise around the major set to N3': (
        sf('clockwise', 'thirdNeighbors'),
        'around the major set',
      ),
      'Single file promenade counterclockwise around the major set to shadow': (
        sf('counterclockwise', 'shadows'),
        'around the major set',
      ),
      // Dance 18433: no destination.
      'Single file promenade counterclockwise around the major set': (
        sf('counterclockwise'),
        'around the major set',
      ),
      // Dances 12751, 71.
      'Single file promenade clockwise around the major set (men behind '
          'neighbor)': (
        sf('clockwise'),
        'role1s behind neighbor; around the major set',
      ),
      'Single file promenade clockwise around the major set to N2 (actually '
          'more of a wide loop)': (
        sf('clockwise', 'nextNeighbors'),
        'actually more of a wide loop; around the major set',
      ),
    };
    cases.forEach((line, expected) {
      test(line, () {
        final f = _single(line);
        expect(f.move, 'promenade');
        expect(f.params, expected.$1);
        expect(f.note, expected.$2);
      });
    });

    test('the destination renders, so its words are not in the note', () {
      final f = _single(
        'Single file promenade counterclockwise around the major set to N2',
      );
      expect(
        FigureRenderer(contraTaxonomy).render(f, Dialect.canonical),
        'single file promenade counterclockwise along to next neighbors',
      );
    });

    test(
      'with no destination the default rotation is not shown (v30 rule)',
      () {
        // Stored and canonical keep `counterclockwise`; the display silences a
        // default turn when no destination is stated, as for every promenade.
        final f = _single(
          'Single file promenade counterclockwise around the major set',
        );
        expect(f.params['direction'], 'counterclockwise');
        expect(
          FigureRenderer(contraTaxonomy).render(f, Dialect.canonical),
          'single file promenade along',
        );
      },
    );

    test(
      '"; women turn around" stays a note on the promenade (dance 3266)',
      () {
        final figures = _parse(
          'Single file promenade clockwise around the major set; women turn '
          'around',
        );
        expect(figures, hasLength(1));
        expect(figures.single.move, 'promenade');
        expect(figures.single.note, contains('role2s turn around'));
      },
    );

    for (final line in const [
      // Dance 3208: a destination that names no dancer set.
      'Single file promenade counterclockwise around the major set to shadow '
          'S4; men turn around',
      // Dances 11909, 17633: two rings turning opposite ways.
      'Single file promenade clockwise around the major set (inner ring ccw, '
          'outer ring cw)',
      // Not corpus wording: a places amount, which a promenade cannot hold.
      'Single file promenade clockwise 3 places around the major set',
    ]) {
      test('"$line" stays custom, never a single-file circle', () {
        final figures = _parse(line);
        expect(figures.any((f) => f.move == 'circle'), isFalse);
        expect(figures.single.isCustom, isTrue);
      });
    }

    test(
      'a single-file promenade NOT around the major set is still a circle',
      () {
        final f = _single('Single file promenade clockwise 3/4');
        expect(f.move, 'circle');
        expect(f.params['places'], 3);
      },
    );

    test('through the importer: dance 18240 A1', () async {
      final payload = jsonEncode({
        'ID': '18240',
        'Name': 'Star Over Thar {Erik Erhardt version}',
        'Permission': 'full',
        'phrases': [
          {
            'name': 'A1',
            'figures': [
              '(8) In long lines, go forward and back',
              '(2) Pass through across (NR)',
              '(2) Single file promenade counterclockwise around the major '
                  'set to N2',
              '(4) Hands-across star left 1/2 [with N2]',
            ],
          },
        ],
      });
      final adapter = CallersBoxAdapter();
      final discovered = await adapter.discover(
        ImportRequest(payload: payload),
      );
      final raw = await adapter.fetch(discovered.single);
      final figures = figuresOf(adapter.parse(raw).dance);
      final promenade = figures.singleWhere((f) => f.move == 'promenade');
      expect(promenade.params['destination'], 'nextNeighbors');
      expect(promenade.params['beats'], 2);
      expect(figures.any((f) => f.move == 'circle'), isFalse);
      expect(figures.fold<int>(0, (a, f) => a + f.beats), 16);
    });
  });
}
