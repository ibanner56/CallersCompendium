import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../figures_support.dart';

/// Issue #2331 — The Caller's Box long waves.
///
/// Maintainer rulings these pin:
/// - A bare `form long wave` is the long waves along the sides of the set
///   (`form_long_waves`). Forming a long wave in the centre is a different
///   figure (`form_a_long_wave`), which `form long wave in center` names.
/// - The balance after a bare long wave is the same figure — even when it
///   opens the next phrase. There is never a long-waves figure followed by a
///   second, balanced one.
/// - `(N2R,N1L, women face in)` is next neighbors by the right, neighbors by
///   the left, women facing in (men facing out): `whom`, `whomHand`, `whom2`.
/// - When the balance says the wave is `in center`, the follower decides: the
///   pair reads as the centre wave, exactly as `form long wave in center` and
///   that balance do.
///
/// Phrases are verbatim from the dance named, unless marked otherwise.
Future<List<Figure>> _import(Map<String, List<String>> phrases) async {
  final payload = jsonEncode({
    'ID': '42',
    'Name': 'Test Dance',
    'Permission': 'full',
    'phrases': [
      for (final e in phrases.entries) {'name': e.key, 'figures': e.value},
    ],
  });
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return figuresOf(adapter.parse(raw).dance);
}

int _total(List<Figure> figures) => figures.fold(0, (a, f) => a + f.beats);

List<String> _labels(List<Figure> figures) => [
  for (final s in deriveSections(figures, PhraseStructure.standard)) s.label,
];

void _expectLongWaves(Figure f, Map<String, Object?> params) {
  expect(f.move, 'form_long_waves');
  expect(f.params.keys.toSet(), params.keys.toSet());
  for (final e in params.entries) {
    expect(f.params[e.key], e.value, reason: e.key);
  }
}

const _unspecified = ParamVocab.unspecified;

