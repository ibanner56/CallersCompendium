// Tests for #843 Parts B and C: the general `;`-run consume.
//
// TCB's `;`-run shorthand — `(ML)`, `(NR;PL)`, `(WR;PL;MR;N2L~)` — encodes
// handedness AND dancer identity. `_stripAnnotations` used to drop it before
// recognition, and the taxonomy then filled the slot with a default that
// sometimes contradicted the source.
//
// ## Two rulings this suite pins
//
// 1. **Write the value even when it equals the taxonomy default** (owner).
//    The decode either fires on a run or it does not. This is byte-identical at
//    both identity layers, which is asserted rather than assumed.
// 2. **Dancer identity fills `who`/`who2` where the move declares them.**
//    `pass_through` declares no `who`, so its dancer code is dropped.
//
// ## Why folding is tested through the ADAPTER
//
// `parseFigureLines` does not run `CallersBoxAdapter`'s cross-line merge, so a
// parser-only test cannot see what an import actually produces — and the
// balance fold is exactly where a written `hand` meets #870's inverse-pair
// re-routing.
//
// ## Corpus figures quoted below
//
// Measured against pristine `f3030cbc` over the 24,107-file mirror (20,516
// parseable / 11,499 `Permission: full`, both reproducing the documented
// denominators): 2,504 dropped runs, of which 2,388 write a value equal to the
// effective default and 116 write the inverse. Zero move-id deltas, zero beat
// deltas, zero custom/structured flips.

import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _dance(List<Map<String, Object?>> phrases) => {
  'ID': '1',
  'Name': 'Test Dance',
  'Permission': 'full',
  'FormationBase': 'Duple Minor - Improper',
  'Progression': 'Single',
  'phrases': phrases,
};

Future<List<Figure>> _importTcb(List<String> lines) async {
  final adapter = CallersBoxAdapter();
  final payload = jsonEncode(
    _dance([
      {'name': 'A1', 'figures': lines},
    ]),
  );
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw).dance.figures;
}

Future<Figure> _importTcbLine(String line) async =>
    (await _importTcb([line])).single;

