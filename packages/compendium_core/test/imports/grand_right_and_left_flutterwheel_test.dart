import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #295 — **grand right and left** and **flutterwheel** are compound
/// SHORTHANDS, not taxonomy moves. Both decompose into moves the taxonomy
/// already has, so neither adds a `MoveDef` and `contraTaxonomyVersion` is
/// unchanged.
///
/// * `Grand right and left (<pass list>)` → one `pull_by_dancers` per stated
///   pass. Decisive evidence: *334* by Diane Silver, transcribed in BOTH
///   sources — TCB #10042 A2 `(4) Grand right and left (N3R;N2L)` is ContraDB
///   #3403 A2 `[2] 3rd neighbors pull by right` + `[2] 2nd neighbors pull by
///   left`. ContraDB carries no grand-right-and-left figure at all.
/// * `(8) <who> flutterwheel:` + indented children → the children, which TCB
///   itself writes as `allemande ½` + `star promenade ½`.
///
/// The negatives matter as much as the positives: a pass code the taxonomy
/// cannot faithfully represent, or any leftover prose, must keep the line
/// custom rather than approximate it.
Future<StructuredDraft> _import(List<String> figures) async {
  final adapter = CallersBoxAdapter();
  final payload = jsonEncode({
    'ID': '9001',
    'Name': 'Synthetic',
    'Permission': 'full',
    'phrases': [
      {'name': 'A1', 'figures': figures},
    ],
  });
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw);
}

Future<List<Figure>> _figures(List<String> lines) async =>
    (await _import(lines)).dance.figures;

