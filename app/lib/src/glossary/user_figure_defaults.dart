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
) async {
  final frozen = <String, String>{};
  Future<void> freeze(
    String key,
    List<Figure> Function(Object? stored) decode,
    String Function(List<Figure> figures) encode,
  ) async {
    final stored = await settings.get(key);
    if (stored == null) return;
    final figures = decode(stored);
    final kept = freezeUserFigureUsesIn(figures, id, renderer);
    if (!identical(kept, figures)) frozen[key] = encode(kept);
  }

  await freeze(
    kDefaultDanceFiguresTemplateKey,
    danceFiguresTemplateFromStored,
    encodeFigures,
  );
  await freeze(
    kDefaultMeanwhileSideFiguresKey,
    meanwhileSideFiguresFromStored,
    encodeMeanwhileSideFigures,
  );
  await freeze(
    kDefaultModifierFiguresKey,
    modifierFiguresFromStored,
    encodeModifierFigures,
  );
  return frozen;
}
