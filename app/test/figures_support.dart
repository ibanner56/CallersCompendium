import 'package:compendium_core/compendium_core.dart';

/// The figure list of a [Dance] whose transcription is known to be decodable.
///
/// A second copy of `compendium_core/test/figures_support.dart`, three lines
/// duplicated on purpose: one package's `test/` tree cannot import another's, and
/// the alternative — putting it in `lib/` so both could reach it — is exactly
/// the production-reachable shortcut this sequence exists to avoid. Duplicating
/// it is cheaper than the import ratchet that defending a shared copy would need.
///
/// See the core copy for why tests get an unwrap and production gets none.
List<Figure> figuresOf(Dance dance) => switch (dance.figuresSource) {
  DecodedFigures(:final figures) => figures,
};
