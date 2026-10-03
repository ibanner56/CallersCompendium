import 'package:compendium_core/compendium_core.dart'
    show MatrixColumnConfig, shareableTextNormalisationScopeKey;

import '../update/update_config.dart'
    show kUpdateAutoCheckKey, kUpdateBetaChannelKey, kUpdateDismissedVersionKey;
import 'aggressive_beats_update_scope.dart' show kAggressiveBeatsUpdateKey;
import 'backup_reminder.dart' show kBackupReminderCadenceKey;
import 'confirm_before_delete_scope.dart' show kConfirmBeforeDeleteKey;
import 'decimal_turns_scope.dart' show kDecimalTurnsKey;
import 'display_defaults.dart'
    show
        kCanonicalDiscouragedTermsKey,
        kCanonicalFigureTextKey,
        kDefaultCollectionSortKey,
        kDefaultDanceDetailRenderingKey,
        kDefaultDanceFiguresTemplateKey,
        kDefaultModifierFiguresKey,
        kDefaultMeanwhileSideFiguresKey,
        kDefaultDanceFormKey,
        kDefaultDanceFormationShapeKey,
        kDefaultDancePhraseStructureKey,
        kDefaultDanceProgressionKey,
        kDefaultMoveParamOverridesKey,
        kDefaultProgramBandKey,
        kDefaultProgramCallerKey,
        kDefaultImportTagNamesKey,
        kDefaultProgramSortKey,
        kDefaultStartingProgramKey,
        kLastUsedCollectionSortDirectionKey,
        kLastUsedCollectionSortKey,
        kLastUsedProgramSortDirectionKey,
        kLastUsedProgramSortKey,
        tryDecodeDefaultImportTagNames,
        tryDecodeStartingProgramTemplate;
import 'formation_colors_controller.dart' show kFormationColorOverridesKey;
import 'locale_scope.dart' show kLocaleKey;
import 'reduce_motion_scope.dart' show kReduceMotionKey;
import 'perform_text_scale.dart' show kPerformMinScale;
import 'regional_formats.dart'
    show kDateFormatCustomPatternKey, kDateFormatKey, kFirstDayOfWeekKey;
