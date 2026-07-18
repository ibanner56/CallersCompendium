import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../data/app_theme_scope.dart';
import '../data/colour_dance_theme_scope.dart';
import '../data/reduce_motion_scope.dart';
import '../theme/app_theme.dart';

/// Scoped theme override for the "colour-named dances tint the theme" easter
/// egg (issue #307).
///
/// Wraps [child] and, **only when every guardrail allows it**, replaces the
/// ambient theme for that subtree with one seeded from the colour named in
/// [title]. The override is intentionally scoped to the dance's own view
/// (dance detail / Perform) rather than mutating global settings, so it tracks
/// "the dance you're looking at".
///
/// Guardrails (all must hold, else [child] renders unchanged):
///  * the [ColourDanceThemeScope] setting is on (off by default — opt-in);
///  * a high-contrast theme is **not** active — readability wins over novelty,
///    so the egg defers (`docs/design/ux.md` §4). Both the in-app high-contrast
///    selection and the OS high-contrast accessibility flag are honoured;
///  * [title] contains a recognised colour word (`colourSeedForTitle`).
///
/// Reduce-motion is honoured: when on, the swap is instant ([Theme]); otherwise
/// it cross-fades ([AnimatedTheme]).
///
/// The generated scheme comes from [ColorScheme.fromSeed] (via
/// [AppTheme.fromScheme]), which derives accessible on-colours, so contrast
/// holds for vivid seeds. The tint is decorative only — it never conveys
/// meaning on its own.
class ColourDanceTheme extends StatelessWidget {
  const ColourDanceTheme({super.key, required this.title, required this.child});

  /// The dance title to scan for a colour word. When `null`/empty, no override.
  final String? title;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = ColourDanceThemeScope.of(context);
    if (!enabled) return child;

    // Defer under high contrast: the in-app HC selection or the OS flag.
    final highContrast =
        AppThemeScope.of(context).isHighContrast ||
        MediaQuery.of(context).highContrast;
    if (highContrast) return child;

    final t = title;
    final seed = (t == null || t.isEmpty) ? null : colourSeedForTitle(t);
    if (seed == null) return child;

    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(seed),
      brightness: base.brightness,
    );
    final data = AppTheme.fromScheme(scheme);

    // Reduce-motion: no animated theme transition.
    return ReduceMotionScope.of(context)
        ? Theme(data: data, child: child)
        : AnimatedTheme(data: data, child: child);
  }
}
