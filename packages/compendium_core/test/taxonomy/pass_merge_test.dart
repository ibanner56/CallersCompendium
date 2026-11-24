import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// Taxonomy v40: pass by and pass through are one figure, `pass_through`, told
/// apart by `passType`; `pass_by` is its alias pinning `passType: by`. Each id
/// keeps what its stored figures meant by an omitted param.
void main() {
  final tax = contraTaxonomy;
  final renderer = FigureRenderer(tax);
  Figure f(String move, [Map<String, Object?> params = const {}]) =>
      Figure(move: move, params: params);

  group('the alias', () {
    test('pass_by pins passType: by, routes against pass_through, and is '
        'listed as a move', () {
      final alias = tax.aliases['pass_by']!;
      expect(alias.targetMove, 'pass_through');
      expect(alias.pinnedParams, {'passType': 'by'});
      expect(alias.inversePairId, 'pass_through');
      expect(alias.listedAsMove, isTrue);
      expect(tax.moves.containsKey('pass_by'), isFalse);
    });

    test('the merged figure has who, where, shoulder, beats and passType, in '
        'that order', () {
      expect(tax.moves['pass_through']!.params.keys, [
        'who',
        'where',
        'shoulder',
        'beats',
        'passType',
      ]);
    });
  });

  group('an omitted param means what it meant before the merge', () {
    // Mutation caught: dropping `MoveAlias.defaultParams` (or not reading it
    // in `effectiveParams`), which turns every stored pass by that leaves
    // `who` out from neighbors into an unstated subject.
    test('a pass by: neighbors, no direction', () {
      final effective = tax.effectiveParams(f('pass_by'));
      expect(effective['who'], 'neighbors');
      expect(effective['where'], ParamVocab.unspecified);
      expect(effective['passType'], 'by');
      expect(tax.defaultParamValue('pass_by', 'who'), 'neighbors');
      expect(tax.defaultParamValue('pass_by', 'passType'), 'by');
    });

    test('a pass through: no subject, along', () {
      final effective = tax.effectiveParams(f('pass_through'));
      expect(effective['who'], ParamVocab.unspecified);
      expect(effective['where'], 'along');
      expect(effective['passType'], 'through');
    });

    test('a stated value still wins over the alias default', () {
      final effective = tax.effectiveParams(
        f('pass_by', {'who': 'partners', 'where': 'across'}),
      );
      expect(effective['who'], 'partners');
      expect(effective['where'], 'across');
    });

    test('an alias default the target does not accept is refused', () {
      expect(
        () => Taxonomy(
          version: 1,
          form: DanceForm.contra,
          moves: [tax.moves['pass_through']!],
          aliases: const [
            MoveAlias(
              id: 'bad',
              displayName: 'bad',
              targetMove: 'pass_through',
              defaultParams: {'where': 'sideways'},
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('stored figures keep their canonical text', () {
    // The pre-v40 renderings, so no canonical/FTS rebuild is owed.
    for (final (figure, text) in [
      (f('pass_by'), 'neighbors pass by'),
      (
        f('pass_by', {'who': 'partners', 'shoulder': 'left'}),
        'partners pass by',
      ),
      (f('pass_through'), 'pass through along'),
      (f('pass_through', {'where': 'across'}), 'pass through across'),
    ]) {
      test('${figure.move} ${figure.params}', () {
        expect(renderer.renderCanonical(figure), text);
      });
    }

    test('a stated new param joins the text', () {
      expect(
        renderer.renderCanonical(
          f('pass_through', {'who': 'neighbors', 'where': 'across'}),
        ),
        'neighbors pass through across',
      );
      expect(
        renderer.renderCanonical(f('pass_by', {'where': 'across'})),
        'neighbors pass by across',
      );
    });
  });

  group('display', () {
    String show(Figure figure) => renderer.render(figure, Dialect.canonical);

    test('a pass by keeps its own line, with a stated direction', () {
      expect(show(f('pass_by')), 'neighbor pass by right shoulders');
      expect(
        show(f('pass_by', {'where': 'across', 'shoulder': 'left'})),
        'neighbor pass by left shoulders across',
      );
    });

    test('a pass through leads with a stated who', () {
      expect(show(f('pass_through')), 'pass through');
      expect(
        show(f('pass_through', {'who': 'neighbors', 'where': 'across'})),
        'neighbor pass through across',
      );
    });

    test('an unstated value shows nothing', () {
      expect(
        show(
          f('pass_through', {
            'who': ParamVocab.unspecified,
            'where': ParamVocab.unspecified,
          }),
        ),
        'pass through',
      );
      expect(
        show(f('pass_by', {'who': ParamVocab.unspecified})),
        'pass by right shoulders',
      );
    });
  });

  group('the pass type toggle', () {
    test('routes each way', () {
      expect(
        tax.resolvedMoveId(f('pass_through', {'passType': 'by'})),
        'pass_by',
      );
      expect(
        tax.resolvedMoveId(f('pass_by', {'passType': 'through'})),
        'pass_through',
      );
      expect(tax.resolvedMoveId(f('pass_by')), 'pass_by');
      expect(tax.resolvedMoveId(f('pass_through')), 'pass_through');
    });

    // Mutation caught: re-routing without `keepOmittedMeaning`, which turns a
    // stored pass by's omitted neighbors into an unstated pass through subject
    // and its omitted (unstated) direction into along.
    test('a pass by turned into a pass through keeps its values', () {
      final params = <String, Object?>{'shoulder': 'left'};
      final move = applyParamChange(
        tax,
        move: 'pass_by',
        params: params,
        key: 'passType',
        value: 'through',
        beatsTouched: false,
        aggressiveBeats: false,
      );
      expect(move, 'pass_through');
      final effective = tax.effectiveParams(f(move, params));
      expect(effective['who'], 'neighbors');
      expect(effective['where'], ParamVocab.unspecified);
      expect(effective['shoulder'], 'left');
    });

    test('a pass through turned into a pass by keeps its values', () {
      final params = <String, Object?>{};
      final move = applyParamChange(
        tax,
        move: 'pass_through',
        params: params,
        key: 'passType',
        value: 'by',
        beatsTouched: false,
        aggressiveBeats: false,
      );
      expect(move, 'pass_by');
      final effective = tax.effectiveParams(f(move, params));
      expect(effective['who'], ParamVocab.unspecified);
      expect(effective['where'], 'along');
    });
  });

  group('as stored', () {
    // Mutation caught: storing `passType`, or an unstated value whose omission
    // already says it, which a taxonomy v39 build rejects as `unknown_param`
    // or `invalid_param_value`.
    test('neither id stores passType, nor an unstated value its omission '
        'means', () {
      expect(
        tax.withoutListedAliasPins('pass_by', {
          'passType': 'by',
          'who': 'neighbors',
          'where': ParamVocab.unspecified,
        }),
        {'who': 'neighbors'},
      );
      expect(
        tax.withoutListedAliasPins('pass_through', {
          'passType': 'through',
          'who': ParamVocab.unspecified,
          'where': 'along',
        }),
        {'where': 'along'},
      );
    });

    test('an unstated value its omission does not mean is kept', () {
      expect(
        tax.withoutListedAliasPins('pass_by', {'who': ParamVocab.unspecified}),
        {'who': ParamVocab.unspecified},
      );
      expect(
        tax.withoutListedAliasPins('pass_through', {
          'where': ParamVocab.unspecified,
        }),
        {'where': ParamVocab.unspecified},
      );
    });

    test('a forward and back is unaffected', () {
      // Its pair param's default is the alias's pin, never dropped here.
      const params = {'formation': 'longLines'};
      expect(
        tax.withoutListedAliasPins('forward_and_back', params),
        same(params),
      );
    });
  });

  group('walkthrough snippet keys', () {
    // Stored library keys: a stored pass keeps the key it had before v40.
    // Mutation caught: letting an unstated `who`/`where` into the key, which
    // orphans every saved pass snippet.
    for (final (figure, key) in [
      (f('pass_by'), 'pass_by(who=neighbors)'),
      (f('pass_by', {'who': 'partners'}), 'pass_by(who=partners)'),
      (f('pass_through'), 'pass_through(where=along)'),
      (f('pass_through', {'where': 'across'}), 'pass_through(where=across)'),
    ]) {
      test('${figure.move} ${figure.params}', () {
        expect(figureSnippetSignature(figure, tax), key);
      });
    }

    test('a stated new param joins the key', () {
      expect(
        figureSnippetSignature(f('pass_through', {'who': 'neighbors'}), tax),
        'pass_through(where=along,who=neighbors)',
      );
      expect(
        figureSnippetSignature(f('pass_by', {'where': 'across'}), tax),
        'pass_by(where=across,who=neighbors)',
      );
    });
  });

  group('matrix columns', () {
    // Mutation caught: a column on `pass_through` matching by resolved id
    // alone, which takes every pass by out of its own column into it.
    test('a column on pass through counts pass throughs, not passes by', () {
      final config = MatrixColumnConfig(
        parameterized: [
          ParameterizedColumn(
            id: 'param:pt',
            baseMove: 'pass_through',
            params: const {},
          ),
        ],
      );
      expect(columnKeyForFigure(f('pass_through'), tax, config), 'param:pt');
      expect(columnKeyForFigure(f('pass_by'), tax, config), 'pass_by');
    });

    test('a column on pass by counts passes by', () {
      final config = MatrixColumnConfig(
        parameterized: [
          ParameterizedColumn(
            id: 'param:pb',
            baseMove: 'pass_by',
            params: const {},
          ),
        ],
      );
      expect(columnKeyForFigure(f('pass_by'), tax, config), 'param:pb');
      expect(
        columnKeyForFigure(f('pass_through'), tax, config),
        'pass_through',
      );
    });
  });

  group('required on entry', () {
    test('a new pass starts with who and where unstated', () {
      for (final id in ['pass_by', 'pass_through']) {
        expect(tax.unstatedRequiredParams(f(id, tax.entryParams(id))), [
          'who',
          'where',
        ], reason: id);
      }
    });

    test('a stored figure leaves unstated only what it omits as such', () {
      expect(tax.unstatedRequiredParams(f('pass_by')), ['where']);
      expect(tax.unstatedRequiredParams(f('pass_through')), ['who']);
      expect(
        tax.unstatedRequiredParams(
          f('pass_through', {'who': 'neighbors', 'where': 'across'}),
        ),
        isEmpty,
      );
    });

    test('only the pass figure requires a value on entry', () {
      for (final def in tax.moves.values) {
        for (final MapEntry(:key, :value) in def.params.entries) {
          if (!value.requiredOnEntry) continue;
          expect(def.id, 'pass_through', reason: '${def.id}.$key');
          expect(
            value.validate(ParamVocab.unspecified),
            isTrue,
            reason: '${def.id}.$key must admit the sentinel it seeds',
          );
        }
      }
    });
  });
}
