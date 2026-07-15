import 'package:flutter/material.dart';

/// Contrast-safe [ColorScheme] derivation for the UX-6 theme gallery
/// (`docs/design/ux-modernization.md` §4A).
///
/// The gallery ships ~10 IDE-inspired palettes. Rather than hand-authoring
/// 30 role hexes per palette and hoping each pair clears WCAG, we take each
/// palette's *identity* colors (surface, foreground, three accents) and derive
/// a full [ColorScheme] whose text/non-text pairs pass **WCAG 2.2 AA by
/// construction**: foreground and accent tones are nudged toward the nearest
/// contrast pole until they clear the required ratio. This is verified
/// exhaustively by `test/theme/palette_contrast_test.dart`.
///
/// Policy (per §4A): *preserve the identity hue, tune the tone.* Accent colors
/// (primary/secondary/tertiary/error and their containers) are adjusted in HSL
/// by lightness only, so hue is preserved — Solarized still reads as Solarized.
/// Neutral foregrounds (onSurface/onSurfaceVariant/outline) are instead blended
/// straight toward the nearest contrast pole (black/white); that can shift a
/// slightly-tinted grey toward true neutral, which is the desired result for
/// body text and borders.
///
/// Pure data + math (no widgets); consumed by [AppTheme] via the theme
/// selection resolvers in `data/app_theme_scope.dart`.
class GalleryPalettes {
  const GalleryPalettes._();

  // WCAG AA targets.
  static const double _text = 4.5; // body text & icons
  static const double _nonText = 3.0; // large text & non-text UI (borders)

  // ---- Light palettes -----------------------------------------------------

