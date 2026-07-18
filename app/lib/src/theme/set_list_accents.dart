import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

/// Coarse "family" grouping of the 15 canonical [FormationShape]s, used to
/// drive the optional set-list row **accent colour** (issue #270).
///
/// The families are deliberately few (six) so the palette stays small,
/// mutually distinguishable, and easy to keep contrast-safe across the light
/// and high-contrast themes. The accent is only ever a *redundant* cue — every
/// row also carries its formation **text** (`formationLabel`), which is what
/// screen readers announce, per `docs/design/ux.md` §4 ("never colour alone").
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
Color? setListAccentForShape(
  FormationShape shape, {
  required bool highContrast,
}) => setListAccent(formationFamilyOf(shape), highContrast: highContrast);
