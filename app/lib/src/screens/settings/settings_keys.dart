/// Persistence keys owned by the Settings screen.
///
/// Kept in their own library (and re-exported from `settings_screen.dart`) so
/// the section widgets and other consumers (`main.dart`, the Perform screens)
/// can import them without a dependency cycle. String values are unchanged.
library;

/// Key used to persist and load the app theme selection.
const String kAppThemeKey = 'theme_mode';

/// Key used to persist the "Require mark-performed for calling history" General
/// setting (ROADMAP G.2). Stored as a bool; absent/unset means off (`false`),
/// so a dance's calling history shows every program that contains it.
const String kRequirePerformedForHistoryKey = 'require_performed_for_history';

/// Key used to persist and load the "auto-size Perform cards" preference
/// (ROADMAP G.1). Defaults to `true` (on) when unset.
const String kAutoSizePerformKey = 'auto_size_perform_cards';

/// Key used to persist the in-Perform manual text scale (issue #449). Stored as
/// a number; absent/invalid means the built-in default (`kPerformDefaultScale`),
/// so a low-vision caller's manual size survives relaunch instead of resetting.
const String kPerformTextScaleKey = 'perform_text_scale';

/// Key used to persist the in-Perform dark-stage high-contrast theme toggle
/// (issue #449). Stored as a bool; absent/unset means on (`true`), matching the
/// stage-mode-on-by-default behaviour (`docs/design/ux.md` §5).
const String kPerformStageModeKey = 'perform_stage_mode';

/// Key used to persist the in-Perform "show canonical role/move tokens" toggle
/// (issue #449). Stored as a bool; absent/unset means off (`false`), so figures
/// render in the active dialect until the caller opts into canonical tokens.
const String kPerformCanonicalViewKey = 'perform_canonical_view';

/// Key used to persist the "Ignore leading articles when sorting" General
/// setting. Stored as a bool; absent/unset means on (`true`), so the dance
/// list alphabetizes titles with a leading article ("the"/"a"/"an") ignored.
const String kSortIgnoreArticlesKey = 'sort_ignore_articles';

/// Key used to persist the "colour-named dances tint the theme" easter egg
/// (issue #307). Stored as a bool; absent/unset means off (`false`), so the
/// feature is strictly opt-in.
const String kColourDanceThemeKey = 'colour_dance_theme';
