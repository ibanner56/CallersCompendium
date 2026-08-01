import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// The `courtesy_turn` move (taxonomy v23) and its Caller's Box recognizer.
///
/// The figure did not exist before this version: every corpus line naming one
/// fell to `custom`, so nothing here can regress an existing reading. What the
/// suite guards instead is the *boundary* — the far larger set of wordings that
/// mention a courtesy turn but must KEEP falling to `custom`, because
/// structuring them would either double-count a chain or drop information the
/// unstructured fallback preserves.
///
/// Corpus figures cited throughout are a census over the full 24,107-dance
/// Caller's Box mirror; see `docs/research/callersbox.md`.
String _text(Figure f) => f.params['text'] as String;

void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  Figure? parseTcb(String rawText, {int beats = 0}) =>
      parseFigureLine(rawText, beats: beats, frontEnd: tcbFigureFrontEnd);

  List<Figure> parseTcbLines(String rawText, {int beats = 0}) =>
      parseFigureLines(rawText, beats: beats, frontEnd: tcbFigureFrontEnd);

  group('taxonomy — the v23 move', () {
    test('contraTaxonomyVersion is 23', () {
      expect(contraTaxonomyVersion, 23);
      expect(tax.version, 23);
    });

    test(
      'v23 is purely additive — the DB schema version is unchanged at 20',
      () {
        // A new move renames nothing and removes nothing, so no stored figure
        // can reference an id the taxonomy stopped defining and no persisted
        // data needs rewriting. Contrast v21 (a rename → schema 19) and v22
        // (a merge → schema 20), each of which DID owe a migration.
        expect(kCompendiumSchemaVersion, 20);
      },
    );

    test('registers with the maintainer-ruled param set', () {
      final def = tax.resolve('courtesy_turn')!;
      expect(def.displayName, 'courtesy turn');
      expect(def.params.keys, [
        'who',
        'whom',
        'direction',
        'endFacing',
        'beats',
      ]);
      expect(def.params['who']!.defaultValue, 'partners');
      expect(def.params['beats']!.defaultValue, 4);
    });

    test('whom and endFacing default to the unspecified sentinel', () {
      // "You can make the end_facing and whom optional, left out by default
      // unless it actually shows up in parsing data" — so an authored or
      // imported figure that omits them asserts nothing about either.
      final def = tax.resolve('courtesy_turn')!;
      for (final name in ['whom', 'endFacing']) {
        final spec = def.params[name]!;
        expect(spec.defaultValue, ParamVocab.unspecified, reason: name);
        expect(spec.choices, contains(ParamVocab.unspecified), reason: name);
        expect(spec.validate(ParamVocab.unspecified), isTrue, reason: name);
      }
    });

    test('endFacing is a DANCER domain, NOT swing.endFacing\'s cardinals', () {
      // The single easiest thing to get wrong about this move: the name matches
      // `swing.endFacing` but the domain does not. TCB writes `, face N2` — a
      // relationship — never `, face out`.
      final spec = tax.resolve('courtesy_turn')!.params['endFacing']!;
      expect(spec.kind, ParamKind.dancerSet);
      for (final token in [
        'prevNeighbors',
        'nextNeighbors',
        'thirdNeighbors',
      ]) {
        expect(spec.validate(token), isTrue, reason: token);
      }
      // The four set-relative cardinals `swing.endFacing` / `gate.face` use are
      // NOT in this domain.
      for (final cardinal in gateFacings) {
        expect(spec.validate(cardinal), isFalse, reason: cardinal);
      }
      // And the two really are different: `swing.endFacing` still holds them.
      final swingSpec = tax.resolve('swing')!.params['endFacing']!;
      expect(swingSpec.choices, unorderedEquals(gateFacings));
    });

    test('direction is a spinDirection defaulting to clockwise, NO sentinel', () {
      // Issue #726: `figure_param_editors.dart` renders ParamKind.spinDirection
      // from a HARDCODED `ParamVocab.spins`, ignoring `spec.choices`. A
      // sentinel here would not merely be missing from the dropdown — the
      // editor's reconciliation pushes a substitute back into the draft, so
      // opening the editor would rewrite "unstated" into "clockwise". The move
      // does not need a sentinel (a courtesy turn wheels clockwise by
      // construction), so it uses the honest kind and a real default.
      final spec = tax.resolve('courtesy_turn')!.params['direction']!;
      expect(spec.kind, ParamKind.spinDirection);
      expect(spec.defaultValue, 'clockwise');
      expect(spec.choices, isNull);
      expect(spec.validate(ParamVocab.unspecified), isFalse);
      expect(spec.validate('counterclockwise'), isTrue);
    });

    test('goodBeats are the counts the corpus actually attests', () {
      // 4 x97, 2 x8, 3 x6, 6 x4 across the 115 lines this grammar claims. The
      // `5` and `8` that appear elsewhere in a "courtesy turn" grep belong to
      // lines that can never structure as this move (a `;` compound, and the
      // `("courtesy fling")` right-and-left-throughs), so they are absent.
      expect(tax.resolve('courtesy_turn')!.goodBeats, [2, 3, 4, 6]);
    });

    test('the attested beat counts raise no warning; 8 does', () {
      for (final beats in [2, 3, 4, 6]) {
        final issues = tax.validateFigure(
          Figure(move: 'courtesy_turn', params: {'beats': beats}),
        );
        expect(issues, isEmpty, reason: '$beats beats');
      }
      expect(
        tax.validateFigure(Figure(move: 'courtesy_turn', params: {'beats': 8})),
        isNotEmpty,
      );
    });
  });

  group('recognizer — the wordings TCB actually writes', () {
    test('bare `<pairing> courtesy turn` for every attested subject', () {
      const cases = {
        'Partner courtesy turn': 'partners',
        'Neighbor courtesy turn': 'neighbors',
        'N2 neighbor courtesy turn': 'nextNeighbors',
        'N3 neighbor courtesy turn': 'thirdNeighbors',
        'Shadow courtesy turn': 'shadows',
        'Twos courtesy turn': 'twos',
      };
      cases.forEach((line, who) {
        final f = parseTcb(line, beats: 4);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isFalse, reason: line);
        expect(f.move, 'courtesy_turn', reason: line);
        expect(f.params['who'], who, reason: line);
        expect(f.beats, 4, reason: line);
        // Nothing the line did not state.
        expect(f.params.containsKey('direction'), isFalse, reason: line);
        expect(f.params.containsKey('endFacing'), isFalse, reason: line);
        expect(f.params.containsKey('whom'), isFalse, reason: line);
        expect(f.assumedSubject, isFalse, reason: line);
      });
    });

    test('a stated direction is carried; an unstated one is not invented', () {
      final stated = parseTcb('Partner courtesy turn clockwise', beats: 4)!;
      expect(stated.params['direction'], 'clockwise');

      final bare = parseTcb('Partner courtesy turn', beats: 4)!;
      expect(bare.params.containsKey('direction'), isFalse);
      // The taxonomy default still applies on read — the figure simply does not
      // claim the SOURCE said it.
      expect(
        tax.resolve('courtesy_turn')!.params['direction']!.defaultValue,
        'clockwise',
      );
    });

    test('counterclockwise parses even though the corpus never states it', () {
      // Authoring parity: the param admits it, so the recognizer must not
      // reject a hand-written line that uses it.
      final f = parseTcb('Neighbor courtesy turn counterclockwise', beats: 4)!;
      expect(f.move, 'courtesy_turn');
      expect(f.params['direction'], 'counterclockwise');
    });

    test('`, face <N-tag>` fills endFacing with the DANCER it names', () {
      const cases = {
        'Partner courtesy turn, face N0': 'prevNeighbors',
        'Partner courtesy turn, face N2': 'nextNeighbors',
        'Partner courtesy turn, face N3': 'thirdNeighbors',
      };
      cases.forEach((line, facing) {
        final f = parseTcb(line, beats: 4);
        expect(f, isNotNull, reason: line);
        expect(f!.move, 'courtesy_turn', reason: line);
        // The facing's dancer must NOT be mistaken for the subject.
        expect(f.params['who'], 'partners', reason: line);
        expect(f.params['endFacing'], facing, reason: line);
      });
    });

    test('the facing clause is read BEFORE the subject is taken', () {
      // Without the ordering guard, a subject-less line would resolve
      // `who: nextNeighbors` from the facing's dancer, inverting its meaning.
      final f = parseTcb('Courtesy turn, face N2', beats: 4)!;
      expect(f.params['endFacing'], 'nextNeighbors');
      expect(f.params['who'], 'partners');
      // The subject was ASSUMED, not stated — surfaced as such, never asserted.
      expect(f.assumedSubject, isTrue);
    });

    test('a facing clause BEFORE the move name declines the line', () {
      // The clause is read by index, so it must be bounded to positions after
      // the `courtesy turn` anchor. Unbounded, `face N2 courtesy turn` would be
      // lifted apart and structured as though it were the attested word order —
      // normalising a wording no source writes into a reading it never
      // expressed. This file's settled posture is to DECLINE an unattested word
      // order (cf. `_takeLeadingDancer`).
      for (final line in [
        'face N2 courtesy turn',
        'face N2 partner courtesy turn',
        'face N3 neighbor courtesy turn clockwise',
      ]) {
        final f = parseTcb(line, beats: 4);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
        // Nothing is lost: the whole line survives in the custom text.
        expect(_text(f).toLowerCase(), contains('face'), reason: line);
      }
    });

    test('a second dancer is never captured as `whom`', () {
      // The two `<dancer>?` slots in the grammar are alternative positions for
      // the SAME value (`who`), not two params. No corpus line writes the
      // two-dancer form, so filling `whom` would invent a reading no source
      // states — a line naming two dancers leaves one over and declines.
      for (final line in [
        'ones courtesy turn twos',
        'partner courtesy turn neighbor',
      ]) {
        final f = parseTcb(line, beats: 4);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
      }
      // And the post-anchor position still works as the SUBJECT fallback.
      final fallback = parseTcb('Courtesy turn partner', beats: 4)!;
      expect(fallback.move, 'courtesy_turn');
      expect(fallback.params['who'], 'partners');
      expect(fallback.params.containsKey('whom'), isFalse);
    });

    test('a redundant "N2 neighbor" pairing is absorbed on both slots', () {
      final f = parseTcb('N2 neighbor courtesy turn, face N3 neighbor')!;
      expect(f.move, 'courtesy_turn');
      expect(f.params['who'], 'nextNeighbors');
      expect(f.params['endFacing'], 'thirdNeighbors');
    });

    test('every attested beat count survives the parse exactly', () {
      for (final beats in [2, 3, 4, 6]) {
        final f = parseTcb('Partner courtesy turn', beats: beats)!;
        expect(f.move, 'courtesy_turn', reason: '$beats');
        expect(f.beats, beats, reason: '$beats');
      }
    });
  });

  group('must stay custom — chain-embedded courtesy turns', () {
    // 30 corpus lines write a chain (or a right-and-left-through / promenade,
    // which end the same way) together with its courtesy turn. Emitting a
    // standalone `courtesy_turn` for one of these would double-count both the
    // figure and its beats — and there is no slot for the qualifier in either
    // model: ContraDB's `chain` has exactly four params and none is a
    // courtesy turn.
    const lines = [
      '[W1+W2] Ladies chain, with half courtesy turn in center',
      '[Groups of four] Ladies chain to partner, with half courtesy turn in '
          'center',
      'Ladies chain to partner with double courtesy turn '
          '(begin with woman on the left)',
      'Right and left through with partner with double courtesy turn',
      'Right and left through with partner with double courtesy turn '
          '(along the set)',
      'Neighbor promenade across with double courtesy turn',
      'Partner promenade across with double courtesy turn',
      'Reverse-order ladies chain to neighbor '
          '(Neighbor courtesy turn; women pull by right)',
    ];

    for (final line in lines) {
      test('"$line" stays custom', () {
        final f = parseTcb(line, beats: 8);
        expect(f, isNotNull);
        expect(f!.isCustom, isTrue);
        expect(f.beats, 8);
        // The whole line survives verbatim (post-scrub) — nothing dropped.
        expect(_text(f).toLowerCase(), contains('courtesy turn'));
      });
    }

    test('a line whose courtesy turn is only in a PARENTHETICAL still emits no '
        'courtesy_turn figure', () {
      // `_stripAnnotations` drops `()` for recognition, so these resolve to
      // the bare chain/promenade they lead with. The invariant this move owes
      // is that no SECOND figure appears and no beat is counted twice — and
      // it holds, because the annotation never reaches a recognizer.
      //
      // These lines DO lose their parenthetical, which for "(without
      // courtesy turn)" is choreographically load-bearing. That loss is
      // PRE-EXISTING and unchanged by taxonomy v23 (verified against the
      // corpus before and after): it belongs to `chain`/`promenade`, which
      // have no annotation-preserving pre-recognizer of their own. Closing it
      // means generalizing the `gate`/`courtesy_turn` note mechanism to those
      // moves, which changes notes on far more of the corpus than this unit
      // touches. Tracked separately; pinned here so the gap is visible rather
      // than silent.
      for (final line in [
        'Ladies chain to partner (optional double courtesy turn)',
        'Partner promenade across (without courtesy turn)',
        'Neighbor promenade across (without courtesy turn)',
      ]) {
        final figs = parseTcbLines(line, beats: 6);
        expect(figs, hasLength(1), reason: line);
        expect(figs.single.move, isNot('courtesy_turn'), reason: line);
        expect(figs.single.beats, 6, reason: line);
      }
    });

    test('a chain WITHOUT a courtesy turn is untouched by the new move', () {
      final f = parseTcb('Ladies chain to partner', beats: 8)!;
      expect(f.move, 'chain');
      expect(f.params['who'], 'role2s');
      expect(f.note, 'to partner');
    });

    test('a "courtesy fling" right-and-left-through is not a courtesy turn', () {
      // 19 corpus lines name the "courtesy fling" variant of a right and left
      // through. They contain the word "courtesy" but no courtesy turn, and the
      // trailing facing clause is unmodelable, so they stay whole-custom.
      final figs = parseTcbLines(
        'Right and left through with partner; face partner '
        '("courtesy fling")',
        beats: 8,
      );
      expect(figs, hasLength(1));
      expect(figs.single.isCustom, isTrue);
      expect(figs.single.beats, 8);
    });
  });

  group('must stay custom — "arky" (roles reversed, unmodeled)', () {
    // "Arky" reverses the roles. The taxonomy has no model for that, and
    // ContraDB has no such concept either (0 hits for "arky" repo-wide), so
    // structuring the rest of the line would silently drop real choreography.
    // No exclusion logic is written for this — the whole-line contract declines
    // it because `arky` is left over.
    for (final line in [
      'Partner arky courtesy turn',
      'Partner arky courtesy turn without hands',
      'Partner arky courtesy turn clockwise (in center)',
    ]) {
      test('"$line" stays custom, keeping the word "arky"', () {
        final f = parseTcb(line, beats: 4);
        expect(f, isNotNull);
        expect(f!.isCustom, isTrue);
        expect(_text(f).toLowerCase(), contains('arky'));
        expect(f.beats, 4);
      });
    }
  });

  group(
    'must stay custom — dancers the taxonomy deliberately does not map',
    () {
      // `P2`+ (a mixer's future partners), phantoms, square corners and the
      // free-form positional phrases have no faithful token; approximating them
      // onto one that means someone else would be worse than declining.
      for (final line in [
        'Phantom partner courtesy turn',
        'P1 partner courtesy turn',
        'P2 partner courtesy turn',
        'P4 partner courtesy turn',
        'Next corner courtesy turn',
        '[Ends] Opposite neighbor courtesy turn',
        'Bottom couple courtesy turn',
        'Fives courtesy turn to face one of other two couples',
        'Left-end partner and right-end partner courtesy turn',
        'Center people and left-end neighbor courtesy turn',
      ]) {
        test('"$line" stays custom', () {
          final f = parseTcb(line, beats: 4);
          expect(f, isNotNull);
          expect(f!.isCustom, isTrue);
          expect(f.beats, 4);
        });
      }
    },
  );

  group('must stay custom — modifiers the four-slot model cannot express', () {
    test('a rotation amount is never dropped to fit the model', () {
      // 6 corpus lines state an amount. The maintainer's ruling gives this move
      // no `turn` param, so an amount-bearing line must decline rather than
      // structure and lose the amount.
      for (final line in [
        'Partner courtesy turn 3/4',
        "Partner courtesy turn 1 // partner courtesy turn 2 (dancer's choice)",
      ]) {
        final f = parseTcb(line, beats: 4);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
      }
    });

    test('"without hands" is never dropped', () {
      final f = parseTcb('Partner courtesy turn without hands', beats: 3)!;
      expect(f.isCustom, isTrue);
      expect(_text(f).toLowerCase(), contains('without hands'));
    });

    test('a `; face <cardinal>` compound stays WHOLE custom', () {
      // The corpus DOES state cardinal ending facings — but always after a `;`,
      // where the all-or-nothing compound rule keeps the line whole-custom
      // because "face down" structures to nothing. This is the guard that stops
      // a cardinal ever reaching `endFacing`'s dancer domain.
      for (final line in [
        'Ones courtesy turn; face down',
        'Partner courtesy turn (power turn); face out',
        'Partner courtesy turn 2; face clockwise around the major set',
        'Partner courtesy turn (in center); form ring',
      ]) {
        final figs = parseTcbLines(line, beats: 4);
        expect(figs, hasLength(1), reason: line);
        expect(figs.single.isCustom, isTrue, reason: line);
        expect(figs.single.beats, 4, reason: line);
      }
    });

    test('`face` followed by a non-dancer declines the line', () {
      // The requirement that the very next word resolve to a dancer is what
      // keeps a cardinal out of the slot even without the `;` guard.
      final f = parseTcb('Partner courtesy turn, face down', beats: 4)!;
      expect(f.isCustom, isTrue);
    });
  });

  group('annotation preservation — a structured match loses nothing', () {
    // `_stripAnnotations` drops `()`/`[]` for RECOGNITION, so without the TCB
    // front-end's pre-recognizer these 7 corpus lines would structure while
    // silently losing text the custom fallback keeps.
    test('a parenthetical staging note survives as the figure note', () {
      final f = parseTcb('Partner courtesy turn (in center)', beats: 4)!;
      expect(f.move, 'courtesy_turn');
      expect(f.params['who'], 'partners');
      expect(f.note, 'in center');
    });

    test('a bracketed subject and a "(continued)" marker both survive', () {
      final f = parseTcb(
        '[Ones and threes] Partner courtesy turn (continued)',
        beats: 4,
      )!;
      expect(f.move, 'courtesy_turn');
      expect(f.note, 'Ones and threes; continued');
    });

    test('an un-annotated line carries no note', () {
      expect(parseTcb('Partner courtesy turn', beats: 4)!.note, isNull);
    });

    test('the canonical core does NOT preserve annotations (front-end only)', () {
      // Without the TCB front-end there is no annotation reader at all, so the
      // line is simply unrecognised — the preservation belongs to the dialect.
      final f = parseFigureLine('Partner courtesy turn (in center)', beats: 4)!;
      expect(f.isCustom, isTrue);
      expect(_text(f), contains('(in center)'));
    });

    test(
      'the pre-recognizer never claims a line that is not a courtesy turn',
      () {
        // It requires the anchor AND a successful resolution to the move, so an
        // annotated chain line is untouched by it.
        final f = parseTcb(
          '[W1+W2] Ladies chain, with half courtesy turn in center',
          beats: 4,
        )!;
        expect(f.isCustom, isTrue);
      },
    );
  });

  group('renderer', () {
    Figure fig(Map<String, Object?> params) =>
        Figure(move: 'courtesy_turn', params: {'beats': 4, ...params});

    test('canonical is flat and includes the default direction', () {
      // A `renderTemplate` cannot hold a conditional, so the canonical
      // (dedupe/FTS) text carries every slot — exactly as
      // `right_left_through` carries its default `across`. Keeping `direction`
      // here is what stops a counterclockwise courtesy turn deduping as
      // identical to a clockwise one.
      expect(
        renderer.renderCanonical(fig({'who': 'partners'})),
        'partners courtesy turn clockwise',
      );
      expect(
        renderer.renderCanonical(
          fig({'who': 'neighbors', 'direction': 'counterclockwise'}),
        ),
        'neighbors courtesy turn counterclockwise',
      );
      expect(
        renderer.renderCanonical(fig({'endFacing': 'nextNeighbors'})),
        'partners courtesy turn clockwise next neighbors',
      );
    });

    test('display silences clockwise and states counterclockwise', () {
      expect(
        renderer.render(fig({'who': 'partners'}), Dialect.canonical),
        'partner courtesy turn',
      );
      expect(
        renderer.render(
          fig({'who': 'partners', 'direction': 'clockwise'}),
          Dialect.canonical,
        ),
        'partner courtesy turn',
      );
      expect(
        renderer.render(
          fig({'who': 'partners', 'direction': 'counterclockwise'}),
          Dialect.canonical,
        ),
        'partner courtesy turn counterclockwise',
      );
    });

    test('display adds "to face <dancer>" only when endFacing is set', () {
      expect(
        renderer.render(
          fig({'who': 'partners', 'endFacing': 'nextNeighbors'}),
          Dialect.canonical,
        ),
        'partner courtesy turn to face next neighbor',
      );
      expect(
        renderer.render(
          fig({'who': 'partners', 'endFacing': ParamVocab.unspecified}),
          Dialect.canonical,
        ),
        'partner courtesy turn',
      );
    });

    test('display states whom only when it is set', () {
      expect(
        renderer.render(
          fig({'who': 'ones', 'whom': 'twos'}),
          Dialect.canonical,
        ),
        'ones courtesy turn twos',
      );
      expect(
        renderer.render(
          fig({'who': 'ones', 'whom': ParamVocab.unspecified}),
          Dialect.canonical,
        ),
        'ones courtesy turn',
      );
    });

    test('all four optional slots at once, in the ruled order', () {
      expect(
        renderer.render(
          fig({
            'who': 'ones',
            'whom': 'twos',
            'direction': 'counterclockwise',
            'endFacing': 'thirdNeighbors',
          }),
          Dialect.canonical,
        ),
        'ones courtesy turn twos counterclockwise to face third neighbor',
      );
    });

    test('an out-of-domain value is surfaced, never silently dropped', () {
      // Tolerant decode: malformed stored data reads as itself rather than
      // vanishing into a line that looks correct.
      expect(
        renderer.render(
          fig({'who': 'partners', 'direction': 'widdershins'}),
          Dialect.canonical,
        ),
        'partner courtesy turn widdershins',
      );
    });
  });

  group('round-trip and validation', () {
    test('a fully-populated figure survives a JSON round-trip', () {
      final before = Figure(
        move: 'courtesy_turn',
        params: {
          'who': 'ones',
          'whom': 'twos',
          'direction': 'counterclockwise',
          'endFacing': 'nextNeighbors',
          'beats': 6,
        },
        note: 'in center',
      );
      final after = figureFromJson(figureToJson(before));
      expect(after.move, before.move);
      expect(after.params, before.params);
      expect(after.note, 'in center');
      expect(tax.validateFigure(after), isEmpty);
    });

    test('a fully-defaulted figure validates', () {
      expect(
        tax.validateFigure(Figure(move: 'courtesy_turn', params: {'beats': 4})),
        isEmpty,
      );
    });
  });

  group('beat totals are preserved across the whole pipeline', () {
    test('a phrase of mixed structured and custom lines keeps its total', () {
      const lines = {
        'Partner courtesy turn': 4,
        'Partner arky courtesy turn': 4,
        'Ladies chain to partner with double courtesy turn': 8,
        'Ones courtesy turn; face down': 2,
        'N2 neighbor courtesy turn': 6,
      };
      var total = 0;
      for (final entry in lines.entries) {
        final figs = parseTcbLines(entry.key, beats: entry.value);
        total += figs.fold<int>(0, (a, f) => a + f.beats);
      }
      expect(total, lines.values.fold<int>(0, (a, b) => a + b));
    });
  });

  group('parse never fails (OWASP: untrusted import input)', () {
    test('adversarial courtesy-turn shapes never throw', () {
      const hostile = [
        'courtesy turn',
        'courtesy turn courtesy turn courtesy turn',
        'face face face courtesy turn face',
        'courtesy turn face',
        'partner courtesy turn face',
        'courtesy turn, face ',
        '(((courtesy turn)))',
        '[[[partner courtesy turn]]]',
        'partner courtesy turn (((((((((',
        'partner courtesy turn; ; ;',
        'partner courtesy turn || || ||',
        'COURTESY TURN CLOCKWISE COUNTERCLOCKWISE',
        'partner courtesy turn clockwise clockwise clockwise',
        'partner \u0000courtesy\u0000turn',
        'partner courtesy turn \u{1F483}',
        'n2 n3 n0 courtesy turn face n2 n3 n0',
      ];
      for (final raw in hostile) {
        for (final beats in [0, 4, 999, -5]) {
          expect(
            () => parseTcbLines(raw, beats: beats),
            returnsNormally,
            reason: '$raw @ $beats',
          );
          expect(
            () => parseTcb(raw, beats: beats),
            returnsNormally,
            reason: '$raw @ $beats',
          );
        }
      }
    });

    test('a long repeated-annotation line stays bounded and structured', () {
      // The note reader is capped (`_maxAnnotations` / `_maxAnnotationNote`),
      // so a hostile line cannot inflate a note without bound.
      final raw = 'Partner courtesy turn ${'(x)' * 500}';
      final f = parseTcb(raw, beats: 4);
      expect(f, isNotNull);
      expect((f!.note ?? '').length, lessThanOrEqualTo(200));
    });

    test('a rendered figure never throws on garbage params', () {
      final f = Figure(
        move: 'courtesy_turn',
        params: {
          'who': 42,
          'whom': const <String>[],
          'direction': false,
          'endFacing': 3.14,
          'beats': 4,
        },
      );
      expect(() => renderer.renderCanonical(f), returnsNormally);
      expect(() => renderer.render(f, Dialect.canonical), returnsNormally);
    });
  });
}
