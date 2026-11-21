import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

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
    ]) {
      test(line, () => expect(_single(line).isCustom, isTrue));
    }
  });
}
