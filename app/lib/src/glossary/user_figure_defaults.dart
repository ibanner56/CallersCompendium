import 'package:compendium_core/compendium_core.dart';

import '../data/display_defaults.dart';

/// What deleting the user's figure [id] (#1023, plan C9) makes of the
/// default figure lists that use it: for each one whose stored value holds a
/// use, its settings key and the value to store, with each use made plain
/// text with the line it renders to through [renderer] now, as the dances
/// are frozen (maintainer decision 2). Read while the figure still exists,
/// so [renderer] can render it; written once it is deleted.
///
/// A list never stored is the app's own default, which holds no figure of
/// the user's, so it is left alone.
Future<Map<String, String>> frozenDefaultFigureLists(
  SettingsRepository settings,
  String id,
  FigureRenderer renderer,
) => _rewrittenDefaultFigureLists(
  settings,
  (figures) => freezeUserFigureUsesIn(figures, id, renderer),
);

/// What switching the user's figure [id] to the shipped figure [mapping]
/// names (#1023, maintainer decision 5) makes of the default figure lists
/// that use it, as [frozenDefaultFigureLists] for a delete: each use
/// switched as the dances are ([switchUserFigureUsesIn]). Read while the
/// figure still exists; written once it is retired.
Future<Map<String, String>> switchedDefaultFigureLists(
  SettingsRepository settings,
  String id,
  UserFigureDefinition definition,
  UserFigureSwitch mapping,
  FigureRenderer renderer,
) => _rewrittenDefaultFigureLists(
  settings,
  (figures) => switchUserFigureUsesIn(
    figures,
    id,
    definition,
    mapping,
    renderer.taxonomy,
    renderer,
  ),
);

/// For each stored default figure list that [rewrite] changes (returning a
/// list not identical to the one it was given), its settings key and the
/// value to store.
Future<Map<String, String>> _rewrittenDefaultFigureLists(
  SettingsRepository settings,
  List<Figure> Function(List<Figure> figures) rewrite,
) async {
  final rewritten = <String, String>{};
  Future<void> rewriteList(
    String key,
    List<Figure> Function(Object? stored) decode,
    String Function(List<Figure> figures) encode,
  ) async {
    final stored = await settings.get(key);
    if (stored == null) return;
    final figures = decode(stored);
    final kept = rewrite(figures);
    if (!identical(kept, figures)) rewritten[key] = encode(kept);
  }

  await rewriteList(
    kDefaultDanceFiguresTemplateKey,
    danceFiguresTemplateFromStored,
    encodeFigures,
  );
  await rewriteList(
    kDefaultMeanwhileSideFiguresKey,
    meanwhileSideFiguresFromStored,
    encodeMeanwhileSideFigures,
  );
  await rewriteList(
    kDefaultModifierFiguresKey,
    modifierFiguresFromStored,
    encodeModifierFigures,
  );
  return rewritten;
}
