import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import 'canonical_discouraged_terms_scope.dart';
import 'decimal_turns_scope.dart';

/// The one-line text a caller sees for [figure] on a list preview or a value
/// comparison: [FigureRenderer.renderSummary], so a balance flag, a hall-
/// direction ender, a hey length and a long-lines go-back all show, with the
/// "Show turns as decimals" and "Auto-convert all discouraged terms" display
/// settings applied.
///
/// Registers rebuild dependencies on both scopes. Use it instead of
/// [FigureRenderer.render], which deliberately omits those modifiers and so can
/// show two different figures as the same text.
String renderFigureSummary(
  BuildContext context,
  FigureRenderer renderer,
  Figure figure,
  Dialect dialect,
) {
  final decimals = DecimalTurnsScope.of(context);
  return CanonicalDiscouragedTermsScope.of(context)
      ? renderer.renderSummaryWithCanonicalDiscouragedTerms(
          figure,
          dialect,
          decimals: decimals,
        )
      : renderer.renderSummary(figure, dialect, decimals: decimals);
}
