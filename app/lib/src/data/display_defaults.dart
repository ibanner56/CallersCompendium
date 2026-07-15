/// App-only default-value settings for the Defaults settings pane
/// (ROADMAP "Defaults (settings pane)"). These persist the user's preferred
/// STARTING state via `SettingsRepository`; they only seed the initial
/// display/starting state and never mutate stored data.
///
/// Key constants and small serialization live here (rather than in
/// `settings_screen.dart` alongside the theme/dialect keys) so the consumers
/// that seed from them — the Collection list and the dance-detail screen — can
/// import them without pulling in the settings screen (avoiding an import
/// cycle). Later Defaults-pane PRs (G.3, DD.1–DD.3) add their key constants
/// here too.
library;

/// Key used to persist the default Collection sort order (ROADMAP G.6a).
/// Stored as the [CollectionSort] enum's stable `.name`. Absent/invalid ⇒ the
/// list falls back to its historical default (`title`).
const String kDefaultCollectionSortKey = 'default_collection_sort';

/// Key used to persist the default caller name for new programs (ROADMAP G.3).
/// Free text; prefills a NEW program's caller in the program editor. Absent or
/// empty ⇒ no prefill (the field opens blank).
const String kDefaultProgramCallerKey = 'default_program_caller';

/// Key used to persist the default band for new programs (ROADMAP G.3).
/// Free text; prefills a NEW program's band in the program editor. Absent or
/// empty ⇒ no prefill (the field opens blank).
const String kDefaultProgramBandKey = 'default_program_band';

/// Key used to persist the default dance-detail rendering (ROADMAP G.6b).
/// Stored as the [DanceDetailRendering] enum's stable `.name`. Absent/invalid ⇒
/// [DanceDetailRendering.activeDialect] (the historical default).
const String kDefaultDanceDetailRenderingKey = 'default_dance_detail_rendering';

/// The user's preferred STARTING rendering for the dance-detail figure table
/// (ROADMAP G.6b).
///
/// - [activeDialect]: render figures in the user's active dialect (today's
///   default; `_canonicalView == false`).
/// - [canonical]: render canonical role/move tokens from the start — for
///   callers who always want the canonical view.
///
/// An in-view canonical⇄dialect toggle (when shown) still overrides this for
/// that session; this only seeds the initial state.
enum DanceDetailRendering { activeDialect, canonical }

/// Resolves a persisted settings value into a [DanceDetailRendering].
///
/// Returns [DanceDetailRendering.activeDialect] for `null`, a non-string, or an
/// unrecognized name — preserving today's behavior for users who never touch
/// the setting.
DanceDetailRendering danceDetailRenderingFromStored(Object? stored) {
  if (stored is String) {
    for (final value in DanceDetailRendering.values) {
      if (value.name == stored) return value;
    }
  }
  return DanceDetailRendering.activeDialect;
}
