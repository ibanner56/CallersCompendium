import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Free text reads what a caller types (#1826): every taxonomy display name
/// and alias as typed, plus the caller phrasings the import grammar does not
/// accept.
void main() {
  final taxonomy = contraTaxonomy;

  /// Display names that do NOT parse to a structured figure of their own move,
  /// and why. Every entry is asserted below, so the list cannot go stale.
  const exceptions = {
    // `custom` is the sentinel move for text the parser does not read, not a
    // call. The word typed alone is kept as a custom figure whose text is
    // `custom`; reading it as an empty custom would lose the word.
    'custom': 'the unparsed-text sentinel, not a call',
  };

  String describe(List<Figure> fs) => fs
      .map(
        (f) => f.isCustom
            ? 'custom(${f.params['text']})'
            : '${f.move}${f.params}${f.note == null ? '' : ' note=${f.note}'}',
      )
      .join(' | ');

  group('every display name parses as itself', () {
    for (final dialect in [null, ...Dialect.presets]) {
      final label = dialect?.name ?? 'no dialect';
      test('under $label', () {
        final failures = <String>[];
        for (final move in taxonomy.moves.values) {
          if (exceptions.containsKey(move.id)) continue;
          for (final typed in {
            move.displayName,
            move.displayName.toLowerCase(),
            move.displayName.toUpperCase(),
          }) {
            final fs = parseFreeTextFigureEntry(
              typed,
              taxonomy: taxonomy,
              dialect: dialect,
            );
            final ok =
                fs.length == 1 &&
                !fs.single.isCustom &&
                fs.single.note == null &&
                taxonomy.resolvedMoveId(fs.single) == move.id;
            if (!ok) failures.add('"$typed" -> ${describe(fs)}');
          }
        }
        expect(failures, isEmpty);
      });
    }

    test('every exception is a real move and still fails as described', () {
      for (final id in exceptions.keys) {
        final move = taxonomy.moves[id];
        expect(move, isNotNull, reason: 'stale exception "$id"');
        final fs = parseFreeTextFigureEntry(move!.displayName);
        expect(fs.single.isCustom, isTrue);
        expect(fs.single.params['text'], move.displayName);
      }
    });

    test('every alias display name parses to that alias or its move', () {
      for (final alias in taxonomy.aliases.values) {
        final fs = parseFreeTextFigureEntry(alias.displayName);
        expect(fs, hasLength(1), reason: alias.displayName);
        final f = fs.single;
        expect(f.isCustom, isFalse, reason: alias.displayName);
        expect(f.note, isNull, reason: alias.displayName);
        expect(
          f.move == alias.id || f.move == alias.targetMove,
          isTrue,
          reason: '"${alias.displayName}" -> ${describe(fs)}',
        );
      }
    });
  });

  group('a bare name', () {
    test('states only the beats it was given', () {
      final f = parseFreeTextFigureEntry('mad robin').single;
      expect(f.move, 'mad_robin');
      expect(f.params, isEmpty);
      final counted = parseFreeTextFigureEntry('hey (16)').single;
      expect(counted.move, 'hey');
      expect(counted.params, {'beats': 16});
    });

    test('marks a defaulted subject as assumed (#460)', () {
      expect(parseFreeTextFigureEntry('mad robin').single.assumedSubject, true);
      // `slice` has no subject to assume.
      expect(parseFreeTextFigureEntry('slice').single.assumedSubject, false);
    });

    test('accepts `&` for `and` and a hyphen for a space', () {
      expect(
        parseFreeTextFigureEntry('give and take').single.move,
        'give_and_take',
      );
      expect(
        parseFreeTextFigureEntry('arch & dive').single.move,
        'arch_and_dive',
      );
      expect(parseFreeTextFigureEntry('zig-zag').single.move, 'zig_zag');
    });

    test('a name with anything else on the line stays custom', () {
      for (final line in ['mad robin twice round', 'the gate', 'hey hey']) {
        expect(
          parseFreeTextFigureEntry(line).single.isCustom,
          isTrue,
          reason: line,
        );
      }
    });

    test('the import grammar wins when it reads the line', () {
      // The grammar reads `swing` with its subject; the name table would
      // state none, so it must not be consulted first.
      expect(parseFreeTextFigureEntry('swing').single.params, {
        'who': 'partners',
      });
      // `pull by` is the move's name and two aliases' names: the move.
      expect(parseFreeTextFigureEntry('pull by').single.move, 'pull_by');
    });

    test(
      'imports are unchanged: the fan-out still keeps a bare `hey` custom',
      () {
        expect(parseFigureLinesFanOut('hey').single.isCustom, isTrue);
        expect(parseFigureLinesFanOut('mad robin').single.isCustom, isTrue);
      },
    );

    test("the active dialect's own move name is read", () {
      final dialect = Dialect(
        name: 'Custom',
        moves: const {'mad_robin': 'dizzy robin', 'orbit': 'gate'},
      );
      expect(
        parseFreeTextFigureEntry('dizzy robin', dialect: dialect).single.move,
        'mad_robin',
      );
      expect(parseFreeTextFigureEntry('dizzy robin').single.isCustom, isTrue);
      // A wording with a `%S` side placeholder is a template, not a name.
      final templated = Dialect(
        name: 'Custom',
        moves: const {'orbit': '%S whirligig'},
      );
      expect(
        parseFreeTextFigureEntry(
          '%S whirligig',
          dialect: templated,
        ).single.isCustom,
        isTrue,
      );
      // A dialect name that is another move's taxonomy name reads as the
      // taxonomy move.
      expect(
        parseFreeTextFigureEntry('gate', dialect: dialect).single.move,
        'gate',
      );
    });
  });

  group('caller phrasings', () {
    test('the turn-amount rewrite never changes a line the grammar read', () {
      // The rewritten line does not read cleanly, so the line is read as
      // typed: the note keeps the user's words.
      final f = parseFreeTextFigureEntry(
        'neighbors allemande right one and a half times',
      ).single;
      expect(f.note, contains('one and a half'));
    });

    test('hey for four, half hey, full hey', () {
      final four = parseFreeTextFigureEntry('hey for four').single;
      expect(four.move, 'hey');
      expect(four.params, isEmpty);
      expect(parseFreeTextFigureEntry('half hey').single.params, {
        'length': 'half',
      });
      expect(parseFreeTextFigureEntry('Full hey').single.params, {
        'length': 'full',
      });
      expect(parseFreeTextFigureEntry('full hey for four').single.params, {
        'length': 'full',
      });
    });

    test('turn as a couple', () {
      expect(
        parseFreeTextFigureEntry('turn as a couple').single.move,
        'turn_as_couples',
      );
    });

    test('`once and a half` is one and a half times, not once plus a note', () {
      for (final line in [
        'allemande right once and a half',
        'neighbors allemande right once and a half',
        'neighbors do si do one and a half',
        'partners two hand turn once & a half',
      ]) {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.isCustom, isFalse, reason: line);
        expect(f.params['travel'], 1.5, reason: line);
        expect(f.note, isNull, reason: line);
      }
    });

    test('a line the rewrite does not rescue keeps its typed text', () {
      final f = parseFreeTextFigureEntry('frobnicate once and a half').single;
      expect(f.isCustom, isTrue);
      expect(f.params['text'], 'frobnicate once and a half');
    });

    test(
      'a discouraged role term reads by its meaning (`ravens` → role2s)',
      () {
        for (final dialect in [null, ...Dialect.presets]) {
          final f = parseFreeTextFigureEntry(
            'ravens chain',
            dialect: dialect,
          ).single;
          expect(f.isCustom, isFalse, reason: dialect?.name);
          expect(f.params['who'], 'role2s', reason: dialect?.name);
        }
      },
    );

    test('a dialect that claims the term keeps its own meaning', () {
      final ravensLarks = Dialect(
        name: 'Custom',
        roles: const {'role1': RoleTerm('raven'), 'role2': RoleTerm('lark')},
      );
      final f = parseFreeTextFigureEntry(
        'ravens chain',
        dialect: ravensLarks,
      ).single;
      expect(f.params['who'], 'role1s');
    });
  });

  group('a count with a `beats` unit', () {
    test('is the figure\'s beats, not a note', () {
      for (final line in [
        'neighbor swing (16 beats)',
        'neighbor swing [16 beats]',
        'neighbor swing 16 beats',
        '(16 beats) neighbor swing',
        '16 beats neighbor swing',
        'neighbor swing (16 Beats)',
      ]) {
        final f = parseFreeTextFigureEntry(line).single;
        expect(f.isCustom, isFalse, reason: line);
        expect(f.move, 'swing', reason: line);
        expect(f.params['beats'], 16, reason: line);
        expect(f.note, isNull, reason: line);
      }
      final one = parseFreeTextFigureEntry('circle left [8 beat]').single;
      expect(one.params['beats'], 8);
    });

    test(
      'a trailing unit count that is not the beats keeps the line custom',
      () {
        final f = parseFreeTextFigureEntry('circle left 8 beats (16)').single;
        expect(f.isCustom, isTrue);
        expect(f.params['text'], 'circle left 8 beats (16)');
      },
    );

    test('the re-parse upgrade does not read the unit (imports unchanged)', () {
      Figure saved(String text, int beats) =>
          customFigure(text, beats: beats, origin: CustomOrigin.importGap);
      final outcome = reparseImportGapFigures([
        saved('neighbors swing (8 beats)', 16),
        saved('neighbors swing 8 beats', 0),
      ]);
      final [mismatched, unitless] = outcome.figures;
      expect(mismatched.move, 'swing');
      expect(mismatched.params['beats'], 16);
      expect(mismatched.note, '(8 beats)');
      expect(unitless.move, 'swing');
      expect(unitless.note, '8 beats');
    });

    test('a line free text kept custom for a stray unit count stays custom '
        'on re-parse', () {
      final typed = parseFreeTextFigureEntry('circle left 8 beats (16)').single;
      expect(typed.isCustom, isTrue);
      final outcome = reparseImportGapFigures([typed]);
      expect(outcome.upgradedCount, 0);
      expect(outcome.figures.single.isCustom, isTrue);
      expect(outcome.figures.single.params['text'], 'circle left 8 beats (16)');
    });

    test('a second count keeps the whole line custom', () {
      final f = parseFreeTextFigureEntry(
        '(8 beats) neighbor swing (16)',
      ).single;
      expect(f.isCustom, isTrue);
      expect(f.params['text'], '(8 beats) neighbor swing (16)');
    });

    test('`bars` is not converted: it stays a note', () {
      // Beats per bar is the dance's phrase structure, which a typed line
      // does not see.
      final f = parseFreeTextFigureEntry('circle left 4 bars').single;
      expect(f.move, 'circle');
      expect(f.note, '4 bars');
      expect(f.params.containsKey('beats'), isFalse);
    });
  });
}
