import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  final tax = contraTaxonomy;

  group('construction guards', () {
    test('alias targeting an unknown move is rejected', () {
      expect(
        () => Taxonomy(
          version: 1,
          form: DanceForm.contra,
          moves: const [
            MoveDef(
              id: 'swing',
              displayName: 'swing',
              renderTemplate: '{move}',
            ),
          ],
          aliases: const [
            MoveAlias(id: 'x', displayName: 'x', targetMove: 'nope'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('alias pinning an unknown param is rejected', () {
      expect(
        () => Taxonomy(
          version: 1,
          form: DanceForm.contra,
          moves: const [
            MoveDef(
              id: 'swing',
              displayName: 'swing',
              renderTemplate: '{move}',
            ),
          ],
          aliases: const [
            MoveAlias(
              id: 'x',
              displayName: 'x',
              targetMove: 'swing',
              pinnedParams: {'ghost': 1},
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('resolve', () {
    test('finds canonical moves', () {
      expect(tax.resolve('swing')?.id, 'swing');
    });

    test('resolves aliases to their canonical move', () {
      expect(tax.resolve('see_saw')?.id, 'do_si_do');
      expect(tax.resolve('meltdown_swing')?.id, 'swing');
    });

    test('returns null for unknown moves', () {
      expect(tax.resolve('nonsense'), isNull);
    });
  });

  group('effectiveParams', () {
    test('fills defaults for omitted params', () {
      final p = tax.effectiveParams(Figure(move: 'allemande'));
      expect(p['who'], 'neighbors');
      expect(p['hand'], 'right');
      expect(p['turn'], 1.0);
      expect(p['beats'], 8);
    });

    test('figure params override defaults', () {
      final p = tax.effectiveParams(
        Figure(move: 'allemande', params: {'hand': 'left'}),
      );
      expect(p['hand'], 'left');
    });

    test('alias pins take effect but figure params still win', () {
      expect(tax.effectiveParams(Figure(move: 'see_saw'))['shoulder'], 'left');
      expect(
        tax.effectiveParams(
          Figure(move: 'see_saw', params: {'shoulder': 'right'}),
        )['shoulder'],
        'right',
      );
    });

    test('unknown move preserves an authored beats and passes params through '
        '(#358)', () {
      final figure = Figure(
        move: 'a_move_from_the_future',
        params: {'beats': 12, 'flavor': 'spicy'},
      );
      final p = tax.effectiveParams(figure);
      // An authored beats is preserved verbatim (no fallback applied).
      expect(p, {'beats': 12, 'flavor': 'spicy'});
    });

    test(
      'unknown move with no beats gets a sensible beats fallback, not 0 (#358)',
      () {
        final figure = Figure(move: 'totally_unknown', params: {'flavor': 'x'});
        final p = tax.effectiveParams(figure);
        // A neutral fallback keeps downstream duration/phrase math sane.
        expect(p['beats'], 8);
        expect(p['flavor'], 'x');
        // The fallback lives only in the returned map — figure.params is
        // never mutated (lossless preservation).
        expect(figure.params.containsKey('beats'), isFalse);
        expect(figure.params, {'flavor': 'x'});
      },
    );

    test(
      'effectiveParams result is decoupled from the stored params (#358)',
      () {
        final figure = Figure(move: 'unknown_x', params: {'beats': 8});
        final p = tax.effectiveParams(figure)..['beats'] = 99;
        // Mutating the returned best-effort map must not touch the figure.
        expect(figure.params['beats'], 8);
        expect(p['beats'], 99);
      },
    );
  });

  group('validateFigure', () {
    test('a well-formed figure has no issues', () {
      expect(
        tax.validateFigure(
          Figure(move: 'swing', params: {'who': 'partners', 'beats': 8}),
        ),
        isEmpty,
      );
    });

    test('unknown move is a single error', () {
      final issues = tax.validateFigure(Figure(move: 'floop'));
      expect(issues.single.code, 'unknown_move');
      expect(issues.single.severity, ValidationSeverity.error);
    });

    test('unknown param name is an error', () {
      final issues = tax.validateFigure(
        Figure(move: 'swing', params: {'ghost': 1}),
      );
      expect(issues.any((i) => i.code == 'unknown_param'), isTrue);
    });

    test('out-of-domain param value is an error', () {
      expect(
        tax
            .validateFigure(
              Figure(move: 'allemande', params: {'hand': 'sideways'}),
            )
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
      );
      expect(
        tax
            .validateFigure(Figure(move: 'allemande', params: {'turn': 0.3}))
            .any((i) => i.code == 'invalid_param_value'),
        isTrue,
        reason: '0.3 is not a quarter-turn step',
      );
    });

    test('atypical beats is a warning, not an error', () {
      final issues = tax.validateFigure(
        Figure(move: 'balance', params: {'beats': 6}),
      );
      expect(issues.single.severity, ValidationSeverity.warning);
      expect(issues.single.code, 'atypical_beats');
    });

    test('custom move accepts any beats without warning', () {
      expect(
        tax.validateFigure(
          Figure(move: customMove, params: {'text': 'x', 'beats': 13}),
        ),
        isEmpty,
      );
    });
  });

  group('ParamSpec domains', () {
    test('rotation accepts quarter steps within range only', () {
      const spec = ParamSpec(ParamKind.rotation, defaultValue: 1.0);
      expect(spec.validate(0.25), isTrue);
      expect(spec.validate(2.5), isTrue);
      expect(spec.validate(1.5), isTrue);
      expect(spec.validate(0.1), isFalse);
      expect(spec.validate(3.0), isFalse);
      expect(spec.validate(0.3), isFalse);
    });

    test('beats accept 0..64 ints only', () {
      const spec = ParamSpec(ParamKind.beats, defaultValue: 8);
      expect(spec.validate(0), isTrue);
      expect(spec.validate(64), isTrue);
      expect(spec.validate(-1), isFalse);
      expect(spec.validate(65), isFalse);
      expect(spec.validate(8.0), isFalse);
    });

    test('narrowed dancer choices reject out-of-list values', () {
      const spec = ParamSpec(
        ParamKind.dancerSet,
        defaultValue: 'role2s',
        choices: ['role1s', 'role2s'],
      );
      expect(spec.validate('role1s'), isTrue);
      expect(spec.validate('partners'), isFalse);
    });

    // Issue #736 review: the five kinds #726 taught the EDITOR to honour
    // `spec.choices` for must also be honoured by the VALIDATOR — otherwise a
    // spec that opts a kind into the `unspecified` sentinel would let the
    // editor render and store it, then have `validateFigure` reject it. One
    // representative kind (handedness) pinned directly; the taxonomy-wide
    // sweep lives in `sentinel_choices_test.dart`.
    test('a sentinel-bearing handedness spec validates the sentinel, still '
        'rejects out-of-domain values', () {
      const spec = ParamSpec(
        ParamKind.handedness,
        defaultValue: 'right',
        choices: [...ParamVocab.sides, ParamVocab.unspecified],
      );
      expect(spec.validate(ParamVocab.unspecified), isTrue);
      expect(spec.validate('right'), isTrue);
      expect(spec.validate('sideways'), isFalse);
    });

    test('a handedness spec WITHOUT choices keeps the strict fixed domain', () {
      const spec = ParamSpec(ParamKind.handedness, defaultValue: 'right');
      expect(spec.validate('right'), isTrue);
      expect(spec.validate('left'), isTrue);
      expect(spec.validate(ParamVocab.unspecified), isFalse);
    });
  });
}
