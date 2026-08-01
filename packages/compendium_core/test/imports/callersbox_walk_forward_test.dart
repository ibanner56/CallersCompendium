import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Issue #733 — The Caller's Box `walk forward` lines.
///
/// TCB writes `walk forward` on a large minority of its figure lines. It is not
/// one family and it is NOT a missing move; every group below maps onto moves
/// the taxonomy already has (no new `MoveDef`, no taxonomy version bump). Line
/// counts and the population they are measured over live in the `walk forward`
/// census in `docs/research/callersbox.md`, not here.
///
/// - **1a — absorbed.** `[<dancer>] walk forward; form long wave in center`
///   emits ONLY `form_a_long_wave`, with the walk clause's dancer TRANSFERRED
///   onto the wave. The move's `in` defaults to `true` and its rendered line
///   already reads "`<who>` dance in to a long wave in the center", so a
///   separate travel figure would state the same travel twice.
/// - **1b — pass through, then the wave.** A
///   `walk forward; form wave of four with <dancer>` line emits
///   `pass_through()` plus the `form_short_waves` figure that already parses
///   today.
/// - **2 — pass through.** `walk forward to <dancer>` emits a `pass_through`
///   with the destination preserved as a note (`to n2`). `to <dancer>` names
///   the DESTINATION arrived at, not a dancer passed: you walk past your
///   current neighbour and finish facing the named one, which is the standard
///   contra progression.
/// - **3 — left custom.** A bare `walk forward`, and anything carrying a
///   qualifier the mapping cannot faithfully carry.
///
/// Wordings below are verbatim corpus samples.
List<Figure> _parse(String text, {int beats = 0}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

Future<List<Figure>> _importedFigures(List<String> lines) async {
  final payload = jsonEncode({
    'ID': '42',
    'Name': 'Test Dance',
    'Permission': 'full',
    'phrases': [
      {'name': 'A1', 'figures': lines},
    ],
  });
  final adapter = CallersBoxAdapter();
  final discovered = await adapter.discover(ImportRequest(payload: payload));
  final raw = await adapter.fetch(discovered.single);
  return adapter.parse(raw).dance.figures;
}

int _totalBeats(List<Figure> figures) => figures.fold(0, (a, f) => a + f.beats);

void main() {
  group('#733 group 1a — absorbed into form_a_long_wave', () {
    test('emits ONE figure: the wave, with the walk clause dropped', () {
      final figures = _parse(
        'Women walk forward; form long wave in center',
        beats: 4,
      );
      expect(figures, hasLength(1));
      expect(figures.single.move, 'form_a_long_wave');
    });

    // THE regression that matters: every subject-bearing line in this group
    // states the role on the WALK clause and NONE on the wave clause, while
    // `form_a_long_wave.who` defaults to `role2s`. Absorbing without
    // transferring the subject would render every men's line as a women's
    // figure.
    test('a "Men …" source NEVER yields a role2s subject', () {
      final figure = _parse(
        'Men walk forward; form long wave in center',
        beats: 4,
      ).single;
      expect(figure.move, 'form_a_long_wave');
      expect(figure.params['who'], isNot('role2s'));
      expect(figure.params['who'], 'role1s');
      // A transferred subject is STATED by the source, never an assumption.
      expect(figure.assumedSubject, isFalse);
    });

    for (final (wording, who) in const [
      ('Women walk forward; form long wave in center', 'role2s'),
      ('Men walk forward; form long wave in center', 'role1s'),
      ('Ones walk forward; form long wave in center', 'ones'),
    ]) {
      test('"$wording" transfers who: $who', () {
        final figure = _parse(wording, beats: 4).single;
        expect(figure.move, 'form_a_long_wave');
        expect(figure.params['who'], who);
        expect(figure.assumedSubject, isFalse);
      });
    }

    test(
      'a subject-less walk keeps the move default (still an assumption)',
      () {
        final figure = _parse(
          'Walk forward; form long wave in center',
          beats: 4,
        ).single;
        expect(figure.move, 'form_a_long_wave');
        expect(figure.params.containsKey('who'), isFalse);
        expect(figure.assumedSubject, isTrue);
      },
    );

    test('the pair\'s beats budget rides on the single emitted figure', () {
      final figures = _parse(
        'Men walk forward; form long wave in center',
        beats: 4,
      );
      expect(_totalBeats(figures), 4);
      expect(figures.single.beats, 4);
    });
  });

  group('#733 group 1b — pass_through + form_short_waves', () {
    test('emits a bare pass through, then the wave', () {
      final figures = _parse(
        'Walk forward; form wave of four with N2',
        beats: 4,
      );
      expect(figures.map((f) => f.move), ['pass_through', 'form_short_waves']);
      expect(figures[1].params['sides'], 'nextNeighbors');
    });

    // `pass_through` declares `dir: along` and `shoulder: right` as its own
    // taxonomy defaults. Writing either here would assert a direction and a
    // shoulder the source never stated.
    test('never writes dir or shoulder', () {
      for (final wording in const [
        'Walk forward; form wave of four with N2',
        'Walk forward; form wave of four with shadow',
        'Walk forward to N2',
      ]) {
        final pass = _parse(wording, beats: 4).first;
        expect(pass.move, 'pass_through');
        expect(pass.params.containsKey('dir'), isFalse, reason: wording);
        expect(pass.params.containsKey('shoulder'), isFalse, reason: wording);
      }
    });

    test('the source total rides on the first clause, once', () {
      final figures = _parse(
        'Walk forward; form wave of four with N2',
        beats: 4,
      );
      expect(figures[0].beats, 4);
      expect(figures[1].beats, 0);
      expect(_totalBeats(figures), 4);
    });

    // `pass_through` has no `who` slot, so a stated subject cannot ride — the
    // line stays whole-custom rather than silently dropping the role.
    test('a stated subject declines the line (prefer-custom)', () {
      final figures = _parse(
        'Women walk forward; form wave of four with N2',
        beats: 4,
      );
      expect(figures, hasLength(1));
      expect(figures.single.isCustom, isTrue);
    });
  });

  group('#733 group 2 — walk forward to <dancer>', () {
    for (final (wording, note) in const [
      ('Walk forward to N2', 'to n2'),
      ('Walk forward to N1', 'to n1'),
      ('Walk forward to N0', 'to n0'),
      ('Walk forward to N3', 'to n3'),
      ('Walk forward to shadow', 'to shadow'),
      ('Walk forward to partner', 'to partner'),
    ]) {
      test('"$wording" → pass_through with note "$note"', () {
        final figure = _parse(wording, beats: 4).single;
        expect(figure.move, 'pass_through');
        expect(figure.beats, 4);
        // The destination has no structured slot, so it MUST stay recoverable:
        // `to n0` / `to n1` / `to shadow` are not the ordinary progression
        // target and the distinction cannot be flattened away.
        expect(figure.note, note);
      });
    }

    test('destinations stay distinct from one another', () {
      final notes = {
        for (final w in const [
          'Walk forward to N0',
          'Walk forward to N1',
          'Walk forward to N2',
          'Walk forward to N3',
          'Walk forward to shadow',
          'Walk forward to partner',
        ])
          _parse(w, beats: 4).single.note,
      };
      expect(notes, hasLength(6));
    });

    test('a stated subject declines the line (pass_through has no who)', () {
      expect(
        _parse('Women walk forward to N2', beats: 4).single.isCustom,
        isTrue,
      );
    });

    test('a "to <dancer>" clause pairs with a following wave clause', () {
      final figures = _parse(
        'Walk forward to N3; form wave of four with N3',
        beats: 4,
      );
      expect(figures.map((f) => f.move), ['pass_through', 'form_short_waves']);
      expect(figures[0].note, 'to n3');
      expect(figures[1].params['sides'], 'thirdNeighbors');
      expect(_totalBeats(figures), 4);
    });

    test('the recognizer is shared, not TCB-front-end-only', () {
      // It lives with the other TCB-attested-but-source-neutral recognizers in
      // `figure_parser.dart`, so the canonical front end reads it too.
      final figure = parseFigureLine('Walk forward to N2', beats: 4)!;
      expect(figure.isCustom, isFalse);
      expect(figure.move, 'pass_through');
      expect(figure.note, 'to n2');
    });
  });

  group('#733 group 2 — annotation preservation', () {
    // `_stripAnnotations` drops `()` for recognition, so without the
    // `walk forward` anchor these lines would structure while SILENTLY losing
    // the per-role diagonals the custom fallback preserves today.
    test('keeps the parenthetical, destination note leading', () {
      final figure = _parse(
        'Walk forward to N2 (women going on slight right diagonal, men on '
        'slight left diagonal)',
        beats: 4,
      ).single;
      expect(figure.move, 'pass_through');
      expect(figure.note, startsWith('to n2; '));
      expect(figure.note, contains('slight right diagonal'));
      expect(figure.note, contains('slight left diagonal'));
    });

    test('a long qualifier truncates without amputating the destination', () {
      // Several annotations, each within the per-run bound, that together
      // exceed the note cap: the JOINED note truncates, and the destination —
      // the load-bearing half — leads and survives.
      final qualifier = 'a' * 100;
      final figure = _parse(
        'Walk forward to N2 ($qualifier) ($qualifier) ($qualifier)',
        beats: 4,
      ).single;
      expect(figure.move, 'pass_through');
      expect(figure.note, startsWith('to n2; '));
      // The combined note is bounded by the shared annotation cap, so a hostile
      // line cannot inflate it.
      expect(figure.note!.length, lessThanOrEqualTo(200));
    });

    test('an over-long parenthetical takes the annotation-stripped path', () {
      // The per-run bound inside the shared annotation regex means a single
      // pathological parenthetical never matches at all; the line falls back to
      // the ordinary reading rather than building an unbounded note.
      final figure = _parse(
        'Walk forward to N2 (${'very long qualifier ' * 40})',
        beats: 4,
      ).single;
      expect(figure.move, 'pass_through');
      expect(figure.note, 'to n2');
    });

    test('an ordinary annotated pass-through line is untouched', () {
      // The anchor is `walk forward`, not the `pass_through` MOVE, so an
      // existing TCB pass-through keeps its annotation-stripped reading.
      final figure = _parse('Pass through across (PR)', beats: 2).single;
      expect(figure.move, 'pass_through');
      expect(figure.params['dir'], 'across');
      expect(figure.note, isNull);
    });
  });

  group('#733 group 3 + declines — must stay custom', () {
    for (final wording in const [
      // Bare: nothing anchors an interpretation.
      'Walk forward',
      'Men walk forward',
      'Women walk forward',
      // A qualifier the mapping cannot carry.
      'Walk forward one step',
      'Walk forward slowly (step; step)',
      'Walk forward quickly (step; step; step; close)',
      'Walk forward (out of the set)',
      'Walk forward until right shoulders are adjacent',
      'Walk forward towards partner',
      // Non-dancer destinations.
      'Walk forward to center',
      'Walk forward to next star',
      'Walk forward to second person',
      'Walk forward to wave of four positions with N2',
      // A qualified destination the note cannot distinguish.
      'Walk forward to shadow S1',
      'Walk forward to same-role neighbor (on diagonal within minor set)',
      // A following clause that is not a formation we absorb into.
      'Walk forward; turn alone',
      'Walk forward; face across',
      'Walk forward; turn right',
      // Formations with no faithful mapping.
      'Walk forward; form ring of four with N2',
      'Walk forward; form wave of two with partner',
      'Walk forward; form interlocking long waves in center',
      'Walk forward; form wave of four with phantom shadow',
      // "for all" has no consumed reading, and defaulting `who` would
      // fabricate a role the source did not name.
      'Walk forward; form long wave for all in center',
    ]) {
      test('"$wording" stays custom', () {
        final figures = _parse(wording, beats: 4);
        expect(figures, hasLength(1));
        expect(figures.single.isCustom, isTrue);
      });
    }

    // The diagonals are declined DELIBERATELY, not by accident:
    // `form_a_long_wave` has no `dir` param at all, and on the short-wave side
    // the source states the direction of TRAVEL, not the wave's orientation —
    // mapping one onto the other would assert a formation the source did not
    // state (the recognizer already refuses TCB's explicit `form diagonal wave
    // of four` for the same reason). `(optional spin)` has no slot either.
    for (final wording in const [
      'Walk forward on left diagonal',
      'Walk forward on right diagonal (optional spin)',
      'Walk forward on right diagonal; form wave of four with N2',
      'Walk forward on left diagonal; form wave of four with shadow',
      'Walk forward on right diagonal (optional spin); form wave of four with N2',
      'Walk forward on left diagonal (optional spin); form wave of four with N3',
      'Walk forward on slight left diagonal; form wave of four with N2',
      'Walk forward on slight left diagonal; form intersecting waves of four',
    ]) {
      test('diagonal: "$wording" stays custom', () {
        final figures = _parse(wording, beats: 4);
        expect(figures, hasLength(1));
        expect(figures.single.isCustom, isTrue);
      });
    }
  });

  group('#733 — end-to-end through CallersBoxAdapter', () {
    test('a walk/long-wave pair keeps the source beat total', () async {
      final figures = await _importedFigures([
        '(8) In long lines, go forward and back',
        '(4) Ones walk forward; form long wave in center',
        '(4) Neighbor swing',
      ]);
      expect(_totalBeats(figures), 16);
      final wave = figures[1];
      expect(wave.move, 'form_a_long_wave');
      expect(wave.params['who'], 'ones');
      expect(wave.beats, 4);
    });

    // A newly-structured wave lets the EXISTING trailing-balance fold (#577)
    // claim the balance line that follows it, which it could not do while the
    // walk line was custom. The two figures merge and their beats sum, so the
    // dance total is unchanged.
    test(
      'a following balance-wave line folds into the newly-formed wave',
      () async {
        final figures = await _importedFigures([
          '(4) Ones walk forward; form long wave in center',
          '(4) Balance long wave',
        ]);
        expect(figures, hasLength(1));
        expect(figures.single.move, 'form_a_long_wave');
        expect(figures.single.params['who'], 'ones');
        expect(figures.single.params['balance'], isTrue);
        expect(_totalBeats(figures), 8);
      },
    );

    test(
      'a walk/short-wave pair emits two figures and keeps the total',
      () async {
        final figures = await _importedFigures([
          '(4) Walk forward; form wave of four with N2',
          '(12) N2 neighbor swing',
        ]);
        expect(figures.map((f) => f.move), [
          'pass_through',
          'form_short_waves',
          'swing',
        ]);
        expect(_totalBeats(figures), 16);
      },
    );
  });
}
