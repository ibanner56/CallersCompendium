import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// Issue #295 — give the existing `mad_robin` and `butterfly_whirl` moves the
/// params The Caller's Box actually states, so its normalized wordings stop
/// falling to `custom` (taxonomy v20).
///
/// Source evidence (see the v20 note in `contra_taxonomy.dart`):
/// - TCB `Glossary.htm` "Mad robin": "you travel in an oval AROUND THE PERSON
///   AT YOUR SIDE… **Who you go around is listed**… A clockwise mad robin
///   begins with the left-hand person going in front." A 5,147-line TCB sample
///   states BOTH the direction and the "around `<target>`" on 24/24 mad robin
///   lines.
/// - TCB `Glossary.htm` "Butterfly whirl": "Two people face the same
///   direction… and **rotate clockwise or counterclockwise** about a common
///   center." The same sample states BOTH the pair and the direction on 18/18
///   butterfly whirl lines.
/// - ContraDB `libfigure` models NEITHER: `butterfly whirl` is `[beats_4]`
///   alone, and mad robin's `circling` is `once_around` — a
///   `chooser_revolutions` ANGLE in degrees, already carried by our `turn`.
///   ContraDB's mad robin `who` is a third concept again ("`<who>` in front"),
///   which is why TCB's target gets its own `whom` slot.
///
/// Everything added defaults to the `unspecified` sentinel, so a figure that
/// omits it renders byte-identically to v19 — asserted here against the real
/// v19 canonical strings.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  final d = Dialect.canonical;

  Figure? parseTcb(String rawText, {int beats = 0}) =>
      parseFigureLine(rawText, beats: beats, frontEnd: tcbFigureFrontEnd);

  List<Figure> parseTcbLines(String rawText, {int beats = 0}) =>
      parseFigureLines(rawText, beats: beats, frontEnd: tcbFigureFrontEnd);

  group('taxonomy', () {
    test('contraTaxonomyVersion is 30', () {
      expect(contraTaxonomyVersion, 30);
      expect(tax.version, 30);
    });

    test('mad_robin gains direction + whom, keeping who/turn/beats', () {
      final def = tax.resolve('mad_robin')!;
      expect(def.params.keys, ['who', 'turn', 'direction', 'whom', 'beats']);
      expect(def.params['who']!.defaultValue, 'ones');
      expect(def.params['turn']!.defaultValue, 1.0);
      // Issue #739: the NATURAL kind. `direction` wore `ParamKind.choice` from
      // v20 until #726/#736 (editor + validator) and #746 (search facet) taught
      // all three consumers of the kind + `choices` contract to read
      // `spec.choices ?? <fixed vocabulary>` — the workaround's only purpose
      // was to smuggle the sentinel past consumers that ignored `choices`.
      expect(def.params['direction']!.kind, ParamKind.spinDirection);
      expect(def.params['direction']!.defaultValue, ParamVocab.unspecified);
      // ⚠️ The string literals below are DELIBERATE, and the apparent
      // inconsistency with the `ParamVocab.unspecified` on the line above is
      // principled. Two different kinds of assertion live in this file:
      //
      // - IDENTITY ("the default IS the sentinel", "the sentinel validates")
      //   uses `ParamVocab.unspecified`. It expresses intent and stays correct
      //   however the sentinel is spelled.
      // - DOMAIN-CONTENT PINNING (this one: "the declared domain is exactly
      //   these values, in this order") uses literals. Its entire purpose is to
      //   NOTICE when the underlying vocabulary changes.
      //
      // Writing this as `[...ParamVocab.spins, ParamVocab.unspecified]` — the
      // DRY-looking form a reviewer will keep suggesting — makes it
      // self-referential and unable to fail: both sides move together, so a
      // value added to, removed from or reordered within `ParamVocab.spins`
      // would silently change this param's domain with nothing catching it.
      // Measured, not assumed: reordering `ParamVocab.spins` fails these
      // literal assertions in both tests; rewritten in the `spread` form the
      // whole file passes green against that same mutation.
      //
      // So changing `ParamVocab.spins` SHOULD break this test. That is the
      // point of it — do not "fix" it.
      expect(def.params['direction']!.choices, [
        'clockwise',
        'counterclockwise',
        'unspecified',
      ]);
      // The point of the natural kind is that it costs nothing: a typed spin
      // direction still validates the sentinel, because it reads `choices`.
      expect(def.params['direction']!.validate(ParamVocab.unspecified), isTrue);
      expect(def.params['direction']!.validate('sideways'), isFalse);
      expect(def.params['whom']!.kind, ParamKind.dancerSet);
      expect(def.params['whom']!.defaultValue, ParamVocab.unspecified);
      expect(def.goodBeats, [6, 8]);
    });

    test('butterfly_whirl gains who + direction, and NO rotation amount', () {
      final def = tax.resolve('butterfly_whirl')!;
      expect(def.params.keys, ['who', 'direction', 'beats']);
      expect(def.params['who']!.defaultValue, ParamVocab.unspecified);
      expect(def.params['direction']!.defaultValue, ParamVocab.unspecified);
      // Issue #739: shares `_spinOrUnspecified` with `mad_robin.direction`, so
      // it carries the same natural kind and the same sentinel admission.
      expect(def.params['direction']!.kind, ParamKind.spinDirection);
      // Literals again, deliberately — see the note on `mad_robin.direction`
      // above. This is a domain-content pin, not an identity assertion.
      expect(def.params['direction']!.choices, [
        'clockwise',
        'counterclockwise',
        'unspecified',
      ]);
      expect(def.params['direction']!.validate(ParamVocab.unspecified), isTrue);
      // TCB states an amount on only 4/18 lines and no source models one, so
      // there is deliberately no `turn`/`amount` slot (prefer-custom).
      expect(def.params.containsKey('turn'), isFalse);
      expect(def.params.containsKey('amount'), isFalse);
      expect(def.goodBeats, [4]);
    });

    test('both moves validate at their defaults and with stated params', () {
      expect(tax.validateFigure(Figure(move: 'mad_robin')), isEmpty);
      expect(tax.validateFigure(Figure(move: 'butterfly_whirl')), isEmpty);
      expect(
        tax.validateFigure(
          Figure(
            move: 'mad_robin',
            params: const {
              'who': 'role1s',
              'turn': 1.5,
              'direction': 'counterclockwise',
              'whom': 'nextNeighbors',
              'beats': 8,
            },
          ),
        ),
        isEmpty,
      );
      expect(
        tax.validateFigure(
          Figure(
            move: 'butterfly_whirl',
            params: const {
              'who': 'partners',
              'direction': 'clockwise',
              'beats': 4,
            },
          ),
        ),
        isEmpty,
      );
    });

    test('out-of-domain direction/target values are rejected', () {
      Object? severities(Figure f) =>
          tax.validateFigure(f).map((i) => i.severity).toList();
      expect(
        severities(
          // invalid-fixture: value is deliberately out of domain — out-of-domain direction/target values are rejected
          Figure(move: 'mad_robin', params: const {'direction': 'widdershins'}),
        ),
        contains(ValidationSeverity.error),
      );
      // `whom` names a PAIR relationship — never a single dancer, and never
      // `everyone`/`centers`, which cannot be a mad-robin target.
      for (final bad in ['onesRole1', 'everyone', 'centers']) {
        expect(
          severities(
            invalidTestFigure(
              move: 'mad_robin',
              params: {'whom': bad},
              reason:
                  'asserts validateFigure REJECTS a single dancer for whom, which names a pair relationship',
            ),
          ),
          contains(ValidationSeverity.error),
          reason: '$bad must not be a mad robin target',
        );
      }
      expect(
        severities(
          // invalid-fixture: value is deliberately out of domain — out-of-domain direction/target values are rejected
          Figure(move: 'butterfly_whirl', params: const {'who': 'twosRole2'}),
        ),
        contains(ValidationSeverity.error),
      );
    });
  });

  group('renderCanonical is byte-identical for pre-v20 figures', () {
    // The whole point of the `unspecified` sentinel: adding params to the
    // render templates must not disturb the dedupe/FTS key of a single stored
    // figure. These are the exact v19 strings.
    final cases = <String, Figure>{
      'ones mad robin once': Figure(move: 'mad_robin'),
      'ones mad robin 1½': Figure(move: 'mad_robin', params: {'turn': 1.5}),
      'neighbors mad robin once': Figure(
        move: 'mad_robin',
        params: {'who': 'neighbors'},
      ),
      'butterfly whirl': Figure(move: 'butterfly_whirl'),
      'butterfly whirl ': Figure(move: 'butterfly_whirl', params: {'beats': 8}),
    };
    cases.forEach((expected, figure) {
      test('"${expected.trim()}"', () {
        expect(renderer.renderCanonical(figure), expected.trim());
        // Exercising the display paths must never disturb canonical.
        renderer.render(figure, d);
        renderer.renderSummary(figure, d);
        renderer.renderVerbose(figure, d);
        expect(renderer.renderCanonical(figure), expected.trim());
      });
    });

    test(
      'an explicitly-unspecified param renders identically to omitting it',
      () {
        expect(
          renderer.renderCanonical(
            testFigure(
              move: 'butterfly_whirl',
              params: const {
                'who': ParamVocab.unspecified,
                'direction': ParamVocab.unspecified,
              },
            ),
          ),
          renderer.renderCanonical(Figure(move: 'butterfly_whirl')),
        );
      },
    );
  });

  group('renderCanonical carries the stated params', () {
    test('mad robin', () {
      expect(
        renderer.renderCanonical(
          Figure(
            move: 'mad_robin',
            params: const {
              'direction': 'clockwise',
              'turn': 1.5,
              'whom': 'neighbors',
            },
          ),
        ),
        'ones mad robin 1½ clockwise neighbors',
      );
    });

    test('butterfly whirl', () {
      expect(
        renderer.renderCanonical(
          Figure(
            move: 'butterfly_whirl',
            params: const {'who': 'partners', 'direction': 'counterclockwise'},
          ),
        ),
        'partners butterfly whirl counterclockwise',
      );
    });

    test('clockwise and counterclockwise get DISTINCT canonical keys', () {
      Figure whirl(String dir) => testFigure(
        move: 'butterfly_whirl',
        params: {'who': 'partners', 'direction': dir},
      );
      expect(
        renderer.renderCanonical(whirl('clockwise')),
        isNot(renderer.renderCanonical(whirl('counterclockwise'))),
      );
    });
  });

  group('display rendering', () {
    test('bare figures read exactly as they did in v19', () {
      expect(
        renderer.render(Figure(move: 'mad_robin'), d),
        'mad robin, ones in front',
      );
      expect(
        renderer.render(Figure(move: 'butterfly_whirl'), d),
        'butterfly whirl',
      );
    });

    test('mad robin folds the target into the "around" clause', () {
      expect(
        renderer.render(
          Figure(
            move: 'mad_robin',
            params: const {'direction': 'clockwise', 'whom': 'neighbors'},
          ),
          d,
        ),
        'mad robin clockwise around neighbor, ones in front',
      );
      // A stated amount joins the SAME clause — never "1½ around around N".
      expect(
        renderer.render(
          Figure(
            move: 'mad_robin',
            params: const {
              'direction': 'counterclockwise',
              'turn': 1.5,
              'whom': 'partners',
            },
          ),
          d,
        ),
        'mad robin counterclockwise 1½ around partner, ones in front',
      );
    });

    test('mad robin keeps the v19 bare "<turn> around" clause', () {
      expect(
        renderer.render(Figure(move: 'mad_robin', params: {'turn': 1.5}), d),
        'mad robin 1½ around, ones in front',
      );
    });

    test('mad robin never emits a dangling "around" or the sentinel word', () {
      final line = renderer.render(
        Figure(move: 'mad_robin', params: const {'direction': 'clockwise'}),
        d,
      );
      expect(line, 'mad robin clockwise, ones in front');
      expect(line, isNot(contains('around')));
      expect(line, isNot(contains('unspecified')));
    });

    test('butterfly whirl reads as the TCB line, dialect-aware', () {
      final f = Figure(
        move: 'butterfly_whirl',
        params: const {'who': 'role2s', 'direction': 'clockwise'},
      );
      expect(renderer.render(f, d), 'role2s butterfly whirl clockwise');
      expect(
        renderer.render(f, Dialect.larksRobins),
        'robins butterfly whirl clockwise',
      );
    });

    test('an import-assumed mad robin subject is flagged, not stated', () {
      final f = parseTcb('Mad robin clockwise around neighbor')!;
      expect(f.assumedSubject, isTrue);
      expect(renderer.render(f, d), contains('(assumed)'));
      // …but the canonical/dedupe text never carries the marker.
      expect(renderer.renderCanonical(f), isNot(contains('assumed')));
    });

    test('an unexpected imported value is surfaced, never blanked', () {
      expect(
        renderer.render(
          // invalid-fixture: value is deliberately out of domain — an unexpected imported value is surfaced, never blanked
          Figure(
            move: 'mad_robin',
            params: const {'direction': 'someImportedSpin'},
          ),
          d,
        ),
        'mad robin some imported spin, ones in front',
      );
    });
  });

  group('TCB recognition — positives (every sampled wording)', () {
    // Corpus wordings from a 900-id / 5,147-line Caller's Box sample.
    test('"Mad robin clockwise around neighbor"', () {
      final f = parseTcb('Mad robin clockwise around neighbor', beats: 8)!;
      expect(f.move, 'mad_robin');
      expect(f.params['direction'], 'clockwise');
      expect(f.params['whom'], 'neighbors');
      // TCB never states the in-front role, so it must NOT be invented.
      expect(f.params.containsKey('who'), isFalse);
      expect(f.params.containsKey('turn'), isFalse);
      expect(f.beats, 8);
    });

    test('"Mad robin counterclockwise around partner"', () {
      final f = parseTcb('Mad robin counterclockwise around partner')!;
      expect(f.move, 'mad_robin');
      expect(f.params['direction'], 'counterclockwise');
      expect(f.params['whom'], 'partners');
    });

    test('"Mad robin clockwise around neighbor N2" → nextNeighbors', () {
      final f = parseTcb('Mad robin clockwise around neighbor N2', beats: 6)!;
      expect(f.move, 'mad_robin');
      expect(f.params['whom'], 'nextNeighbors');
    });

    test('"Mad robin clockwise 1 & 1/2 around neighbor" → turn 1.5', () {
      final f = parseTcb('Mad robin clockwise 1 & 1/2 around neighbor')!;
      expect(f.move, 'mad_robin');
      expect(f.params['turn'], 1.5);
      expect(f.params['whom'], 'neighbors');
    });

    test('"Mad robin clockwise 1/2 around partner" → turn 0.5', () {
      final f = parseTcb('Mad robin clockwise 1/2 around partner', beats: 3)!;
      expect(f.move, 'mad_robin');
      expect(f.params['turn'], 0.5);
      expect(f.params['direction'], 'clockwise');
    });

    test('a TCB parenthetical is a recognition-only annotation', () {
      // `(facing up)` is stripped for recognition exactly like `(NR)` /
      // `(M1-W2-M2-W1)` elsewhere in the TCB dialect — a deliberate, documented
      // dialect behaviour, not a new source of loss.
      final f = parseTcb(
        'Mad robin counterclockwise around partner (facing up)',
      )!;
      expect(f.move, 'mad_robin');
      expect(f.params['whom'], 'partners');
    });

    test('"Partner butterfly whirl counterclockwise"', () {
      final f = parseTcb('Partner butterfly whirl counterclockwise', beats: 4)!;
      expect(f.move, 'butterfly_whirl');
      expect(f.params['who'], 'partners');
      expect(f.params['direction'], 'counterclockwise');
      expect(f.assumedSubject, isFalse);
      expect(f.beats, 4);
    });

    test('"Neighbor butterfly whirl clockwise"', () {
      final f = parseTcb('Neighbor butterfly whirl clockwise')!;
      expect(f.move, 'butterfly_whirl');
      expect(f.params['who'], 'neighbors');
      expect(f.params['direction'], 'clockwise');
    });

    test('"N2 neighbor butterfly whirl clockwise" → nextNeighbors', () {
      final f = parseTcb('N2 neighbor butterfly whirl clockwise')!;
      expect(f.move, 'butterfly_whirl');
      expect(f.params['who'], 'nextNeighbors');
    });

    test('both N-tag word orders resolve to the SAME relationship', () {
      // "neighbor N2" (mad robin) and "N2 neighbor" (butterfly whirl) are the
      // same TCB relationship and must not disagree.
      expect(
        parseTcb('Mad robin clockwise around neighbor N2')!.params['whom'],
        parseTcb('N2 neighbor butterfly whirl clockwise')!.params['who'],
      );
    });

    test('"CCW"/"CW" shorthands and a spaced "counter clockwise" resolve', () {
      expect(
        parseTcb('Partner butterfly whirl CCW')!.params['direction'],
        'counterclockwise',
      );
      expect(
        parseTcb(
          'Partner butterfly whirl counter clockwise',
        )!.params['direction'],
        'counterclockwise',
      );
      expect(
        parseTcb('Mad robin CW around neighbor')!.params['direction'],
        'clockwise',
      );
    });

    test('a structured match validates cleanly against the taxonomy', () {
      const linesAtTypicalBeats = {
        'Mad robin clockwise around neighbor': 8,
        'Partner butterfly whirl counterclockwise': 4,
      };
      linesAtTypicalBeats.forEach((line, beats) {
        expect(tax.validateFigure(parseTcb(line, beats: beats)!), isEmpty);
      });
    });
  });

  group('TCB recognition — negatives (must stay custom)', () {
    // Prefer-custom: an honest custom figure always beats a confident-but-wrong
    // structured match. Each of these states LESS than the model needs, or MORE
    // than the model carries.
    const mustStayCustom = <String, String>{
      'Mad robin around neighbor': 'no direction stated',
      'Mad robin clockwise': 'no target stated',
      'Mad robin': 'ContraDB-style bare line, neither fact stated',
      'Mad robin clockwise around the hall': 'target is not a dancer set',
      'Mad robin clockwise around neighbor then swing':
          'trailing prose beyond the modeled figure',
      'Partner butterfly whirl': 'no direction stated',
      'Butterfly whirl clockwise': 'no pair stated',
      'Butterfly whirl': 'ContraDB-style bare line, neither fact stated',
      'Partner butterfly whirl counterclockwise 1 & 1/2':
          'rotation amount is not modeled for this move',
      'Partner butterfly whirl counterclockwise 2, shifting right to N2':
          'amount plus an unmodeled shift clause',
    };
    mustStayCustom.forEach((line, why) {
      test('"$line" stays custom ($why)', () {
        final f = parseTcb(line, beats: 4)!;
        expect(f.isCustom, isTrue, reason: why);
        // Parse-never-fails: the source text survives verbatim (modulo the
        // scrub's case-insensitive "mad robin" term normalisation) — nothing
        // is dropped, reordered, or structured away.
        expect(f.params['text'], equalsIgnoringCase(line));
      });
    });
  });

  group('composition with the TCB line operators', () {
    test('a ";" compound splits, both clauses structuring', () {
      // Real corpus line (with its parenthetical annotation).
      final figs = parseTcbLines(
        'Mad robin counterclockwise around partner (facing down); turn alone (ccw)',
        beats: 8,
      );
      expect(figs.map((f) => f.move), ['mad_robin', 'turn_alone']);
      // Lossless beats: the source's single total rides on the first clause.
      expect(figs.map((f) => f.beats), [8, 0]);
    });

    test('a "||" line fans into a meanwhile container', () {
      final figs = parseTcbLines(
        'Partner butterfly whirl clockwise || Neighbor butterfly whirl counterclockwise',
        beats: 8,
      );
      expect(figs, hasLength(1));
      final container = figs.single;
      expect(container.isMeanwhile, isTrue);
      expect(container.beats, 8);
      expect(container.subFigures.map((f) => f.move), [
        'butterfly_whirl',
        'butterfly_whirl',
      ]);
      expect(container.subFigures.map((f) => f.params['direction']), [
        'clockwise',
        'counterclockwise',
      ]);
    });
  });

  group('ContraDB keeps asserting nothing', () {
    // ContraDB models neither concept, so its reverse-render dialect must not
    // acquire one — an imported ContraDB figure stays at the sentinel.
    test('"mad robin, ladles in front" carries no direction or target', () {
      final f = parseFigureLine(
        'mad robin, ladles in front',
        frontEnd: contraDbHtmlFigureFrontEnd,
      )!;
      expect(f.move, 'mad_robin');
      expect(f.params['who'], 'role2s');
      expect(f.params.containsKey('direction'), isFalse);
      expect(f.params.containsKey('whom'), isFalse);
      expect(renderer.renderCanonical(f), 'role2s mad robin once');
    });

    test('"butterfly whirl" carries no pair or direction', () {
      final f = parseFigureLine(
        'butterfly whirl',
        frontEnd: contraDbHtmlFigureFrontEnd,
      )!;
      expect(f.move, 'butterfly_whirl');
      expect(f.params.containsKey('who'), isFalse);
      expect(f.params.containsKey('direction'), isFalse);
      expect(renderer.renderCanonical(f), 'butterfly whirl');
    });
  });
}
