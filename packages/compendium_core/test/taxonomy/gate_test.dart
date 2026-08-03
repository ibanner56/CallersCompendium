import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/testing.dart';

/// The UNIFIED `gate` move (taxonomy v22) — the merge of ContraDB's `gate` and
/// the TCB-only `rotation_gate` (issue #294) into one figure carrying a
/// direction, a duration AND an ending facing.
///
/// Covers the whole path: the merged param model, both importers' halves, the
/// display renderer's word order + STORED facing clause, and a JSON round-trip.
///
/// The headline behaviour change is the ending facing. Before v22 it was
/// DERIVED at render time from a nominal `in` start orientation, so every 1/2
/// gate rendered "to face out of the set" — including after a down-the-hall,
/// where dancers face down and a half turn ends facing **up**. The derivation is
/// withdrawn (see `gate_facing.dart`); the facing is stored, and a source that
/// does not state one leaves it unspecified rather than guessing.
String _text(Figure f) => f.params['text'] as String;

void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);

  group('merged move — one gate, three sources of truth', () {
    test('there is exactly ONE move displaying "gate"', () {
      final gates = tax.moves.values
          .where((m) => m.displayName == 'gate')
          .map((m) => m.id)
          .toList();
      expect(gates, ['gate']);
      // The retired TCB-only move is gone (stored figures are migrated by
      // CompendiumDatabase schema v20).
      expect(tax.resolve('rotation_gate'), isNull);
    });

    test(
      'every slot defaults to unspecified — a bare gate asserts nothing',
      () {
        final def = tax.resolve('gate')!;
        for (final name in [
          'who',
          'whom',
          'pair',
          'direction',
          'turn',
          'face',
        ]) {
          expect(
            def.params[name]?.defaultValue,
            ParamVocab.unspecified,
            reason: '$name must default to the unspecified sentinel',
          );
        }
        expect(def.params['beats']?.defaultValue, 8);
        expect(renderer.renderCanonical(Figure(move: 'gate')), 'gate');
      },
    );

    test('defaults validate (incl. the rotation sentinel on `turn`)', () {
      final figure = Figure(move: 'gate');
      final issues = tax.validateFigure(
        testFigure(move: 'gate', params: tax.effectiveParams(figure)),
      );
      expect(
        issues.where((i) => i.severity == ValidationSeverity.error),
        isEmpty,
      );
    });

    test('`turn` accepts real rotations AND the sentinel, nothing else', () {
      final spec = tax.resolve('gate')!.params['turn']!;
      expect(spec.validate(0.5), isTrue);
      expect(spec.validate(1.25), isTrue);
      expect(spec.validate(ParamVocab.unspecified), isTrue);
      expect(spec.validate('anything else'), isFalse);
      expect(spec.validate(0.1), isFalse);
      // The opt-in is per-spec: a rotation without the sentinel in `choices`
      // keeps the strict numeric domain.
      expect(
        tax
            .resolve('mad_robin')!
            .params['turn']!
            .validate(ParamVocab.unspecified),
        isFalse,
      );
    });

    test('goodBeats spans both sources (ContraDB 8; TCB 2/3/4/6/8)', () {
      expect(tax.resolve('gate')!.goodBeats, [2, 3, 4, 6, 8]);
    });

    test('mirror survives the merge — it has no ContraDB equivalent', () {
      expect(
        tax.resolve('gate')!.params['direction']!.choices,
        containsAll(['clockwise', 'counterclockwise', 'mirror']),
      );
    });
  });

  group('ContraDB half — who backs up, whom walks forward, face ENDS', () {
    // libfigure `figure.js:844`: "'ones gate twos' means: ones, extend a hand to
    // twos - twos walk forward, ones back up, orbiting around the joined hands".
    // libfigure `figure.js:841` renders the facing after the literal words "to
    // face", over `{up: "up the set", …}` (`param.js:711`) — so `face` is the
    // ENDING facing, not a direction of travel.
    Figure contraDbGate({String face = 'up'}) => testFigure(
      move: 'gate',
      params: {'who': 'ones', 'whom': 'neighbors', 'face': face, 'beats': 8},
    );

    test('renders ContraDB word order with the stored ending facing', () {
      expect(
        renderer.render(contraDbGate(), Dialect.canonical),
        'ones gate neighbor to face up the hall',
      );
      expect(
        renderer.render(contraDbGate(face: 'out'), Dialect.canonical),
        'ones gate neighbor to face out of the set',
      );
    });

    test('canonical render stays template-driven', () {
      expect(
        renderer.renderCanonical(contraDbGate()),
        'ones gate neighbors up',
      );
    });

    test('a ContraDB gate asserts NO rotation sense or amount', () {
      final params = tax.effectiveParams(contraDbGate());
      expect(params['direction'], ParamVocab.unspecified);
      expect(params['turn'], ParamVocab.unspecified);
      expect(params['pair'], ParamVocab.unspecified);
    });
  });

  group('TCB half — the subject is the PAIRING (`pair`), never `who`', () {
    // TCB names who you gate WITH; ContraDB's `who` names the side that backs
    // up, and its domain (libfigure `chooser.js:114` `chooser_pair`) cannot even
    // hold `neighbors`/`partners`. Writing TCB's subject into `who` would
    // silently reinterpret every imported TCB gate.
    ({Figure f}) parse(String line, int beats) =>
        (f: parseFigureLine(line, beats: beats, frontEnd: tcbFigureFrontEnd)!);

    test('#15 Back to Dublin: mirror, full turn, 8 beats', () {
      final f = parse('Neighbor mirror gate 1 (ones forward)', 8).f;
      expect(f.isCustom, isFalse);
      expect(f.move, 'gate');
      expect(f.params['pair'], 'neighbors');
      expect(f.params.containsKey('who'), isFalse);
      expect(f.params['direction'], 'mirror');
      expect(f.params['turn'], 1.0);
      expect(f.params['beats'], 8); // authored, not fixed
      // v22: "(ones forward)" is STRUCTURED onto `whom` — which means exactly
      // "the side that walks forward" (libfigure figure.js:844), so this is
      // source-verified, not inferred. Before v22 every structured gate simply
      // dropped it.
      expect(f.params['whom'], 'ones');
      // Consumed into a param, so it is not ALSO duplicated as a note.
      expect(f.note, isNull);
    });

    test('#289 Run Around Susie: ccw 3/4, 6 beats', () {
      final f = parse('Partner gate counterclockwise 3/4', 6).f;
      expect(f.move, 'gate');
      expect(f.params['pair'], 'partners');
      expect(f.params['direction'], 'counterclockwise');
      expect(f.params['turn'], 0.75);
      expect(f.params['beats'], 6);
      // No annotation on this line → no note, and never an invented one.
      expect(f.note, isNull);
    });

    test('#519 A Rose…: ccw 1/2, 4 beats (both N2 and N3)', () {
      final n2 = parse('N2 neighbor gate counterclockwise 1/2', 4).f;
      expect(n2.move, 'gate');
      expect(n2.params['pair'], 'nextNeighbors');
      expect(n2.params['direction'], 'counterclockwise');
      expect(n2.params['turn'], 0.5);
      expect(n2.params['beats'], 4);

      final n3 = parse('N3 neighbor gate counterclockwise 1/2', 4).f;
      expect(n3.params['pair'], 'thirdNeighbors');
      expect(n3.params['beats'], 4);
    });

    test('a TCB gate never fabricates an ending facing', () {
      final f = parse('Partner gate counterclockwise 1/2', 4).f;
      expect(f.params.containsKey('face'), isFalse);
      expect(tax.effectiveParams(f)['face'], ParamVocab.unspecified);
    });

    test('a "<dancers> forward" annotation structures onto whom', () {
      for (final c in const [
        (line: 'Neighbor mirror gate 3/4 (twos forward)', whom: 'twos'),
        (line: 'Neighbor mirror gate 1 (ones forward)', whom: 'ones'),
      ]) {
        final f = parse(c.line, 4).f;
        expect(f.move, 'gate', reason: c.line);
        expect(f.params['whom'], c.whom, reason: c.line);
        expect(f.note, isNull, reason: c.line);
      }
    });

    test('a STATIONARY annotation never structures a dancer slot', () {
      // `whom` walks forward; `who` extends a hand and backs up. BOTH move, so
      // "stay put" / "are posts" matches neither and must never be structured.
      // Notes carry the POST-SCRUB text, so gendered terms have already become
      // canonical role tokens (women -> role2s) by the time they land here.
      for (final c in const [
        (
          line: 'Neighbor mirror gate 1/2 (women are posts)',
          note: 'role2s are posts',
        ),
        (
          line: 'Neighbor gate clockwise 1/4 (centers are posts)',
          note: 'centers are posts',
        ),
      ]) {
        final f = parse(c.line, 4).f;
        expect(f.move, 'gate', reason: c.line);
        expect(f.params.containsKey('whom'), isFalse, reason: c.line);
        expect(f.params.containsKey('who'), isFalse, reason: c.line);
        // Nothing is lost: the words ride along verbatim as the note.
        expect(f.note, c.note, reason: c.line);
      }
    });

    test("TCB's two-argument gate form stays custom (not half-structured)", () {
      // "Men gate partner …" names a subject AND an object. The shared grammar
      // resolves only the pairing form, so the leftover "partner" forces the
      // custom fallback rather than a figure missing one of its dancers.
      final f = parseFigureLine(
        'Men gate partner counterclockwise 1/2 (men stay put)',
        beats: 4,
        frontEnd: tcbFigureFrontEnd,
      )!;
      expect(f.isCustom, isTrue);
      // Post-scrub, so "men" is already the canonical role token.
      expect(_text(f).toLowerCase(), contains('role1s stay put'));
    });

    test('a "forward" annotation naming an unmodelled set stays note-only', () {
      // These DO say "forward", but name no dancer set our vocabulary models,
      // so they are preserved verbatim rather than approximated.
      for (final line in const [
        'Partner mirror gate 3/4 (M1+W2 forward)',
        'Neighbor mirror gate 1/2 (ends forward)',
        'Neighbor mirror gate 1 (twos and fours forward)',
      ]) {
        final f = parse(line, 4).f;
        expect(f.move, 'gate', reason: line);
        expect(f.params.containsKey('whom'), isFalse, reason: line);
        expect(f.note, isNotNull, reason: line);
        expect(
          line.toLowerCase(),
          contains(f.note!.toLowerCase()),
          reason: 'the note must be verbatim source text ($line)',
        );
      }
    });

    // The #717 interaction (issue #715). A preserved annotation is stored
    // POST-SCRUB, so a gendered source term is already a canonical role token by
    // the time it lands in the note. Since #717 routes figure notes through
    // `renderFreeText` on the display/export paths, that token is dialect-
    // rendered for the user — which is exactly right, and is the whole point of
    // #715. Pinned here because it is the class of bug that passes under the
    // canonical dialect and silently differs under every other one: the STORED
    // note must stay canonical, and only the RENDER may vary.
    test('a preserved annotation stays canonical in storage and is '
        'dialect-rendered for the reader', () {
      final f = parse('Neighbor mirror gate 1/2 (women are posts)', 4).f;
      expect(f.note, 'role2s are posts');

      expect(
        renderer.renderFreeText(f.note!, Dialect.canonical),
        'role2s are posts',
      );
      final dialectal = renderer.renderFreeText(f.note!, Dialect.larksRobins);
      expect(dialectal, 'robins are posts');
      // The canonical token must never reach the reader.
      expect(dialectal, isNot(contains('role2s')));
    });

    test(
      'an annotation with no role token is byte-identical in any dialect',
      () {
        final f = parse('Neighbor mirror gate 1/2 (ends forward)', 4).f;
        expect(f.note, 'ends forward');
        for (final d in [Dialect.canonical, Dialect.larksRobins]) {
          expect(renderer.renderFreeText(f.note!, d), 'ends forward');
        }
      },
    );

    test('a multi-annotation line keeps whatever it does NOT structure', () {
      final f = parse(
        '[Ones and twos] Neighbor mirror gate 3/4 (twos forward)',
        4,
      ).f;
      expect(f.move, 'gate');
      expect(f.params['pair'], 'neighbors');
      expect(f.params['whom'], 'twos'); // consumed
      expect(f.note, 'Ones and twos'); // not consumed → preserved verbatim
    });
  });

  group('parser — defensive fallback (OWASP: untrusted import input)', () {
    // A TCB gate line only structures when it fully resolves to
    // (pair, direction, turn); otherwise it degrades to a faithful custom
    // figure. The parser must never throw on adversarial input.
    const stayCustom = <String>[
      'gate',
      'Partner gate',
      'Partner gate counterclockwise', // no fraction
      'Partner gate 3/4', // no direction
      'Neighbor gate up', // ContraDB facing token, not a rotation qualifier
      'Partner gate counterclockwise 3/4 and swing', // trailing move
      'gate mirror mirror mirror 9/9', // adversarial repetition / bad fraction
      'Partner gate counterclockwise 999', // absurd amount (not a valid turn)
      r'Partner gate counterclockwise 3/4 <script>alert(1)</script>',
    ];
    for (final line in stayCustom) {
      test('"$line" stays custom (no throw)', () {
        final f = parseFigureLine(line, beats: 8);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
        // The original text is preserved on the custom fallback.
        expect(_text(f), isNotEmpty, reason: line);
      });
    }

    // The same lines must also degrade through the TCB front-end, where the
    // annotation pre-recognizer runs first: a line it cannot fully resolve must
    // fall through, never half-structure.
    for (final line in const [
      'gate (ones forward)',
      'Partner gate (men stay put)',
      'Neighbor gate up (ones forward)',
    ]) {
      test('"$line" stays custom through the TCB front-end (no throw)', () {
        final f = parseFigureLine(line, beats: 8, frontEnd: tcbFigureFrontEnd);
        expect(f, isNotNull, reason: line);
        expect(f!.isCustom, isTrue, reason: line);
        // The annotation survives verbatim on the custom text.
        expect(_text(f), contains('('), reason: line);
      });
    }

    test('a pathological annotation run is bounded and never throws', () {
      final line = 'Neighbor gate counterclockwise 1/2 ${'(x)' * 5000}';
      final f = parseFigureLine(line, beats: 4, frontEnd: tcbFigureFrontEnd);
      expect(f, isNotNull);
      // Whatever it resolves to, the note can never grow unbounded.
      expect((f!.note ?? '').length, lessThanOrEqualTo(200));
    });

    test('a truncated note never splits a surrogate pair', () {
      // Astral-plane characters are 2 UTF-16 code units each; a naive
      // `substring(0, 200)` would leave a lone surrogate at the cut.
      final line = 'Neighbor gate counterclockwise 1/2 (${'\u{1F483}' * 300})';
      final f = parseFigureLine(line, beats: 4, frontEnd: tcbFigureFrontEnd);
      expect(f, isNotNull);
      final note = f!.note ?? '';
      expect(note.length, lessThanOrEqualTo(200));
      for (final unit in note.codeUnits) {
        // No unpaired high surrogate can survive: re-decoding must round-trip.
        expect(unit, isNot(inInclusiveRange(0xDC00, 0xDFFF)));
      }
      expect(String.fromCharCodes(note.runes), note);
    });

    test('an unterminated annotation never throws', () {
      for (final line in const [
        'Neighbor gate counterclockwise 1/2 (ones forward',
        'Neighbor gate counterclockwise 1/2 [[[[',
        'Neighbor gate counterclockwise 1/2 ()',
      ]) {
        expect(
          () => parseFigureLine(line, beats: 4, frontEnd: tcbFigureFrontEnd),
          returnsNormally,
          reason: line,
        );
      }
    });

    test('a malformed line preserves its beats on the custom fallback', () {
      final f = parseFigureLine('Partner gate', beats: 6)!;
      expect(f.isCustom, isTrue);
      expect(f.params['beats'], 6);
    });
  });

  group('renderer — display word order + STORED facing clause', () {
    Figure gate(String pair, String dir, num turn, {int beats = 8}) =>
        testFigure(
          move: 'gate',
          params: {
            'pair': pair,
            'direction': dir,
            'turn': turn,
            'beats': beats,
          },
        );

    test('mirror reads BEFORE the move name', () {
      final f = gate('neighbors', 'mirror', 1.0);
      expect(
        renderer.render(f, Dialect.canonical),
        'neighbor mirror gate once',
      );
      expect(
        renderer.renderVerbose(f, Dialect.canonical),
        'neighbor mirror gate once',
      );
    });

    test('clockwise/counterclockwise read AFTER the move name', () {
      expect(
        renderer.render(
          gate('partners', 'counterclockwise', 0.75),
          Dialect.canonical,
        ),
        'partner gate counterclockwise ¾',
      );
    });

    // THE BUG THIS UNIT FIXES. Before v22 this rendered
    // "next neighbor gate counterclockwise ½ to face out of the set", derived
    // from a nominal `in` start orientation. That claim is wrong whenever the
    // dancers did not arrive facing across — e.g. straight after a
    // down-the-hall, where a half turn ends facing UP, not out. TCB states no
    // ending facing for a gate, so the correct render states none.
    test('a half turn no longer fabricates "to face out of the set"', () {
      final f = gate('nextNeighbors', 'counterclockwise', 0.5, beats: 4);
      final out = renderer.render(f, Dialect.canonical);
      expect(out, 'next neighbor gate counterclockwise ½');
      expect(out, isNot(contains('to face')));
    });

    test('a half turn after a down-the-hall can be corrected to "up"', () {
      // The user (or a source that states it) supplies the real facing, and it
      // renders exactly as authored — no geometry guess in the way.
      final f = Figure(
        move: 'gate',
        params: {
          'pair': 'nextNeighbors',
          'direction': 'counterclockwise',
          'turn': 0.5,
          'face': 'up',
          'beats': 4,
        },
      );
      expect(
        renderer.render(f, Dialect.canonical),
        'next neighbor gate counterclockwise ½ to face up the hall',
      );
    });

    test('a TCB gate states its forward-walking side as a trailing clause', () {
      // ContraDB's "<who> gate <whom>" only reads as "whom walks forward" when
      // a subject precedes it. A TCB gate names the pairing instead, so the
      // forward side is stated explicitly, mirroring the source's own wording.
      final f = Figure(
        move: 'gate',
        params: {
          'pair': 'neighbors',
          'direction': 'mirror',
          'turn': 1.0,
          'whom': 'ones',
          'beats': 8,
        },
      );
      expect(
        renderer.render(f, Dialect.canonical),
        'neighbor mirror gate once, ones forward',
      );
    });

    test('convention-dependent 3/4 still shows no facing clause', () {
      final out = renderer.render(
        gate('partners', 'counterclockwise', 0.75, beats: 6),
        Dialect.canonical,
      );
      expect(out, 'partner gate counterclockwise ¾');
      expect(out.contains('to face'), isFalse);
    });

    test(
      'canonical render is template-driven: no reorder, no facing clause',
      () {
        expect(
          renderer.renderCanonical(gate('neighbors', 'mirror', 1.0)),
          'neighbors gate mirror once',
        );
        expect(
          renderer.renderCanonical(gate('partners', 'counterclockwise', 0.75)),
          'partners gate counterclockwise ¾',
        );
      },
    );

    test('an unexpected direction surfaces rather than vanishing', () {
      // invalid-fixture: value is deliberately out of domain — an unexpected direction surfaces rather than vanishing
      final f = Figure(
        move: 'gate',
        params: {'pair': 'neighbors', 'direction': 'sideways', 'turn': 0.5},
      );
      expect(renderer.render(f, Dialect.canonical), contains('sideways'));
    });

    test('an unknown face token renders no clause (tolerant decode)', () {
      // invalid-fixture: value is deliberately out of domain — an unknown face token renders no clause (tolerant decode)
      final f = Figure(
        move: 'gate',
        params: {
          'pair': 'neighbors',
          'direction': 'mirror',
          'turn': 1.0,
          'face': 'sideways',
        },
      );
      // Allow-listed like `swing.endFacing`: a facing is a closed cardinal
      // vocabulary, so an out-of-domain token is never injected into the line.
      final out = renderer.render(f, Dialect.canonical);
      expect(out, 'neighbor mirror gate once');
      expect(out, isNot(contains('to face')));
    });
  });

  group('JSON round-trip — the facing is STORED, not derived', () {
    test('encode→decode preserves move/params/beats including `face`', () {
      final figures = <Figure>[
        Figure(
          move: 'gate',
          params: {
            'pair': 'neighbors',
            'direction': 'mirror',
            'turn': 1.0,
            'beats': 8,
          },
          note: 'ones forward',
        ),
        Figure(
          move: 'gate',
          params: {
            'who': 'ones',
            'whom': 'neighbors',
            'face': 'up',
            'beats': 8,
          },
        ),
      ];
      final decoded = decodeFigures(encodeFigures(figures));
      expect(decoded, figures);

      // The authored facing IS persisted now — that is the whole point of the
      // merge; it can no longer drift or be re-derived from a wrong assumption.
      final json = figureToJson(figures[1]);
      final params = json['params'] as Map<String, Object?>;
      expect(params['face'], 'up');

      final r = FigureRenderer(contraTaxonomy);
      for (var i = 0; i < figures.length; i++) {
        expect(
          r.render(decoded[i], Dialect.canonical),
          r.render(figures[i], Dialect.canonical),
        );
      }
    });
  });
}