/// Parses ONE figure line the way the CallersBox adapter does.
List<Figure> _line(String text, {int beats = 0}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

int _totalBeats(Iterable<Figure> figures) =>
    figures.fold(0, (sum, f) => sum + f.beats);

String _text(Figure f) => f.params['text'] as String;

void main() {
  // --- Part A: grand right and left ------------------------------------------

  group('grand right and left decomposes into pull_by_dancers (#295)', () {
    test('adds NO taxonomy move and does not bump the taxonomy version', () {
      expect(contraTaxonomyVersion, 20);
      expect(contraTaxonomy.moves.containsKey('grand_right_and_left'), isFalse);
      expect(contraTaxonomy.moves.containsKey('flutterwheel'), isFalse);
      // The moves both shorthands lower onto DO exist.
      expect(contraTaxonomy.moves.containsKey('pull_by_dancers'), isTrue);
      expect(contraTaxonomy.moves.containsKey('allemande'), isTrue);
      expect(contraTaxonomy.moves.containsKey('star_promenade'), isTrue);
    });

    test('TCB #10042 A2 matches ContraDB #3403 A2 pass-for-pass', () {
      // TCB: `(4) Grand right and left (N3R;N2L)`
      // ContraDB: `[2] 3rd neighbors pull by right` + `[2] 2nd neighbors pull
      // by left`. Same dancers, same hands, same 2-beat shares, same 4 total.
      final figures = _line('Grand right and left (N3R;N2L)', beats: 4);
      expect(figures.map((f) => f.move), [
        'pull_by_dancers',
        'pull_by_dancers',
      ]);
      expect(figures[0].params['who'], 'thirdNeighbors');
      expect(figures[0].params['hand'], 'right');
      expect(figures[0].beats, 2);
      expect(figures[1].params['who'], 'nextNeighbors');
      expect(figures[1].params['hand'], 'left');
      expect(figures[1].beats, 2);
      expect(_totalBeats(figures), 4);
    });

    test('the shorthand name is preserved as a note on the first pass', () {
      final figures = _line('Grand right and left (N1R;N2L)', beats: 4);
      expect(figures.first.note, 'grand right and left');
      // Only the first — the name belongs to the block, not to every pass.
      expect(figures[1].note, isNull);
    });

    // Every pass-list shape attested in the full TCB corpus that this decoder
    // can faithfully map, with its corpus frequency.
    final attested = <String, List<List<String>>>{
      'Grand right and left (N1R;N2L)': [
        ['neighbors', 'right'],
        ['nextNeighbors', 'left'],
      ],
      'Grand right and left (N3R;N2L)': [
        ['thirdNeighbors', 'right'],
        ['nextNeighbors', 'left'],
      ],
      'Grand right and left (S2R;S1L)': [
        ['secondShadows', 'right'],
        ['shadows', 'left'],
      ],
      'Grand right and left (N1R;N2L;N3R)': [
        ['neighbors', 'right'],
        ['nextNeighbors', 'left'],
        ['thirdNeighbors', 'right'],
      ],
      'Grand right and left (PR;S1L;S2R)': [
        ['partners', 'right'],
        ['shadows', 'left'],
        ['secondShadows', 'right'],
      ],
      'Grand right and left (N1L;N2R)': [
        ['neighbors', 'left'],
        ['nextNeighbors', 'right'],
      ],
      'Grand right and left (N4R;N3L)': [
        ['fourthNeighbors', 'right'],
        ['thirdNeighbors', 'left'],
      ],
      'Grand right and left (N0R;N1L)': [
        ['prevNeighbors', 'right'],
        ['neighbors', 'left'],
      ],
      'Grand right and left (P1R;P2L;P3R;P4L)': [], // mixer series → custom
      'Grand right and left (N1R;N2L;N3R;N4L)': [
        ['neighbors', 'right'],
        ['nextNeighbors', 'left'],
        ['thirdNeighbors', 'right'],
        ['fourthNeighbors', 'left'],
      ],
    };

    attested.forEach((line, expected) {
      test('corpus shape: $line', () {
        // 12 divides 2, 3 and 4 passes evenly, so one beat count exercises
        // every shape without the divisibility guard interfering.
        final figures = _line(line, beats: 12);
        if (expected.isEmpty) {
          expect(figures.single.isCustom, isTrue);
          return;
        }
        expect(figures.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          expect(figures[i].move, 'pull_by_dancers');
          expect(figures[i].params['who'], expected[i][0]);
          expect(figures[i].params['hand'], expected[i][1]);
        }
        expect(_totalBeats(figures), 12, reason: 'beats must be preserved');
      });
    });

    test('a beats-absent line yields beats-absent passes', () {
      final figures = _line('Grand right and left (N1R;N2L)');
      expect(figures.length, 2);
      expect(figures.every((f) => f.beats == 0), isTrue);
      expect(figures.every((f) => f.params.containsKey('beats')), isFalse);
    });
  });

  group('grand right and left declines (prefer-custom, never fabricate)', () {
    // Each entry is a real corpus line that must NOT decompose.
    final declines = <String, String>{
      'no pass list at all': 'Grand right and left',
      'square corners are not the taxonomy first/second corners':
          'Grand right and left (PR;C3L;C2R;C1L)',
      'a corner code anywhere in the list': 'Grand right and left (C2R;C1L)',
      'mixer partner series beyond the current partner':
          'Grand right and left (P1R;P2L;P3R;P4L)',
      'neighbors beyond the modelled depth':
          'Grand right and left (N9R;N8L;N7R;N6L)',
      'negative-index neighbors': 'Grand right and left (N1R;N0L;N-1R)',
      'phantoms': 'Grand right and left (Ph1R;Ph2L)',
      'trail buddy': 'Grand right and left (TBR;L;R;L)',
      'a bare hand with no dancer': 'Grand right and left (R;L)',
      'progressive grand right and left is a different figure':
          'Progressive grand right and left (N1R;N2L)',
      'same-role grand right and left is a different figure':
          'Same-role grand right and left (N1R;N2L)',
      'a trailing qualifier': 'Grand right and left (N1R;N2L) [with N2]',
      'a leading qualifier':
          'In columns across the hall, grand right and left '
          '(N1R;N2L)',
      'a second parenthetical':
          'Grand right and left (N1R;N2L) (ones and twos '
          'begin with neighbor)',
      'a single pass is not a grand right and left':
          'Grand right and left (N1R)',
      'an empty cell': 'Grand right and left (N1R;;N2L)',
    };

    declines.forEach((why, line) {
      test('stays custom: $why', () {
        final figures = _line(line, beats: 12);
        expect(figures.length, 1, reason: 'must not fan out');
        expect(figures.single.isCustom, isTrue);
        expect(figures.single.beats, 12);
        // The source text is kept verbatim (scrubbed), never dropped.
        expect(_text(figures.single), isNotEmpty);
      });
    });

    test(
      'a trailing `;` clause keeps the WHOLE line custom (nothing dropped)',
      () {
        // Decomposing here would silently drop "face across".
        final figures = _line(
          'Grand right and left (N1R;N2L); face across',
          beats: 8,
        );
        expect(figures.single.isCustom, isTrue);
        expect(_text(figures.single).toLowerCase(), contains('face across'));
        expect(_totalBeats(figures), 8);
      },
    );

    test('beats that do not divide by the pass count stay custom', () {
      // `(8) Grand right and left (N0L;N1R;N2L)` — the ONE corpus line where an
      // even split is impossible. Splitting 8 over 3 passes would invent a
      // per-pass duration the source never states.
      final figures = _line('Grand right and left (N0L;N1R;N2L)', beats: 8);
      expect(figures.single.isCustom, isTrue);
      expect(figures.single.beats, 8);
      // The same shape DOES decompose when the beats divide.
      expect(_line('Grand right and left (N0L;N1R;N2L)', beats: 6).length, 3);
    });

    test(
      'a hostile over-long pass list degrades safely instead of fanning out',
      () {
        // OWASP: imported text is untrusted; the fan-out is bounded by
        // `kMaxPassListCells`, and going over it declines rather than throwing.
        final cells = List.generate(
          kMaxPassListCells + 1,
          (i) => i.isEven ? 'N1R' : 'N2L',
        ).join(';');
        final figures = _line('Grand right and left ($cells)', beats: 0);
        expect(figures.single.isCustom, isTrue);

        // A list exactly AT the cap still decomposes.
        final atCap = List.generate(
          kMaxPassListCells,
          (i) => i.isEven ? 'N1R' : 'N2L',
        ).join(';');
        expect(
          _line('Grand right and left ($atCap)').length,
          kMaxPassListCells,
        );
      },
    );

    test('a pathological line never throws (parse-never-fails)', () {
      for (final line in [
        'Grand right and left (',
        'Grand right and left )',
        'Grand right and left ()',
        'Grand right and left (;;;)',
        'Grand right and left (${'N1R;' * 400}N2L)',
        'Grand right and left (${'(' * 200})',
      ]) {
        expect(() => _line(line, beats: 8), returnsNormally, reason: line);
      }
    });
  });

  group('the shared TCB people-code map gains P1/S1/S2 (glossary-backed)', () {
    // Glossary: "Your current partner is P1", "Shadow S1 is the first shadow…
    // S2 is one hands-four beyond that". The map is shared with the hey
    // decoder, so the hey gains the same codes.
    test('a hey pass list may use P1', () {
      final figure = _line('Hey 1/2 (P1R;N2L)', beats: 8).single;
      expect(figure.move, 'hey');
      expect(figure.params['pass1'], 'partners');
    });

    test('a hey pass list may use S1/S2', () {
      final figure = _line('Hey 1/2 (S1R;S2L)', beats: 8).single;
      expect(figure.move, 'hey');
      expect(figure.params['pass1'], 'shadows');
      expect(figure.params['pass2'], 'secondShadows');
    });
  });

  // --- Part B: flutterwheel ---------------------------------------------------

  group('an unknown compound parent emits TCB\'s own children (#295)', () {
    test('neighbor flutterwheel becomes allemande + star promenade', () async {
      final figures = await _figures([
        '(8) Neighbor flutterwheel:',
        '     (4) Women allemande right 1/2',
        '     (4) Neighbor star promenade 1/2 (WR) (hand-in-hand with neighbor)',
      ]);
      expect(figures.map((f) => f.move), ['allemande', 'star_promenade']);
      expect(figures[0].params['who'], 'role2s');
      expect(figures[0].params['hand'], 'right');
      expect(figures[1].params['who'], 'neighbors');
      // Beats are the children's own, summing EXACTLY to the parent's 8.
      expect(figures.map((f) => f.beats), [4, 4]);
      expect(_totalBeats(figures), 8);
      // No custom figure survives for the shorthand parent.
      expect(figures.any((f) => f.isCustom), isFalse);
    });

    test('the shorthand parent name is preserved on the first child', () async {
      final figures = await _figures([
        '(8) Partner flutterwheel:',
        '     (4) Women allemande right 1/2',
        '     (4) Partner star promenade 1/2 (WR) (hand-in-hand with partner)',
      ]);
      expect(figures.first.note?.toLowerCase(), contains('flutterwheel'));
      expect(figures.first.note?.toLowerCase(), contains('partner'));
      expect(figures[1].note, isNull);
    });

    final variants = <String, List<String>>{
      'partner': [
        '(8) Partner flutterwheel:',
        '     (4) Women allemande right 1/2',
        '     (4) Partner star promenade 1/2 (WR) (hand-in-hand with partner)',
      ],
      'partner reverse (men lead, left hand)': [
        '(8) Partner reverse flutterwheel:',
        '     (4) Men allemande left 1/2',
        '     (4) Partner star promenade 1/2 (ML) (hand-in-hand with partner)',
      ],
      'neighbor reverse': [
        '(8) Neighbor reverse flutterwheel:',
        '     (4) Men allemande left 1/2',
        '     (4) Neighbor star promenade 1/2 (ML) (hand-in-hand with neighbor)',
      ],
      'along the set': [
        '(8) Partner flutterwheel (along the set):',
        '     (4) Women allemande right 1/2',
        '     (4) Partner star promenade 1/2 (WR) (hand-in-hand with partner)',
      ],
      'with an N-relationship qualifier': [
        '(8) Partner flutterwheel [with N2]:',
        '     (4) Women allemande right 1/2',
        '     (4) Partner star promenade 1/2 (WR) (hand-in-hand with partner)',
      ],
      'N2 neighbor': [
        '(8) N2 neighbor flutterwheel:',
        '     (4) Women allemande right 1/2',
        '     (4) N2 neighbor star promenade 1/2 (WR)',
      ],
      'shadow, uneven child beats': [
        '(6) Shadow reverse flutterwheel:',
        '     (2) Men allemande left 1/2',
        '     (4) Shadow star promenade 1/2 (ML) (hand-in-hand with shadow)',
      ],
    };

    variants.forEach((label, lines) {
      test('corpus variant: $label', () async {
        final figures = await _figures(lines);
        expect(figures.map((f) => f.move), ['allemande', 'star_promenade']);
        expect(figures.any((f) => f.isCustom), isFalse);
        // Children's beats always total the parent's stated beats.
        final parentBeats = int.parse(
          RegExp(r'^\((\d+)\)').firstMatch(lines.first)!.group(1)!,
        );
        expect(_totalBeats(figures), parentBeats);
      });
    });

    test('a (START-END) parent span is read as an inclusive duration', () async {
      // Real corpus line. Before #295 the range prefix did not match the
      // compound-parent pattern at all, so the parent AND its children were
      // emitted and the section beats were double-counted (6 → 12).
      final figures = await _figures([
        '(7-12) [Top two couples] Neighbor flutterwheel:',
        '     (2) Women allemande right 1/2',
        '     (4) Neighbor star promenade 1/2 (WR) (hand-in-hand with neighbor)',
      ]);
      expect(figures.map((f) => f.move), ['allemande', 'star_promenade']);
      expect(_totalBeats(figures), 6);
    });

    test(
      'ANY unstructurable child keeps the block whole-custom (never a mix)',
      () async {
        // `Women star right 1/2` does not structure, so the real corpus block
        // `(12) Grand partner flutterwheel:` stays one custom parent.
        final figures = await _figures([
          '(12) Grand partner flutterwheel:',
          '     (4) Women star right 1/2',
          '     (8) Partner star promenade 1/2 (WR) (hand-in-hand with partner)',
        ]);
        expect(figures.length, 1);
        expect(figures.single.isCustom, isTrue);
        expect(figures.single.beats, 12);
        // The decomposition still rides along in the note (nothing dropped).
        expect(figures.single.note, contains('star promenade'));
        expect(figures.single.note, contains('star right'));
      },
    );

    test('a preceding balance line does NOT fold into a child', () async {
      final figures = await _figures([
        '(4) Balance ring',
        '(8) Neighbor flutterwheel:',
        '     (4) Women allemande right 1/2',
        '     (4) Neighbor star promenade 1/2 (WR) (hand-in-hand with neighbor)',
      ]);
      expect(figures.map((f) => f.move), [
        'balance_the_ring',
        'allemande',
        'star_promenade',
      ]);
      expect(_totalBeats(figures), 12);
    });
  });

  group('known compound parents are unchanged', () {
    test('revolving door still collapses to the single parent move', () async {
      final figures = await _figures([
        '(6) Revolving door:',
        '     (4) Partner star promenade 1/2 (WR)',
        '     (2) Women allemande right 1/2',
        '(10) Neighbor swing',
      ]);
      expect(figures.map((f) => f.move), ['revolving_door', 'swing']);
      expect(figures.first.beats, 6);
      // Children are subsumed, never emitted, even though BOTH structure.
      expect(figures.where((f) => f.move == 'star_promenade'), isEmpty);
      expect(figures.where((f) => f.move == 'allemande'), isEmpty);
      expect(_totalBeats(figures), 16);
    });

    test(
      'an unknown parent with unstructurable children is still one custom',
      () async {
        final figures = await _figures([
          '(8) Mystery move:',
          '     (4) Do the first thing',
          '     (4) Do the second thing',
        ]);
        expect(figures.length, 1);
        expect(figures.single.isCustom, isTrue);
        expect(figures.single.beats, 8);
      },
    );
  });

  // --- End to end -------------------------------------------------------------

  group('end-to-end: TCB #10042 "334" (Diane Silver)', () {
    late StructuredDraft draft;

    setUp(() async {
      // The dance verbatim from `dance.php?id=10042&format=JSON`, whose
      // ContraDB twin (#3403) writes the same choreography as pull-bys.
      final adapter = CallersBoxAdapter();
      final payload = jsonEncode({
        'ID': '10042',
        'Name': '334',
        'Permission': 'full',
        'Authors': ['Diane Silver'],
        'phrases': [
          {
            'name': 'A1',
            'figures': [
              '(4) N1 neighbor balance (RH)',
              '(4) Grand right and left (N1R;N2L)',
              '(4) N3 neighbor balance (RH)',
              '(4) N3 neighbor box the gnat',
            ],
          },
          {
            'name': 'A2',
            'figures': [
              '(4) Grand right and left (N3R;N2L)',
              '(12) N1 neighbor swing',
            ],
          },
          {
            'name': 'B1',
            'figures': ['(8) Men allemande left 1 & 1/2', '(8) Partner swing'],
          },
          {
            'name': 'B2',
            'figures': [
              '(8) Circle left 3/4',
              '(4) Balance ring',
              '(4) Partner California twirl',
            ],
          },
        ],
      });
      final discovered = await adapter.discover(
        ImportRequest(payload: payload),
      );
      final raw = await adapter.fetch(discovered.single);
      draft = adapter.parse(raw);
    });

    test('both grand-right-and-lefts decompose to 2 pull-bys each', () {
      final pullBys = draft.dance.figures
          .where((f) => f.move == 'pull_by_dancers')
          .toList();
      expect(pullBys.length, 4);
      expect(pullBys.map((f) => f.params['who']), [
        'neighbors',
        'nextNeighbors',
        'thirdNeighbors',
        'nextNeighbors',
      ]);
      expect(pullBys.map((f) => f.params['hand']), [
        'right',
        'left',
        'right',
        'left',
      ]);
      expect(pullBys.every((f) => f.beats == 2), isTrue);
    });

    test('the dance still totals 64 beats (no drift from the fan-out)', () {
      expect(_totalBeats(draft.dance.figures), 64);
    });

    test('section placement is unchanged (A1/A2/B1/B2 all land on 16)', () {
      final sections = deriveSections(
        draft.dance.figures,
        PhraseStructure.standard,
      );
      final byLabel = <String, int>{};
      for (final sectioned in sections) {
        byLabel[sectioned.label] =
            (byLabel[sectioned.label] ?? 0) + sectioned.figure.beats;
      }
      expect(byLabel['A1'], 16);
      expect(byLabel['A2'], 16);
      expect(byLabel['B1'], 16);
      expect(byLabel['B2'], 16);
      // The first grand-right-and-left pass starts mid-A1, at beat 4.
      final firstPullBy = sections.firstWhere(
        (s) => s.figure.move == 'pull_by_dancers',
      );
      expect(firstPullBy.startBeat, 4);
      expect(firstPullBy.label, 'A1');
    });

    test('parse never fails and the draft is well structured', () {
      expect(draft.dance.figures, isNotEmpty);
      expect(draft.dance.figures.where((f) => f.isCustom), isEmpty);
      expect(draft.quality.score, greaterThan(0.5));
    });
  });
}
