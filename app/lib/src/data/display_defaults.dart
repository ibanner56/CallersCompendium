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
