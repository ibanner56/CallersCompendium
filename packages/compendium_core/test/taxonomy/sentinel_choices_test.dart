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
      // This is a REGRESSION GUARD, not a bug-finder: on today's taxonomy it
      // passes trivially, because every existing sentinel-bearing param
      // (`_handOrUnspecified`, `_spinOrUnspecified`, `_gateDirectionOrUnspecified`,
      // `_dancerOrUnspecified`, `_heyPass2Choices`, `_heyMeetTargetChoices`,
      // `_pairOrUnspecified`) was deliberately routed to `ParamKind.choice` or
      // `ParamKind.dancerSet`/`dancerPair` — kinds that already honoured
      // `spec.choices` before issue #726 — specifically to avoid this exact
      // trap. It exists to catch the NEXT author who declares a sentinel on a
      // kind the editor doesn't render it for. If this ever fails, the fix is
      // either: (a) give the param `ParamKind.choice` (or another kind already
      // in `_sentinelCapableKinds`), or (b) extend the editor's switch AND add
      // the kind to `_sentinelCapableKinds` above, together.
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
  });
}
