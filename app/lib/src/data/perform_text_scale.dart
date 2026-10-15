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

/// Lower bound for the *auto-size* fit search only (ROADMAP G.1). Unlike manual
/// mode — which must never drop below the large-print [kPerformMinScale] — the
/// whole point of auto-size is "the full dance or slot fits the screen without
/// scrolling", so on a window smaller than the card's natural large-print
/// height the fit must be allowed to shrink *below* 1.0 to make the card fit.
/// Flooring the auto-fit search at [kPerformMinScale] (issue #527) left the card
/// unable to shrink enough for a smaller-than-fullscreen window, so trailing
/// sections (e.g. B1, calling notes) fell off the viewport. This is a generous
/// floor: below it text is unreadably small, at which point the scroll fallback
/// keeps content reachable rather than clipping it.
const double kPerformMinAutoScale = 0.2;

/// Upper bound for the *auto-size* fit search only (ROADMAP G.1). Manual mode
/// keeps its "no practical upper bound" behaviour; auto-size is naturally
/// bounded by what fits the viewport, but the binary search needs a finite
/// ceiling. This is generous enough that short slots ("break", a title-only
/// card) grow to fill the screen.
const double kPerformMaxAutoScale = 12.0;

/// Step for the A-/A+ size control.
const double kPerformScaleStep = 0.2;
