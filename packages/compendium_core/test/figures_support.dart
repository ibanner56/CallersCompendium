import 'package:compendium_core/compendium_core.dart';

/// The figure list of a [Dance] whose transcription is known to be decodable.
///
/// **This lives in `test/` on purpose, and production code cannot import it.**
/// [FigureSource] deliberately offers no shortcut that returns a `List<Figure>`,
/// because the next change in this sequence adds a second case and relies on
/// every *production* reader failing to compile until it says what that case
/// means there. A shortcut in `lib/` would make them all compile silently and
/// give back exactly the hazard the type exists to prevent.
///
/// A test is not one of those readers. No test is a write-back path, so the
/// compile-time forcing buys nothing here and would put a `switch` inside 270
/// assertions — the very lines a reviewer reads to judge whether a refactor
/// preserved behaviour. So tests get this, and `lib/` gets none.
///
/// Note that this helper is itself a `switch` over the sealed type, so the
/// second case will break *it* — one place, deliberately — at which point tests
/// that need to exercise an undecodable transcription stop using it and say so
/// explicitly.
List<Figure> figuresOf(Dance dance) => switch (dance.figuresSource) {
  DecodedFigures(:final figures) => figures,
};
