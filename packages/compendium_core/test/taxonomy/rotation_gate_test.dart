import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #294 — structured TCB rotation-gate figures (Option B).
///
/// Covers the whole path for the new `rotation_gate` figure kind: the pure
/// ending-facing derivation, the parser recognizer (incl. the three corpus
/// lines and defensive fallback), the display renderer's word order + derived
/// facing clause, and a JSON round-trip that proves the facing is re-derived
/// (never persisted).
String _text(Figure f) => f.params['text'] as String;

void main() {
  group('gateEndFacing — deterministic, never fabricated', () {
    // Convention-INDEPENDENT cases: a full turn returns to the start facing; a
    // half turn faces the opposite way. These hold for cw and ccw alike.
    test('full turn ⇒ unchanged facing (cw/ccw/mirror)', () {
      expect(gateEndFacing(direction: 'clockwise', turn: 1.0), 'in');
      expect(gateEndFacing(direction: 'counterclockwise', turn: 1.0), 'in');
      expect(gateEndFacing(direction: 'mirror', turn: 1.0), 'in');
      // Two full turns (2.0) is still a whole number of turns.
      expect(gateEndFacing(direction: 'clockwise', turn: 2.0), 'in');
    });

    test('half turn ⇒ opposite facing (cw/ccw)', () {
      expect(gateEndFacing(direction: 'clockwise', turn: 0.5), 'out');
      expect(gateEndFacing(direction: 'counterclockwise', turn: 0.5), 'out');
      // 1½ turns is a half turn mod full → opposite.
      expect(gateEndFacing(direction: 'counterclockwise', turn: 1.5), 'out');
    });

    test('custom start orientation flips consistently', () {
      expect(
        gateEndFacing(direction: 'clockwise', turn: 0.5, startFacing: 'up'),
        'down',
      );
      expect(
        gateEndFacing(direction: 'clockwise', turn: 1.0, startFacing: 'up'),
        'up',
      );
    });

    test('convention-dependent quarter/three-quarter turns ⇒ null (no '
        'fabrication)', () {
      expect(gateEndFacing(direction: 'clockwise', turn: 0.25), isNull);
      expect(gateEndFacing(direction: 'counterclockwise', turn: 0.75), isNull);
      expect(gateEndFacing(direction: 'clockwise', turn: 1.25), isNull);
    });

    test('a partial mirror gate has no single ending facing ⇒ null', () {
      expect(gateEndFacing(direction: 'mirror', turn: 0.5), isNull);
      expect(gateEndFacing(direction: 'mirror', turn: 0.75), isNull);
    });

    test('defensive: bad direction / start / turn ⇒ null, never throws', () {
      expect(gateEndFacing(direction: 'sideways', turn: 0.5), isNull);
      expect(gateEndFacing(direction: '', turn: 1.0), isNull);
      expect(
        gateEndFacing(direction: 'clockwise', turn: 0.5, startFacing: 'zzz'),
        isNull,
      );
      expect(gateEndFacing(direction: 'clockwise', turn: 0), isNull);
      expect(gateEndFacing(direction: 'clockwise', turn: -1), isNull);
      // Non-quarter fraction lands on no cardinal facing.
      expect(gateEndFacing(direction: 'clockwise', turn: 0.1), isNull);
    });
  });

  group('parser — rotation_gate (corpus) with beats layered from source', () {
    // These corpus lines are CallersBox/TCB-authored (e.g. #15's `(ones
    // forward)` which-pair annotation), so they are recognised through the
    // relocated CallersBox front-end.
    ({Figure f}) parse(String line, int beats) =>
        (f: parseFigureLine(line, beats: beats, frontEnd: tcbFigureFrontEnd)!);

    test('#15 Back to Dublin: mirror, full turn, 8 beats', () {
      final f = parse('Neighbor mirror gate 1 (ones forward)', 8).f;
      expect(f.isCustom, isFalse);
      expect(f.move, 'rotation_gate');
      expect(f.params['who'], 'neighbors');
      expect(f.params['direction'], 'mirror');
      expect(f.params['turn'], 1.0);
      expect(f.params['beats'], 8); // authored, not fixed
      // The which-pair note is stripped from the structured match.
      expect(f.note, isNull);
    });

    test('#289 Run Around Susie: ccw 3/4, 6 beats', () {
      final f = parse('Partner gate counterclockwise 3/4', 6).f;
      expect(f.move, 'rotation_gate');
      expect(f.params['who'], 'partners');
      expect(f.params['direction'], 'counterclockwise');
      expect(f.params['turn'], 0.75);
      expect(f.params['beats'], 6);
    });

    test('#519 A Rose…: ccw 1/2, 4 beats (both N2 and N3)', () {
      final n2 = parse('N2 neighbor gate counterclockwise 1/2', 4).f;
      expect(n2.move, 'rotation_gate');
      expect(n2.params['who'], 'nextNeighbors');
      expect(n2.params['direction'], 'counterclockwise');
      expect(n2.params['turn'], 0.5);
      expect(n2.params['beats'], 4);

      final n3 = parse('N3 neighbor gate counterclockwise 1/2', 4).f;
      expect(n3.params['who'], 'thirdNeighbors');
      expect(n3.params['beats'], 4);
    });
  });

  group('parser — defensive fallback (OWASP: untrusted import input)', () {
    // A rotation-gate line only structures when it fully resolves to
    // (who, direction, turn); otherwise it degrades to a faithful custom
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

    test('a malformed line preserves its beats on the custom fallback', () {
      final f = parseFigureLine('Partner gate', beats: 6)!;
      expect(f.isCustom, isTrue);
      expect(f.params['beats'], 6);
    });
  });

  group('renderer — display word order + DERIVED facing clause', () {
    final renderer = FigureRenderer(contraTaxonomy);
    Figure gate(String who, String dir, num turn, {int beats = 8}) => Figure(
      move: 'rotation_gate',
      params: {'who': who, 'direction': dir, 'turn': turn, 'beats': beats},
    );

    test(
      'mirror reads BEFORE the move; full turn ⇒ "to face into the set"',
      () {
        final f = gate('neighbors', 'mirror', 1.0);
        expect(
          renderer.render(f, Dialect.canonical),
          'neighbor mirror gate once to face into the set',
        );
        expect(
          renderer.renderVerbose(f, Dialect.canonical),
          'neighbor mirror gate once to face into the set',
        );
      },
    );

    test('half turn ⇒ "to face out of the set"', () {
      final f = gate('nextNeighbors', 'counterclockwise', 0.5, beats: 4);
      expect(
        renderer.render(f, Dialect.canonical),
        'next neighbor gate counterclockwise ½ to face out of the set',
      );
    });

    test('convention-dependent 3/4 ⇒ NO fabricated facing clause', () {
      final f = gate('partners', 'counterclockwise', 0.75, beats: 6);
      final out = renderer.render(f, Dialect.canonical);
      expect(out, 'partner gate counterclockwise ¾');
      expect(out.contains('to face'), isFalse);
    });

    test('canonical render is template-driven: no reorder, no facing', () {
      expect(
        renderer.renderCanonical(gate('neighbors', 'mirror', 1.0)),
        'neighbors gate mirror once',
      );
      expect(
        renderer.renderCanonical(gate('partners', 'counterclockwise', 0.75)),
        'partners gate counterclockwise ¾',
      );
    });
  });

  group('JSON round-trip — facing is derived, not persisted', () {
    test('encode→decode preserves move/params/beats; facing re-derives', () {
      final figures = <Figure>[
        Figure(
          move: 'rotation_gate',
          params: {
            'who': 'neighbors',
            'direction': 'mirror',
            'turn': 1.0,
            'beats': 8,
          },
        ),
        Figure(
          move: 'rotation_gate',
          params: {
            'who': 'nextNeighbors',
            'direction': 'counterclockwise',
            'turn': 0.5,
            'beats': 4,
          },
        ),
      ];
      final decoded = decodeFigures(encodeFigures(figures));
      expect(decoded, figures);

      // No `facing`/`face` key is persisted — the tuple's ending facing is
      // purely derived.
      final json = figureToJson(figures.first);
      final params = json['params'] as Map<String, Object?>;
      expect(params.containsKey('facing'), isFalse);
      expect(params.containsKey('face'), isFalse);

      // The derived facing is identical before and after the round-trip.
      final renderer = FigureRenderer(contraTaxonomy);
      expect(
        renderer.render(decoded.first, Dialect.canonical),
        renderer.render(figures.first, Dialect.canonical),
      );
    });
  });
}
