import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

final _renderer = FigureRenderer(contraTaxonomy);

/// Issue #744 — prose annotation preservation for three new annotation classes:
///
/// 1. **Balance role-hand pair** (`_balancePairHandAnnotation`): `(MRH,WLH)` /
///    `(MLH,WRH)` on balance lines → synthesised note with canonical role tokens.
/// 2. **Per-role choreography** (`_perRoleChoreoAnnotation`): `(W roll R, M
///    side-step L)` → synthesised note with canonical role tokens.
/// 3. **General prose** (`_proseAnnotation`): `(in center)`, `(along the set)`
///    → verbatim note, shape-gated by the presence of at least one lowercase
///    letter in the annotation body.
///
/// The test file is structured to support red-run verification of each
/// mechanism. For each guard test:
///   - **Red-run**: break the guard (mutate out the check) and confirm the
///     test goes red before adding the guard back.
///   - **Green-run**: re-add the guard and confirm the test passes.
///
/// Red-run results are documented in each group's leading comment.

List<Figure> _parse(String text, {int beats = 0}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

Figure _single(String text, {int beats = 0}) =>
    _parse(text, beats: beats).single;

void main() {
  // ---------------------------------------------------------------------------
  // 1. Balance role-hand pair (`_balancePairHandAnnotation`)
  // ---------------------------------------------------------------------------
  //
  // Corpus source: 148 `Permission: full` lines with `(MRH,WLH)` or
  // `(MLH,WRH)` on structured balance figures.
  //
  // Example dance ID: 03601571 (`Neighbor balance (MRH,WLH)`)
  //
  // Red-run target: remove the `_balancePairHandAnnotation` entry from the
  // `preRecognizers` list (do NOT revert — the balance move still structures
  // via `_balanceHandAnnotation`'s base path; the annotation simply drops).
  // Red result: `f.note` is null instead of `role1s by the right, role2s by
  // the left`.

  group('#744 — balance role-hand pair: synthesised note with role tokens', () {
    test('MRH,WLH → role1s by the right, role2s by the left', () {
      final f = _single('Neighbor balance (MRH,WLH)', beats: 4);
      expect(f.move, 'balance');
      expect(f.params['who'], 'neighbors');
      expect(f.note, 'role1s by the right, role2s by the left');
    });

    test('MLH,WRH → role1s by the left, role2s by the right', () {
      final f = _single('Partner balance (MLH,WRH)', beats: 4);
      expect(f.move, 'balance');
      expect(f.params['who'], 'partners');
      expect(f.note, 'role1s by the left, role2s by the right');
    });

    test('NRH,WLH → neighbors by the right, role2s by the left', () {
      final f = _single('Neighbor balance (NRH,WLH)', beats: 4);
      expect(f.move, 'balance');
      expect(f.note, 'neighbors by the right, role2s by the left');
    });

    test('note carries canonical role tokens, not raw MRH/WLH', () {
      // Proves the note is dialect-renderable: `role1s`/`role2s` tokens are
      // substituted by renderFreeText; a literal `MRH` would be frozen as
      // gendered shorthand in every dialect permanently.
      final f = _single('Neighbor balance (MRH,WLH)', beats: 4);
      expect(f.note, isNotNull);
      expect(f.note, isNot(contains('MRH')));
      expect(f.note, isNot(contains('WLH')));
      expect(f.note, contains('role1s'));
      expect(f.note, contains('role2s'));
    });

    test(
      'single-hand (RH) on balance is NOT claimed — leaves _balanceHandAnnotation intact',
      () {
        // (RH) is handled by the existing _balanceHandAnnotation which consumes
        // it into the `hand` param. The pair recognizer must not claim it.
        final f = _single('Neighbor balance (RH)', beats: 4);
        expect(f.move, 'balance');
        expect(f.params['hand'], 'right');
        // No note from the pair handler.
        expect(f.note, isNull);
      },
    );

    test(
      'unmapped people code → falls to normal path (annotation dropped by _stripAnnotations)',
      () {
        // `O` (opposite) is not in tcbPassPeople; the pair recognizer returns null.
        // The line takes the annotation-stripped path and structures normally.
        final f = _single('Neighbor balance (ORH,WLH)', beats: 4);
        expect(f.move, 'balance');
        // No synthesised note — unmapped code declines.
        expect(f.note, isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2. Per-role choreography (`_perRoleChoreoAnnotation`)
  // ---------------------------------------------------------------------------
  //
  // Corpus source: 796 `Permission: full` lines; 789 on `roll_away`.
  // Top shapes: `W roll R, M side-step L` (411), `W roll L, M side-step R`
  // (228), `M roll R, W side-step L` (61).
  //
  // Example dance IDs: 00071234 (`Neighbor roll away (W roll R, M side-step L)`)
  //
  // Red-run target: mutate out the guard in `_perRoleChoreoAnnotation` by
  // removing the `if (!hasSynthesized) return null;` check, so the function
  // always claims any structured figure. A shorthand annotation like `(OR)`
  // on a swing would then produce a spurious note `OR` instead of no note.
  //
  // Red result (test "shorthand annotation does NOT become a note"):
  // `f.note` would be `OR` instead of null.

  group(
    '#744 — per-role choreo: synthesised note with canonical role tokens',
    () {
      test('W roll R, M side-step L', () {
        final f = _single(
          'Neighbor roll away (W roll R, M side-step L)',
          beats: 8,
        );
        expect(f.move, 'roll_away');
        expect(f.note, 'role2s roll right, role1s side-step left');
      });

      test('W roll L, M side-step R', () {
        final f = _single(
          'Neighbor roll away (W roll L, M side-step R)',
          beats: 8,
        );
        expect(f.move, 'roll_away');
        expect(f.note, 'role2s roll left, role1s side-step right');
      });

      test('M roll R, W side-step L', () {
        final f = _single(
          'Neighbor roll away (M roll R, W side-step L)',
          beats: 8,
        );
        expect(f.move, 'roll_away');
        expect(f.note, 'role1s roll right, role2s side-step left');
      });

      test('W roll R, M step aside (no direction in second clause)', () {
        final f = _single(
          'Neighbor roll away (W roll R, M step aside)',
          beats: 8,
        );
        expect(f.move, 'roll_away');
        expect(f.note, 'role2s roll right, role1s step aside');
      });

      test('note carries canonical role tokens, not raw W/M', () {
        // Proves the note is dialect-renderable.
        final f = _single(
          'Neighbor roll away (W roll R, M side-step L)',
          beats: 8,
        );
        expect(f.note, isNot(contains('W roll')));
        expect(f.note, isNot(contains('M side-step')));
        expect(f.note, contains('role2s'));
        expect(f.note, contains('role1s'));
      });

      // SHAPE RULE GUARD: shorthand annotation does NOT become a note.
      // Red-run: mutate out `if (!hasSynthesized) return null;` in
      // `_perRoleChoreoAnnotation`. Then `(OR)` on a swing would slip through
      // to `_joinAnnotations` and produce a spurious note `OR`.
      test('shorthand annotation (no lowercase) does NOT become a note', () {
        // `OR` = opposite by the right: all-uppercase, no lowercase → shape rule
        // skips it. The swing still structures; no note.
        final f = _single('Neighbor swing (OR)', beats: 8);
        expect(f.move, 'swing');
        expect(f.note, isNull);
      });
    },
  );

  // ---------------------------------------------------------------------------
  // 3. General prose (`_proseAnnotation`)
  // ---------------------------------------------------------------------------
  //
  // Corpus source: 3,215 `Permission: full` annotations across all classes
  // with lowercase-containing bodies.
  //
  // Red-run target: mutate out the shape guard in `_proseAnnotation` by
  // removing the `.where(_annotationBodyHasLowercase)` filter and passing
  // all annotations to `_joinAnnotations`. A shorthand annotation like `(OR)`
  // on a chain would then produce a spurious note `OR` instead of no note.
  //
  // Red result (test "shorthand annotation does NOT become a note"):
  // `f.note` would contain `OR` instead of being null.

  group('#744 — prose annotation: verbatim preserve, shape-gated', () {
    test('(in center) on a swing → preserved verbatim', () {
      final f = _single('Neighbor swing (in center)', beats: 8);
      expect(f.move, 'swing');
      expect(f.note, 'in center');
    });

    test('(along the set) on a chain → combined with chain\'s own note', () {
      final f = _single('Ladies chain (along the set)', beats: 8);
      expect(f.move, 'chain');
      // Chain's own "to <dancer>" note absent (no destination); annotation only.
      expect(f.note, 'along the set');
    });

    test('(past partner) on a do si do → preserved verbatim', () {
      final f = _single('Neighbor do si do (past partner)', beats: 8);
      expect(f.move, 'do_si_do');
      expect(f.note, 'past partner');
    });

    // SHAPE RULE GUARD: shorthand annotation does NOT become a note.
    // Red-run: remove `.where(_annotationBodyHasLowercase)` in `_proseAnnotation`
    // so all annotations pass through. `(OR)` on a do si do would then produce
    // a spurious note `OR`.
    //
    // Note: chain is not a valid guard target here because `_chainAnnotation`
    // fires first and preserves ALL annotations verbatim (it is move-anchored
    // and less discriminating). The shape rule guard lives only in
    // `_proseAnnotation`, which fires only when no specific pre-recognizer
    // claims the line. `do si do` has no specific pre-recognizer.
    test('shorthand annotation (no lowercase) does NOT become a note', () {
      // `OR` is all-uppercase → shape rule skips it → no note on the do si do.
      final f = _single('Neighbor do si do (OR)', beats: 8);
      expect(f.move, 'do_si_do');
      expect(f.note, isNull);
    });

    test('prose annotation preserved while move still structures', () {
      // The annotation must not prevent structuring: the figure must NOT be
      // custom just because it carries an annotation.
      final f = _single('Neighbor swing (with partner)', beats: 8);
      expect(f.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.note, 'with partner');
    });

    test('multiple prose annotations joined with semicolon', () {
      // Both annotations pass the shape rule; they are joined by '; '.
      final f = _single('Neighbor swing (in center) (face partner)', beats: 8);
      expect(f.move, 'swing');
      expect(f.note, 'in center; face partner');
    });

    test('mixed prose + shorthand: prose preserved, shorthand dropped', () {
      // `(in center)` has lowercase → preserved. `(OR)` is all-uppercase →
      // skipped. Only the prose annotation survives.
      final f = _single('Neighbor swing (in center) (OR)', beats: 8);
      expect(f.move, 'swing');
      expect(f.note, 'in center');
      expect(f.note, isNot(contains('OR')));
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Scope boundary: `[…]` annotations are NOT preserved as notes
  // ---------------------------------------------------------------------------
  //
  // TCB uses `[…]` brackets for formation/who-performs context markers
  // (`[Others]`, `[with N3]`, `[Top two couples]`).  These have a different
  // payload from `(…)` prose annotations and must not become notes.
  // Both `_perRoleChoreoAnnotation` and `_proseAnnotation` use
  // `_parenAnnotations` (round-paren only) so `[…]` bodies never reach them.
  //
  // `_balancePairHandAnnotation` was already safe: its regex is `\(…\)`.
  //
  // Red-run target (for `[…]` scope): change `_parenAnnotations` to
  // `_annotations` in `_proseAnnotation`.  Then `[with N3]` on a balance_ring
  // would produce note `with N3` instead of null.

  group('#744 — scope boundary: [bracket] annotations unchanged', () {
    test('[bracket] body on a structured figure does NOT become a note', () {
      // `[with N3]` is TCB formation context, not a prose annotation.
      // `_proseAnnotation` uses _parenAnnotations (paren-only), so this
      // bracket body must not reach it and must produce no note.
      final f = _single('Balance ring [with N3]', beats: 4);
      expect(f.move, 'balance_the_ring');
      expect(f.note, isNull);
    });

    test(
      '[bracket] body does not interfere with adjacent (paren) prose note',
      () {
        // If both a [bracket] and a (paren) annotation are present, only the
        // paren annotation should produce a note.
        final f = _single('Neighbor swing [Others] (in center)', beats: 8);
        expect(f.move, 'swing');
        expect(f.note, 'in center');
        expect(f.note, isNot(contains('Others')));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 5. Digit-bearing per-role codes: declined, not verbatim-preserved
  // ---------------------------------------------------------------------------
  //
  // TCB occasionally writes couple-specific per-role codes like
  // `M1 past M3, W1 past W2` where the digit refers to couple position.
  // These cannot be mapped to `role1s`/`role2s` (couple-specific, not
  // gender-role) so synthesis fails.  `_looksLikePerRoleBody` detects the
  // structural pattern and prevents the body from being preserved verbatim as
  // gendered shorthand.  56 such annotations exist in the corpus.
  //
  // Red-run target: remove `&& !_looksLikePerRoleBody(body)` from
  // `_perRoleChoreoAnnotation`.  Then `M1 past M3, W1 past W2` would survive
  // to `_proseAnnotation` and be preserved as the literal string
  // `M1 past M3, W1 past W2` — freezing gendered shorthand.

  group('#744 — digit-bearing per-role codes: declined not verbatim', () {
    test('M1/W1 couple codes on roll_away: no note (declined)', () {
      // `M1 past M3, W1 past W2` — structurally matches per-role pattern but
      // people codes carry a digit (couple position); not representable as
      // role1s/role2s.  Must NOT appear verbatim in a note.
      final f = _single(
        'Neighbor roll away (M1 past M3, W1 past W2)',
        beats: 8,
      );
      expect(f.move, 'roll_away');
      expect(f.note, isNull);
    });

    test('standard W/M without digit: synthesis still works', () {
      // Sanity check: non-digit forms are unaffected by _looksLikePerRoleBody.
      final f = _single(
        'Neighbor roll away (W roll R, M side-step L)',
        beats: 8,
      );
      expect(f.move, 'roll_away');
      expect(f.note, 'role2s roll right, role1s side-step left');
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Round-trip: synthesised role tokens reach renderFreeText
  // ---------------------------------------------------------------------------
  //
  // Proves that notes produced by the annotation pre-recognizers carry
  // canonical role tokens (`role1s`/`role2s`) and that [FigureRenderer.renderFreeText]
  // substitutes them for the active dialect.
  //
  // This closes the "parser produces it → user sees it" gap: in the app,
  // `DanceEditorController._renderNote` calls `_noteRenderer.renderFreeText(
  // stored, _activeDialect)` on every `FigureDraft.note` at load and
  // dialect-change time. The same function is exercised here.

  group('#744 — round-trip: role tokens in notes are dialect-rendered', () {
    test('balance pair-hand note: role1s/role2s → larks/robins', () {
      // Corpus line: `Neighbor balance (MRH,WLH)` (dance 03601571).
      // Parser stores `role1s by the right, role2s by the left` — canonical.
      // renderFreeText in the larks/robins dialect maps role1s → larks,
      // role2s → robins.
      final f = _single('Neighbor balance (MRH,WLH)', beats: 4);
      final note = f.note!;
      expect(note, contains('role1s'));
      final rendered = _renderer.renderFreeText(note, Dialect.larksRobins);
      expect(rendered, 'larks by the right, robins by the left');
    });

    test('per-role choreo note: role1s/role2s → leads/follows', () {
      // `(W roll R, M side-step L)` on a roll away: parser synthesises
      // `role2s roll right, role1s side-step left`.  Leads/follows dialect
      // maps role2s → follows, role1s → leads.
      final f = _single(
        'Neighbor roll away (W roll R, M side-step L)',
        beats: 8,
      );
      final note = f.note!;
      expect(note, contains('role1s'));
      expect(note, contains('role2s'));
      final rendered = _renderer.renderFreeText(note, Dialect.leadsFollows);
      expect(rendered, 'follows roll right, leads side-step left');
    });

    test(
      'prose note: no role tokens → passes through unchanged in any dialect',
      () {
        // `(in center)` carries no role tokens, so renderFreeText is a no-op.
        final f = _single('Neighbor swing (in center)', beats: 8);
        final note = f.note!;
        expect(_renderer.renderFreeText(note, Dialect.larksRobins), note);
        expect(_renderer.renderFreeText(note, Dialect.leadsFollows), note);
      },
    );
  });
}
