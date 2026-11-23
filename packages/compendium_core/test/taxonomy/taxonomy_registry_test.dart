import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';
import 'package:compendium_core/src/imports/typed_figure_names.dart';

/// A stand-in for ECD's own taxonomy, which ADR-006's registry work adds: one
/// move and one alias, both carrying the `ecd_` prefix.
Taxonomy _ecd({String moveId = 'ecd_set', int version = 1}) => Taxonomy(
  version: version,
  form: DanceForm.ecd,
  moves: [
    MoveDef(
      id: moveId,
      displayName: 'set',
      renderTemplate: '{who} {move}',
      params: const {
        'who': ParamSpec(ParamKind.dancerSet, defaultValue: 'partners'),
        'beats': ParamSpec(ParamKind.beats, defaultValue: 4),
      },
    ),
  ],
  aliases: [
    MoveAlias(id: 'ecd_set_to', displayName: 'set to', targetMove: moveId),
  ],
);

Taxonomy _square() => Taxonomy(
  version: 1,
  form: DanceForm.square,
  moves: const [
    MoveDef(id: 'sq_do_paso', displayName: 'do paso', renderTemplate: '{move}'),
  ],
);

void main() {
  group('the shipped registry', () {
    test('ships contra, and ECD over contra; squares use contra', () {
      expect(shippedTaxonomies.forForm(DanceForm.contra), same(contraTaxonomy));
      expect(shippedTaxonomies.forForm(DanceForm.square), same(contraTaxonomy));
      expect(
        shippedTaxonomies.ownTaxonomy(DanceForm.contra),
        same(contraTaxonomy),
      );
      expect(shippedTaxonomies.ownTaxonomy(DanceForm.ecd), same(ecdTaxonomy));
      expect(shippedTaxonomies.ownTaxonomy(DanceForm.square), isNull);
      final ecd = shippedTaxonomies.forForm(DanceForm.ecd);
      expect(ecd.resolve('ecd_set')?.id, 'ecd_set');
      // An ECD dance keeps the contra moves it was stored with (F5).
      expect(ecd.resolve('poussette')?.id, 'poussette');
      expect(shippedTaxonomies.anyForm.resolve('ecd_star')?.id, 'ecd_star');
      expect(shippedTaxonomies.anyForm.resolve('star')?.id, 'star');
    });

    test('contra owns no ID that carries another form\'s prefix', () {
      // The registry's constructor would throw; this names what it checks.
      for (final id in [
        ...contraTaxonomy.moves.keys,
        ...contraTaxonomy.aliases.keys,
      ]) {
        expect(
          shippedTaxonomies.formOfMoveId(id),
          DanceForm.contra,
          reason: id,
        );
      }
    });
  });

  // invalid-fixture: these figures are ECD moves, or an unknown move on purpose, which contra's taxonomy rightly rejects
  group('with ECD registered', () {
    final ecd = _ecd();
    final registry = TaxonomyRegistry(base: contraTaxonomy, forms: [ecd]);

    test('an ECD dance resolves ecd_ IDs through ECD, and plain IDs through '
        'contra (ADR-006 §5.1)', () {
      final forEcd = registry.forForm(DanceForm.ecd);
      expect(forEcd.form, DanceForm.ecd);
      expect(forEcd.resolve('ecd_set'), same(ecd.moves['ecd_set']));
      expect(forEcd.resolve('ecd_set_to'), same(ecd.moves['ecd_set']));
      expect(forEcd.resolve('swing'), same(contraTaxonomy.moves['swing']));
      expect(forEcd.resolve('see_saw'), same(contraTaxonomy.moves['do_si_do']));
      expect(forEcd.validateFigure(Figure(move: 'ecd_set')), isEmpty);
      expect(forEcd.effectiveParams(Figure(move: 'ecd_set')), {
        'who': 'partners',
        'beats': 4,
      });
    });

    test('a contra dance does not resolve ecd_ IDs', () {
      final forContra = registry.forForm(DanceForm.contra);
      expect(forContra, same(contraTaxonomy));
      expect(forContra.resolve('ecd_set'), isNull);
      expect(
        forContra.validateFigure(Figure(move: 'ecd_set')).single.code,
        'unknown_move',
      );
    });

    test('a form with no taxonomy of its own keeps contra', () {
      expect(registry.forForm(DanceForm.square), same(contraTaxonomy));
      expect(registry.ownTaxonomy(DanceForm.square), isNull);
      expect(registry.ownTaxonomy(DanceForm.ecd), same(ecd));
    });

    test('anyForm resolves a stored ID of either form', () {
      final any = registry.anyForm;
      expect(any.resolve('ecd_set'), same(ecd.moves['ecd_set']));
      expect(any.resolve('swing'), same(contraTaxonomy.moves['swing']));
      expect(any.moves.length, contraTaxonomy.moves.length + ecd.moves.length);
      expect(
        any.aliases.length,
        contraTaxonomy.aliases.length + ecd.aliases.length,
      );
      expect(
        any.validateFigure(Figure(move: 'nope')).single.message,
        contains('taxonomy of every dance form'),
      );
    });

    test('an ECD figure renders through the ECD taxonomy', () {
      final renderer = FigureRenderer(registry.forForm(DanceForm.ecd));
      expect(
        renderer.renderCanonical(
          Figure(move: 'ecd_set', params: {'who': 'neighbors'}),
        ),
        'neighbors set',
      );
      // Contra's renderer sees the same figure as a move it does not know.
      expect(
        FigureRenderer(contraTaxonomy).renderCanonical(
          Figure(move: 'ecd_set', params: {'who': 'neighbors'}),
        ),
        isNot('neighbors set'),
      );
    });

    test('in an ECD dance a name both forms share looks up the ECD move', () {
      final shared = TaxonomyRegistry(
        base: contraTaxonomy,
        forms: [
          Taxonomy(
            version: 1,
            form: DanceForm.ecd,
            moves: const [
              MoveDef(
                id: 'ecd_poussette',
                displayName: 'poussette',
                renderTemplate: '{move}',
              ),
            ],
          ),
        ],
      );
      expect(contraTaxonomy.resolve('poussette'), isNotNull);
      final forEcd = shared.forForm(DanceForm.ecd);
      expect(forEcd.moves.keys.first, 'ecd_poussette');
      // The typed-name table keeps the first move with a name, so the
      // form's own move wins. (The free-text parser still reads contra's
      // grammar first, until ECD has a parser of its own.)
      expect(
        figureFromTypedName(
          'poussette',
          taxonomy: forEcd,
          dialect: Dialect.larksRobins,
        )?.move,
        'ecd_poussette',
      );
      expect(
        figureFromTypedName(
          'poussette',
          taxonomy: shared.forForm(DanceForm.contra),
          dialect: Dialect.larksRobins,
        )?.move,
        'poussette',
      );
    });

    test('formOfMoveId reads the prefix', () {
      expect(registry.formOfMoveId('ecd_set'), DanceForm.ecd);
      expect(registry.formOfMoveId('swing'), DanceForm.contra);
      // Squares have no prefix until their taxonomy is registered (ADR-007).
      expect(registry.formOfMoveId('sq_do_paso'), DanceForm.contra);
    });
  });

  group('rejects', () {
    test('a form move without its prefix', () {
      expect(
        () => TaxonomyRegistry(
          base: contraTaxonomy,
          forms: [_ecd(moveId: 'set')],
        ),
        throwsArgumentError,
      );
    });

    test('two taxonomies for one form', () {
      expect(
        () => TaxonomyRegistry(
          base: contraTaxonomy,
          forms: [_ecd(), _ecd(version: 2)],
        ),
        throwsArgumentError,
      );
    });

    test('a second taxonomy for the base form', () {
      expect(
        () => TaxonomyRegistry(base: contraTaxonomy, forms: [contraTaxonomy]),
        throwsArgumentError,
      );
    });

    test('a form with no move ID prefix', () {
      expect(
        () => TaxonomyRegistry(base: contraTaxonomy, forms: [_square()]),
        throwsArgumentError,
      );
    });

    test('a base ID that carries a form prefix', () {
      final base = Taxonomy(
        version: 1,
        form: DanceForm.contra,
        moves: const [
          MoveDef(
            id: 'ecd_swing',
            displayName: 'swing',
            renderTemplate: '{move}',
          ),
        ],
      );
      expect(() => TaxonomyRegistry(base: base), throwsArgumentError);
    });
  });
}
