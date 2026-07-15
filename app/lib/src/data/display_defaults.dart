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

import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';

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

/// Key used to persist the default dance FORM for new dances (ROADMAP DD.1).
/// Stored as the [DanceForm] enum's stable `.name`. Absent/invalid ⇒
/// [DanceForm.contra] (the historical new-dance default).
const String kDefaultDanceFormKey = 'default_dance_form';

/// Key used to persist the default formation SHAPE for new dances (ROADMAP
/// DD.1). Stored as the [FormationShape] enum's stable `.name`. Absent/invalid
/// ⇒ [FormationShape.dupleImproper] (the historical new-dance default). DD.1
/// covers the shape only; the free-text formation detail stays per-dance.
const String kDefaultDanceFormationShapeKey = 'default_dance_formation_shape';

/// Key used to persist the default PROGRESSION for new dances (ROADMAP DD.1).
/// Stored as the [Progression] enum's stable `.name`. Absent/invalid ⇒
/// [Progression.single] (the historical new-dance default).
const String kDefaultDanceProgressionKey = 'default_dance_progression';

/// Key used to persist the default PHRASE STRUCTURE for new dances (ROADMAP
/// DD.1). Stored as the compact raw string (`PhraseStructure.raw`); `''` = the
/// standard 4×16 structure. Absent/non-string ⇒ `''` (standard).
const String kDefaultDancePhraseStructureKey = 'default_dance_phrase_structure';

/// Resolves a persisted settings value into a [DanceForm].
///
/// Returns [DanceForm.contra] for `null`, a non-string, or an unrecognized
/// name — preserving today's hardcoded new-dance default.
DanceForm danceFormFromStored(Object? stored) {
  if (stored is String) {
    for (final value in DanceForm.values) {
      if (value.name == stored) return value;
    }
  }
  return DanceForm.contra;
}

/// Resolves a persisted settings value into a [FormationShape].
///
/// Returns [FormationShape.dupleImproper] for `null`, a non-string, or an
/// unrecognized name — preserving today's hardcoded new-dance default.
FormationShape formationShapeFromStored(Object? stored) {
  if (stored is String) {
    for (final value in FormationShape.values) {
      if (value.name == stored) return value;
    }
  }
  return FormationShape.dupleImproper;
}

/// Resolves a persisted settings value into a [Progression].
///
/// Returns [Progression.single] for `null`, a non-string, or an unrecognized
/// name — preserving today's hardcoded new-dance default.
Progression progressionFromStored(Object? stored) {
  if (stored is String) {
    for (final value in Progression.values) {
      if (value.name == stored) return value;
    }
  }
  return Progression.single;
}

/// Resolves a persisted settings value into a phrase-structure RAW string.
///
/// Returns `''` (the standard 4×16 structure) for `null` or a non-string;
/// otherwise the stored string verbatim (empty ⇒ standard). Callers seed a
/// text field with this and let [PhraseStructure.parse] validate.
String dancePhraseStructureRawFromStored(Object? stored) {
  return stored is String ? stored : '';
}

/// Key used to persist the default starting-figures TEMPLATE for new dances
/// (ROADMAP DD.2). Stored as a `figures_json` string (the same shape a dance's
/// figures use — see [encodeFigures]/[decodeFigures]). Absent/non-string/empty/
/// invalid ⇒ [defaultNewDanceFigureTemplate] (ContraDB's `stand_still × 8`).
const String kDefaultDanceFiguresTemplateKey = 'default_dance_figures_template';

/// The default figure list a blank NEW dance begins with when the user hasn't
/// configured a template (ROADMAP DD.2). Matches ContraDB's new-dance template:
/// eight `stand_still` figures of 8 beats each.
///
/// Returns a fresh list on each call so callers can safely map it into mutable
/// drafts without sharing state.
List<Figure> defaultNewDanceFigureTemplate() => [
  Figure(move: 'stand_still', params: const {'beats': 8}),
  Figure(move: 'stand_still', params: const {'beats': 8}),
  Figure(move: 'stand_still', params: const {'beats': 8}),
  Figure(move: 'stand_still', params: const {'beats': 8}),
  Figure(move: 'stand_still', params: const {'beats': 8}),
  Figure(move: 'stand_still', params: const {'beats': 8}),
  Figure(move: 'stand_still', params: const {'beats': 8}),
  Figure(move: 'stand_still', params: const {'beats': 8}),
];

/// Resolves a persisted settings value into the starting-figures template.
///
/// A valid `figures_json` string is decoded verbatim — including `'[]'`, which
/// yields an intentional EMPTY template. `null`, a non-string, or an
/// unparseable/garbage string falls back to [defaultNewDanceFigureTemplate],
/// preserving ContraDB parity for users who never touch the setting.
List<Figure> danceFiguresTemplateFromStored(Object? stored) {
  if (stored is String) {
    try {
      return decodeFigures(stored);
    } catch (_) {
      // Empty / malformed JSON ⇒ fall back to the default template.
    }
  }
  return defaultNewDanceFigureTemplate();
}

/// Key used to persist the per-move figure-entry parameter overrides (ROADMAP
/// DD.3). Stored as `jsonEncode(Map<moveId, Map<paramKey, value>>)` holding
/// ONLY the params the user overrode (diffs vs the taxonomy's `MoveDef`
/// defaults), so taxonomy default changes still flow through for params the
/// user didn't touch. Absent/invalid ⇒ no overrides (pure taxonomy defaults).
const String kDefaultMoveParamOverridesKey = 'default_move_param_overrides';

/// Resolves a persisted settings value into the per-move param-override map
/// (ROADMAP DD.3).
///
/// Returns an empty (mutable) map for `null`, a non-string, or an
/// unparseable/garbage string — preserving today's pure-taxonomy-default
/// behavior for users who never touch the setting. Parses defensively: only
/// top-level entries whose value is itself a JSON object are kept, and any
/// empty inner map is dropped (an empty inner map means the move has no
/// overrides, i.e. it is absent). Returned inner maps are mutable so callers
/// can edit them in place.
Map<String, Map<String, Object?>> moveParamOverridesFromStored(Object? stored) {
  final result = <String, Map<String, Object?>>{};
  if (stored is! String || stored.isEmpty) return result;
  Object? decoded;
  try {
    decoded = jsonDecode(stored);
  } catch (_) {
    return result;
  }
  if (decoded is! Map) return result;
  decoded.forEach((moveId, value) {
    if (moveId is! String || value is! Map) return;
    final inner = <String, Object?>{};
    value.forEach((paramKey, paramValue) {
      if (paramKey is String) inner[paramKey] = paramValue;
    });
    if (inner.isNotEmpty) result[moveId] = inner;
  });
  return result;
}

/// Encodes the per-move param-override map to a `jsonEncode` string for storage
/// (ROADMAP DD.3). Empty inner maps are dropped before encoding so a move with
/// no diffs is never persisted (an empty inner map means the move is absent).
String encodeMoveParamOverrides(Map<String, Map<String, Object?>> overrides) {
  return jsonEncode({
    for (final entry in overrides.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  });
}
