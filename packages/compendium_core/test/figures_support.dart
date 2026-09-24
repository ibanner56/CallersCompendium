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
/// compile-time forcing buys nothing here and would put a `switch` inside every
/// read site in both test trees — the very lines a reviewer reads to judge
/// whether a refactor preserved behaviour. So tests get this, and `lib/` gets
/// none. (Deliberately no count here: the first version of this comment carried
/// one and it was stale within the same pull request. The analyzer is the
/// instrument for that question, not a comment.)
///
/// Note that this helper is itself a `switch` over the sealed type, so the
/// second case will break *it* — one place, deliberately — at which point tests
/// that need to exercise an undecodable transcription stop using it and say so
/// explicitly.
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

/// The tune list of a [Dance] whose `tunes_json` is known to be decodable.
///
/// Same confinement and same reasoning as [figuresOf] above: it lives in
/// `test/`, production cannot import it, and it throws rather than returning an
/// empty list so a test cannot pass while asserting nothing.
List<String> tunesOf(Dance dance) => switch (dance.tunesSource) {
  DecodedTunes(:final tunes) => tunes,
  UnreadableTunes() => throw StateError(
    'tunesOf() called on a dance whose tune list could not be decoded; '
    'match on UnreadableTunes instead',
  ),
};
