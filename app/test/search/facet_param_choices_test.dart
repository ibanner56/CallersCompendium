import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `figureParamChoices` is the value vocabulary behind the optional param
/// dropdowns on an Advanced "has figure" row. It is the THIRD consumer of the
/// `ParamSpec.kind` + `ParamSpec.choices` contract — the other two being
/// `FigureParamEditor` (the figure edit dropdowns) and `ParamSpec.validate` —
/// and was the last one still ignoring `spec.choices` for five kinds.
///
/// Every spec that pairs a typed kind WITH a `choices` list is synthetic here,
/// deliberately: no param in `contraTaxonomy` declares that combination today
/// (taxonomy authors routed such params to `ParamKind.choice` to work around
/// the editor's matching gap, see #739), so nothing real exercises this path.
/// That is exactly why it needs pinning — the defect is latent, and a test
/// suite that only walks the live taxonomy would never catch it.
void main() {
  // Kind -> the fixed vocabulary that kind falls back to when a spec declares
  // no `choices`. Drives the table-driven cases below.
  const fixedVocabByKind = <ParamKind, List<String>>{
    ParamKind.handedness: ParamVocab.sides,
    ParamKind.shoulder: ParamVocab.sides,
    ParamKind.spinDirection: ParamVocab.spins,
    ParamKind.fraction: ParamVocab.fractions,
    ParamKind.direction: ParamVocab.directions,
  };

  group('the five formerly-hardcoded kinds', () {
    fixedVocabByKind.forEach((kind, fixedVocab) {
      final defaultValue = fixedVocab.first;

      // Unchanged-behaviour guard. EVERY param of these kinds in today's
      // taxonomy omits `choices`, so this is the case that must not move: the
      // fix is additive, and a spec that opts into nothing keeps exactly the
      // vocabulary it had before.
      test('$kind without choices returns the fixed vocabulary', () {
        final spec = ParamSpec(kind, defaultValue: defaultValue);
        expect(figureParamChoices(spec), fixedVocab);
        expect(
          figureParamChoices(spec),
          isNot(contains(ParamVocab.unspecified)),
        );
      });

      // The headline case, and the reason this is a defect rather than a
      // missing feature: a spec that NARROWS its kind's domain used to get a
      // dropdown offering the values it had just excluded. The search row would
      // then build a filter for a value the param cannot hold — and which
      // `ParamSpec.validate` rejects outright (see the invariant group below).
      test('$kind with narrowed choices returns only the narrowed values', () {
        final narrowed = [fixedVocab.first];
        final spec = ParamSpec(
          kind,
          defaultValue: defaultValue,
          choices: narrowed,
        );
        expect(figureParamChoices(spec), narrowed);
        for (final excluded in fixedVocab.skip(1)) {
          expect(
            figureParamChoices(spec),
            isNot(contains(excluded)),
            reason:
                '$kind narrowed to $narrowed must not offer $excluded — the '
                'param cannot hold it',
          );
        }
      });

      // The #726 sentinel case, in the facet layer. A spec may opt into
      // "the source stated nothing" by listing it in `choices`; the facet has
      // to offer it or the user can never search for figures whose source was
      // silent about this param.
      test('$kind with a sentinel in choices offers the sentinel', () {
        final withSentinel = [...fixedVocab, ParamVocab.unspecified];
        final spec = ParamSpec(
          kind,
          defaultValue: defaultValue,
          choices: withSentinel,
        );
        expect(figureParamChoices(spec), withSentinel);
        expect(figureParamChoices(spec), contains(ParamVocab.unspecified));
      });
    });
  });

  // These branches were already correct before this change. Pinned so a future
  // edit to the switch cannot quietly regress them along with the five above.
  group('branches that already honoured the contract stay put', () {
    test(
      'dancerSet/dancerPair without choices return the full dancer domain',
      () {
        for (final kind in [ParamKind.dancerSet, ParamKind.dancerPair]) {
          final spec = ParamSpec(kind, defaultValue: 'everyone');
          expect(
            figureParamChoices(spec),
            ParamVocab.dancerSets,
            reason: '$kind',
          );
        }
      },
    );

    test('dancerSet/dancerPair with choices return them verbatim', () {
      const narrowed = ['role1s', 'role2s', ParamVocab.unspecified];
      for (final kind in [ParamKind.dancerSet, ParamKind.dancerPair]) {
        final spec = ParamSpec(kind, defaultValue: 'role1s', choices: narrowed);
        expect(figureParamChoices(spec), narrowed, reason: '$kind');
      }
    });

    test('choice returns its declared domain', () {
      const spec = ParamSpec(
        ParamKind.choice,
        defaultValue: 'gypsy',
        choices: ['gypsy', 'gyre', ParamVocab.unspecified],
      );
      expect(figureParamChoices(spec), [
        'gypsy',
        'gyre',
        ParamVocab.unspecified,
      ]);
    });

    test('choice without a domain offers no dropdown at all', () {
      // A `choice` spec with no `choices` is malformed, but the facet must not
      // invent a vocabulary for it: `null` means "no dropdown", which is
      // strictly better than an empty one the user can only stare at.
      const spec = ParamSpec(ParamKind.choice, defaultValue: null);
      expect(figureParamChoices(spec), isNull);
    });
  });

  group('kinds with no closed vocabulary return null', () {
    // `rotation`/`places`/`beats` are numeric and `text`/`flag` are not
    // enumerable, so there is nothing to put in a dropdown. Note `rotation` may
    // still opt into the sentinel via `choices` (taxonomy v22's `gate.turn`) —
    // the facet deliberately still declines, because a rotation's domain is not
    // its `choices` list. See the PR's "known adjacent gaps" note.
    const cases = <ParamKind, Object?>{
      ParamKind.rotation: 1.0,
      ParamKind.places: 1,
      ParamKind.beats: 8,
      ParamKind.text: '',
      ParamKind.flag: false,
    };
    cases.forEach((kind, defaultValue) {
      test('$kind', () {
        expect(
          figureParamChoices(ParamSpec(kind, defaultValue: defaultValue)),
          isNull,
        );
      });
    });

    test('rotation stays null even when it opts into the sentinel', () {
      const spec = ParamSpec(
        ParamKind.rotation,
        defaultValue: ParamVocab.unspecified,
        choices: [ParamVocab.unspecified],
      );
      expect(figureParamChoices(spec), isNull);
    });
  });

  // The invariant that makes the whole contract falsifiable, and the direction
  // PR #736's review caught for the editor: a facet that OFFERS a value
  // `ParamSpec.validate` REJECTS lets the user build a search filter that can
  // never match a valid figure. Before this change the narrowed cases below
  // failed — the facet offered `left` for a handedness spec whose domain was
  // `['right']`, which `validate` (post-#736) rejects.
  group('the facet never offers a value ParamSpec.validate rejects', () {
    test('across synthetic specs for every kind that has a vocabulary', () {
      final specs = <ParamSpec>[
        for (final entry in fixedVocabByKind.entries) ...[
          ParamSpec(entry.key, defaultValue: entry.value.first),
          ParamSpec(
            entry.key,
            defaultValue: entry.value.first,
            choices: [entry.value.first],
          ),
          ParamSpec(
            entry.key,
            defaultValue: entry.value.first,
            choices: [...entry.value, ParamVocab.unspecified],
          ),
        ],
        const ParamSpec(ParamKind.dancerSet, defaultValue: 'everyone'),
        const ParamSpec(
          ParamKind.dancerPair,
          defaultValue: 'role1s',
          choices: ['role1s', 'role2s', ParamVocab.unspecified],
        ),
        const ParamSpec(
          ParamKind.choice,
          defaultValue: 'gypsy',
          choices: ['gypsy', 'gyre'],
        ),
      ];

      for (final spec in specs) {
        for (final choice in figureParamChoices(spec) ?? const <String>[]) {
          expect(
            spec.validate(choice),
            isTrue,
            reason:
                'the facet offers "$choice" for a ${spec.kind} spec whose '
                'domain is ${spec.choices ?? "the fixed vocabulary"}, but '
                'ParamSpec.validate rejects it — the search row would build a '
                'filter no valid figure can match',
          );
        }
      }
    });

    // ⚠️ This one CANNOT FAIL ON TODAY'S TAXONOMY, by construction — it is a
    // REGRESSION GUARD, not a bug-finder, and must not be mistaken for active
    // coverage of the fix (the synthetic sweep above is what actually proves
    // it; that one IS red without the fix). No live param pairs one of the
    // five typed kinds with a `choices` list, so every spec here takes a
    // branch that was already correct. It exists to start doing real work the
    // moment that stops being true — #739 re-declaring `_handOrUnspecified` /
    // `_spinOrUnspecified` with their natural kinds is the next such change —
    // and to fail loudly if the facet and the validator ever disagree again.
    // Same convention as `sentinel_choices_test.dart` in compendium_core.
    test('across every param in contraTaxonomy (drift guard — cannot fail '
        'on today\'s taxonomy)', () {
      final offenders = <String>[];
      for (final move in contraTaxonomy.moves.values) {
        move.params.forEach((name, spec) {
          for (final choice in figureParamChoices(spec) ?? const <String>[]) {
            if (!spec.validate(choice)) {
              offenders.add('${move.id}.$name (${spec.kind}) offers "$choice"');
            }
          }
        });
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these params offer a search-facet value their own validator '
            'rejects, so the Advanced "has figure" row would build a filter no '
            'valid figure can match: $offenders\n'
            'NOTE: this assertion passes trivially on the taxonomy as of the '
            'fix (nothing exercises the five typed-kind-plus-choices paths), '
            'so if you are reading this it means a taxonomy change made it '
            'live — fix the param or the facet, do not relax the test.',
      );
    });
  });
}
