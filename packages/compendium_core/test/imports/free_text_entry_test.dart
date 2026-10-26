import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseFreeTextFigureEntry — empty / whitespace', () {
    test('blank input yields no figures (nothing to insert)', () {
      expect(parseFreeTextFigureEntry(''), isEmpty);
      expect(parseFreeTextFigureEntry('    '), isEmpty);
      expect(parseFreeTextFigureEntry('\t\n '), isEmpty);
    });
  });

  group('parseFreeTextFigureEntry — matched → structured', () {
    test('a recognised line becomes a single structured taxonomy figure', () {
      final fs = parseFreeTextFigureEntry('Neighbor swing');
      expect(fs, hasLength(1));
      final f = fs.single;
      expect(f.isCustom, isFalse);
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
    });

    test('recognition matches the same line an import would produce', () {
      final f = parseFreeTextFigureEntry('neighbors balance & swing').single;
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
      expect(f.params['prefix'], 'balance');
    });
  });

  group('parseFreeTextFigureEntry — `;` compound (all-or-nothing)', () {
    test('a compound where every clause structures yields one row per clause '
        'in order', () {
      final fs = parseFreeTextFigureEntry('Circle left 3/4; turn alone');
      expect(fs.map((f) => f.move), ['circle', 'turn_alone']);
      expect(fs.every((f) => !f.isCustom), isTrue);
    });

    test('a three-clause fully-structured compound emits three rows', () {
      final fs = parseFreeTextFigureEntry(
        'Circle left 3/4; pass through across; turn alone',
      );
      expect(fs.map((f) => f.move), ['circle', 'pass_through', 'turn_alone']);
    });

    test('all-or-nothing: a clause that cannot structure keeps the WHOLE line '
        'as one custom figure', () {
      final fs = parseFreeTextFigureEntry('Star right 3/4; form new wave');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.params['text'], contains('Star right 3/4'));
      expect(fs.single.params['text'], contains('form new wave'));
    });

    test('a top-level `||` (simultaneity) fans into a `meanwhile` container '
        '(#591/#572)', () {
      final fs = parseFreeTextFigureEntry(
        'Balance the ring || California twirl',
      );
      expect(fs, hasLength(1));
      final container = fs.single;
      expect(container.isCustom, isFalse);
      expect(container.isMeanwhile, isTrue);
      expect(container.subFigures.map((f) => f.move), [
        'balance_the_ring',
        'california_twirl',
      ]);
      expect(container.subFigures.every((f) => !f.isCustom), isTrue);
    });
  });

  group('parseFreeTextFigureEntry — unparsed → importGap custom', () {
    test('an unrecognised line becomes a custom tagged importGap '
        '(reparse-eligible, not userEntered)', () {
      final fs = parseFreeTextFigureEntry('flourish and spin the widget');
      expect(fs, hasLength(1));
      final f = fs.single;
      expect(f.isCustom, isTrue);
      expect(f.customOrigin, CustomOrigin.importGap);
    });

    test('an unrecognised line with no inline beats stays beats-absent', () {
      final f = parseFreeTextFigureEntry('flourish and spin the widget').single;
      expect(f.params.containsKey('beats'), isFalse);
      expect(f.beats, 0);
    });
  });

  group('parseFreeTextFigureEntry — inline beats', () {
    test('leading "N …" is captured as the beat count', () {
      final f = parseFreeTextFigureEntry('16 Neighbor swing').single;
      expect(f.move, 'swing');
      expect(f.params['who'], 'neighbors');
      expect(f.params['beats'], 16);
    });

    test('trailing "… (N)" is captured as the beat count', () {
      final f = parseFreeTextFigureEntry('Neighbor swing (16)').single;
      expect(f.move, 'swing');
      expect(f.params['beats'], 16);
    });

    test('leading inline beats ride on the first clause of a `;` compound', () {
      final fs = parseFreeTextFigureEntry('8 Circle left 3/4; turn alone');
      expect(fs, hasLength(2));
      expect(fs[0].beats, 8);
      expect(fs[1].beats, 0);
    });

    test('a fraction glued to leading digits is NOT read as a beat count', () {
      // "1/2 hey" has no space after the leading "1", so the leading-beats
      // pattern does not fire — the whole token survives into the parser.
      final f = parseFreeTextFigureEntry('1/2 hey for four').single;
      expect(f.params.containsKey('beats'), isFalse);
    });

    test('a trailing prose annotation is NOT read as a beat count', () {
      final f = parseFreeTextFigureEntry('Neighbor swing (smooth)').single;
      // The trailing "(smooth)" is not digits-only, so no beats are extracted;
      // the leftover prose forces the honest custom fallback.
      expect(f.params.containsKey('beats'), isFalse);
    });

    test('an absurdly long digit run is treated as text, not beats', () {
      final f = parseFreeTextFigureEntry('99999 Neighbor swing').single;
      // 5 digits exceeds the inline-beat bound, so it is left in the text.
      expect(f.params['beats'], isNot(99999));
    });

    test('a trailing "(0)" is not stripped as a beat count', () {
      // 0 is "unspecified" downstream, so peeling a `(0)` token would silently
      // mutate the user's line for no gain. The token is left in place and no
      // explicit beats param is set (the parser tolerates the parenthetical).
      final f = parseFreeTextFigureEntry('Neighbor swing (0)').single;
      expect(f.params.containsKey('beats'), isFalse);
      expect(f.beats, 0);
    });

    test(
      'a leading "0 " is left in the text, not stripped as a beat count',
      () {
        final f = parseFreeTextFigureEntry('0 Neighbor swing').single;
        expect(f.params.containsKey('beats'), isFalse);
        // The literal "0" survives into the parser rather than being dropped.
        expect(f.isCustom, isTrue);
        expect(f.params['text'], contains('0 Neighbor swing'));
      },
    );

    test('only one inline form is honoured: a trailing "(N)" wins and the '
        'leftover leading digits stay in the text', () {
      final f = parseFreeTextFigureEntry('16 Neighbor swing (8)').single;
      // Trailing (8) is peeled first; the leading "16 " remains, so the line no
      // longer matches and degrades to a verbatim custom carrying the 8 beats.
      expect(f.params['beats'], 8);
      expect(f.isCustom, isTrue);
      expect(f.params['text'], contains('16 Neighbor swing'));
    });
  });

  group('parseFreeTextFigureEntry — a count is never silently dropped '
      '(#1824)', () {
    test('a leading "(N)" is the beat count, like a trailing one', () {
      final f = parseFreeTextFigureEntry('(16) swing').single;
      expect(f.move, 'swing');
      expect(f.params['beats'], 16);
    });

    test('a bracketed "[N]" count is read at either end', () {
      final lead = parseFreeTextFigureEntry('[8] circle left').single;
      expect(lead.move, 'circle');
      expect(lead.params['beats'], 8);
      final trail = parseFreeTextFigureEntry('neighbor swing [16]').single;
      expect(trail.move, 'swing');
      expect(trail.params['beats'], 16);
    });

    test(
      'a second stated count the parser would drop keeps the line whole',
      () {
        final f = parseFreeTextFigureEntry('(16) swing (8)').single;
        expect(f.isCustom, isTrue);
        expect(f.params['text'], '(16) swing (8)');
        expect(f.params['beats'], 8);
      },
    );

    test('a count too long to be beats is kept in a custom, not dropped', () {
      for (final line in ['(99999) gibberish xyz', 'gibberish xyz [99999]']) {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.isCustom, isTrue, reason: line);
        expect(f.params['text'], line);
      }
    });

    test(
      'a count too long to be beats on a move is kept as a note (#1863)',
      () {
        final lead = parseFreeTextFigureEntry('(99999) swing').single;
        expect(lead.move, 'swing');
        expect(lead.note, '99999');
        final tail = parseFreeTextFigureEntry('swing [99999]').single;
        expect(tail.move, 'swing');
        expect(tail.note, '99999');
      },
    );

    test('a bracketed count glued to the move is still a count', () {
      final lead = parseFreeTextFigureEntry('(16)swing').single;
      expect(lead.move, 'swing');
      expect(lead.params['beats'], 16);
      final both = parseFreeTextFigureEntry('swing(16)(8)').single;
      expect(both.isCustom, isTrue);
      expect(both.params['text'], 'swing(16)(8)');
    });

    test('re-parse never drops a count a free-text custom kept', () {
      for (final line in [
        '(99999) gibberish xyz',
        '(99999) swing (8)',
        '(16) swing (8)',
      ]) {
        final custom = parseFreeTextFigureEntry(line);
        final out = reparseImportGapFigures(custom);
        expect(out.upgradedCount, 0, reason: line);
        expect(out.figures.single.params['text'], line);
      }
    });

    test('re-parse peels the count the beats already state', () {
      final custom = customFigure(
        '16 neighbor swing',
        beats: 16,
        origin: CustomOrigin.importGap,
      );
      final out = reparseImportGapFigures([custom]);
      expect(out.upgradedCount, 1);
      expect(out.figures.single.move, 'swing');
      expect(out.figures.single.params['beats'], 16);
    });

    test('a zero count stays unspecified and tolerated, as before', () {
      final f = parseFreeTextFigureEntry('(0) swing').single;
      expect(f.isCustom, isFalse);
      expect(f.params.containsKey('beats'), isFalse);
    });

    test('a compound that fails keeps every clause\'s count in its text', () {
      final f = parseFreeTextFigureEntry(
        '8 neighbor swing; 8 gibberish xyz',
      ).single;
      expect(f.isCustom, isTrue);
      expect(f.params['text'], '8 neighbor swing; 8 gibberish xyz');
    });

    test('a compound whose clauses each state a count keeps both (#1870)', () {
      final fs = parseFreeTextFigureEntry('8 neighbor swing; 8 partner swing');
      expect(fs.map((f) => f.move), ['swing', 'swing']);
      expect(fs.map((f) => f.params['beats']), [8, 8]);
    });

    test('a custom keeps the typed count in its text, beats alongside', () {
      final lead = parseFreeTextFigureEntry('16 foo bar').single;
      expect(lead.params['text'], '16 foo bar');
      expect(lead.params['beats'], 16);
      final trail = parseFreeTextFigureEntry('foo bar (16)').single;
      expect(trail.params['text'], 'foo bar (16)');
      expect(trail.params['beats'], 16);
    });

    test('a line that structures is unchanged by the verbatim rule', () {
      final fs = parseFreeTextFigureEntry('8 neighbor swing; partner swing');
      expect(fs, hasLength(2));
      expect(fs.every((f) => !f.isCustom), isTrue);
      expect(fs.first.params['beats'], 8);
    });
  });

  group('parseFreeTextFigureEntry — a count on any `;` clause is that '
      "clause's own (#1870)", () {
    List<Object?> beatsOf(List<Figure> fs) => [
      for (final f in fs) f.params['beats'],
    ];

    test('a bracketed count on the first clause stays on it', () {
      for (final line in [
        'circle left (8); turn alone',
        'circle left [8]; turn alone',
        'circle left (8 beats); turn alone',
        'circle left 3/4 (8); turn alone',
      ]) {
        final fs = parseFreeTextFigureEntry(line);
        expect(fs.map((f) => f.move), ['circle', 'turn_alone'], reason: line);
        expect(beatsOf(fs), [8, null], reason: line);
        expect(fs.any((f) => f.note != null), isFalse, reason: line);
      }
    });

    test('a count on a later clause stays on that clause', () {
      final fs = parseFreeTextFigureEntry('turn alone; circle left (8)');
      expect(fs.map((f) => f.move), ['turn_alone', 'circle']);
      expect(beatsOf(fs), [null, 8]);
      final tail = parseFreeTextFigureEntry('circle left; turn alone (4)');
      expect(tail.map((f) => f.move), ['circle', 'turn_alone']);
      expect(beatsOf(tail), [null, 4]);
    });

    test('every clause keeps its own count', () {
      final fs = parseFreeTextFigureEntry(
        'circle left (8); turn alone (4); neighbor swing [16]',
      );
      expect(fs.map((f) => f.move), ['circle', 'turn_alone', 'swing']);
      expect(beatsOf(fs), [8, 4, 16]);
      final bare = parseFreeTextFigureEntry(
        'circle left; 4 turn alone; neighbor swing 16 beats',
      );
      expect(bare.map((f) => f.move), ['circle', 'turn_alone', 'swing']);
      expect(beatsOf(bare), [null, 4, 16]);
    });

    test('a clause whose count cannot be honoured keeps the whole line '
        'as a custom, typed text intact', () {
      for (final line in [
        // A clause no parse reads.
        'gibberish xyz; circle left (8)',
        // A clause that is only a note, so which figure a later count
        // belongs to is a guess.
        'circle left (8); gibberish xyz; turn alone (4)',
        'circle left; face up; turn alone (4)',
        'circle left; face up (4)',
        // A later count the beats range (0..64) refuses, as it does on the
        // first clause or a one-clause line.
        'circle left; turn alone (100)',
        'circle left (64); turn alone (65)',
        // A second count on one clause: the parser would drop one.
        'circle left (8) (4); turn alone',
        // A count too long to be beats, on a clause that is not read.
        'gibberish xyz (99999); turn alone',
      ]) {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.isCustom, isTrue, reason: line);
        expect(f.params['text'], line, reason: line);
      }
    });

    test('a shorthand clause and a counted clause each keep their own', () {
      final shorthands = ShorthandMappings([
        ShorthandMapping(
          token: 'pbs',
          figures: [
            Figure(move: 'swing', params: const {'who': 'partners'}),
          ],
        ),
      ]);
      final first = parseFreeTextFigureEntry(
        'circle left (8); pbs',
        shorthands: shorthands,
      );
      expect(first.map((f) => f.move), ['circle', 'swing']);
      expect(beatsOf(first), [8, null]);
      final second = parseFreeTextFigureEntry(
        'pbs; circle left (8)',
        shorthands: shorthands,
      );
      expect(second.map((f) => f.move), ['swing', 'circle']);
      expect(beatsOf(second), [null, 8]);
      // No shorthand in the line: the same reading as without a store.
      final none = parseFreeTextFigureEntry(
        'circle left (8); turn alone',
        shorthands: shorthands,
      );
      expect(beatsOf(none), [8, null]);
    });

    test('a clause that is only a note to the one before keeps working', () {
      final f = parseFreeTextFigureEntry('circle left (8); face up').single;
      expect(f.move, 'circle');
      expect(f.params['beats'], 8);
      expect(f.note, 'face up');
    });

    test('forms that already worked are unchanged', () {
      // A count at the line's start is the first clause's.
      final lead = parseFreeTextFigureEntry('(8) circle left; turn alone');
      expect(lead.map((f) => f.move), ['circle', 'turn_alone']);
      expect(beatsOf(lead), [8, null]);
      // A count-free compound gets no beats.
      final plain = parseFreeTextFigureEntry('circle left 3/4; turn alone');
      expect(beatsOf(plain), [null, null]);
      // A bare number with no unit is not a count; the line stays custom.
      final bare = parseFreeTextFigureEntry('circle left 8; turn alone');
      expect(bare.single.isCustom, isTrue);
      expect(bare.single.params['text'], 'circle left 8; turn alone');
      // One clause: the count is the line's, as ever.
      expect(beatsOf(parseFreeTextFigureEntry('circle left (8)')), [8]);
    });
  });

  group('parseFreeTextFigureEntry — a count that cannot be beats takes the '
      'figure\'s default (#1863)', () {
    // What the figure picker gives the same move and options: no explicit
    // beats, the default derived on read.
    final picked = Figure(move: 'circle', params: const {'direction': 'left'});
    final pickedBeats = contraTaxonomy.effectiveParams(picked)['beats'];

    void expectDefaultWithNote(String line, String note) {
      final f = parseFreeTextFigureEntry(line).single;
      expect(f.isCustom, isFalse, reason: line);
      expect(f.move, 'circle', reason: line);
      expect(f.params['direction'], 'left', reason: line);
      expect(f.params.containsKey('beats'), isFalse, reason: line);
      expect(contraTaxonomy.effectiveParams(f)['beats'], pickedBeats);
      expect(f.note, note, reason: line);
    }

    test('five or more digits read as the move at its default beats, the '
        'number kept as a note', () {
      expectDefaultWithNote('circle left 10000 beats', '10000 beats');
      expectDefaultWithNote('circle left (10000)', '10000');
      expectDefaultWithNote('circle left [10000 beats]', '10000 beats');
      expectDefaultWithNote('10000 circle left', '10000');
      expectDefaultWithNote('10000 beats circle left', '10000 beats');
      expectDefaultWithNote('(10000) circle left', '10000');
      // Longer than any int: never parsed, so it cannot overflow.
      expectDefaultWithNote('circle left (${'9' * 40})', '9' * 40);
    });

    test('a count of up to four digits over the 0..64 range is left to the '
        'range check, as before: a custom whose beats are the count', () {
      for (final line in [
        'circle left 65 beats',
        'circle left (100)',
        '9999 circle left',
      ]) {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.isCustom, isTrue, reason: line);
        expect(f.params['text'], line, reason: line);
        expect(f.note, isNull, reason: line);
      }
    });

    test('a count in range is still the beats, and 64 is the last one', () {
      final ok = parseFreeTextFigureEntry('circle left 64 beats').single;
      expect(ok.params['beats'], 64);
      expect(ok.note, isNull);
    });

    test(
      'on a `;` clause the number stays on the clause it was typed with',
      () {
        final last = parseFreeTextFigureEntry(
          'circle left; turn alone (10000)',
        );
        expect(last.map((f) => f.move), ['circle', 'turn_alone']);
        expect(last[0].note, isNull);
        expect(last[1].note, '10000');
        expect(last[1].params.containsKey('beats'), isFalse);
        final alone = parseFreeTextFigureEntry(
          'circle left (10000); turn alone',
        );
        expect(alone.map((f) => f.move), ['circle', 'turn_alone']);
        expect(alone[0].note, '10000');
        expect(alone[1].note, isNull);
        final first = parseFreeTextFigureEntry(
          '10000 beats circle left; turn alone (4)',
        );
        expect(first.map((f) => f.move), ['circle', 'turn_alone']);
        expect(first[0].note, '10000 beats');
        expect(first[0].params.containsKey('beats'), isFalse);
        expect(first[1].params['beats'], 4);
      },
    );

    test('a valid count elsewhere on the line wins and the long one is kept '
        'whole, as a second count always is', () {
      for (final line in [
        '10000 circle left (8)',
        'circle left 10000 beats (8)',
        '(10000) circle left (20000)',
      ]) {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.isCustom, isTrue, reason: line);
        expect(f.params['text'], line, reason: line);
      }
    });

    test(
      'a line the parser cannot read stays a custom with its typed text',
      () {
        for (final line in ['gibberish xyz 10000 beats', '(10000) gibberish']) {
          final f = parseFreeTextFigureEntry(line).single;
          expect(f.isCustom, isTrue, reason: line);
          expect(f.params['text'], line, reason: line);
          expect(f.params.containsKey('beats'), isFalse, reason: line);
        }
      },
    );

    test('a bare trailing number is still not a count', () {
      final f = parseFreeTextFigureEntry('circle left 10000').single;
      expect(f.isCustom, isTrue);
      expect(f.params['text'], 'circle left 10000');
    });

    test('re-check upgrades a custom stored with the long count as before', () {
      final custom = customFigure(
        'circle left 10000 beats',
        origin: CustomOrigin.importGap,
      );
      final out = reparseImportGapFigures([custom]);
      expect(out.upgradedCount, 1);
      expect(out.figures.single.move, 'circle');
      expect(out.figures.single.params.containsKey('beats'), isFalse);
      expect(out.figures.single.note, contains('10000'));
    });

    test('re-check keeps a bracketed long count custom, never dropping it', () {
      final custom = customFigure(
        'circle left (10000)',
        origin: CustomOrigin.importGap,
      );
      final out = reparseImportGapFigures([custom]);
      expect(out.upgradedCount, 0);
      expect(out.figures.single.params['text'], 'circle left (10000)');
    });
  });

  group('parseFreeTextFigureEntry — bounded input (OWASP)', () {
    test('a line exactly at the length bound is still processed', () {
      // A non-trimmable payload exactly at the bound is not dropped: it flows
      // to the parser and becomes a (verbatim custom) figure, not nothing.
      final atBound = 'a' * maxFreeTextEntryLength;
      final fs = parseFreeTextFigureEntry(atBound);
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
    });

    test('a line past the length bound yields nothing (never throws)', () {
      final huge = 'a' * (maxFreeTextEntryLength + 1);
      expect(parseFreeTextFigureEntry(huge), isEmpty);
    });

    test(
      'length is checked after trimming, so whitespace padding is ignored',
      () {
        final padded = '  Neighbor swing  '.padRight(
          maxFreeTextEntryLength + 50,
          ' ',
        );
        expect(parseFreeTextFigureEntry(padded).single.move, 'swing');
      },
    );
  });

  group('parseFreeTextFigureEntry — no inline beats → taxonomy default', () {
    test('a matched figure with no inline beats carries no explicit beats and '
        'derives its default on read via effectiveParams', () {
      final f = parseFreeTextFigureEntry('Neighbor swing').single;
      // parseFigureLine only sets beats when > 0, so the structured figure
      // leaves beats unspecified…
      expect(f.params.containsKey('beats'), isFalse);
      // …and the taxonomy derives the move/param default (swing prefix none →
      // 8) on read, never a forced literal 0.
      expect(contraTaxonomy.effectiveParams(f)['beats'], 8);
    });

    test('a balance-prefixed swing derives its 16-beat default', () {
      final f = parseFreeTextFigureEntry('neighbors balance & swing').single;
      expect(f.params.containsKey('beats'), isFalse);
      expect(contraTaxonomy.effectiveParams(f)['beats'], 16);
    });
  });

  group('parseFreeTextFigureEntry — reparse upgrade path', () {
    // A minimal taxonomy that recognises no moves: every structured candidate
    // fails validation, so a typed line degrades to an importGap custom exactly
    // as it would have under an older/leaner taxonomy.
    final emptyTaxonomy = Taxonomy(
      version: 1,
      form: DanceForm.contra,
      moves: const [],
    );

    test('a locally-typed importGap custom is upgraded once the taxonomy can '
        'recognise its text; a userEntered custom is left untouched', () {
      // Type "Neighbor swing" against a taxonomy that cannot validate it → the
      // free-text path keeps it as an importGap custom (the #398 flag).
      final typed = parseFreeTextFigureEntry(
        'Neighbor swing',
        taxonomy: emptyTaxonomy,
      ).single;
      expect(typed.isCustom, isTrue);
      expect(typed.customOrigin, CustomOrigin.importGap);

      // A user-authored custom carrying the SAME text must NOT be touched by
      // the reparse — only importGap customs are eligible.
      final authored = typed.copyWith(customOrigin: CustomOrigin.userEntered);

      final outcome = reparseImportGapFigures([
        typed,
        authored,
      ], taxonomy: contraTaxonomy);
      expect(outcome.upgradedCount, 1);
      expect(outcome.figures[0].isCustom, isFalse);
      expect(outcome.figures[0].move, 'swing');
      expect(outcome.figures[0].params['who'], 'neighbors');
      // The userEntered custom is preserved byte-identical.
      expect(outcome.figures[1], authored);
    });
  });

  group('parseFreeTextFigureEntry — fan-out across source front-ends', () {
    test(
      'a shorthand hit STILL wins over the fan-out parse (shorthand-first)',
      () {
        // The fan-out would structure "neighbor swing" to swing/who:neighbors,
        // but a shorthand mapping for the same whole-line token must short-circuit
        // FIRST and return its own target (swing/who:partners) verbatim.
        final shorthands = ShorthandMappings([
          ShorthandMapping(
            token: 'neighbor swing',
            figures: [
              Figure(move: 'swing', params: const {'who': 'partners'}),
            ],
          ),
        ]);
        final fs = parseFreeTextFigureEntry(
          'neighbor swing',
          shorthands: shorthands,
        );
        expect(fs, hasLength(1));
        expect(fs.single.move, 'swing');
        expect(fs.single.params['who'], 'partners');
      },
    );

    test('a CallersBox/TCB hey pass-list structures through the fan-out', () {
      // Only the TCB front-end decodes the parenthetical pass list; the ContraDB
      // (canonical) attempt misses first, so this proves the fan-out reaches the
      // CallersBox front-end.
      final fs = parseFreeTextFigureEntry('hey 1/2 (ml;pr)');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isFalse);
      expect(fs.single.move, 'hey');
    });

    test('an unrecognised line still degrades to an import-gap custom', () {
      final fs = parseFreeTextFigureEntry('qwx zzz nonsense (16)');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.customOrigin, CustomOrigin.importGap);
      // The trailing inline beat is peeled before the fan-out parse and rides
      // on the custom, whose text stays as typed (#1824).
      expect(fs.single.params['beats'], 16);
      expect(fs.single.params['text'], 'qwx zzz nonsense (16)');
    });
  });

  group('parseFreeTextFigureEntry — active dialect', () {
    test('a role word from the active dialect parses (Follows chain)', () {
      final fs = parseFreeTextFigureEntry(
        'Follows chain',
        dialect: Dialect.leadsFollows,
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isFalse);
      expect(fs.single.move, 'chain');
      expect(fs.single.params['who'], 'role2s');
    });

    test('the raw line is tried first: `lead` stays a move word', () {
      final fs = parseFreeTextFigureEntry(
        'ones lead down the hall',
        dialect: Dialect.leadsFollows,
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isFalse);
      expect(fs.single.move, 'down_the_hall');
    });

    test('a miss under the dialect keeps the typed text in the custom', () {
      final fs = parseFreeTextFigureEntry(
        'qwx follows nonsense',
        dialect: Dialect.leadsFollows,
      );
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.params['text'], 'qwx follows nonsense');
    });

    test('without a dialect, Follows chain still degrades to a custom', () {
      final fs = parseFreeTextFigureEntry('Follows chain');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
    });
  });
  group('parseFreeTextFigureEntry — common phrasings (COL-02)', () {
    // Each row: typed line, expected move, expected params (subset).
    const structured = <(String, String, Map<String, Object?>)>[
      (
        'half hey, ladies start by the right',
        'hey',
        {'length': 'half', 'pass1': 'role2s', 'shoulder': 'right'},
      ),
      ('N swing', 'swing', {'who': 'neighbors'}),
      ('neighbours balance and swing', 'swing', {'who': 'neighbors'}),
      ('N2 neighbor swing', 'swing', {'who': 'nextNeighbors'}),
    ];
    for (final (line, move, params) in structured) {
      test('"$line" → structured $move', () {
        final fs = parseFreeTextFigureEntry(line);
        expect(fs, hasLength(1));
        expect(fs.single.isCustom, isFalse, reason: 'got ${fs.single.params}');
        expect(fs.single.move, move);
        params.forEach((k, v) => expect(fs.single.params[k], v, reason: k));
      });
    }

    test('"ladies chain over and back" is never a note-bearing chain', () {
      final fs = parseFreeTextFigureEntry('ladies chain over and back');
      expect(fs.any((f) => f.note == 'and back'), isFalse);
      expect(fs.single.isCustom, isTrue);
    });

    // "X chain back" is ordinary phrasing for the return chain: the brief's
    // leftover rule is "and back", not a bare "back" (the sweep's corpus diff
    // found these structured at cb40eb5 and custom after CS-45d).
    for (final line in [
      'Ladies chain back',
      'Robins chain back',
      'ladies chain, back',
    ]) {
      test('"$line" stays a structured chain', () {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.isCustom, isFalse);
        expect(f.move, 'chain');
      });
    }

    for (final line in [
      'ladies chain, and back',
      'ladies chain, over and back',
      'ladies chain, then over and back',
      'ladies chain, and over and back',
    ]) {
      test('"$line" is still demoted', () {
        final fs = parseFreeTextFigureEntry(line);
        expect(fs.any((f) => (f.note ?? '').endsWith('and back')), isFalse);
        expect(fs.single.isCustom, isTrue);
      });
    }

    test('"neighbors swing 16" is 16 beats or custom, never 8 + note', () {
      final f = parseFreeTextFigureEntry('neighbors swing 16').single;
      expect(f.note, isNull);
      if (!f.isCustom) expect(f.beats, 16);
    });

    test('a leftover move name is demoted to custom, not a note', () {
      final f = parseFreeTextFigureEntry('neighbors swing petronella').single;
      expect(f.isCustom, isTrue);
    });

    test('a note-tail rejected in a while-container stays custom', () {
      final fs = parseFreeTextFigureEntry(
        'neighbors swing 16 while partners swing',
      );
      expect(fs.single.isCustom, isTrue);
    });

    test('entry → reparse: a demoted custom is not upgraded back to a swing '
        'with note "16"', () {
      final typed = parseFreeTextFigureEntry('neighbors swing 16').single;
      expect(typed.isCustom, isTrue);
      final outcome = reparseImportGapFigures([typed]);
      expect(outcome.upgradedCount, 0);
      expect(outcome.figures.single.isCustom, isTrue);
      expect(outcome.figures.single.customOrigin, CustomOrigin.importGap);
    });

    test('bare "give and take" is the move as typed (#1826), stating no '
        'giver or target; imports still keep it custom', () {
      final fs = parseFreeTextFigureEntry('give and take');
      expect(fs, hasLength(1));
      expect(fs.single.move, 'give_and_take');
      expect(fs.single.params, isEmpty);
      expect(parseFigureLinesFanOut('give and take').single.isCustom, isTrue);
    });
  });

  group(
    'parseFreeTextFigureEntry — shorthands with a count or a `;` (#1827)',
    () {
      final pbs = Figure(move: 'swing', params: const {'who': 'partners'});
      final shorthands = ShorthandMappings([
        ShorthandMapping(token: 'pbs', figures: [pbs]),
        ShorthandMapping(
          token: 'combo',
          figures: [
            Figure(move: 'swing', params: const {'who': 'partners'}),
            Figure(move: 'turn_alone'),
          ],
        ),
        ShorthandMapping(token: '3 swings', figures: [pbs]),
      ]);

      test(
        '`16 pbs` applies the leading count to the one-figure shorthand',
        () {
          final fs = parseFreeTextFigureEntry('16 pbs', shorthands: shorthands);
          expect(fs, hasLength(1));
          expect(fs.single.isCustom, isFalse);
          expect(fs.single.move, 'swing');
          expect(fs.single.params['who'], 'partners');
          expect(fs.single.params['beats'], 16);
        },
      );

      test('`pbs (16)` applies the trailing count', () {
        final fs = parseFreeTextFigureEntry('pbs (16)', shorthands: shorthands);
        expect(fs, hasLength(1));
        expect(fs.single.move, 'swing');
        expect(fs.single.params['beats'], 16);
      });

      test('a count on a multi-figure shorthand leaves the expansion as saved '
          '(the count has no single figure to land on)', () {
        for (final line in ['8 combo', 'combo (8)']) {
          final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
          expect(fs.map((f) => f.move), ['swing', 'turn_alone'], reason: line);
          expect(fs.any((f) => f.params.containsKey('beats')), isFalse);
        }
      });

      test('a count on a shorthand for one container sets the container\'s own '
          'beats', () {
        final container = ShorthandMappings([
          ShorthandMapping(
            token: 'mw',
            figures: [
              Figure.meanwhile(
                figures: [
                  Figure(move: 'swing', params: const {'who': 'partners'}),
                  Figure(move: 'turn_alone'),
                ],
                beats: 8,
              ),
            ],
          ),
        ]);
        final fs = parseFreeTextFigureEntry('16 mw', shorthands: container);
        expect(fs.single.isMeanwhile, isTrue);
        expect(fs.single.params['beats'], 16);
        expect(fs.single.subFigures, hasLength(2));
      });

      test('a token that itself starts with a number still matches whole-line '
          'first', () {
        final fs = parseFreeTextFigureEntry('3 swings', shorthands: shorthands);
        expect(fs.single.move, 'swing');
        expect(fs.single.params['who'], 'partners');
        expect(fs.single.params.containsKey('beats'), isFalse);
      });

      test('a count in front of an unknown word is not a shorthand', () {
        final fs = parseFreeTextFigureEntry(
          '16 zzqx widget',
          shorthands: shorthands,
        );
        expect(fs.single.isCustom, isTrue);
      });

      test('`pbs; ladies chain` expands the shorthand clause and parses the '
          'other', () {
        final fs = parseFreeTextFigureEntry(
          'pbs; ladies chain',
          shorthands: shorthands,
        );
        expect(fs.map((f) => f.move), ['swing', 'chain']);
        expect(fs.any((f) => f.isCustom), isFalse);
        expect(fs.first.params['who'], 'partners');
      });

      test('each `;` clause takes its own count', () {
        final fs = parseFreeTextFigureEntry(
          '8 pbs; pbs (4)',
          shorthands: shorthands,
        );
        expect(fs.map((f) => f.params['beats']), [8, 4]);
      });

      test('all-or-nothing holds: one clause that cannot structure keeps the '
          'whole line one custom', () {
        final fs = parseFreeTextFigureEntry(
          'pbs; zzqx widget',
          shorthands: shorthands,
        );
        expect(fs, hasLength(1));
        expect(fs.single.isCustom, isTrue);
      });

      test('a line of more than $maxShorthandTargetFigures clauses is not '
          'expanded clause by clause', () {
        final line = List.filled(
          maxShorthandTargetFigures + 1,
          'pbs',
        ).join('; ');
        final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
        expect(fs, hasLength(1));
        expect(fs.single.isCustom, isTrue);
      });

      test('a `;` line with no shorthand clause is unchanged', () {
        final fs = parseFreeTextFigureEntry(
          'Circle left 3/4; turn alone',
          shorthands: shorthands,
        );
        expect(fs.map((f) => f.move), ['circle', 'turn_alone']);
      });

      group('a count outside the beats range (#1879)', () {
        // The shape a non-shorthand line with the same count has (#1878,
        // #1880): the rule a shorthand follows, so the two cannot drift.
        void expectKeptWhole(String line, String sibling) {
          final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
          final twin = parseFreeTextFigureEntry(sibling).single;
          expect(fs, hasLength(1), reason: line);
          expect(fs.single.isCustom, isTrue, reason: line);
          expect(fs.single.params['text'], line, reason: line);
          expect(fs.single.params['beats'], twin.params['beats'], reason: line);
          expect(fs.single.note, isNull, reason: line);
        }

        test('65..9999 on a one-figure shorthand keeps the whole line custom, '
            'as `circle left (100)` is', () {
          expectKeptWhole('pbs (100)', 'circle left (100)');
          expectKeptWhole('100 pbs', '100 circle left');
          expectKeptWhole('pbs (65)', 'circle left (65)');
          expectKeptWhole('pbs [100 beats]', 'circle left [100 beats]');
          expectKeptWhole('9999 pbs', '9999 circle left');
        });

        test('5 or more digits take the figure as saved, default beats, with '
            'the count in its note, as `circle left (10000)` does', () {
          for (final line in ['pbs (10000)', '10000 pbs', 'pbs 10000 beats']) {
            final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
            expect(fs, hasLength(1), reason: line);
            expect(fs.single.move, 'swing', reason: line);
            expect(fs.single.params['who'], 'partners', reason: line);
            expect(fs.single.params.containsKey('beats'), isFalse);
            expect(fs.single.note, startsWith('10000'), reason: line);
          }
        });

        test('a multi-figure shorthand drops any count, as it does an in-range '
            'one, so nothing invalid is made', () {
          for (final line in ['combo (100)', '100 combo', 'combo (10000)']) {
            final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
            expect(fs.map((f) => f.move), [
              'swing',
              'turn_alone',
            ], reason: line);
            expect(fs.every((f) => f.note == null), isTrue, reason: line);
            expect(fs.every((f) => !f.params.containsKey('beats')), isTrue);
          }
        });

        test('in a `;` line the whole line stays custom with its text as '
            'typed, whichever clause holds the count', () {
          for (final line in [
            'pbs (100); circle left',
            'circle left; pbs (100)',
            'pbs; 100 pbs',
            'pbs (64); pbs (65)',
          ]) {
            final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
            expect(fs, hasLength(1), reason: line);
            expect(fs.single.isCustom, isTrue, reason: line);
            expect(fs.single.params['text'], line, reason: line);
          }
        });

        test('5 or more digits on a `;` clause ride on that clause', () {
          final fs = parseFreeTextFigureEntry(
            'pbs (10000); circle left',
            shorthands: shorthands,
          );
          expect(fs.map((f) => f.move), ['swing', 'circle']);
          expect(fs.first.note, '10000');
          expect(fs.last.note, isNull);
        });

        test('64 is the last count a shorthand takes, 1 the first', () {
          for (final (line, beats) in [
            ('pbs (64)', 64),
            ('64 pbs', 64),
            ('pbs (1)', 1),
            ('pbs (64); circle left', 64),
            ('circle left; 64 pbs', 64),
          ]) {
            final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
            expect(fs.every((f) => !f.isCustom), isTrue, reason: line);
            expect(
              fs.firstWhere((f) => f.move == 'swing').params['beats'],
              beats,
              reason: line,
            );
          }
        });

        test('a zero count is no count: the line stays custom as typed', () {
          for (final line in ['pbs (0)', '0 pbs']) {
            final fs = parseFreeTextFigureEntry(line, shorthands: shorthands);
            expect(fs.single.isCustom, isTrue, reason: line);
            expect(fs.single.params['text'], line, reason: line);
          }
        });
      });
    },
  );

  group('shorthandTokenShadowsFigure (#1827)', () {
    test('is true for a token that already parses to figures', () {
      expect(shorthandTokenShadowsFigure('swing'), isTrue);
      expect(shorthandTokenShadowsFigure('  Neighbor swing '), isTrue);
      expect(
        shorthandTokenShadowsFigure('Circle left 3/4; turn alone'),
        isTrue,
      );
    });

    test('is false for a token that would only be a custom, or is empty', () {
      expect(shorthandTokenShadowsFigure('pbs'), isFalse);
      expect(shorthandTokenShadowsFigure('zzqx widget'), isFalse);
      expect(shorthandTokenShadowsFigure('   '), isFalse);
    });

    test('is false when any clause stays custom', () {
      expect(shorthandTokenShadowsFigure('swing; zzqx widget'), isFalse);
    });
  });

  group('splitShorthandClauses (#1866)', () {
    test('splits at top-level ; and trims each clause', () {
      expect(splitShorthandClauses('zm ;  ladies chain'), [
        'zm',
        'ladies chain',
      ]);
      expect(splitShorthandClauses('zm'), ['zm']);
    });

    test('keeps a bracketed ; inside its clause', () {
      expect(splitShorthandClauses('zm; pass (PR;WL)'), ['zm', 'pass (PR;WL)']);
    });

    test('declines an empty clause', () {
      expect(splitShorthandClauses('zm;;swing'), isNull);
      expect(splitShorthandClauses('zm;'), isNull);
    });

    test('allows 64 clauses and declines 65', () {
      expect(
        splitShorthandClauses(List.filled(64, 'zm').join(';')),
        hasLength(64),
      );
      expect(splitShorthandClauses(List.filled(65, 'zm').join(';')), isNull);
    });
  });

  group('splitShorthandCount (#1861)', () {
    test('peels a leading or trailing count', () {
      expect(splitShorthandCount('16 pbs'), (
        text: 'pbs',
        beats: 16,
        unread: null,
      ));
      expect(splitShorthandCount('pbs (16)'), (
        text: 'pbs',
        beats: 16,
        unread: null,
      ));
      expect(splitShorthandCount('  pbs 16 beats '), (
        text: 'pbs',
        beats: 16,
        unread: null,
      ));
    });

    test('a count too long to be beats is unread, with no beats (#1879)', () {
      expect(splitShorthandCount('pbs (10000)'), (
        text: 'pbs',
        beats: 0,
        unread: '10000',
      ));
      // Four digits are still beats here; the range is the caller's to hold.
      expect(splitShorthandCount('100 pbs'), (
        text: 'pbs',
        beats: 100,
        unread: null,
      ));
    });

    test('is null when the line states no count', () {
      expect(splitShorthandCount('pbs'), isNull);
      expect(splitShorthandCount('pbs (0)'), isNull);
    });
  });

  group('parseFreeTextFigureEntry — hand-prefixed lines (#1908)', () {
    test('"Left-hand star" structures as a star', () {
      final fs = parseFreeTextFigureEntry('Left-hand star 3/4');
      expect(fs.single.move, 'star');
      expect(fs.single.params, {'hand': 'left', 'places': 3});
    });
  });
}
