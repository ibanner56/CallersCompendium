import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

/// [ParamKind]s the figure param editor (`FigureParamEditor.build` in
/// `app/lib/src/widgets/figure_param_editors.dart`) renders FROM
/// `spec.choices` — i.e. a spec of one of these kinds that lists
/// [ParamVocab.unspecified] in `choices` gets a dropdown/stepper that actually
/// offers the sentinel. `compendium_core` cannot import the app widget, so
/// this list is a plain, hand-maintained mirror of that `switch (spec.kind)`;
/// it must be updated in lockstep whenever a kind is added there or a new kind
/// starts (or stops) consulting `spec.choices`. The app-side widget tests
/// (`app/test/widgets/figure_param_editors_test.dart`) are what actually
/// exercise the rendering — this test only guards the TAXONOMY side of the
/// contract: a param's `choices` and its `kind` must not disagree about
/// whether "not stated" is representable.
const _sentinelCapableKinds = {
  ParamKind.dancerSet,
  ParamKind.dancerPair,
  ParamKind.choice,
  ParamKind.rotation,
  ParamKind.handedness,
  ParamKind.shoulder,
  ParamKind.spinDirection,
  ParamKind.fraction,
  ParamKind.direction,
};

void main() {
  group('sentinel-bearing params are only declared on renderable kinds '
      '(#726)', () {
    test('every param whose choices admit ParamVocab.unspecified has a kind '
        'the editor can render', () {
      final offenders = <String>[];
      for (final move in contraTaxonomy.moves.values) {
        move.params.forEach((name, spec) {
          final choices = spec.choices;
          if (choices != null &&
              choices.contains(ParamVocab.unspecified) &&
              !_sentinelCapableKinds.contains(spec.kind)) {
            offenders.add('${move.id}.$name (${spec.kind})');
          }
        });
      }
      // This is a REGRESSION GUARD, not a bug-finder: it passes on today's
      // taxonomy because every sentinel-bearing param is declared on a kind
      // that honours `spec.choices`. Since issue #739 that includes the
      // NATURAL typed kinds — `form_long_waves.hand` is a `handedness` and
      // `mad_robin.direction` / `butterfly_whirl.direction` are
      // `spinDirection`s, each listing the sentinel in `choices`. The rest sit
      // on `ParamKind.choice` (`gate.direction`, `swing.endFacing`) or
      // `dancerSet`/`dancerPair` (`_dancerOrUnspecified`, `_heyPass2Choices`,
      // `_heyMeetTargetChoices`, `_pairOrUnspecified`), and `gate.turn` is the
      // one `rotation` that opts in. It exists to catch the NEXT author who
      // declares a sentinel on a kind the editor doesn't render it for. If this
      // ever fails, the fix is either: (a) move the param to a kind already in
      // `_sentinelCapableKinds`, or (b) extend the editor's switch AND add the
      // kind to `_sentinelCapableKinds` above, together.
      expect(
        offenders,
        isEmpty,
        reason:
            'these params declare ParamVocab.unspecified in `choices` but a '
            'kind the figure param editor cannot render the sentinel for — '
            'the user could never express, or return to, "not stated": '
            '$offenders',
      );
    });

    // The matching direction (issue #736 review finding): a sentinel the
    // editor can OFFER is worthless if `ParamSpec.validate` then REJECTS it —
    // the figure would fail `Taxonomy.validateFigure`/import validation the
    // moment a user (or importer) actually selects "not stated". Unlike the
    // editor-side check above, this needs no hand-maintained kind list:
    // `spec.validate` is right here in core, so we just call it.
    test('every param whose choices admit ParamVocab.unspecified is accepted '
        'by its own validator', () {
      final offenders = <String>[];
      for (final move in contraTaxonomy.moves.values) {
        move.params.forEach((name, spec) {
          final choices = spec.choices;
          if (choices != null &&
              choices.contains(ParamVocab.unspecified) &&
              !spec.validate(ParamVocab.unspecified)) {
            offenders.add('${move.id}.$name (${spec.kind})');
          }
        });
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these params declare ParamVocab.unspecified in `choices` but '
            'ParamSpec.validate rejects it for their kind — a figure that '
            'stores the sentinel (via the editor or an importer) would fail '
            'validateFigure/import validation: $offenders',
      );
    });

    // Issue #739. The two checks above accept `ParamKind.choice` as a home for
    // a sentinel — correctly, since it honours `choices`. But `choice` is also
    // where the OBSOLETE workaround lived: before #726/#736/#746 the five typed
    // dropdown kinds rendered and validated from a hardcoded vocabulary that
    // ignored `spec.choices`, so the only way to give a semantically typed
    // param the "source stated nothing" sentinel was to launder it through
    // `choice` and lose the type information. That is fixed, and #739 unwound
    // the three declarations that used it.
    //
    // This guard stops it creeping back. Its signature is precise: a `choice`
    // whose domain, minus the sentinel, is EXACTLY one of the fixed
    // vocabularies has no reason to be a `choice` — it is that kind. A `choice`
    // that merely OVERLAPS a fixed vocabulary is legitimate and must not be
    // flagged: `gate.direction` is `spins` PLUS `mirror` (the two-couple gate,
    // which `ParamKind.spinDirection` cannot express, so converting it would
    // silently drop `mirror`), and `swing.endFacing`/`gate.face` are the
    // set-relative `gateFacings`, a different concept from
    // `ParamKind.direction`'s eight spatial tokens.
    //
    // ⚠️ `ParamVocab.sides` needs the extra `hand`/`shoulder` name test, and it
    // is not belt-and-braces — writing this guard without it flagged five
    // params that are CORRECTLY `choice`: `slide_along_set.slide`,
    // `rory_o_more.slide`, `slice.slice`, `zig_zag.turn` and `circle.turn`.
    // `['left', 'right']` is an overloaded vocabulary: in those params it is a
    // SPATIAL side (which way the move travels), not a hand or a shoulder, and
    // `ParamKind.handedness` means specifically "right/left **hand**". Token
    // identity is not kind identity for this one vocabulary, so the name is
    // what distinguishes them. The other four vocabularies are unambiguous —
    // nothing but a spin is `clockwise`/`counterclockwise` — and need no such
    // qualification.
    test('no param launders a fixed vocabulary through ParamKind.choice', () {
      const unambiguousVocabs = <String, List<String>>{
        'ParamKind.spinDirection (ParamVocab.spins)': ParamVocab.spins,
        'ParamKind.fraction (ParamVocab.fractions)': ParamVocab.fractions,
        'ParamKind.direction (ParamVocab.directions)': ParamVocab.directions,
        'ParamKind.dancerSet/dancerPair (ParamVocab.dancerSets)':
            ParamVocab.dancerSets,
      };
      String key(Iterable<String> values) =>
          (values.toSet().toList()..sort()).join('\u0000');

      final offenders = <String>[];
      for (final move in contraTaxonomy.moves.values) {
        move.params.forEach((name, spec) {
          if (spec.kind != ParamKind.choice) return;
          final domain = (spec.choices ?? const <String>[])
              .where((v) => v != ParamVocab.unspecified)
              .toList();
          if (domain.isEmpty) return;
          unambiguousVocabs.forEach((label, vocab) {
            if (key(domain) == key(vocab)) {
              offenders.add('${move.id}.$name is exactly $label');
            }
          });
          if ((name == 'hand' || name == 'shoulder') &&
              key(domain) == key(ParamVocab.sides)) {
            offenders.add(
              '${move.id}.$name is exactly ParamKind.handedness/shoulder '
              '(ParamVocab.sides)',
            );
          }
        });
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these params are declared ParamKind.choice but their domain is a '
            "fixed kind's whole vocabulary, so they are throwing away type "
            'information for nothing — declare the natural kind and keep the '
            '`choices` list (that is what issue #739 did, and every consumer '
            'now reads `spec.choices ?? <fixed vocabulary>`): $offenders',
      );
    });
  });
}
