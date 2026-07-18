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

/// Key used to persist the "Ignore leading articles when sorting" General
/// setting. Stored as a bool; absent/unset means on (`true`), so the dance
/// list alphabetizes titles with a leading article ("the"/"a"/"an") ignored.
const String kSortIgnoreArticlesKey = 'sort_ignore_articles';

/// Key used to persist the "colour-named dances tint the theme" easter egg
/// (issue #307). Stored as a bool; absent/unset means off (`false`), so the
/// feature is strictly opt-in.
const String kColourDanceThemeKey = 'colour_dance_theme';
