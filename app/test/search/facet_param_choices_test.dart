import 'package:compendium_app/src/search/facet_labels.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `figureParamChoices` is the value vocabulary behind the optional param
/// dropdowns on an Advanced "has figure" row. It is the THIRD consumer of the
/// `ParamSpec.kind` + `ParamSpec.choices` contract — the other two being
/// `FigureParamEditor` (the figure edit dropdowns) and `ParamSpec.validate` —
/// and was the last one still ignoring `spec.choices` for five kinds.
///
/// The synthetic specs below stay synthetic on purpose — they sweep kinds and
/// shapes the taxonomy does not currently declare, so the contract is pinned
/// independently of whatever the taxonomy happens to contain. They were the
/// ONLY coverage when this was written, because no live param then paired a
/// typed kind with a `choices` list: taxonomy authors routed such params to
/// `ParamKind.choice` to work around the gap this file fixes. Issue #739 has
/// since unwound that workaround, so the live-taxonomy sweep at the bottom is
/// no longer vacuous (see its own note).
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

      // Unchanged-behaviour guard: a spec that opts into nothing keeps exactly
      // the vocabulary it had before, because the fix is additive.
      //
      // This was once justified as "EVERY param of these kinds omits
      // `choices`", which #739 / PR #751 falsified — `form_long_waves.hand`,
      // `mad_robin.direction` and `butterfly_whirl.direction` now declare one.
      // The guard does not depend on that being true, so the claim is dropped
      // rather than re-counted: what matters is the omit-`choices` SHAPE, which
      // is a permanent case whether or not any live param currently takes it.
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

      // The sentinel scenario #726 fixed for the EDITOR, here in the facet
      // layer (#726 did not reach this function — PR #746 did). A spec may opt
      // into "the source stated nothing" by listing it in `choices`; the facet
      // has to offer it or the user can never search for figures whose source
      // was silent about this param.
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

    // Live-taxonomy sweep #1 — the direction that ACTUALLY catches a dropped
    // sentinel, and the reason issue #739 had to wait for this file's fix.
    //
    // The `offers nothing validate rejects` sweep below is one-directional: it
    // catches the facet offering TOO MUCH, never too little. Re-declaring
    // `form_long_waves.hand` as a `handedness` and `mad_robin.direction` /
    // `butterfly_whirl.direction` as `spinDirection`s under the OLD hardcoded
    // facet would have moved them into a branch returning `ParamVocab.sides` /
    // `ParamVocab.spins`, silently dropping `unspecified` from the Advanced
    // search dropdown — a real loss of the ability to search for "the source
    // stated nothing" — while every other guard in the repo stayed green,
    // because `sides` and `spins` are perfectly valid values.
    //
    // So: whenever a spec declares a domain AND the facet offers a dropdown at
    // all, the dropdown must be that domain, exactly. Unlike the sweep below,
    // this is NOT vacuous — since #739 three live params pair a typed kind with
    // a sentinel-bearing `choices` list, so reverting `figureParamChoices` to
    // its hardcoded form turns this red.
    test('every param with a declared domain is offered exactly that domain', () {
      final offenders = <String>[];
      for (final move in contraTaxonomy.moves.values) {
        move.params.forEach((name, spec) {
          final declared = spec.choices;
          if (declared == null) return;
          final offered = figureParamChoices(spec);
          // `null` means "no dropdown for this kind at all" (e.g. `gate.turn`,
          // a rotation that opts into the sentinel); that is a deliberate
          // decision the facet makes per KIND, not a dropped value.
          if (offered == null) return;
          if (offered.join('\u0000') != declared.join('\u0000')) {
            offenders.add(
              '${move.id}.$name (${spec.kind}) declares $declared but the '
              'facet offers $offered',
            );
          }
        });
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'the Advanced "has figure" row must offer a param\'s declared '
            'domain verbatim. Offering LESS is the silent failure mode: a '
            'param that opts into ParamVocab.unspecified becomes unsearchable '
            'for "not stated" with every other test still green: $offenders',
      );
    });

    // Live-taxonomy sweep #2 — the opposite direction, and much weaker.
    //
    // ⚠️ Read the reason string before trusting this one. It catches only the
    // facet offering a value the validator REJECTS, so on any taxonomy where
    // the facet under-offers it stays green (that is what the sweep above is
    // for). The synthetic cases earlier in this file are what actually prove
    // the fix; those ARE red without it. Same convention as
    // `sentinel_choices_test.dart` in compendium_core.
    test('across every param in contraTaxonomy, the facet never offers a '
        'value validate rejects', () {
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
            'NOTE: this direction is the weak one — it cannot see a value the '
            'facet fails to offer. The "declared domain" sweep above covers '
            'that; fix the param or the facet, do not relax either test.',
      );
    });
  });
}
