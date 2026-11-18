/// Text-scale bounds for Performance mode (`docs/design/ux.md` §5).
///
/// Live in `data/` so the backup settings schema can validate the stored scale
/// without importing a screen; the Perform screens import them from here.
library;

/// Default in-view scale so the card reads from across a room on first open.
const double kPerformDefaultScale = 1.8;

/// A sensible lower bound (below the app's normal text size the "large-print"
/// intent is lost). There is deliberately no practical upper bound.
const double kPerformMinScale = 1.0;

/// Lower bound for the *auto-size* fit search only (ROADMAP G.1; UI/UX audit
/// A-03, decision DS-12 option A): the card's own body text may shrink to fit
/// the viewport, but never below the user's OS-scaled body text size.
///
/// The card's text is composed on top of the system text scale, so a card
/// whose body is drawn at [cardFontSize] reads at the OS body size
/// ([bodyFontSize] under the same system scale) when the in-view scale is
/// `bodyFontSize / cardFontSize` — whatever the system scale is. Below that the
/// card scrolls instead of shrinking further. The earlier fixed floor of 0.2
/// (issue #527) let a long dance shrink to a fifth of the user's size, so at
/// accessibility text sizes — where the footer also grows — the figures came
/// out *smaller* than at the default text size. Clamped to `(0, 1]`: the floor
/// never forces a card above its natural size.
double performMinAutoScale({
  required double bodyFontSize,
  required double cardFontSize,
}) {
  if (cardFontSize <= 0 || bodyFontSize <= 0) return 1.0;
  return (bodyFontSize / cardFontSize).clamp(0.01, 1.0);
}

/// Upper bound for the *auto-size* fit search only (ROADMAP G.1). Manual mode
/// keeps its "no practical upper bound" behaviour; auto-size is naturally
/// bounded by what fits the viewport, but the binary search needs a finite
/// ceiling. This is generous enough that short slots ("break", a title-only
/// card) grow to fill the screen.
const double kPerformMaxAutoScale = 12.0;

/// Step for the A-/A+ size control.
const double kPerformScaleStep = 0.2;

/// Ceiling on the system text scale applied to Perform's chrome — the program
/// footer (position and timers) and the program title (UI/UX audit A-03,
/// P-12). The card itself always follows the full system scale. Uncapped, an
/// accessibility text size grew the footer to triple size while auto-size
/// shrank the figures to fit the space left. 2.0 still honours a 200% text
/// enlargement (WCAG 1.4.4) for the chrome, and stops it there.
const double kPerformChromeMaxTextScale = 2.0;
