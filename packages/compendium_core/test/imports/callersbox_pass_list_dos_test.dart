import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The Caller's Box pass-list decoders (`hey`, `square through`, `grand right
/// and left`) used to `split(';')` the parenthetical FIRST and check the cell
/// count afterwards, so a hostile import line carrying millions of `;` built the
/// oversized list before the guard that exists to bound it ever ran. The shared
/// `_boundedPassListCells` helper now length-caps the untrusted text **before**
/// the split, degrading an over-long pass list to the unchanged whole-custom
/// line (OWASP; imported figure text is untrusted).
///
/// **What these tests do and do not prove.** A unit test cannot directly observe
/// "no large list was allocated". These pin the *observable* consequence of the
/// pre-split bound: an over-length pass list is no longer decoded — it falls
/// through to the custom reading. The `hey` decoder is the one that changes
/// behaviour, because it had no cell-count cap at all, so an alternating pass
/// list of any length used to decode to a structured `hey`. `square through` and
/// `grand right and left` already rejected over-count lines *after* splitting,
/// so for them the change is allocation-only and produces no behavioural diff a
/// test could distinguish — the fix there is that the rejection now happens
/// before the allocation, which this file documents but does not assert.
List<Figure> _parse(String text, {int beats = 8}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

/// A pass list whose raw length is far beyond any real one (~1600 chars, 400
/// cells) yet whose shoulders alternate consistently, so the pre-fix `hey`
/// decoder would have accepted and structured it.
String _megaPassList() => List.filled(200, 'N2R;N2L').join(';');

void main() {
  group('pass-list DoS bound (pre-split length cap)', () {
    test('an over-length hey pass list is NOT decoded (falls to custom)', () {
      // RED RUN target: against the unfixed decoder this alternating list
      // decodes to a structured `hey` (isCustom false, pass1 == nextNeighbors)
      // because `hey` had no cap and split the whole list first. With the
      // pre-split length cap it is rejected before the split and the line stays
      // whole-custom.
      final f = _parse('Hey (${_megaPassList()})').single;
      expect(
        f.isCustom,
        isTrue,
        reason: 'over-length pass list must not decode',
      );
      expect(f.move, isNot('hey'));
      expect(f.params['pass1'], isNull);
    });

    test('a normal hey pass list still decodes (bound does not over-reject)', () {
      // Guard against a bound so tight it rejects real choreography. Passes both
      // before and after the fix; here to pin that the cap only excludes the
      // absurd.
      final f = _parse('Hey (WR;PL;MR;N2L)').single;
      expect(f.isCustom, isFalse);
      expect(f.move, 'hey');
      expect(f.params['pass1'], 'role2s');
    });

    test('an over-length square-through pass list is rejected', () {
      // Not a red run: an over-count square through is rejected before AND after
      // the fix (the count can never equal `places` <= 10). Pinned so the
      // whole-custom outcome for a hostile line is guarded regardless of which
      // guard fires.
      final f = _parse(
        'Square through 2 (${_megaPassList()})',
        beats: 4,
      ).single;
      expect(f.move, 'square_through');
      expect(f.params['who'], isNull, reason: 'not structured -> default');
    });
  });
}