void main() {
  final tax = contraTaxonomy;

  // -------------------------------------------------------------------------
  // Part B — the side is consumed
  // -------------------------------------------------------------------------

  group('B — `;`-run sides are consumed', () {
    // Mutation caught: not wiring the decoder in at all, or gating it on
    // "differs from the default" (2,388 of the 2,504 corpus runs agree with
    // the default, so a difference-gated decoder would silently do nothing on
    // the overwhelming majority).
    test('a default-valued run is still written explicitly', () async {
      final f = await _importTcbLine('(2) Pass through along (NR)');
      expect(f.move, 'pass_through');
      expect(f.params['shoulder'], 'right');
      expect(f.params.containsKey('shoulder'), isTrue);
    });

    // Mutation caught: reading the LAST cell's side instead of deriving the
    // position-1 base. `(NL;PR)` has a left base and a right second cell.
    test('a non-default run overrides the taxonomy default', () async {
      final f = await _importTcbLine('(2) Pass through along (NL)');
      expect(f.params['shoulder'], 'left');
    });

    test('the base side comes from position 1, not the last cell', () async {
      final f = await _importTcbLine('(4) Cross trail through (NL;PR)');
      expect(f.move, 'cross_trails');
      expect(f.params['shoulder'], 'left');
    });

    // Mutation caught: keying the slot lookup on the literal param name
    // `hand`. Seven moves name it `shoulder` and two name it `centerHand`, so
    // a name check misses nine of the twenty moves that declare one.
    test('the slot is found by ParamKind, not by the name "hand"', () async {
      // `pass_through` names it `shoulder`...
      final shoulder = await _importTcbLine('(2) Pass through along (NL)');
      expect(shoulder.params['shoulder'], 'left');
      // ...and `square_through` names it `hand`. Both must be filled.
      final hand = await _importTcbLine('(16) Square through 2 (PR;NL)');
      expect(hand.move, 'square_through');
      expect(hand.params['hand'], 'right');
    });

    // The property that makes the owner's "write it anyway" ruling safe, and
    // the one that keeps #686's "Variation?" prompt quiet for the 2,388.
    test(
      'an explicit default keys and renders identically to an absent one',
      () {
        final renderer = FigureRenderer(tax);
        final bare = Figure(move: 'pass_through', params: {'dir': 'along'});
        final explicit = Figure(
          move: 'pass_through',
          params: {'dir': 'along', 'shoulder': 'right'},
        );
        expect(
          figureCanonicalKey(explicit, tax),
          figureCanonicalKey(bare, tax),
        );
        expect(
          renderer.renderCanonical(explicit),
          renderer.renderCanonical(bare),
        );
      },
    );

    // ...and the honest other half: the INVERSE value genuinely changes the
    // key, so re-importing one of the 116 raises a real #686 prompt. That is
    // correct — the stored choreography contradicted its source — but it must
    // not be claimed as "consequence-free".
    test('an explicit INVERSE value DOES change the canonical key', () {
      final bare = Figure(move: 'pass_through', params: {'dir': 'along'});
      final inverse = Figure(
        move: 'pass_through',
        params: {'dir': 'along', 'shoulder': 'left'},
      );
      expect(
        figureCanonicalKey(inverse, tax),
        isNot(figureCanonicalKey(bare, tax)),
      );
    });

    // Mutation caught: dropping the `~` handling, which would make the final
    // cell's people code unmappable and decline the whole (very common) run.
    test('a trailing `~` partial-pass marker is tolerated', () async {
      final f = await _importTcbLine('(16) Square through 2 (PR;NL~)');
      expect(f.move, 'square_through');
      expect(f.params['hand'], 'right');
    });
  });

  // -------------------------------------------------------------------------
  // Part C — dancer identity
  // -------------------------------------------------------------------------

  group('C — dancer identity fills who/who2 where declared', () {
    // Mutation caught: filling only the side and leaving the dancers to their
    // defaults — which is what asserts the WRONG dancers on 28 of the 31
    // remaining visible contradictions.
    test('odd positions name `who`, even positions `who2`', () async {
      final f = await _importTcbLine('(16) Square through 2 (SR;NL)');
      expect(f.move, 'square_through');
      expect(f.params['who'], 'shadows');
      expect(f.params['who2'], 'neighbors');
      expect(f.params['hand'], 'right');
    });

    test('cross_trails takes its pair from the two cells', () async {
      final f = await _importTcbLine('(4) Cross trail through (NR;PL)');
      expect(f.move, 'cross_trails');
      expect(f.params['who'], 'neighbors');
      expect(f.params['who2'], 'partners');
      expect(f.params['shoulder'], 'right');
    });

    // `pass_through` declares NO `who`. The dancer therefore has nowhere to go
    // and must not be forced somewhere it does not belong.
    //
    // Mutation caught: writing `who` unconditionally, which
    // `Taxonomy.validateFigure` rejects as an unknown param — sending the whole
    // line to the custom fallback and REGRESSING 2,136 corpus figures from
    // structured to custom.
    test('pass_through gains a shoulder but no `who`', () async {
      final f = await _importTcbLine('(2) Pass through along (NR)');
      expect(f.isCustom, isFalse);
      expect(f.move, 'pass_through');
      expect(f.params.containsKey('who'), isFalse);
      expect(f.params['shoulder'], 'right');
    });
  });

  // -------------------------------------------------------------------------
  // Declines — prefer-custom at param granularity
  // -------------------------------------------------------------------------

  group('declines', () {
    // Mutation caught: approximating an unmapped people code onto a nearby
    // token. `o` (opposite), `ph` (phantom) and `srn` (same-role neighbor) are
    // the three most common unmapped prefixes in the corpus.
    test('an unmapped people code leaves the line at its default', () async {
      for (final code in ['OR', 'PhL', 'SrnR']) {
        final f = await _importTcbLine('(2) Pass through along ($code)');
        expect(
          f.params['shoulder'],
          isNull,
          reason: '$code must not decode to a shoulder',
        );
      }
    });

    // Mutation caught: taking the first cell's side and ignoring the rest.
    test('a non-alternating run is declined', () async {
      final f = await _importTcbLine('(16) Square through 2 (PR;NR)');
      expect(f.params.containsKey('hand'), isFalse);
    });

    // Mutation caught: dropping the periodicity check. The alternation check
    // alone accepts this — the SIDES alternate correctly — but the dancers
    // break the period the renderer's "then repeat" model requires.
    test('a non-periodic square_through 4-list is declined', () async {
      final f = await _importTcbLine('(16) Square through 4 (PR;NL;SR;NL)');
      expect(f.params.containsKey('hand'), isFalse);
    });

    // Mutation caught: dropping the cross_trails shape check.
    test('a cross_trails run longer than `?R;?L` is declined', () async {
      final f = await _importTcbLine('(4) Cross trail through (NR;PL;NR)');
      expect(f.params.containsKey('shoulder'), isFalse);
    });

    // A ONE-cell run on a `who2` move is ACCEPTED (`<= 2`, not `== 2`), and
    // this pins that choice against the obvious "tighten it for symmetry with
    // square_through" change.
    //
    // The symmetry argument is wrong here, and the reason is measurable rather
    // than stylistic. `square_through` states its pass count in prose, so a
    // short list contradicts the line's own arity — decline. `cross_trails`
    // states no count, so one cell is incomplete rather than contradictory.
    // `who2` renders from its `neighbors` default either way (a bare
    // `Cross trails` renders it too), so declining would NOT suppress the
    // defaulted second pass — it would only replace the FIRST pass's
    // source-stated `neighbors` with the `partners` default. That trades a
    // stated fact for an assumed one.
    //
    // Mutation caught: changing `<= 2` to `== 2`. Verified red — `who` comes
    // back `partners`, contradicting the `(NR)` the source wrote.
    test('a one-cell run on a who2 move is consumed, not declined', () async {
      final f = await _importTcbLine('(4) Cross trail through (NR)');
      expect(f.move, 'cross_trails');
      expect(f.params['shoulder'], 'right');
      // The stated pass is kept...
      expect(f.params['who'], 'neighbors');
      // ...and the unstated one is NOT invented.
      expect(f.params.containsKey('who2'), isFalse);
    });

    // A cell is a PASS. `pass_through` models one, so a two-cell run describes
    // choreography it cannot express.
    //
    // Mutation caught: collapsing a multi-cell run onto its first cell for a
    // single-pass move — which would silently discard the second pass while
    // reporting the line as fully structured.
    test('a multi-cell run on a single-pass move is declined', () async {
      final f = await _importTcbLine('(2) Pass through along (NR;PL)');
      expect(f.params.containsKey('shoulder'), isFalse);
    });

    // #799 declined to guess the unstated third pass of `Square through 3
    // (N2R;SL)`. This decoder must not undo that ruling by the side door: it
    // sees the same line after `_squareThroughPassList` declines it.
    //
    // Mutation caught: dropping the `cells.length == places` rule, which lets
    // the general decoder structure exactly the lines the specific one refused.
    test(
      'a square_through cell count that disagrees with places is declined',
      () async {
        final f = await _importTcbLine('(16) Square through 3 (N2R;SL)');
        expect(f.move, 'square_through');
        expect(f.params['places'], 3);
        expect(f.params.containsKey('who'), isFalse);
        expect(f.params.containsKey('hand'), isFalse);
      },
    );

    // Mutation caught: letting the annotation overwrite a side the grammar
    // already resolved from prose — which would silently flip this figure from
    // the left hand the words state to the right hand the code states.
    //
    // The line FALLS THROUGH to today's reading rather than declining to
    // custom: the prose value stands and the annotation is dropped. Forcing
    // custom here would regress a line that structures today, which is a bigger
    // loss than declining to consume one contradictory annotation. Asserted
    // explicitly, because "declines" and "falls through" look the same from a
    // decoder that returns null and are very different for the user.
    test(
      'an annotation contradicting a prose side leaves the prose value',
      () async {
        final f = await _importTcbLine('(8) Neighbor allemande left 1 (NR)');
        expect(f.isCustom, isFalse);
        expect(f.move, 'allemande');
        expect(f.params['hand'], 'left');
      },
    );

    test('an annotation AGREEING with a prose side is kept', () async {
      final f = await _importTcbLine('(8) Neighbor allemande left 1 (NL)');
      expect(f.isCustom, isFalse);
      expect(f.move, 'allemande');
      expect(f.params['hand'], 'left');
    });

    // **This test pins the OUTCOME, not the bound — stated plainly because the
    // two look the same and only one of them is actually guarded here.**
    //
    // Removing `_boundedPassListCells` was tried as a mutation and this stayed
    // GREEN. It has to: a hostile run is rejected several layers earlier, by
    // the alternation check and then by the shape rule (`pass_through` models
    // one pass, so anything past one cell declines). There is no input that
    // decodes successfully at 400 cells but not at 12, because every move's
    // shape rule already caps the accepted count at 10 or fewer.
    //
    // What the shared bound actually buys is that the oversized list is never
    // ALLOCATED — an O(1) length check ahead of `String.split` — and allocation
    // is not observable from a behavioural test. The bound is kept because
    // every other pass-list decoder in this file shares it and a new path that
    // quietly skipped it would be the start of the drift OWASP-wise, not
    // because this test proves anything about it.
    test(
      'a hostile over-long run is rejected (outcome, not the bound)',
      () async {
        final hostile = List.filled(400, 'NR').join(';');
        final f = await _importTcbLine('(2) Pass through along ($hostile)');
        expect(f.params.containsKey('shoulder'), isFalse);
      },
    );

    test('a second parenthetical declines rather than guessing', () async {
      final f = await _importTcbLine('(2) Pass through along (NR) (optional)');
      expect(f.params.containsKey('shoulder'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // The #870 inverse-pair guarantee, in both directions
  // -------------------------------------------------------------------------

  group('#870 inverse-pair re-routing is value-sensitive', () {
    // `resolvedMoveId` is called at write time in `DanceRepository._upsert`,
    // so these assert the taxonomy contract directly — the population that
    // reaches it from THIS decoder is zero in the corpus (verified: no TCB
    // figure line attaches a `<code><R|L>` cell to an inverse-pair move), but
    // the guarantee is what makes writing explicit hands safe in general.
    //
    // Mutation caught: "simplifying" resolution to fire whenever a side is
    // EXPLICIT rather than when its VALUE is the inverse. The pair of cases
    // below is what distinguishes the two rules; either one alone does not.
    test('an explicit default does NOT re-route', () {
      expect(
        tax.resolvedMoveId(
          Figure(move: 'box_the_gnat', params: {'hand': 'right'}),
        ),
        'box_the_gnat',
      );
      expect(
        tax.resolvedMoveId(
          Figure(move: 'do_si_do', params: {'shoulder': 'right'}),
        ),
        'do_si_do',
      );
    });

    test('an explicit inverse DOES re-route, both ways', () {
      expect(
        tax.resolvedMoveId(
          Figure(move: 'box_the_gnat', params: {'hand': 'left'}),
        ),
        'swat_the_flea',
      );
      // The alias side inverts the rule, so it is asserted separately rather
      // than assumed to follow.
      expect(
        tax.resolvedMoveId(
          Figure(move: 'swat_the_flea', params: {'hand': 'right'}),
        ),
        'box_the_gnat',
      );
      expect(
        tax.resolvedMoveId(
          Figure(move: 'do_si_do', params: {'shoulder': 'left'}),
        ),
        'see_saw',
      );
      expect(
        tax.resolvedMoveId(
          Figure(move: 'see_saw', params: {'shoulder': 'right'}),
        ),
        'do_si_do',
      );
    });
  });

  // -------------------------------------------------------------------------
  // The existing decoders keep their lines
  // -------------------------------------------------------------------------

  group('the bespoke decoders above are unaffected', () {
    test('a hey still decodes through its own decoder', () async {
      final f = await _importTcbLine('(16) Hey 1/2 (WR;PL;MR;N2L~)');
      expect(f.move, 'hey');
      expect(f.params['pass1'], 'role2s');
      expect(f.params['shoulder'], 'right');
    });

    test(
      'a square through pass list still decodes with balance: false',
      () async {
        final f = await _importTcbLine('(16) Square through 2 (N2R;SL)');
        expect(f.move, 'square_through');
        expect(f.params['balance'], false);
        expect(f.params['who'], 'nextNeighbors');
        expect(f.params['who2'], 'shadows');
      },
    );

    test('a balance hand annotation still folds (#870)', () async {
      final figures = await _importTcb([
        '(4) Neighbor balance (RH)',
        '(4) Neighbor box the gnat',
      ]);
      expect(figures.single.move, 'box_the_gnat');
      expect(figures.single.params['hand'], 'right');
      expect(figures.single.params['balance'], true);
    });

    test('a star promenade center note still fires (#843 Part A)', () async {
      final f = await _importTcbLine('(4) Neighbor star promenade 1/2 (WR)');
      expect(f.move, 'star_promenade');
      expect(f.params['who'], 'neighbors');
      expect(f.note, 'role2s by the right in the center');
    });
  });
}
