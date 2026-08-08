import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #799 — The Caller's Box `Square through <n> (<pass list>)` lines.
///
/// TCB writes a square through's dancer sets and hands as a compact
/// parenthetical pass list — `Square through 2 (N2R;SL)` means "pass N2 by the
/// right, then the shadow by the left". Before this change the shared
/// `_stripAnnotations` dropped the `()` payload BEFORE recognition, so the line
/// reached the recognizer as a bare `square through 2` and structured with only
/// `places`: `who`/`who2`/`hand`/`balance` then fell to their taxonomy defaults
/// (`partners`/`neighbors`/`right`/`true`). That is not merely lossy — it
/// asserts the WRONG dancers and, via the `balance: true` default, a balance the
/// line never states (which, inside the reported `interrupted square through`
/// compound, DOUBLES the balance the sibling sub-figure already carries).
///
/// The [_squareThroughPassList] pre-recognizer (mirroring the `hey` pass-list
/// decoder) reads the pass codes: odd passes name `who`, even passes name
/// `who2`, hands alternate to give the base `hand`, and `balance: false` is
/// emitted explicitly so the recognizer does not inherit the taxonomy default
/// of `true`. A preceding balance line is then folded into the square_through
/// as `balance: true` by [_foldBalanceIntoMove] (#804), matching ContraDB's
/// shape for the same choreography.
///
/// The reference dance is **Tangled Yarns** by Isaac Banner
/// (TCB dance 18623 / ContraDB 2210); its B1 compound is reproduced verbatim
/// below. No network is used.
List<Figure> _parse(String text, {int beats = 0}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

Future<List<Figure>> _importedFigures(List<String> lines) async {
  final payload = jsonEncode({
    'ID': '18623',
    'Name': 'Tangled Yarns',
    'Permission': 'full',
    'phrases': [
      {'name': 'B1', 'figures': lines},
    ],
  });
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw).dance.figures;
}

void main() {
  group('#799 — square through pass-list decode', () {
    test('(N2R;SL): who/who2/hand structured, balance NOT fabricated', () {
      final figures = _parse('Square through 2 (N2R;SL)', beats: 4);
      expect(figures, hasLength(1));
      final f = figures.single;
      expect(f.isCustom, isFalse);
      expect(f.move, 'square_through');
      expect(f.params['places'], 2);
      // The pass list — not the taxonomy defaults (partners / neighbors).
      expect(f.params['who'], 'nextNeighbors', reason: 'N2 → nextNeighbors');
      expect(f.params['who2'], 'shadows', reason: 'S → shadows');
      expect(f.params['hand'], 'right', reason: 'first pass R');
      // The default is `true`; TCB writes the balance as a separate line, so the
      // decoded square-through line must NOT assert one of its own.
      expect(f.params['balance'], isFalse);
      expect(f.note, isNull);
    });

    test('(PR;N2L): partners then nextNeighbors', () {
      final f = _parse('Square through 2 (PR;N2L)', beats: 4).single;
      expect(f.move, 'square_through');
      expect(f.params['who'], 'partners');
      expect(f.params['who2'], 'nextNeighbors');
      expect(f.params['hand'], 'right');
      expect(f.params['balance'], isFalse);
    });

    test('square through 4 with a repeating two-set pattern', () {
      // Passes 1&3 name the same set, 2&4 the other, hands alternating.
      final f = _parse('Square through 4 (N2R;SL;N2R;SL)', beats: 8).single;
      expect(f.move, 'square_through');
      expect(f.params['places'], 4);
      expect(f.params['who'], 'nextNeighbors');
      expect(f.params['who2'], 'shadows');
      expect(f.params['hand'], 'right');
      expect(f.params['balance'], isFalse);
    });
  });

  group('#799 — conservative declines (fall back to places-only)', () {
    test('unknown people code (square corners) is not approximated', () {
      // C1/C2 are square corners with no taxonomy token; decode declines and the
      // shared recognizer still yields a bare, defaulted square_through.
      final f = _parse('Square through 2 (C1R;C2L)', beats: 4).single;
      expect(f.move, 'square_through');
      expect(f.params['places'], 2);
      expect(
        f.params['who'],
        isNull,
        reason: 'not structured → default applies',
      );
    });

    test('cell count that disagrees with the count declines', () {
      // "Square through 3" is three passes; a two-cell list is an unmodeled
      // variant, so the decoder declines rather than guess the third pass.
      final f = _parse('Square through 3 (N2R;SL)', beats: 4).single;
      expect(f.move, 'square_through');
      expect(f.params['places'], 3);
      expect(f.params['who'], isNull);
    });

    test('a bare square through (no pass list) is unchanged', () {
      final f = _parse('Square through 2', beats: 4).single;
      expect(f.move, 'square_through');
      expect(f.params['places'], 2);
      expect(f.params['who'], isNull);
    });
  });

  group('#799 — end-to-end: Tangled Yarns B1 compound (TCB 18623)', () {
    test(
      'the two interrupted-square-through blocks import faithfully',
      () async {
        final figures = await _importedFigures([
          '(8) Interrupted square through 2 [with N2, shadow]:',
          '     (4) N2 neighbor balance (RH)',
          '     (4) Square through 2 (N2R;SL)',
          '(8) Interrupted square through 2 [with N2, partner]:',
          '     (4) Partner balance (RH)',
          '     (4) Square through 2 (PR;N2L)',
        ]);

        // #804: square_through is now in _balanceMergeMoves, so the preceding
        // balance folds into the square_through (balance: true, summed beats),
        // matching ContraDB's shape. Two figures, none custom.
        expect(figures, hasLength(2));
        expect(figures.every((f) => !f.isCustom), isTrue);

        // Block 1: balance folded into square through neighbors → shadows.
        expect(figures[0].move, 'square_through');
        expect(figures[0].params['who'], 'nextNeighbors');
        expect(figures[0].params['who2'], 'shadows');
        expect(figures[0].params['balance'], isTrue);
        expect(figures[0].beats, 8);

        // Block 2: balance folded into square through partners → nextNeighbors.
        expect(figures[1].move, 'square_through');
        expect(figures[1].params['who'], 'partners');
        expect(figures[1].params['who2'], 'nextNeighbors');
        expect(figures[1].params['balance'], isTrue);
        expect(figures[1].beats, 8);

        // The whole B1 phrase's beats are preserved (8 + 8 = 16).
        expect(figures.fold<int>(0, (a, f) => a + f.beats), 16);
      },
    );
  });
}
