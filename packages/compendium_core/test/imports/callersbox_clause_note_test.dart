import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Tests for the `;`-clause NOTE FALLBACK in [parseFigureLines]
/// (`callersbox_figure_dialect.dart`) and the machinery it depends on:
/// [combineFigureNotes], the note-eligibility allowlist, and the CallersBox
/// adapter's cross-line folds.
///
/// Before this change a single unstructurable clause collapsed the WHOLE line
/// to one custom figure. Now a clause the dialect can preserve losslessly as
/// prose is dropped from the figure list and kept as a note on the nearest
/// preceding figure, so the line's moves survive.
///
/// Every wording asserted here was measured over the whole Caller's Box mirror
/// (non-mixer, `Permission: full`, top-level `;` clauses only); the counts in
/// the comments are that census, not estimates. No corpus file is read — the
/// adapter cases are built from synthetic JSON to the documented TCB schema.

List<Figure> _lines(String text, {int beats = 8}) =>
    parseFigureLines(text, beats: beats, frontEnd: tcbFigureFrontEnd);

Figure _one(String text, {int beats = 8}) {
  final figures = _lines(text, beats: beats);
  expect(figures, hasLength(1), reason: text);
  return figures.single;
}

void _staysWholeCustom(String text, {int beats = 8}) {
  final only = _one(text, beats: beats);
  expect(only.isCustom, isTrue, reason: text);
  expect(only.beats, beats, reason: text);
  expect(only.note, isNull, reason: text);
}

Map<String, Object?> _tcbDance(List<String> figures) => {
  'ID': '4242',
  'Name': 'Clause Note Probe',
  'Permission': 'full',
  'FormationBase': 'Duple Minor - Improper',
  'phrases': [
    {'name': 'A1', 'figures': figures},
  ],
};

List<Figure> _importFigures(List<String> figureLines) {
  final dance = _tcbDance(figureLines);
  final draft = CallersBoxAdapter().parse(
    RawRecord(
      source: ProvenanceSource.callersbox,
      externalId: '4242',
      payload: jsonEncode(dance),
      contentType: 'application/json',
      permission: 'full',
    ),
  );
  return draft.dance.figures;
}

