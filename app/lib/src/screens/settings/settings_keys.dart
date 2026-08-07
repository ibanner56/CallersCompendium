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

/// Key used to persist the "Track calling history for all callers" General
/// setting (issue #583). Stored as a bool; absent/unset means off (`false`).
///
/// When OFF (the default) AND a default caller is configured
/// ([kDefaultProgramCallerKey] non-empty), a dance's calling history and counts
/// only include programs whose HOST caller matches that default caller (trim +
/// case-insensitive) **or** whose caller is NULL or blank (unattributed programs
/// are treated as the user's own; #850 supersedes the original #583 exclusion).
/// When ON — or when no default caller is set — history tracks every program
/// that contains the dance, as it always has. This gate is AND-combined with
/// [kRequirePerformedForHistoryKey], never a replacement.
const String kTrackHistoryForAllCallersKey = 'track_history_for_all_callers';

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

/// Key used to persist the "venue entity mode" General setting. Stored as a
/// bool; absent/unset means off (`false`), so programs use the simple free-text
/// venue field by default. When on, the program editor swaps that field for a
/// picker over reusable [Venue] records (address/contacts/schedule). The toggle
/// is entry/display-mode only: `Program.venue` and `Program.venueId` persist
/// independently so flipping it is lossless in both directions.
const String kVenueEntityModeKey = 'venue_entity_mode';

/// Key used to persist the "Free-text entry" dance-authoring toggle (issue
/// #419). Stored as a bool; absent/unset means off (`false`), so free-text
/// entry is strictly opt-in. When on, adding a NEW figure opens a single
/// free-text field (routed through the shared core parser) instead of a blank
/// structured draft; editing an existing figure always stays structured.
const String kFreeTextEntryKey = 'free_text_entry';

/// Idempotency latch for the one-time disclosure shown when a user creates
/// their first custom field, informing them that custom field values travel
/// with the collection in exports and shares (issue #780). Presence of the key
/// (see [SettingsRepository.contains]) is the latch — set once, on the first
/// successful field save, and never consulted for its value.
const String kCustomFieldSharingDisclosureKey =
    'custom_fields.sharing.disclosed';

/// Key used to persist the set of [CollectionTileField]s the user wants shown
/// on each collection dance row (issue #767). Stored as a JSON list of field
/// name strings; absent/unset means all fields are visible, so existing users
/// see no change until they adjust the preference.
const String kCollectionTileVisibleFieldsKey = 'collection_tile_visible_fields';
