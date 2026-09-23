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
  // Deliberately loud. A test reaching here expected a decodable
  // transcription and did not get one, which is a wrong expectation rather
  // than a case to paper over — returning an empty list would let the test
  // pass while asserting nothing. A test that means to exercise an
  // undecodable transcription matches on [UnreadableFigures] itself.
  UnreadableFigures() => throw StateError(
    'figuresOf() called on a dance whose transcription could not be decoded; '
    'match on UnreadableFigures instead',
  ),
};