void main() {
  group('a bare "form long wave" is the long waves at the sides', () {
    List<Figure> parse(String line) =>
        parseFigureLines(line, beats: 8, frontEnd: tcbFigureFrontEnd);

    test('alone it states no facing', () {
      final f = parse('form long wave').single;
      _expectLongWaves(f, {'who': _unspecified, 'beats': 8});
      expect(
        FigureRenderer(contraTaxonomy).render(f, Dialect.canonical),
        'form long waves',
      );
    });

    test('as the tail of a ;-compound it carries no beats', () {
      final figures = parse('Men left shoulder round 1; form long wave');
      expect(figures.map((f) => f.move), ['shoulder_round', 'form_long_waves']);
      expect(figures.last.params, {'who': _unspecified});
    });

    test('a prose annotation is kept as the note', () {
      final f = parse('form long wave (release right hands)').single;
      expect(f.move, 'form_long_waves');
      expect(f.note, 'release right hands');
    });

    test('"in center" is the centre wave, a different figure', () {
      expect(parse('form long wave in center').single.move, 'form_a_long_wave');
      expect(parse('Form a long wave').single.move, 'form_a_long_wave');
    });

    for (final line in const [
      // Dance 3484's bracket, alone and after a clause that structures (the
      // dance's own first clause, `Neighbor arm right 1`, does not).
      'form long wave [M1 with N2, W1 with N1]',
      'Neighbor allemande right 1; form long wave [M1 with N2, W1 with N1]',
      // Not corpus wording: holds that do not decode — a role code, two
      // holds by one hand, the same pair twice, three pairs, two hold
      // annotations.
      'form long wave (WL, role2s face in)',
      'form long wave (P2L,P3L, women face in)',
      'form long wave (P2L,P2R)',
      'form long wave (P1L,P2R,P3L)',
      'form long wave (P2L) (P3R)',
    ]) {
      test('"$line" keeps its holds as text', () {
        final figures = parse(line);
        expect(figures.any((f) => f.move == 'form_a_long_wave'), isFalse);
        expect(figures.any((f) => f.move == 'form_long_waves'), isFalse);
        expect(figures.single.isCustom, isTrue);
      });
    }

    group('holds on the forming line read as on its balance', () {
      // Maintainer (2026-11-23, #2331 follow-up): the annotation means the
      // same on `form long wave` as on `Balance long wave`.
      const cases = <String, Map<String, Object?>>{
        // Dance 10547.
        'form long wave (P2L, P3R, women face in)': {
          'whom': 'nextPartners',
          'whomHand': 'left',
          'whom2': 'thirdPartners',
          'who': 'role2s',
        },
        // Dance 15139.
        'Form long wave (P2R,P1L, men face in)': {
          'whom': 'nextPartners',
          'whomHand': 'right',
          'whom2': 'partners',
          'who': 'role1s',
        },
        // Dance 16002.
        'form long wave (N2R, women face in)': {
          'whom': 'nextNeighbors',
          'whomHand': 'right',
          'who': 'role2s',
        },
        // Dance 1210: no facing stated.
        'form long wave (P2L,P3R)': {
          'whom': 'nextPartners',
          'whomHand': 'left',
          'whom2': 'thirdPartners',
          'who': _unspecified,
        },
      };
      cases.forEach((line, params) {
        test(line, () {
          final f = parse(line).single;
          expect(f.move, 'form_long_waves');
          expect({...f.params}..remove('beats'), params);
        });
      });

      test('dance 16002 B2: the swing before it structures too', () {
        final figures = parse(
          'N2 neighbor swing; form long wave (N2R, women face in)',
        );
        expect(figures.map((f) => f.move), ['swing', 'form_long_waves']);
        expect(figures.last.params['whom'], 'nextNeighbors');
      });
    });

    test('"Women walk forward; form long wave" (dance 130) stays text', () {
      // The walk-forward fold reads only the centre wave, whose subject is who
      // dances in; nothing says who faces in at the sides.
      expect(
        parse('Women walk forward; form long wave').single.isCustom,
        isTrue,
      );
    });
  });

  group('the balance after it folds in, keeping every word', () {
    test('dance 2635 A2: (N2R,N1L, women face in) is both hands', () async {
      final figures = await _import({
        'A2': [
          '(8) Men left shoulder round 1; form long wave',
          '(4) Balance long wave (N2R,N1L, women face in)',
          '(2) N2 neighbor allemande right 1/2',
          '(2) Men cross by right',
        ],
      });
      expect(figures.map((f) => f.move), [
        'shoulder_round',
        'form_long_waves',
        'allemande',
        'pass_by',
      ]);
      _expectLongWaves(figures[1], {
        'who': 'role2s',
        'whom': 'nextNeighbors',
        'whomHand': 'right',
        'whom2': 'neighbors',
        'balance': true,
        'beats': 4,
      });
      expect(figures.any((f) => f.isCustom), isFalse);
      expect(_total(figures), 16);
    });

    test('dance 2636 A2', () async {
      final figures = await _import({
        'A2': [
          '(8) Men seesaw; face out; form long wave',
          '(4) Balance long wave (N2R,N1L, women face in)',
          '(2) N2 neighbor allemande right 1/2',
          '(2) Men cross by right',
        ],
      });
      _expectLongWaves(figures[1], {
        'who': 'role2s',
        'whom': 'nextNeighbors',
        'whomHand': 'right',
        'whom2': 'neighbors',
        'balance': true,
        'beats': 4,
      });
      expect(_total(figures), 16);
    });

    test('dance 3672: one hold, (NR, women face in)', () async {
      final figures = await _import({
        'B1': [
          '(8) Neighbor do-si-do; form long wave',
          '(4) Balance long wave (NR, women face in)',
        ],
      });
      expect(figures, hasLength(2));
      _expectLongWaves(figures.last, {
        'who': 'role2s',
        'whom': 'neighbors',
        'whomHand': 'right',
        'balance': true,
        'beats': 4,
      });
    });

    test('the hands may be listed left first (dance 6403 shape)', () async {
      final figures = await _import({
        'A1': [
          '(8) Neighbor do-si-do; form long wave',
          '(4) Balance long wave (N1L,N2R, men face in)',
        ],
      });
      _expectLongWaves(figures.last, {
        'who': 'role1s',
        'whom': 'neighbors',
        'whomHand': 'left',
        'whom2': 'nextNeighbors',
        'balance': true,
        'beats': 4,
      });
    });

    test("the forming line's note survives the fold", () async {
      // Not corpus wording: dance 11820's annotation on a simpler first
      // clause, so the line structures.
      final figures = await _import({
        'B2': [
          '(8) Neighbor do-si-do; form long wave (release right hands)',
          '(4) Balance long wave (P1L,P2R, women face in)',
        ],
      });
      _expectLongWaves(figures.last, {
        'who': 'role2s',
        'whom': 'partners',
        'whomHand': 'left',
        'whom2': 'nextPartners',
        'balance': true,
        'beats': 4,
      });
      expect(figures.last.note, 'release right hands');
    });

    test('a bare "Balance long wave" folds in as the balance alone', () async {
      // Not corpus wording.
      final figures = await _import({
        'A1': [
          '(8) Neighbor do-si-do; form long wave',
          '(4) Balance long wave',
        ],
      });
      _expectLongWaves(figures.last, {
        'who': _unspecified,
        'balance': true,
        'beats': 4,
      });
    });

    for (final balance in const [
      // A dancer prefix and no hold: a balance by one role, which long waves
      // cannot say.
      '(4) Men balance long wave',
      '(4) Women balance long wave',
      // Words the fold would drop. (`for all` keeps the wave's line as text
      // too: see the `for all` group.)
      '(4) Balance long wave (1R)',
    ]) {
      test('"$balance" after a bare long wave stays text', () async {
        // Not corpus wording.
        final figures = await _import({
          'A1': ['(8) Neighbor do-si-do; form long wave', balance],
        });
        expect(figures, hasLength(3));
        expect(figures[1].params, {'who': _unspecified});
        expect(figures[2].isCustom, isTrue);
        expect(_total(figures), 12);
      });
    }

    test('a wave-of-four balance is its own short waves, not folded', () async {
      // Not corpus wording (400712 has this pair across a phrase). Folding
      // would drop the `(N2R,ML)` holds into a long wave that has no slot for
      // a short wave's centre.
      final figures = await _import({
        'A1': [
          '(8) Neighbor do-si-do; form long wave',
          '(4) Balance wave of four (N2R,ML)',
        ],
      });
      expect(figures.map((f) => f.move), [
        'do_si_do',
        'form_long_waves',
        'form_short_waves',
      ]);
      expect(figures[1].params, {'who': _unspecified});
      expect(figures[2].params['sides'], 'nextNeighbors');
    });
  });

  test('explicitly formed long waves keep their existing fold', () async {
    // The refusal of words a fold would drop is scoped to the bare wave. The
    // plural `Form long waves` keeps the path it had before #2331 — including
    // a dancer-prefixed balance whose prefix agrees with the default facing,
    // which folds and drops the prefix (pre-existing; not changed here).
    final figures = await _import({
      'A1': ['(0) Form long waves', '(4) Men balance long wave'],
    });
    expect(figures, hasLength(1));
    expect(figures.single.move, 'form_long_waves');
    expect(figures.single.params['balance'], isTrue);
  });

  group('across a phrase boundary it is still one figure', () {
    test('dance 119: the balance opens A2', () async {
      final figures = await _import({
        'A1': [
          '(8) In long lines, go forward and back',
          '(8) Women allemande right 1 & 1/2; form long wave',
        ],
        'A2': [
          '(4) Balance long wave (SR,PL, men face in)',
          '(4) Shadow allemande right 3/4',
          '(4) Balance wave of four (SR,WL)',
          '(4) Walk forward; form wave of four with partner',
        ],
      });
      final waves = figures.where((f) => f.move == 'form_long_waves').toList();
      expect(waves, hasLength(1));
      _expectLongWaves(waves.single, {
        'who': 'role1s',
        'whom': 'shadows',
        'whomHand': 'right',
        'whom2': 'partners',
        'balance': true,
        'beats': 4,
      });
      expect(figures.any((f) => f.move == 'form_a_long_wave'), isFalse);
      expect(_total(figures), 32);
      // The wave took no beats, so every surviving figure keeps its section;
      // the folded figure sits where its beats are, at the start of A2.
      final labels = _labels(figures);
      expect(labels[figures.indexOf(waves.single)], 'A2');
      expect(labels.where((l) => l == 'A1'), hasLength(2));
    });

    test('one hold, balance opening the next phrase', () async {
      // Not corpus wording: the 1-code shape of the 86 cross-phrase pairs.
      final figures = await _import({
        'A1': ['(8) Ladies chain', '(8) Neighbor do-si-do; form long wave'],
        'A2': [
          '(4) Balance long wave (NR, women face in)',
          '(12) Partner swing',
        ],
      });
      expect(figures.map((f) => f.move), [
        'chain',
        'do_si_do',
        'form_long_waves',
        'swing',
      ]);
      _expectLongWaves(figures[2], {
        'who': 'role2s',
        'whom': 'neighbors',
        'whomHand': 'right',
        'balance': true,
        'beats': 4,
      });
      expect(_labels(figures), ['A1', 'A1', 'A2', 'A2']);
    });

    test('a refused balance leaves both as they were', () async {
      final figures = await _import({
        'A1': ['(8) Ladies chain', '(8) Neighbor do-si-do; form long wave'],
        'A2': ['(4) Men balance long wave', '(12) Partner swing'],
      });
      expect(figures, hasLength(5));
      expect(figures[2].params, {'who': _unspecified});
      expect(figures[3].isCustom, isTrue);
      expect(_total(figures), 32);
    });
  });

  group('a standalone bare wave that carries its own beats', () {
    // Review finding B1: a `form long wave` on its own line carries `beats`,
    // and is still a bare wave — the guards must not miss it. Not corpus
    // wording (the corpus has `(0) Form long wave`, dance 2325).
    test('an in-center balance after it reads as the centre wave', () async {
      final figures = await _import({
        'A1': [
          '(12) Partner swing',
          '(4) form long wave',
          '(4) Balance long wave in center',
        ],
      });
      expect(figures.map((f) => f.move), ['swing', 'form_a_long_wave']);
      expect(figures.last.params['balance'], isTrue);
      expect(figures.last.params['beats'], 8);
      expect(_total(figures), 20);
    });

    test('a dancer-prefixed balance after it stays text', () async {
      final figures = await _import({
        'A1': [
          '(12) Partner swing',
          '(4) form long wave',
          '(4) Men balance long wave',
        ],
      });
      expect(figures, hasLength(3));
      expect(figures[1].move, 'form_long_waves');
      expect(figures[1].params, {'who': _unspecified, 'beats': 4});
      expect(figures[2].isCustom, isTrue);
      expect(_total(figures), 20);
    });

    test('a refused in-center balance still leaves the centre wave, with its '
        'beats', () async {
      final figures = await _import({
        'A1': [
          '(12) Partner swing',
          '(4) form long wave',
          '(4) Men balance long wave in center',
        ],
      });
      expect(figures[1].move, 'form_a_long_wave');
      expect(figures[1].params, {'beats': 4});
      expect(figures[2].isCustom, isTrue);
      expect(_total(figures), 20);
    });
  });

  group('an in-center balance after a bare wave: the follower decides', () {
    test(
      'dance 10465 A1: Women … in center folds into the centre wave',
      () async {
        final figures = await _import({
          'A1': [
            '(8) In long lines, go forward and back',
            '(4) Women allemande left 1 & 1/4; form long wave',
            '(4) Women balance long wave in center',
          ],
        });
        expect(figures.map((f) => f.move), [
          'long_lines',
          'allemande',
          'form_a_long_wave',
        ]);
        expect(figures.last.params['balance'], isTrue);
        expect(figures.last.params['beats'], 4);
      },
    );

    test('dance 5771 B2: Men … in center is refused, the wave still turns '
        'into the centre wave', () async {
      final figures = await _import({
        'B2': [
          '(8) Men do-si-do 1 & 1/4; form long wave',
          '(4) Men balance long wave in center',
        ],
      });
      expect(figures[1].move, 'form_a_long_wave');
      expect(figures[1].params, isEmpty);
      expect(figures[2].isCustom, isTrue);
      expect(figures[2].params['text'], contains('in center'));
      expect(_total(figures), 12);
    });

    test('dance 7031: across a phrase, Women … in center folds', () async {
      final figures = await _import({
        'B1': [
          '(4) Balance wave of four (NL,MR)',
          '(4) Neighbor allemande left 1/2',
          '(4) Balance wave of four (NL,WR)',
          '(4) Women allemande right 3/4; form long wave',
        ],
        'B2': [
          '(4) Women balance long wave in center',
          '(4) N2 women allemande left 3/4 || Men shift left',
          '(8) Partner swing',
        ],
      });
      final centre = figures.singleWhere((f) => f.move == 'form_a_long_wave');
      expect(centre.params['balance'], isTrue);
      expect(centre.params['beats'], 4);
      expect(figures.any((f) => f.move == 'form_long_waves'), isFalse);
      // Sections are labelled by beats: the second 16-beat phrase is A2.
      expect(_labels(figures)[figures.indexOf(centre)], 'A2');
      expect(_total(figures), 32);
    });

    test(
      'dance 8066: across a phrase, Ones … in center (1R) is refused',
      () async {
        final figures = await _import({
          'A1': [
            '(8) Neighbor do-si-do',
            '(8) Ones do-si-do 1 & 1/4; form long wave',
          ],
          'A2': [
            '(4) Ones balance long wave in center (1R)',
            '(4) Ones balance long wave in center (1R)',
            '(4) Ones allemande right 3/4',
            '(4) Neighbor allemande left 1',
          ],
        });
        expect(figures[2].move, 'form_a_long_wave');
        expect(figures[2].params, isEmpty);
        expect(figures[3].isCustom, isTrue);
        expect(figures.any((f) => f.move == 'form_long_waves'), isFalse);
        expect(_total(figures), 32);
      },
    );
  });

  group('a standalone balance with both hands', () {
    test('decodes to long waves (dance 12454 shape)', () async {
      final figures = await _import({
        'A1': [
          '(4) Slide right (past P0)',
          '(4) Balance long wave (P0R,P1L, women face in)',
        ],
      });
      _expectLongWaves(figures.last, {
        'who': 'role2s',
        'whom': 'prevPartners',
        'whomHand': 'right',
        'whom2': 'partners',
        'balance': true,
        'beats': 4,
      });
    });

    for (final line in const [
      // Same hand twice: not a long wave's two hands.
      '(4) Balance long wave (N2R,N1R, women face in)',
      // The same pair twice.
      '(4) Balance long wave (NR,NL, women face in)',
      // A people code that names no pair we model (dance 12454).
      '(4) Balance long wave (P0L,P-1R, women face in)',
      // No facing.
      '(4) Balance long wave (N2R,N1L)',
    ]) {
      test('"$line" stays text', () async {
        final figures = await _import({
          'A1': ['(12) Partner swing', line],
        });
        expect(figures.last.isCustom, isTrue);
      });
    }
  });

  group('a "for all" balance after a bare wave keeps both lines as text', () {
    // Maintainer ruling (2026-11-23): `for all` names everyone in the one
    // wave, which neither long-wave move can say, and the sister wording
    // `…; form long wave for all in center` (dance 1032) is already text.
    test('dance 1033 A2', () async {
      final figures = await _import({
        'A2': [
          '(8) In long lines, go forward and back',
          '(4) Partner allemande left 3/4 (in center); form long wave',
          '(4) Balance long wave for all in center',
        ],
      });
      expect(figures.map((f) => f.move), ['long_lines', 'custom', 'custom']);
      expect(figures[1].params, {
        'text': 'Partner allemande left 3/4 (in center); form long wave',
        'beats': 4,
      });
      expect(figures[2].params['text'], 'Balance long wave for all in center');
      expect(_total(figures), 16);
    });

    test('a lone bare wave line goes back to its own text', () async {
      // Not corpus wording.
      final figures = await _import({
        'A1': [
          '(12) Partner swing',
          '(4) Form long wave',
          '(4) Balance long wave for all',
        ],
      });
      expect(figures.map((f) => f.move), ['swing', 'custom', 'custom']);
      expect(figures[1].params, {'text': 'Form long wave', 'beats': 4});
      expect(_total(figures), 20);
    });

    test('across a phrase, the wave\'s line goes back to text', () async {
      // Not corpus wording: the 1033 pair split across a phrase boundary.
      final figures = await _import({
        'A2': [
          '(8) In long lines, go forward and back',
          '(8) Partner allemande left 3/4 (in center); form long wave',
        ],
        'B1': ['(4) Balance long wave for all in center', '(12) Partner swing'],
      });
      expect(figures.map((f) => f.move), [
        'long_lines',
        'custom',
        'custom',
        'swing',
      ]);
      expect(figures[1].params['text'], contains('form long wave'));
      expect(_total(figures), 32);
    });

    test(
      'a line already folded into stays as it is; the balance stays text',
      () async {
        // Not corpus wording. Fold 1 took the balance into the swing, so the
        // line's first figure is no longer its own; the wave is left as side
        // waves and the `for all` balance is refused by the fold.
        final figures = await _import({
          'A1': [
            '(4) Partner balance',
            '(4) Partner swing; form long wave',
            '(4) Balance long wave for all',
            '(4) Neighbor allemande right 1',
          ],
        });
        expect(figures.map((f) => f.move), [
          'swing',
          'form_long_waves',
          'custom',
          'allemande',
        ]);
        expect(figures[1].params, {'who': _unspecified});
        expect(_total(figures), 16);
      },
    );
  });

  group('a long wave whose forming line states holds (#2331 follow-up)', () {
    test('a balance that agrees folds in, both lines\' holds kept', () async {
      // Not corpus wording: dance 16002's forming line, then a balance that
      // adds the other hand.
      final figures = await _import({
        'B2': [
          '(8) N2 neighbor swing; form long wave (N2R, women face in)',
          '(4) Balance long wave (N1L,N2R, women face in)',
        ],
      });
      expect(figures.map((f) => f.move), ['swing', 'form_long_waves']);
      expect(figures.last.params, {
        'whom': 'nextNeighbors',
        'whomHand': 'right',
        'whom2': 'neighbors',
        'who': 'role2s',
        'balance': true,
        'beats': 4,
      });
      expect(_total(figures), 12);
    });

    for (final balance in const [
      // A different pair by the same hand.
      '(4) Balance long wave (P3R, women face in)',
      // The same pair by the other hand.
      '(4) Balance long wave (N2L, women face in)',
      // The other role facing in.
      '(4) Balance long wave (N2R, men face in)',
    ]) {
      test('"$balance" disagreeing stays text', () async {
        // Not corpus wording.
        final figures = await _import({
          'B2': [
            '(8) N2 neighbor swing; form long wave (N2R, women face in)',
            balance,
          ],
        });
        expect(figures.map((f) => f.move), [
          'swing',
          'form_long_waves',
          'custom',
        ]);
        expect(figures[1].params, {
          'whom': 'nextNeighbors',
          'whomHand': 'right',
          'who': 'role2s',
        });
        expect(_total(figures), 12);
      });
    }

    test('a generic balance folds in across a phrase', () async {
      // Not corpus wording: dance 1210's forming line, the balance opening
      // the next phrase.
      final figures = await _import({
        'A1': ['(16) Partner swing', '(0) form long wave (P2L,P3R)'],
        'A2': ['(4) Balance the wave', '(12) Neighbor swing'],
      });
      expect(figures.map((f) => f.move), ['swing', 'form_long_waves', 'swing']);
      expect(figures[1].params, {
        'whom': 'nextPartners',
        'whomHand': 'left',
        'whom2': 'thirdPartners',
        'who': _unspecified,
        'balance': true,
        'beats': 4,
      });
      expect(_total(figures), 32);
    });

    test('across a phrase, a disagreeing balance stays text', () async {
      // Not corpus wording. The next phrase promotes its balance on its own;
      // after this wave it would be a second long-waves figure.
      final figures = await _import({
        'A1': ['(16) Partner swing', '(0) form long wave (P2L,P3R)'],
        'A2': [
          '(4) Balance long wave (P4R, women face in)',
          '(12) Neighbor swing',
        ],
      });
      expect(figures.map((f) => f.move), [
        'swing',
        'form_long_waves',
        'custom',
        'swing',
      ]);
      expect(_total(figures), 32);
    });

    test('dance 15461 B2: two forming lines are one figure', () async {
      final figures = await _import({
        'B2': [
          '(16) P4 partner promenade counterclockwise; form long wave '
              '(release left hands)',
          '(0) Form long wave (P4R,P5L, women face in)',
        ],
      });
      expect(figures.map((f) => f.move), ['promenade', 'form_long_waves']);
      expect(figures.last.params, {
        'who': 'role2s',
        'whom': 'fourthPartners',
        'whomHand': 'right',
        'whom2': 'fifthPartners',
      });
      expect(figures.last.note, 'release left hands');
      expect(_total(figures), 16);
    });

    test('two forming lines, then the balance: one figure', () async {
      // Not corpus wording.
      final figures = await _import({
        'A1': [
          '(12) Partner swing',
          '(0) form long wave',
          '(0) Form long wave (P2R,P1L, men face in)',
          '(4) Balance the wave',
        ],
      });
      expect(figures.map((f) => f.move), ['swing', 'form_long_waves']);
      expect(figures.last.params['balance'], isTrue);
      expect(figures.last.params['whom2'], 'partners');
      expect(_total(figures), 16);
    });
  });
}
