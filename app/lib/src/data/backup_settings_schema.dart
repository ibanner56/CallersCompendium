import '../screens/perform_card.dart' show kPerformMinScale;
import '../screens/settings/settings_keys.dart';
import '../update/update_config.dart'
    show kUpdateAutoCheckKey, kUpdateBetaChannelKey, kUpdateDismissedVersionKey;
import 'aggressive_beats_update_scope.dart' show kAggressiveBeatsUpdateKey;
import 'confirm_before_delete_scope.dart' show kConfirmBeforeDeleteKey;
import 'decimal_turns_scope.dart' show kDecimalTurnsKey;
import 'display_defaults.dart'
    show
        kDefaultCollectionSortKey,
        kDefaultDanceDetailRenderingKey,
        kDefaultDanceFiguresTemplateKey,
        kDefaultDanceFormKey,
        kDefaultDanceFormationShapeKey,
        kDefaultDancePhraseStructureKey,
        kDefaultDanceProgressionKey,
        kDefaultMoveParamOverridesKey,
        kDefaultProgramBandKey,
        kDefaultProgramCallerKey;
import 'formation_colors_controller.dart' show kFormationColorOverridesKey;
import 'locale_scope.dart' show kLocaleKey;
import 'reduce_motion_scope.dart' show kReduceMotionKey;
import 'regional_formats.dart'
    show kDateFormatCustomPatternKey, kDateFormatKey, kFirstDayOfWeekKey;
import 'set_list_color_coding_scope.dart' show kSetListColorCodingKey;
import 'shorthand_mappings_controller.dart' show kShorthandMappingsKey;
import 'soft_delete_retention.dart' show kSoftDeleteRetentionKey;
import 'verbose_figure_rendering_scope.dart' show kVerboseFigureRenderingKey;
import 'walkthrough_snippet_library_controller.dart'
    show kWalkthroughSnippetsKey;

/// Per-key type/range schema for the preference values carried in a backup's
/// `app.settings` map (issue #609).
///
/// SECURITY / RESILIENCE (OWASP input validation at the trust boundary): a
/// backup's checksum proves **integrity, not schema validity** — a corrupt,
/// truncated, hand-edited, or maliciously crafted-but-checksum-valid backup can
/// carry a wrong-typed or out-of-range value under any settings key. Restoring
/// such a value verbatim previously let it reach an unchecked cast at startup
/// and brick the app (it re-threw on every subsequent launch). This schema is
/// the allowlist/validation layer applied while re-applying restored settings:
/// only a value that matches its key's declared type/range is persisted; any
/// invalid value is dropped so the key falls back to its safe default.
///
/// A validator returns `true` when [value] is acceptable for its key. The map
/// is keyed by the settings-table key; a key that is **absent** from the map
/// has no declared schema (an unknown / forward-compatible key from a newer app
/// version) and is passed through unchecked by [validateBackupSettingValue] —
/// every live reader of these keys is already defensive (`is`-guarded / tolerant
/// `*FromStored` resolver), so an unknown key cannot brick startup, and dropping
/// it would silently lose a legitimate preference on a cross-version restore.
final Map<String, bool Function(Object?)> _backupSettingValidators = {
  // Booleans — every one of these is read through an `is bool` guard, so a
  // non-bool must be dropped (never coerced) to keep the safe default.
  for (final key in const <String>[
    kRequirePerformedForHistoryKey,
    kTrackHistoryForAllCallersKey,
    kAutoSizePerformKey,
    kPerformStageModeKey,
    kPerformCanonicalViewKey,
    kSortIgnoreArticlesKey,
    kColourDanceThemeKey,
    kVenueEntityModeKey,
    kFreeTextEntryKey,
    kAggressiveBeatsUpdateKey,
    kReduceMotionKey,
    kVerboseFigureRenderingKey,
    kDecimalTurnsKey,
    kConfirmBeforeDeleteKey,
    kSetListColorCodingKey,
    kUpdateAutoCheckKey,
    kUpdateBetaChannelKey,
  ])
    key: _isBool,

  // Strings — token/opaque values resolved defensively on read (theme name,
  // regional-format tokens, locale tag, dismissed version, default-entry
  // tokens, and the JSON-string-encoded figures template / move-param
  // overrides). Only the container KIND is enforced here; the resolvers reject
  // unknown tokens / malformed JSON and fall back to their own defaults.
  for (final key in const <String>[
    kAppThemeKey,
    kDateFormatKey,
    kDateFormatCustomPatternKey,
    kFirstDayOfWeekKey,
    kLocaleKey,
    kUpdateDismissedVersionKey,
    kDefaultProgramBandKey,
    kDefaultProgramCallerKey,
    kDefaultCollectionSortKey,
    kDefaultDanceDetailRenderingKey,
    kDefaultDanceFormKey,
    kDefaultDanceFormationShapeKey,
    kDefaultDancePhraseStructureKey,
    kDefaultDanceProgressionKey,
    kDefaultDanceFiguresTemplateKey,
    kDefaultMoveParamOverridesKey,
  ])
    key: _isString,

  // Numbers. The in-Perform manual text scale is used for layout sizing, so a
  // non-finite (NaN/Infinity) value is rejected outright rather than flowing
  // into a size calculation. It mirrors the live reader's contract exactly
  // (`PerformA11yPrefs._readTextScale`): finite and at or above the enforced
  // minimum, with NO upper cap — the in-view A+ control is intentionally
  // unbounded, so a large-but-finite manual size is a legitimate low-vision
  // preference that must survive a restore.
  kPerformTextScaleKey: _isValidPerformScale,
  // Retention window is a non-negative day count (0 = "never auto-purge"). A
  // negative or non-int value is rejected so it can't silently alter purging.
  kSoftDeleteRetentionKey: _isNonNegativeInt,

  // Structured container blobs. Their controllers decode the CONTENTS
  // defensively (skipping bad entries), so here we only enforce the outer
  // container kind that each decoder expects.
  kWalkthroughSnippetsKey: _isMap,
  kFormationColorOverridesKey: _isMap,
  // Shorthand mappings persist as a JSON list; the decoder also tolerates a raw
  // JSON string, so accept either and let it validate entries.
  kShorthandMappingsKey: _isListOrString,
};

bool _isBool(Object? v) => v is bool;
bool _isString(Object? v) => v is String;
bool _isNonNegativeInt(Object? v) => v is int && v >= 0;
bool _isValidPerformScale(Object? v) =>
    v is num && v.isFinite && v >= kPerformMinScale;
bool _isMap(Object? v) => v is Map;
bool _isListOrString(Object? v) => v is List || v is String;

/// Validates a restored settings [value] for [key] against the backup schema.
///
/// Returns `true`/`false` when [key] has a declared schema (valid vs. reject),
/// or `null` when [key] is unknown to the schema — the caller passes such
/// forward-compatible keys through unchanged (see [_backupSettingValidators]).
/// Never throws: the whole point is that no restored value can abort the apply.
bool? validateBackupSettingValue(String key, Object? value) {
  final validator = _backupSettingValidators[key];
  if (validator == null) return null;
  return validator(value);
}
