import '../model/enums.dart';
import '../model/figure.dart';
import 'taxonomy_registry.dart';

/// Contra's stand still, the placeholder figure a new dance's rows and a new
/// meanwhile's sides start as in every form. A square dance takes it as its
/// placeholder (Hudson, 23 November 2026: "a fine placeholder figure for
/// squares").
const String standStillMove = 'stand_still';

/// The form whose figures a dance of [form] holds as its own: [form] when it
/// has a taxonomy of its own, else contra's ([TaxonomyRegistry.base]), which
/// a form with none uses.
DanceForm ownFigureForm(DanceForm form, {TaxonomyRegistry? registry}) {
  final r = registry ?? shippedTaxonomies;
  return r.ownTaxonomy(form) == null ? r.base.form : form;
}

/// Whether [move], a non-container move, belongs in a dance of [form]: a
/// custom line, which every form shares, a move of [form]'s own taxonomy
/// ([ownFigureForm]), or a stand still in a square dance ([standStillMove]).
/// A move no taxonomy knows is not judged here and counts as fitting.
bool moveFitsForm(String move, DanceForm form, {TaxonomyRegistry? registry}) {
  final r = registry ?? shippedTaxonomies;
  if (move == customMove || r.anyForm.resolve(move) == null) return true;
  if (form == DanceForm.square && move == standStillMove) return true;
  return r.formOfMoveId(move) == ownFigureForm(form, registry: r);
}

/// Whether [figure], and every figure inside it, belongs in a dance of [form]
/// ([moveFitsForm]); the structural containers are shared by every form.
///
/// A parser reading a dance's text must yield only figures that pass this
/// (Hudson, 24 November 2026: "we should not parse out figures from the wrong
/// taxonomy - we need to match the selected dance type"): a square's line
/// that only contra's grammar can read stays a custom line, not a contra
/// call.
bool figureFitsForm(
  Figure figure,
  DanceForm form, {
  TaxonomyRegistry? registry,
}) => figure.isContainer
    ? figure.subFigures.every(
        (child) => figureFitsForm(child, form, registry: registry),
      )
    : moveFitsForm(figure.move, form, registry: registry);