void main() {
  group('note fallback — the ruled-in clause families', () {
    test('a trailing facing clause becomes a note; the move survives', () {
      // `face up` 351, `face N2` 293, `face next` 229, `face down` 211,
      // `face partner` 209 clause occurrences.
      const cases = {
        'Circle left 3/4; face up': 'face up',
        'Partner swing; face N2': 'face N2',
        'Petronella turn; face next': 'face next',
        'Pass through; face down': 'face down',
        'Long lines forward and back; face across': 'face across',
      };
      for (final entry in cases.entries) {
        final only = _one(entry.key);
        expect(only.isCustom, isFalse, reason: entry.key);
        expect(only.note, entry.value, reason: entry.key);
      }
    });

    test('`finish proper` (137) and `return to place` (235) are eligible', () {
      expect(
        _one('Long lines forward and back; finish proper').note,
        'finish proper',
      );
      expect(
        _one('Ones go up outside; return to place').note,
        'return to place',
      );
    });

    test('`women/men turn around` (221 lines) are eligible and CANONICAL', () {
      // The allowlist matches the POST-SCRUB role tokens, so the note is stored
      // canonically and the reader never sees a raw gendered term.
      const cases = {
        'Partner swing; women turn around': 'role2s turn around',
        'Partner swing; men turn around': 'role1s turn around',
      };
      for (final entry in cases.entries) {
        final only = _one(entry.key);
        expect(only.move, 'swing', reason: entry.key);
        expect(only.note, entry.value, reason: entry.key);
        // The source word itself must appear NOWHERE in the stored note.
        expect(only.note, isNot(contains('women')), reason: entry.key);
        expect(only.note, isNot(contains('men')), reason: entry.key);
      }
    });

    test('the stored note is independent of the SOURCE casing', () {
      for (final source in [
        'women turn around',
        'Women turn around',
        'WOMEN turn around',
      ]) {
        expect(
          _one('Partner swing; $source').note,
          'role2s turn around',
          reason: source,
        );
      }
    });

    test('the annotated `turn around` variants ARE swept in', () {
      // A PREFIX rule, mirroring `^face\b`: the note is verbatim prose either
      // way, so `role2s turn around (cw)` preserves exactly as much as the
      // whole-custom line did. Accepting `face up [with n0]` while rejecting
      // this would be arbitrary.
      // Note the annotation's own casing is preserved verbatim (`[with N2]`):
      // only the role vocabulary is canonicalized.
      const cases = {
        'Partner swing; women turn around (cw)': 'role2s turn around (cw)',
        'Partner swing; men turn around [with N2]':
            'role1s turn around [with N2]',
        'Partner swing; women turn around (by left)':
            'role2s turn around (by left)',
      };
      for (final entry in cases.entries) {
        final figures = _lines(entry.key);
        expect(figures, hasLength(1), reason: entry.key);
        expect(figures.single.isCustom, isFalse, reason: entry.key);
        expect(figures.single.note, entry.value, reason: entry.key);
      }
    });

    test('the prefix rule still excludes the wrong-subject wordings', () {
      // `^` and `\b` are the whole guard. A prefix is far easier to
      // over-widen later than an exact match, so this pins the boundary:
      // neither of these names the subject the rule is scoped to.
      for (final line in [
        'Partner swing; turn around (by right)',
        'Partner swing; woman one and man two turn around',
      ]) {
        _staysWholeCustom(line);
      }
    });

    test('the line KEEPS its source beats — nothing is redistributed', () {
      // The compound's whole budget already rides on the first clause and a
      // note-ified clause emits no figure, so the cumulative total that
      // `deriveSections` reads is byte-identical to the old whole-custom line.
      final figures = _lines('Circle left 3/4; face up', beats: 6);
      expect(figures, hasLength(1));
      expect(figures.single.beats, 6);
      final three = _lines('Men allemande left 1; face out; form long wave');
      expect(three.map((f) => f.beats).toList(), [8, 0]);
      expect(three.fold<int>(0, (a, f) => a + f.beats), 8);
    });
  });

  group('note fallback — placement', () {
    test('a MEDIAL clause lands on the nearest PRECEDING figure', () {
      // 5 corpus lines put the facing between two structured clauses.
      final figures = _lines('Men allemande left 1; face out; form long wave');
      expect(figures.map((f) => f.move).toList(), [
        'allemande',
        'form_a_long_wave',
      ]);
      expect(figures.first.note, 'face out');
      expect(figures.last.note, isNull);
    });

    test(
      'several eligible clauses accumulate on one host, in source order',
      () {
        final only = _one(
          'Ones go up outside; return to place; face woman two',
        );
        expect(only.isCustom, isFalse);
        // Scrubbed, so the gendered term is already a canonical role token.
        expect(only.note, 'return to place; face role2 two');
      },
    );

    test('a LEADING clause never note-ifies — nothing precedes it', () {
      // A note belongs TO a figure. Hanging it on a LATER figure would assert
      // an order the source never stated, so the line keeps its honest
      // whole-custom reading. `walk forward` is the largest such blocker
      // (313 sole-blocker lines) and has no taxonomy move.
      _staysWholeCustom('Walk forward; form long wave in center', beats: 4);
      _staysWholeCustom('Fall back; face up');
    });
  });

  group('note fallback — the allowlist is closed', () {
    test('an ineligible clause still collapses the whole line', () {
      for (final line in [
        'Partner swing; fall back', // 81 occurrences, no model
        'Partner swing; bend the line', // 59
        'Partner swing; form wave of two', // a wave size we do not model
        'Partner swing; form two-faced line',
        'Partner swing; cross over',
      ]) {
        _staysWholeCustom(line);
      }
    });

    test('the `cast … to place` family is NOT swept in by `return to place`', () {
      // Deliberate: `cast` is the largest genuinely-undefined figure left, and
      // note-ifying these lines would make them look handled and cause a future
      // census of `cast` to under-count itself. `return to place` is matched as
      // an EXACT phrase, which is what excludes them.
      for (final line in [
        'Partner swing; cast down to place',
        'Partner swing; cast up to place',
        'Partner swing; cast back to place',
      ]) {
        _staysWholeCustom(line);
        expect(_one(line).params['text'], contains('cast'));
      }
    });

    test('neighbouring `finish`/`return` wordings are excluded', () {
      for (final line in [
        'Partner swing; finish improper',
        'Partner swing; finish progressed',
        'Partner swing; finish next to partner',
        'Partner swing; finish with ones on left',
        'Partner swing; return to original place',
        'Partner swing; return to starting place of a1',
      ]) {
        _staysWholeCustom(line);
      }
    });

    test('`face` is matched on a WORD BOUNDARY, so `facing star` is safe', () {
      // Without `\b` the allowlist would claim a real, recognised move.
      final star = parseFigureLine(
        'Facing star clockwise 1/2',
        beats: 6,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(star!.move, 'facing_star');
      // And as a trailing clause it still structures as a FIGURE, not a note.
      final figures = _lines('Pass through; facing star clockwise 1/2');
      expect(figures.map((f) => f.move).toList(), [
        'pass_through',
        'facing_star',
      ]);
      expect(figures.every((f) => f.note == null), isTrue);
    });
  });

  group('notes COMBINE, never overwrite', () {
    test(
      'a recognizer note LEADS the clause note (chain, 38 corpus lines)',
      () {
        // `chain` keeps its "to <dancer>" target as a note. Resolving this with
        // `existing ?? added` silently dropped one of the two.
        final only = _one('Ladies chain to partner; face down');
        expect(only.move, 'chain');
        expect(only.note, 'to partner; face down');
      },
    );

    test(
      'an ANNOTATION note also combines (courtesy turn, 2 corpus lines)',
      () {
        final only = _one(
          'Partner courtesy turn (power turn); face out',
          beats: 4,
        );
        expect(only.move, 'courtesy_turn');
        expect(only.note, 'power turn; face out');
      },
    );

    test('combineFigureNotes: order, blanks, duplicates, bounds', () {
      expect(
        combineFigureNotes('to partner', 'face down'),
        'to partner; face down',
      );
      expect(combineFigureNotes(null, 'face up'), 'face up');
      expect(combineFigureNotes('to partner', null), 'to partner');
      expect(combineFigureNotes(null, null), isNull);
      expect(combineFigureNotes('  ', 'face up'), 'face up');
      expect(combineFigureNotes('face up', '  '), 'face up');
      // A duplicate is not repeated.
      expect(combineFigureNotes('face up', 'face up'), 'face up');
      // A lone note passes through unchanged even when it exceeds the bound —
      // only the JOINED result is truncated, which is what makes the switch
      // away from `??` provably behaviour-preserving.
      final long = 'x' * (kMaxFigureNote + 50);
      expect(combineFigureNotes(long, null), long);
      expect(combineFigureNotes(long, 'face up')!.length, kMaxFigureNote);
    });

    test('truncateOnRuneBoundary never splits a surrogate pair', () {
      // A naive `substring` would leave a lone surrogate in stored text.
      const emoji = '👍'; // one rune, two UTF-16 code units
      final text = emoji * 10;
      for (var limit = 0; limit <= text.length + 2; limit++) {
        final cut = truncateOnRuneBoundary(text, limit);
        expect(cut.length.isEven, isTrue, reason: 'limit $limit');
        expect(
          cut.runes.every((r) => r > 0xFFFF),
          isTrue,
          reason: 'limit $limit',
        );
        expect(cut.length, lessThanOrEqualTo(limit < 0 ? 0 : limit));
      }
    });
  });

  group('security — untrusted import text (OWASP)', () {
    test('an over-long eligible clause declines rather than making a note', () {
      final huge = 'face ${'a' * (kMaxClauseNote + 10)}';
      _staysWholeCustom('Partner swing; $huge');
    });

    test('an over-long `;` run declines the fallback, never fans out', () {
      final hostile = [
        'Partner swing',
        ...List.filled(40, 'face up'),
      ].join('; ');
      final figures = _lines(hostile);
      expect(figures, hasLength(1));
      expect(figures.single.isCustom, isTrue);
    });

    test('above the clause cap, parsing STOPS at the first failure', () {
      // The cap only ever gated the note fallback, so a crafted line used to
      // cost one `parseFigureLine` per clause before the result was discarded.
      // Bailing early is behaviour-identical (the fallback is unreachable above
      // the cap) and bounds attacker-controlled work.
      var parsed = 0;
      String countingScrub(String s) {
        parsed++;
        return scrubFigureText(s);
      }

      final hostile = [
        'not a move at all',
        ...List.filled(500, 'also not a move'),
      ].join('; ');
      final figures = parseFigureLines(
        hostile,
        beats: 8,
        scrub: countingScrub,
        frontEnd: tcbFigureFrontEnd,
      );
      expect(figures, hasLength(1));
      expect(figures.single.isCustom, isTrue);
      // One scrub for the failing first clause, one for the whole-line custom
      // fallback — NOT 501.
      expect(parsed, lessThan(5));
    });

    test('at or below the cap, every clause is still tried', () {
      // The early return must not change the normal path: the fallback needs to
      // see the WHOLE line to know that every failure is note-eligible.
      final figures = _lines('Partner swing; face up; fall back');
      expect(figures, hasLength(1));
      expect(figures.single.isCustom, isTrue);
    });

    test('truncation is bounded by the LIMIT, not the input length', () {
      // A hostile note must not pay an allocation proportional to its own
      // length before being cut down: the walk stops at the limit.
      expect(truncateOnRuneBoundary('a' * 2000000, 32).length, 32);
      // Still rune-safe at scale — 👍 is two code units, so a limit of 7 cuts
      // after three runes rather than splitting the fourth.
      final wide = truncateOnRuneBoundary('👍' * 500000, 7);
      expect(wide.length, 6);
      expect(wide.runes.every((r) => r > 0xFFFF), isTrue);
    });

    test('a combined note is bounded', () {
      // Eight clauses is the fallback's cap; each note is itself capped, so the
      // combined note can never grow without bound.
      final line = [
        'Partner swing',
        ...List.filled(7, 'face partner'),
      ].join('; ');
      final only = _one(line);
      expect(only.note!.length, lessThanOrEqualTo(kMaxFigureNote));
    });
  });

  group('paths that must NOT be disturbed', () {
    test('a hey pass list keeps its bracketed `;` (never split)', () {
      final f = parseFigureLine(
        'Hey 1/2 (WR;PL;MR;N2L~)',
        frontEnd: tcbFigureFrontEnd,
      );
      expect(f!.move, 'hey');
      expect(f.note, isNull);
    });

    test('a `||` line still fans into a meanwhile container', () {
      final figures = _lines('Balance the ring || California twirl');
      expect(figures, hasLength(1));
      expect(figures.single.isMeanwhile, isTrue);
      expect(figures.single.params['beats'], 8);
    });

    test('a `;` inside a `||` side is still NOT split (unchanged)', () {
      // `meanwhileFromDoublePipe` parses each side with the SINGULAR parser, so
      // the note fallback cannot reach inside a side. Pinned so the asymmetry
      // is a recorded decision, not an accident.
      final figures = _lines('Men walk forward; face up || Women fall back');
      expect(figures, hasLength(1));
      expect(figures.single.isMeanwhile, isTrue);
      expect(figures.single.subFigures.first.isCustom, isTrue);
    });

    test('an all-structuring compound is untouched', () {
      final figures = _lines('Circle left 3/4; form wave of four');
      expect(figures.map((f) => f.move).toList(), [
        'circle',
        'form_short_waves',
      ]);
      expect(figures.every((f) => f.note == null), isTrue);
    });

    test('a degenerate separator run still declines to split', () {
      _staysWholeCustom('Partner swing;; face up');
    });

    test('a single-clause line is unchanged', () {
      final only = _one('Partner swing');
      expect(only.move, 'swing');
      expect(only.note, isNull);
    });
  });

  group('adapter — end to end', () {
    test('a cross-line fold PRESERVES the consumed figure\'s clause note', () {
      // `Balance the ring; face up` now structures to `balance_the_ring` + a
      // note, is still a balance LINE, and folds into the following swing. The
      // fold `copyWith`s the SURVIVOR, so without note propagation "face up"
      // would be silently dropped — and it was, before this change: the old
      // whole-custom balance line was consumed by the very same fold.
      final figures = _importFigures([
        '(4) Balance the ring; face up',
        '(12) Partner swing',
      ]);
      expect(figures, hasLength(1));
      expect(figures.single.move, 'swing');
      expect(figures.single.params['prefix'], 'balance');
      expect(figures.single.beats, 16); // 4 + 12, unchanged
      expect(figures.single.note, 'face up');
    });

    test('a hall/ender fold keeps the hall\'s clause note', () {
      final figures = _importFigures([
        '(4) Go down the hall; face down',
        '(4) Bend the line',
      ]);
      expect(figures, hasLength(1));
      expect(figures.single.move, 'down_the_hall');
      expect(figures.single.params['ender'], 'bendTheLine');
      expect(figures.single.beats, 8);
      expect(figures.single.note, 'face down');
    });

    test('the dance\'s total beats are unchanged by the fallback', () {
      final figures = _importFigures([
        '(6) Circle left 3/4; face up',
        '(10) Partner swing',
        '(8) Long lines forward and back; finish proper',
        '(8) Pass through; form long wave in center',
      ]);
      expect(figures.fold<int>(0, (a, f) => a + f.beats), 32);
    });

    test('the note is dialect-rendered, so no canonical token reaches the '
        'reader (#717)', () {
      final figures = _importFigures(['(8) Partner swing; face women']);
      expect(figures.single.note, 'face role2s');
      final renderer = FigureRenderer(contraTaxonomy);
      expect(
        renderer.renderFreeText(figures.single.note!, Dialect.larksRobins),
        'face robins',
      );
      expect(
        renderer.renderFreeText(figures.single.note!, Dialect.leadsFollows),
        'face follows',
      );
    });

    test('a role-bearing note is STORED canonical and only RENDERED per '
        'dialect (#715/#717)', () {
      final renderer = FigureRenderer(contraTaxonomy);
      const expected = {
        '(8) Partner swing; women turn around': [
          'role2s turn around',
          'robins turn around',
          'follows turn around',
        ],
        '(8) Partner swing; men turn around': [
          'role1s turn around',
          'larks turn around',
          'leads turn around',
        ],
      };
      for (final entry in expected.entries) {
        final note = _importFigures([entry.key]).single.note!;
        // Stored canonical...
        expect(note, entry.value[0], reason: entry.key);
        // ...and the canonical dialect renders it unchanged, which is exactly
        // why storing the canonical token is correct rather than lossy.
        expect(
          renderer.renderFreeText(note, Dialect.canonical),
          entry.value[0],
          reason: entry.key,
        );
        expect(
          renderer.renderFreeText(note, Dialect.larksRobins),
          entry.value[1],
          reason: entry.key,
        );
        expect(
          renderer.renderFreeText(note, Dialect.leadsFollows),
          entry.value[2],
          reason: entry.key,
        );
      }
    });

    test('a note with NO role token is byte-identical in every dialect', () {
      // The control case for the rule above: dialect rendering only ever
      // touches role terms, so a note that names none must never change.
      final renderer = FigureRenderer(contraTaxonomy);
      const lines = {
        '(8) Partner swing; face up': 'face up',
        '(8) Long lines forward and back; finish proper': 'finish proper',
        '(8) Ones go up outside; return to place': 'return to place',
      };
      for (final entry in lines.entries) {
        final note = _importFigures([entry.key]).single.note!;
        expect(note, entry.value, reason: entry.key);
        for (final dialect in [
          Dialect.canonical,
          Dialect.larksRobins,
          Dialect.leadsFollows,
        ]) {
          expect(
            renderer.renderFreeText(note, dialect),
            entry.value,
            reason: '${entry.key} / ${dialect.name}',
          );
        }
      }
    });

    test('a turn-around line keeps its source beats end to end', () {
      final figures = _importFigures([
        '(4) Petronella turn; women turn around',
        '(12) Partner swing',
      ]);
      expect(figures.fold<int>(0, (a, f) => a + f.beats), 16);
    });
  });
}
