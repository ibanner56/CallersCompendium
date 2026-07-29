import '../model/dance.dart';
import '../model/figure.dart';
import '../taxonomy/taxonomy.dart';
import 'snippet_library.dart';
import 'snippet_signature.dart';

/// Resolves the effective walkthrough snippet for a single [figure] (#411):
/// its per-dance [Figure.walkthroughOverride] if set, else the global
/// [library] default for the figure's signature, else `null` (no snippet).
///
/// Returns the RAW snippet text (canonical role tokens preserved). Rendering to
/// the active dialect happens later, at display time, via the dialect renderer's
/// `renderFreeText` — exactly like [Dance.walkthrough]. Never emits markup.
String? resolveFigureSnippet(
  Figure figure,
  WalkthroughSnippetLibrary library,
  Taxonomy taxonomy,
) {
  final override = figure.walkthroughOverride?.trim();
  if (override != null && override.isNotEmpty) return override;
  final resolved = library.resolve(figureSnippetSignature(figure, taxonomy));
  if (resolved == null) return null;
  final trimmed = resolved.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Assembles a plain-text walkthrough draft for [dance] from its per-figure
/// snippets (#411), in figure order, joined by [separator] (blank line by
/// default). Figures with no resolved snippet contribute nothing.
///
/// The result is an editable free-text string suitable for seeding
/// [Dance.walkthrough]; it is soft-clamped to [kMaxWalkthroughLength] so a
/// long dance can never produce an over-bound walkthrough. It is authoring
/// output only — the caller decides whether/how to store it, and it is never
/// written over non-empty user text without explicit confirmation.
String assembleWalkthrough({
  required Dance dance,
  required WalkthroughSnippetLibrary library,
  required Taxonomy taxonomy,
  String separator = '\n\n',
}) {
  final lines = <String>[];
  for (final figure in dance.figures) {
    final text = resolveFigureSnippet(figure, library, taxonomy);
    if (text != null) lines.add(text);
  }
  final joined = lines.join(separator);
  return joined.length <= kMaxWalkthroughLength
      ? joined
      : joined.substring(0, kMaxWalkthroughLength);
}

/// Whether [dance] has at least one figure that resolves to a snippet — i.e.
/// [assembleWalkthrough] would produce non-empty text. Lets the UI enable/disable
/// a "generate from snippets" affordance without building the whole string.
bool danceHasAssemblableWalkthrough(
  Dance dance,
  WalkthroughSnippetLibrary library,
  Taxonomy taxonomy,
) {
  for (final figure in dance.figures) {
    if (resolveFigureSnippet(figure, library, taxonomy) != null) return true;
  }
  return false;
}
