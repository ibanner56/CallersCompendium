import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Unit coverage for issue #560: robust CC beat-prefix parsing. Exercises
/// [splitCcBeatPrefix] directly (beats + residual text) across single, compound,
/// bare/absent, and malformed prefixes — the parse must never throw.
void main() {
  group('splitCcBeatPrefix', () {
    test('a lone (16) yields its beats and strips the prefix', () {
      final p = splitCcBeatPrefix('(16) neighbors balance and swing');
      expect(p.beats, 16);
      expect(p.parts, [16]);
      expect(p.text, 'neighbors balance and swing');
    });

    test('a compound (4,12) sums to 16 and keeps the ordered parts', () {
      final p = splitCcBeatPrefix('(4,12) neighbors balance and swing');
      expect(p.beats, 16);
      expect(p.parts, [4, 12]);
      expect(p.text, 'neighbors balance and swing');
    });

    test('a compound (4, 12) tolerates whitespace after the comma', () {
      final p = splitCcBeatPrefix('(4, 12) neighbors balance and swing');
      expect(p.beats, 16);
      expect(p.parts, [4, 12]);
      expect(p.text, 'neighbors balance and swing');
    });

    test('whitespace inside the parentheses is tolerated', () {
      final p = splitCcBeatPrefix('(  4 , 12  )  do si do');
      expect(p.beats, 16);
      expect(p.parts, [4, 12]);
      expect(p.text, 'do si do');
    });

    test('a three-part compound sums and keeps all parts', () {
      final p = splitCcBeatPrefix('(4,4,8) balance the ring');
      expect(p.beats, 16);
      expect(p.parts, [4, 4, 8]);
      expect(p.text, 'balance the ring');
    });

    test('no prefix yields beats 0 and the whole line as text', () {
      final p = splitCcBeatPrefix('neighbors balance and swing');
      expect(p.beats, 0);
      expect(p.parts, isEmpty);
      expect(p.text, 'neighbors balance and swing');
    });

    test('empty parens () are plain text (beats 0, line intact)', () {
      final p = splitCcBeatPrefix('() neighbors balance and swing');
      expect(p.beats, 0);
      expect(p.parts, isEmpty);
      expect(p.text, '() neighbors balance and swing');
    });

    test('a non-numeric (x) prefix is plain text', () {
      final p = splitCcBeatPrefix('(x) neighbors balance and swing');
      expect(p.beats, 0);
      expect(p.parts, isEmpty);
      expect(p.text, '(x) neighbors balance and swing');
    });

    test('a trailing-comma (4,) prefix is plain text', () {
      final p = splitCcBeatPrefix('(4,) neighbors balance and swing');
      expect(p.beats, 0);
      expect(p.parts, isEmpty);
      expect(p.text, '(4,) neighbors balance and swing');
    });

    test('a leading-comma (,12) prefix is plain text', () {
      final p = splitCcBeatPrefix('(,12) neighbors balance and swing');
      expect(p.beats, 0);
      expect(p.parts, isEmpty);
      expect(p.text, '(,12) neighbors balance and swing');
    });

    test(
      'an empty text after a lone (16) keeps beats and the original line',
      () {
        final p = splitCcBeatPrefix('(16)');
        expect(p.beats, 16);
        expect(p.parts, [16]);
        expect(p.text, '(16)');
      },
    );

    test('a digit run past four digits is not read as a beat count', () {
      final p = splitCcBeatPrefix('(99999) neighbors swing');
      expect(p.beats, 0);
      expect(p.parts, isEmpty);
      expect(p.text, '(99999) neighbors swing');
    });

    test('a four-digit run is still bounded-but-valid', () {
      final p = splitCcBeatPrefix('(9999) swing');
      expect(p.beats, 9999);
      expect(p.parts, [9999]);
      expect(p.text, 'swing');
    });
  });

  group('compound-beat allocation (mapCallersCompanionDance)', () {
    List<Figure> figuresFor(String line) => mapCallersCompanionDance(
      CcDanceRecord(
        name: 'D',
        body: [
          CcBodySection(label: 'A1', lines: [line]),
        ],
      ),
    ).dance.figures;

    test('a compound line that structures as ONE move carries the total', () {
      // Balance-and-swing is a single swing (balance is a prefix param), so the
      // (4,12) total rides on that lone figure.
      final figures = figuresFor('(4,12) neighbors balance and swing');
      expect(figures, hasLength(1));
      expect(figures.single.move, 'swing');
      expect(figures.single.beats, 16);
    });

    test(
      'a compound line that cleanly SPLITS distributes the parts in order',
      () {
        // The fan-out `;`-splits this into two clean figures, so each part is
        // distributed to its figure: balance→4, swing→12 (sum still 16).
        final figures = figuresFor('(4,12) balance; swing partner');
        expect(figures, hasLength(2));
        expect(figures[0].move, 'balance');
        expect(figures[0].beats, 4);
        expect(figures[1].move, 'swing');
        expect(figures[1].beats, 12);
      },
    );

    test('a malformed compound stays plain text and never throws', () {
      // "(4,)" is not a beat prefix, so the whole line is the figure text.
      final figures = figuresFor('(4,) balance and swing');
      expect(figures, hasLength(1));
      expect(figures.single.beats, 0);
    });
  });
}