import 'seed_service.dart' show kInitialSeedCompletedKey;
import 'settings_keys.dart';
import 'set_list_color_coding_scope.dart' show kSetListColorCodingKey;
import 'shorthand_mappings_controller.dart' show kShorthandMappingsKey;
import 'soft_delete_retention.dart' show kSoftDeleteRetentionKey;
import 'verbose_figure_rendering_scope.dart' show kVerboseFigureRenderingKey;
import 'venue_call_count_scope.dart' show kVenueCallCountMax;
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
    kShowIndividualPerformTimerKey,
    kShowProgramSlotCallerNotesKey,
    kAutoCommitProgramChangesKey,
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
    kMatrixExactBeatCollisionKey,
    kCanonicalFigureTextKey,
    kCanonicalDiscouragedTermsKey,
    // Three one-shot latches, written as `true` and read for presence. A
    // non-bool would still latch, but a restore is a trust boundary and
    // nothing legitimate ever writes anything else here.
    kInitialSeedCompletedKey,
    kCustomFieldSharingDisclosureKey,
    kEcdConvertPromptDismissedKey,
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
    kDefaultProgramSortKey,
    kLastUsedCollectionSortKey,
    kLastUsedCollectionSortDirectionKey,
    kLastUsedProgramSortKey,
    kLastUsedProgramSortDirectionKey,
    kDefaultDanceDetailRenderingKey,
    kDefaultDanceFormKey,
    kDefaultDanceFormationShapeKey,
    kDefaultDancePhraseStructureKey,
    kDefaultDanceProgressionKey,
    kDefaultDanceFiguresTemplateKey,
    kDefaultMeanwhileSideFiguresKey,
    kDefaultModifierFiguresKey,
    kDefaultMoveParamOverridesKey,
    // off / weekly / monthly; `backupReminderCadenceFromStored` rejects any
    // other token and falls back to off.
    kBackupReminderCadenceKey,
  ])
    key: _isString,

  // The starting-program template is a JSON string with an invariant-checked
  // semantic codec, not merely an arbitrary string.
  kDefaultStartingProgramKey: _isValidStartingProgramTemplate,
  kDefaultImportTagNamesKey: _isValidDefaultImportTagNames,

  // Numbers. The in-Perform manual text scale is used for layout sizing, so a
  // non-finite (NaN/Infinity) value is rejected outright rather than flowing
  // into a size calculation. It mirrors the live reader's contract exactly
  // (`PerformA11yPrefsStore._readTextScale`): finite and at or above the enforced
  // minimum, with NO upper cap — the in-view A+ control is intentionally
  // unbounded, so a large-but-finite manual size is a legitimate low-vision
  // preference that must survive a restore.
  kPerformTextScaleKey: _isValidPerformScale,
  // Retention window is a non-negative day count (0 = "never auto-purge"). A
  // negative or non-int value is rejected so it can't silently alter purging.
  kSoftDeleteRetentionKey: _isNonNegativeInt,
  kVenueCallCountKey: _isVenueCallCount,

  // Structured container blobs. Their controllers decode the CONTENTS
  // defensively (skipping bad entries), so here we only enforce the outer
  // container kind that each decoder expects.
  kWalkthroughSnippetsKey: _isMap,
  kFormationColorOverridesKey: _isMap,
  // Shorthand mappings persist as a JSON list; the decoder also tolerates a raw
  // JSON string, so accept either and let it validate entries.
  kShorthandMappingsKey: _isListOrString,
  // Collection tile fields (#767), hidden filter sections (#1419), and the
  // shared-program dance-field picker (#1434) persist as JSON lists of name
  // strings; every decoder (`decodeStored`) treats a non-List as "unset" and
  // drops non-String entries, so only the container is enforced.
  kCollectionTileVisibleFieldsKey: _isList,
  kCollectionHiddenFacetsKey: _isList,
  kProgramDanceShareFieldsKey: _isList,
  // The shareable-text normalisation scope marker (`_backupLocalState`, kept
  // in backups by #1134) is a JSON object recording the algorithm version and
  // the exact column / key scope the pass covered. `ensureMigrated` compares
  // its stored text with the live scope and re-runs the pass on any mismatch,
  // so a wrong-but-Map value costs one idempotent pass; a non-Map is dropped.
  shareableTextNormalisationScopeKey: _isMap,
  // Program-matrix column config (issue #935): a JSON object the codec must be
  // able to parse. `MatrixColumnConfig.decode` throws on a malformed blob
  // (wrong types, mis-namespaced/duplicate custom ids) and the live loader
  // falls back to the empty default via `tryDecode` — but a restore is a trust
  // boundary, so reject a wrong-shaped value here rather than persisting it and
  // relying on the reader. Only a Map that round-trips through the codec passes.
  kProgramMatrixColumnsKey: _isValidMatrixColumnConfig,
};

bool _isBool(Object? v) => v is bool;
bool _isString(Object? v) => v is String;
bool _isValidDefaultImportTagNames(Object? v) =>
    tryDecodeDefaultImportTagNames(v) != null;

bool _isValidStartingProgramTemplate(Object? v) =>
    tryDecodeStartingProgramTemplate(v) != null;
bool _isNonNegativeInt(Object? v) => v is int && v >= 0;
bool _isVenueCallCount(Object? v) =>
    v is int && v >= 0 && v <= kVenueCallCountMax;
bool _isValidPerformScale(Object? v) =>
    v is num && v.isFinite && v >= kPerformMinScale;
bool _isMap(Object? v) => v is Map;
bool _isList(Object? v) => v is List;
bool _isListOrString(Object? v) => v is List || v is String;

/// Accepts a program-matrix column config only when it is a JSON object the
/// codec can fully parse (`MatrixColumnConfig.tryDecode` returns non-null),
/// dropping any malformed or wrong-typed blob so it never reaches the throwing
/// decode path at restore.
bool _isValidMatrixColumnConfig(Object? v) =>
    v is Map && MatrixColumnConfig.tryDecode(v) != null;

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
