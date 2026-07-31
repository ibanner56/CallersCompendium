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
      final fs = parseFreeTextFigureEntry('Star right 3/4; form wave of four');
      expect(fs, hasLength(1));
      expect(fs.single.isCustom, isTrue);
      expect(fs.single.params['text'], contains('Star right 3/4'));
      expect(fs.single.params['text'], contains('form wave of four'));
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
      // The trailing inline beat is still peeled before the fan-out parse.
      expect(fs.single.params['beats'], 16);
      expect(fs.single.params['text'], 'qwx zzz nonsense');
    });
  });
}
