import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// ADR-006 §12.1 F5: the opt-in migration of an English dance stored with
/// contra moves.

Figure _f(String move, [Map<String, Object?> params = const {}]) =>
    Figure(move: move, params: params);

Figure? _twin(String move, [Map<String, Object?> params = const {}]) =>
    ecdTwinOfContraMove(_f(move, params));

void main() {
  group('a contra move with a clear ECD twin becomes it', () {
    final cases =
        <(String, Map<String, Object?>), (String, Map<String, Object?>)>{
          ('circle', {'direction': 'left', 'places': 3, 'beats': 8}): (
            'ecd_circle',
            {'direction': 'left', 'places': 3, 'beats': 8},
          ),
          ('star', {'hand': 'right', 'grip': 'none'}): (
            'ecd_star',
            {'hand': 'right'},
          ),
          ('allemande', {'who': 'partners', 'hand': 'left', 'travel': 1.5}): (
            'ecd_hand_turn',
            {
              'who': ['partners'],
              'hand': 'left',
              'travel': 1.5,
            },
          ),
          ('do_si_do', {'who': 'neighbors'}): (
            'ecd_back_to_back',
            {
              'who': ['neighbors'],
            },
          ),
          ('see_saw', {'who': 'partners'}): (
            'ecd_back_to_back',
            {
              'who': ['partners'],
              'shoulder': 'left',
            },
          ),
          ('swing', {'who': 'partners', 'prefix': 'none'}): (
            'ecd_swing',
            {
              'who': ['partners'],
            },
          ),
          ('chain', {'who': 'role2s', 'where': 'across'}): (
            'ecd_chain',
            {
              'who': ['role2s'],
              'where': 'across',
            },
          ),
          ('long_lines', {'beats': 8}): (
            'ecd_forward_and_back',
            {'beats': 8, 'goBack': true, 'distance': 'double'},
          ),
          (
            'forward_and_back',
            {'formation': 'linesOfThree', 'goBack': false},
          ): (
            'ecd_forward_and_back',
            {
              'formation': 'linesOfThree',
              'goBack': false,
              'distance': 'double',
            },
          ),
          ('balance_the_ring', {}): ('ecd_balance_ring', {}),
        };
    for (final c in cases.entries) {
      test('${c.key.$1} ${c.key.$2}', () {
        final twin = _twin(c.key.$1, c.key.$2);
        expect(twin, isNotNull);
        expect(twin!.move, c.value.$1);
        expect(twin.params, c.value.$2);
      });
    }
  });

  test('a contra default is never stored on the twin (R2)', () {
    // Contra's allemande defaults to neighbors, right, 1½; none is stated.
    final twin = _twin('allemande')!;
    expect(twin.params, isEmpty);
    expect(ecdTaxonomy.effectiveParams(twin)['who'], ['unspecified']);
  });

  test('an assumed subject is not carried (R2)', () {
    final assumed = Figure(
      move: 'swing',
      params: const {'who': 'partners'},
      assumedSubject: true,
    );
    final twin = ecdTwinOfContraMove(assumed)!;
    expect(twin.params.containsKey('who'), isFalse);
    expect(twin.assumedSubject, isFalse);
  });

  test(
    'a move with no twin, or a value the twin cannot hold, stays contra',
    () {
      expect(_twin('hey', {'pass1': 'role2s'}), isNull);
      expect(_twin('poussette'), isNull);
      expect(_twin('petronella'), isNull);
      expect(_twin('california_twirl'), isNull);
      // A wrist-grip star: the ECD star has no grip.
      expect(_twin('star', {'hand': 'right', 'grip': 'wristGrip'}), isNull);
      // A balance-and-swing: the ECD swing has no balance before it.
      expect(_twin('swing', {'prefix': 'balance'}), isNull);
      // A swing ending facing along: not an ECD ending.
      expect(_twin('swing', {'endFacing': 'along'}), isNull);
      // Forward and back in squares: not an ECD formation.
      expect(_twin('forward_and_back', {'formation': 'inSquares'}), isNull);
      // ECD moves and customs are not contra moves.
      expect(_twin('ecd_circle'), isNull);
      expect(ecdTwinOfContraMove(customFigure('circle left')), isNull);
    },
  );

  test('note, progression and overrides are kept', () {
    final f = Figure(
      move: 'circle',
      params: const {'direction': 'left'},
      note: 'slowly',
      progression: true,
      walkthroughOverride: 'w',
      wordingOverride: 'o',
    );
    final twin = ecdTwinOfContraMove(f)!;
    expect(twin.note, 'slowly');
    expect(twin.progression, isTrue);
    expect(twin.walkthroughOverride, 'w');
    expect(twin.wordingOverride, 'o');
  });

  group('migrateEcdDance', () {
    test('converts moves, re-reads gap lines, maps the shape', () {
      final figures = [
        _f('circle', {'direction': 'left', 'beats': 8}),
        customFigure(
          'partners set and turn single',
          origin: CustomOrigin.importGap,
        ),
        customFigure('my own words'),
        _f('hey', {'pass1': 'role2s'}),
        Figure.sequence(
          figures: [
            _f('balance', {'who': 'neighbors'}),
            _f('swing', {'who': 'neighbors'}),
          ],
          beats: 16,
        ),
      ];
      final out = migrateEcdDance(
        figures: figures,
        formation: const Formation(FormationShape.dupleImproper),
      );
      expect(out.movesConverted, 3);
      expect(out.linesReread, 1);
      expect(
        out.formation,
        const Formation(FormationShape.dupleMinor, improper: true),
      );
      expect(out.figures[0].move, 'ecd_circle');
      expect(out.figures[1].move, 'sequence');
      expect(out.figures[1].subFigures.map((f) => f.move), [
        'ecd_set',
        'ecd_turn_single',
      ]);
      // A custom the caller typed is theirs: untouched.
      expect(out.figures[2], figures[2]);
      expect(out.figures[3], figures[3]);
      expect(out.figures[4].subFigures.map((f) => f.move), [
        'ecd_balance',
        'ecd_swing',
      ]);
      expect(out.figures[4].beats, 16);
      expect(
        out.changes(const Formation(FormationShape.dupleImproper)),
        isTrue,
      );
    });

    test('a dance already in ECD terms has nothing to change', () {
      final figures = [
        _f('ecd_circle', {'direction': 'left'}),
      ];
      const formation = Formation(FormationShape.dupleMinor);
      final out = migrateEcdDance(figures: figures, formation: formation);
      expect(out.changes(formation), isFalse);
      expect(identical(out.figures, figures), isTrue);
    });

    test('every converted figure is valid in the ECD taxonomy', () {
      final c = shippedTaxonomies.forForm(DanceForm.contra);
      for (final id in ecdMigratableContraMoves) {
        final move = c.resolve(id)!;
        // Each move with every param at its contra default, stated.
        final params = {
          for (final e in move.params.entries)
            if (e.value.defaultValue != null) e.key: e.value.defaultValue,
        };
        final twin = ecdTwinOfContraMove(Figure(move: id, params: params));
        if (twin == null) continue;
        expect(
          ecdTaxonomy
              .validateFigure(twin)
              .where((i) => i.severity == ValidationSeverity.error),
          isEmpty,
          reason: id,
        );
      }
    });
  });
}
