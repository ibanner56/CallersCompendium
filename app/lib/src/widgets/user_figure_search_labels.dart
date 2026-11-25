import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';
import '../search/facet_labels.dart';

/// How the advanced search names each of the user's own [views] (#2294), by
/// figure id: in the dialect of the dance form the figure was made for, as the
/// Glossary shows it, so a figure of yours made for English reads in your
/// English dialect where the list's own [dialect] is contra's.
///
/// Two figures of different forms can read alike in their own dialects; each
/// is then followed by its form's name ("Hey · English (ECD)"), as a move is
/// when another form's move is named like one of the search's own
/// ([moveLabelWithForm]). Both the options a figure is offered as and the
/// text a chosen figure rests as come from this one function, so a chosen
/// figure's field never reads differently from the option that set it.
///
/// With no [dialects], every figure reads in [dialect] and none is told apart:
/// how the search named them before each had a form's dialect.
Map<String, String> userFigureSearchLabels(
  Iterable<UserFigureView> views, {
  required AppLocalizations l10n,
  required FigureRenderer renderer,
  required Dialect dialect,
  DialectsByForm? dialects,
}) {
  String named(UserFigureView view) => renderer.renderFreeText(
    view.name,
    dialects?.forForm(view.form) ?? dialect,
  );
  final labels = {for (final view in views) view.id: named(view)};
  if (dialects == null) return labels;
  final formsByLabel = <String, Set<DanceForm>>{};
  for (final view in views) {
    formsByLabel
        .putIfAbsent(labels[view.id]!.trim().toLowerCase(), () => {})
        .add(view.form);
  }
  return {
    for (final view in views)
      view.id: (formsByLabel[labels[view.id]!.trim().toLowerCase()]!.length > 1)
          ? '${labels[view.id]} · ${danceFormLabel(l10n, view.form)}'
          : labels[view.id]!,
  };
}
