import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import 'wcag.dart';

/// Coarse "family" grouping of the 15 canonical [FormationShape]s, used to
/// drive the optional set-list row **accent colour** (issue #270).
///
/// The families are deliberately few (six) so the palette stays small,
/// mutually distinguishable, and easy to keep contrast-safe across the light
/// and high-contrast themes. The accent is only ever a *redundant* cue — every
/// row also carries its formation **text** and, for mixer-flagged dances, the
/// mixer term appended to that text, which is what screen readers announce,
/// per `docs/design/ux.md` §4 ("never colour alone").
///
/// Note: when [Dance.mixer] is `true`, the row accent is [FormationFamily.mixer]
/// **regardless of the dance's shape** — see [setListAccentForShapeAndMixer].
/// This means the family here describes the shape-to-family mapping only; the
/// resolved accent for a specific dance must go through [setListAccentForDance]
/// or [setListAccentForShapeAndMixer], not [setListAccentForShape].
enum FormationFamily {
  /// The bulk of contra dances: duple (improper/proper/indecent), becket, and
  /// generic longways sets.
  contraLongways,

  /// Triple-minor contras and triplets.
  triple,

  /// Scatter mixers (partner-changing, no fixed set).
  mixer,

  /// Circle-shaped sets: Sicilian circles and circle mixers.
  sicilianCircle,

  /// Big-set / square-ish formations: four-face-four, three-face-three, grid.
  bigSetSquare,

  /// Anything without a clear family (including [FormationShape.other]).
  other,
}

/// Maps a canonical [FormationShape] to its [FormationFamily]. Total over every
/// enum value so a new shape forces an explicit choice here.
FormationFamily formationFamilyOf(FormationShape shape) => switch (shape) {
  FormationShape.dupleImproper ||
  FormationShape.dupleProper ||
  FormationShape.dupleIndecent ||
  FormationShape.becketCw ||
  FormationShape.becketCcw ||
  FormationShape.longways => FormationFamily.contraLongways,
  FormationShape.tripleMinor ||
  FormationShape.triplet => FormationFamily.triple,
  FormationShape.scatterMixer => FormationFamily.mixer,
  FormationShape.sicilianCircle ||
  FormationShape.circleMixer => FormationFamily.sicilianCircle,
  FormationShape.fourFaceFour ||
  FormationShape.threeFaceThree ||
  FormationShape.grid => FormationFamily.bigSetSquare,
  FormationShape.other => FormationFamily.other,
};

/// Light-theme accent palette. Each hue clears WCAG ≥3:1 against the light
/// surface / card backgrounds (measured ≥5:1) so the accent reads clearly
/// while remaining a secondary cue.
const Map<FormationFamily, Color> _lightAccents = {
  FormationFamily.contraLongways: Color(0xFF00696E),
  FormationFamily.triple: Color(0xFF6A3EA1),
  FormationFamily.mixer: Color(0xFFA1266E),
  FormationFamily.sicilianCircle: Color(0xFF3B6B1E),
  FormationFamily.bigSetSquare: Color(0xFF8A5000),
  FormationFamily.other: Color(0xFF545E6B),
};

/// High-contrast / dark-stage accent palette. Bright variants that clear WCAG
/// ≥3:1 against the near-black high-contrast surface (measured ≥8:1), so the
/// accent stays visible without competing with text for legibility.
const Map<FormationFamily, Color> _highContrastAccents = {
  FormationFamily.contraLongways: Color(0xFF5AD6DE),
  FormationFamily.triple: Color(0xFFCBA6FF),
  FormationFamily.mixer: Color(0xFFFF9EC8),
  FormationFamily.sicilianCircle: Color(0xFF9CE06B),
  FormationFamily.bigSetSquare: Color(0xFFFFC24A),
  FormationFamily.other: Color(0xFFCED4DC),
};

/// The accent [Color] for a [FormationFamily] under the active theme, or `null`
/// if the family has no defined accent (never happens for the current families,
/// but keeps callers defensive). Pass [highContrast] `true` when either the
/// app's high-contrast theme or the OS high-contrast setting is active.
Color? setListAccent(FormationFamily family, {required bool highContrast}) =>
    (highContrast ? _highContrastAccents : _lightAccents)[family];

/// Convenience: resolve a [FormationShape] straight to its themed accent.
/// Shape-only — ignores the mixer flag. Use [setListAccentForShapeAndMixer]
/// when you have both a shape and a mixer flag, or [setListAccentForDance]
/// when you have a full [Dance]. This version is correct for surfaces that
/// operate on shape identity alone (e.g. the formation-colour settings screen).
Color? setListAccentForShape(
  FormationShape shape, {
  required bool highContrast,
}) => setListAccent(formationFamilyOf(shape), highContrast: highContrast);

/// Resolves the accent for a dance row, respecting the mixer flag (issue #732).
///
/// When [mixer] is `true`, returns the [FormationFamily.mixer] accent regardless
/// of [shape] — a mixer-flagged Duple Minor - Improper renders mixer pink, not
/// contra teal, and a mixer-flagged Circle Mixer renders mixer pink, not
/// sicilianCircle green (note: [FormationShape.circleMixer] maps to
/// [FormationFamily.sicilianCircle] by shape alone — the mixer flag is what
/// makes it pink). The 589 non-mixer Sicilian Circles stay green.
///
/// Leaves [formationFamilyOf] total and [setListAccentForShape] intact.
Color? setListAccentForShapeAndMixer(
  FormationShape shape,
  bool mixer, {
  required bool highContrast,
}) => setListAccent(
  mixer ? FormationFamily.mixer : formationFamilyOf(shape),
  highContrast: highContrast,
);

/// Convenience: resolve a [Dance] straight to its themed accent.
/// Delegates to [setListAccentForShapeAndMixer] with the dance's shape and
/// mixer flag.
Color? setListAccentForDance(
  Dance dance, {
  required bool highContrast,
}) => setListAccentForShapeAndMixer(
  dance.formation.shape,
  dance.mixer,
  highContrast: highContrast,
);

/// Resolves the color to use for a formation **label** (issue #367): the
/// user's per-shape [overrides] win, otherwise the themed family accent (which
/// may be `null` for a family with no accent). This is the resolution used to
/// *seed the settings picker* and in tests; the label surfaces themselves only
/// paint a highlight when the user explicitly set an override (override-only
/// rendering), reading [FormationColorsController.overrideFor] directly rather
/// than this fallback.
Color? resolveFormationLabelColor(
  FormationShape shape, {
  required Map<FormationShape, Color> overrides,
  required bool highContrast,
}) =>
    overrides[shape] ??
    setListAccentForShape(shape, highContrast: highContrast);

/// Picks a readable foreground (black or white) to lay over [background] for a
/// formation-label highlight badge (issue #367), choosing whichever clears the
/// WCAG AA normal-text bar (≥4.5:1); when neither does (a rare mid-tone), the
/// higher-contrast of the two is returned so the text is still as legible as
/// possible. Keeps the colored label readable regardless of the user's chosen
/// hue.
Color readableForegroundOn(Color background) {
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);
  final blackRatio = Wcag.contrastRatio(black, background);
  final whiteRatio = Wcag.contrastRatio(white, background);
  if (blackRatio >= Wcag.aaText && blackRatio >= whiteRatio) return black;
  if (whiteRatio >= Wcag.aaText) return white;
  return blackRatio >= whiteRatio ? black : white;
}