  /// Solarized Light (Ethan Schoonover, MIT). Exact base/accent hues.
  static final ColorScheme solarizedLight = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFFDF6E3),
    onSurface: const Color(0xFF657B83),
    primary: const Color(0xFF268BD2),
    secondary: const Color(0xFF859900),
    tertiary: const Color(0xFFB58900),
    error: const Color(0xFFDC322F),
  );

  /// Atom One Light — inspired, contrast-tuned.
  static final ColorScheme atomOneLight = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFFAFAFA),
    onSurface: const Color(0xFF383A42),
    primary: const Color(0xFF4078F2),
    secondary: const Color(0xFF50A14F),
    tertiary: const Color(0xFFA626A4),
    error: const Color(0xFFE45649),
  );

  /// Noctis Lux — inspired, contrast-tuned.
  static final ColorScheme noctisLux = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFF9F6F2),
    onSurface: const Color(0xFF53606C),
    primary: const Color(0xFF00A38B),
    secondary: const Color(0xFF2E8B57),
    tertiary: const Color(0xFFC7852A),
    error: const Color(0xFFC5341A),
  );

  // ---- Dark palettes ------------------------------------------------------

  /// Solarized Dark (Ethan Schoonover, MIT). Exact base/accent hues.
  static final ColorScheme solarizedDark = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF002B36),
    onSurface: const Color(0xFF839496),
    primary: const Color(0xFF268BD2),
    secondary: const Color(0xFF859900),
    tertiary: const Color(0xFFB58900),
    error: const Color(0xFFDC322F),
  );

  /// Atom One Dark — inspired, contrast-tuned.
  static final ColorScheme atomOneDark = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF282C34),
    onSurface: const Color(0xFFABB2BF),
    primary: const Color(0xFF61AFEF),
    secondary: const Color(0xFF98C379),
    tertiary: const Color(0xFFC678DD),
    error: const Color(0xFFE06C75),
  );

  /// One Dark Pro — inspired, contrast-tuned.
  static final ColorScheme oneDarkPro = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF282C34),
    onSurface: const Color(0xFFABB2BF),
    primary: const Color(0xFF61AFEF),
    secondary: const Color(0xFF98C379),
    tertiary: const Color(0xFFE5C07B),
    error: const Color(0xFFE06C75),
  );

  /// One Dark Pro Darker — inspired, contrast-tuned.
  static final ColorScheme oneDarkProDarker = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF21252B),
    onSurface: const Color(0xFFABB2BF),
    primary: const Color(0xFF61AFEF),
    secondary: const Color(0xFF98C379),
    tertiary: const Color(0xFFE5C07B),
    error: const Color(0xFFE06C75),
  );

  /// Monokai — inspired, contrast-tuned.
  static final ColorScheme monokai = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF272822),
    onSurface: const Color(0xFFF8F8F2),
    primary: const Color(0xFFF92672),
    secondary: const Color(0xFFA6E22E),
    tertiary: const Color(0xFFFD971F),
    error: const Color(0xFFFF6188),
  );

  /// Noctis — inspired, contrast-tuned.
  static final ColorScheme noctis = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF1B2932),
    onSurface: const Color(0xFFD6DEEB),
    primary: const Color(0xFF49E9A6),
    secondary: const Color(0xFF5DE4C7),
    tertiary: const Color(0xFFE4B781),
    error: const Color(0xFFE34E1C),
  );

  // ---- Community favorites — dark -----------------------------------------

  /// Dracula — inspired, contrast-tuned (purple / pink).
  static final ColorScheme dracula = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF282A36),
    onSurface: const Color(0xFFF8F8F2),
    primary: const Color(0xFFBD93F9),
    secondary: const Color(0xFF50FA7B),
    tertiary: const Color(0xFFFFB86C),
    error: const Color(0xFFFF5555),
  );

  /// Nord — inspired, contrast-tuned (arctic blue).
  static final ColorScheme nord = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF2E3440),
    onSurface: const Color(0xFFD8DEE9),
    primary: const Color(0xFF88C0D0),
    secondary: const Color(0xFFA3BE8C),
    tertiary: const Color(0xFFEBCB8B),
    error: const Color(0xFFBF616A),
  );

  /// Tokyo Night — inspired, contrast-tuned (indigo).
  static final ColorScheme tokyoNight = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF1A1B26),
    onSurface: const Color(0xFFA9B1D6),
    primary: const Color(0xFF7AA2F7),
    secondary: const Color(0xFF9ECE6A),
    tertiary: const Color(0xFFE0AF68),
    error: const Color(0xFFF7768E),
  );

  /// Gruvbox Dark — inspired, contrast-tuned (warm retro amber).
  static final ColorScheme gruvboxDark = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF282828),
    onSurface: const Color(0xFFEBDBB2),
    primary: const Color(0xFFFE8019),
    secondary: const Color(0xFFB8BB26),
    tertiary: const Color(0xFFFABD2F),
    error: const Color(0xFFFB4934),
  );

  /// Catppuccin Mocha — inspired, contrast-tuned (pastel mauve).
  static final ColorScheme catppuccinMocha = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF1E1E2E),
    onSurface: const Color(0xFFCDD6F4),
    primary: const Color(0xFFCBA6F7),
    secondary: const Color(0xFFA6E3A1),
    tertiary: const Color(0xFFF9E2AF),
    error: const Color(0xFFF38BA8),
  );

  /// GitHub Dark — inspired, contrast-tuned (neutral blue).
  static final ColorScheme githubDark = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF0D1117),
    onSurface: const Color(0xFFC9D1D9),
    primary: const Color(0xFF58A6FF),
    secondary: const Color(0xFF3FB950),
    tertiary: const Color(0xFFD29922),
    error: const Color(0xFFF85149),
  );

  /// Night Owl — inspired, contrast-tuned (deep teal-blue).
  static final ColorScheme nightOwl = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF011627),
    onSurface: const Color(0xFFD6DEEB),
    primary: const Color(0xFF82AAFF),
    secondary: const Color(0xFF22DA6E),
    tertiary: const Color(0xFFECC48D),
    error: const Color(0xFFEF5350),
  );

  /// Everforest Dark — inspired, contrast-tuned (soft green).
  static final ColorScheme everforestDark = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF2D353B),
    onSurface: const Color(0xFFD3C6AA),
    primary: const Color(0xFFA7C080),
    secondary: const Color(0xFF7FBBB3),
    tertiary: const Color(0xFFDBBC7F),
    error: const Color(0xFFE67E80),
  );

  /// Rosé Pine — inspired, contrast-tuned (muted rose / iris).
  static final ColorScheme rosePine = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF191724),
    onSurface: const Color(0xFFE0DEF4),
    primary: const Color(0xFFC4A7E7),
    secondary: const Color(0xFF9CCFD8),
    tertiary: const Color(0xFFEBBCBA),
    error: const Color(0xFFEB6F92),
  );

  /// Ayu Mirage — inspired, contrast-tuned (amber / orange).
  static final ColorScheme ayuMirage = _build(
    brightness: Brightness.dark,
    surface: const Color(0xFF1F2430),
    onSurface: const Color(0xFFCBCCC6),
    primary: const Color(0xFFFFCC66),
    secondary: const Color(0xFFBAE67E),
    tertiary: const Color(0xFF73D0FF),
    error: const Color(0xFFFF6666),
  );

  // ---- Community favorites — light ----------------------------------------

  /// GitHub Light — inspired, contrast-tuned (neutral).
  static final ColorScheme githubLight = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF24292F),
    primary: const Color(0xFF0969DA),
    secondary: const Color(0xFF1A7F37),
    tertiary: const Color(0xFF9A6700),
    error: const Color(0xFFCF222E),
  );

  /// Catppuccin Latte — inspired, contrast-tuned (pastel light).
  static final ColorScheme catppuccinLatte = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFEFF1F5),
    onSurface: const Color(0xFF4C4F69),
    primary: const Color(0xFF8839EF),
    secondary: const Color(0xFF40A02B),
    tertiary: const Color(0xFFDF8E1D),
    error: const Color(0xFFD20F39),
  );

  /// Gruvbox Light — inspired, contrast-tuned (warm cream).
  static final ColorScheme gruvboxLight = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFFBF1C7),
    onSurface: const Color(0xFF3C3836),
    primary: const Color(0xFFAF3A03),
    secondary: const Color(0xFF79740E),
    tertiary: const Color(0xFFB57614),
    error: const Color(0xFF9D0006),
  );

  /// Everforest Light — inspired, contrast-tuned (soft green).
  static final ColorScheme everforestLight = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFFDF6E3),
    onSurface: const Color(0xFF5C6A72),
    primary: const Color(0xFF8DA101),
    secondary: const Color(0xFF35A77C),
    tertiary: const Color(0xFFDFA000),
    error: const Color(0xFFF85552),
  );

  /// Rosé Pine Dawn — inspired, contrast-tuned (light rose / iris).
  static final ColorScheme rosePineDawn = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFFAF4ED),
    onSurface: const Color(0xFF575279),
    primary: const Color(0xFF907AA9),
    secondary: const Color(0xFF56949F),
    tertiary: const Color(0xFFD7827E),
    error: const Color(0xFFB4637A),
  );

  /// Ayu Light — inspired, contrast-tuned (bright amber).
  static final ColorScheme ayuLight = _build(
    brightness: Brightness.light,
    surface: const Color(0xFFFAFAFA),
    onSurface: const Color(0xFF5C6166),
    primary: const Color(0xFFFA8D3E),
    secondary: const Color(0xFF86B300),
    tertiary: const Color(0xFF399EE6),
    error: const Color(0xFFF07171),
  );

  // ---- Derivation ---------------------------------------------------------

  /// Builds a full 30-role [ColorScheme] from a palette's identity colors,
  /// tuning tones so every meaningful pair clears WCAG AA.
  static ColorScheme _build({
    required Brightness brightness,
    required Color surface,
    required Color onSurface,
    required Color primary,
    required Color secondary,
    required Color tertiary,
    required Color error,
  }) {
    final dark = brightness == Brightness.dark;

    final onSurf = _tuneFg(onSurface, surface, _text);
    // Variant foreground: a touch lower in emphasis but still AA text.
    final onSurfVar = _tuneFg(_mix(onSurf, surface, 0.30), surface, _text);
    // Borders only need 3:1 (non-text).
    final outline = _tuneFg(_mix(onSurf, surface, 0.55), surface, _nonText);
    final outlineVariant = _mix(onSurf, surface, 0.75);
    final surfaceHighest = _mix(surface, onSurf, dark ? 0.14 : 0.10);

    final p = _accent(_ensureAgainst(primary, surface, _nonText), _text);
    final s = _accent(secondary, _text);
    final t = _accent(tertiary, _text);
    final e = _accent(error, _text);

    final pc = _container(primary, brightness, _text);
    final sc = _container(secondary, brightness, _text);
    final tc = _container(tertiary, brightness, _text);
    final ec = _container(error, brightness, _text);

    return ColorScheme(
      brightness: brightness,
      primary: p.color,
      onPrimary: p.on,
      primaryContainer: pc.color,
      onPrimaryContainer: pc.on,
      secondary: s.color,
      onSecondary: s.on,
      secondaryContainer: sc.color,
      onSecondaryContainer: sc.on,
      tertiary: t.color,
      onTertiary: t.on,
      tertiaryContainer: tc.color,
      onTertiaryContainer: tc.on,
      error: e.color,
      onError: e.on,
      errorContainer: ec.color,
      onErrorContainer: ec.on,
      surface: surface,
      onSurface: onSurf,
      onSurfaceVariant: onSurfVar,
      surfaceContainerHighest: surfaceHighest,
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: onSurf,
      onInverseSurface: surface,
      inversePrimary: p.color,
    );
  }

  // ---- WCAG helpers -------------------------------------------------------

  /// Relative luminance per WCAG 2.x.
  static double _luminance(Color c) => c.computeLuminance();

  /// WCAG contrast ratio between two opaque colors (1..21).
  static double _contrast(Color a, Color b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  /// Picks black or white — whichever contrasts more against [bg].
  static Color _pole(Color bg) {
    const black = Color(0xFF0B0B0B);
    const white = Color(0xFFFAFAFA);
    return _contrast(white, bg) >= _contrast(black, bg) ? white : black;
  }

  /// Nudges [fg] toward the contrast-raising pole (relative to [bg]) until it
  /// clears [target]. Contrast is monotonic in the blend fraction, so we binary
  /// search the minimum shift that satisfies the target.
  static Color _tuneFg(Color fg, Color bg, double target) {
    if (_contrast(fg, bg) >= target) return fg;
    final pole = _pole(bg);
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (_contrast(_mix(fg, pole, mid), bg) >= target) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return _mix(fg, pole, hi);
  }

  /// An accent + its on-color, both AA. Keeps the accent's hue: only the
  /// accent's *lightness* shifts (toward the pole opposite its on-color) when
  /// the natural on-color can't reach the target on the raw accent.
  static _Pair _accent(Color base, double target) {
    final on = _pole(base);
    if (_contrast(on, base) >= target) return _Pair(base, on);

    final hsl = HSLColor.fromColor(base);
    // on is light -> darken base; on is dark -> lighten base.
    final darken = on.computeLuminance() > 0.5;
    var lo = 0.0;
    var hi = 1.0;
    double lightnessAt(double f) {
      final l = darken
          ? hsl.lightness * (1 - f)
          : hsl.lightness + (1 - hsl.lightness) * f;
      return l.clamp(0.0, 1.0);
    }

    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      final c = hsl.withLightness(lightnessAt(mid)).toColor();
      if (_contrast(on, c) >= target) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return _Pair(hsl.withLightness(lightnessAt(hi)).toColor(), on);
  }

  /// Shifts [base]'s lightness (hue preserved) toward the pole opposite [bg]
  /// until it clears [target] against [bg]. Used to keep the primary — which
  /// doubles as the focus ring — visible as a non-text UI element on the
  /// surface, even for accents that are otherwise fine as button fills.
  static Color _ensureAgainst(Color base, Color bg, double target) {
    if (_contrast(base, bg) >= target) return base;
    final hsl = HSLColor.fromColor(base);
    final darken = bg.computeLuminance() >= 0.5; // light bg -> darken accent
    double lightnessAt(double f) {
      final l = darken
          ? hsl.lightness * (1 - f)
          : hsl.lightness + (1 - hsl.lightness) * f;
      return l.clamp(0.0, 1.0);
    }

    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (_contrast(hsl.withLightness(lightnessAt(mid)).toColor(), bg) >=
          target) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hsl.withLightness(lightnessAt(hi)).toColor();
  }

  /// A container tone for [base] plus an AA on-color, keeping [base]'s hue.
  static _Pair _container(Color base, Brightness brightness, double target) {
    final dark = brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(base);
    final container = hsl
        .withLightness(dark ? 0.26 : 0.90)
        .withSaturation((hsl.saturation * (dark ? 0.55 : 0.60)).clamp(0.0, 1.0))
        .toColor();
    final onStart = hsl.withLightness(dark ? 0.92 : 0.20).toColor();
    return _Pair(container, _tuneFg(onStart, container, target));
  }
}

/// A color paired with an AA-compliant on-color.
class _Pair {
  const _Pair(this.color, this.on);
  final Color color;
  final Color on;
}
