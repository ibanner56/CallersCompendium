/// The settings key core writes to record the exact shareable-text columns
/// covered by the normalization backfill.
///
/// Nothing imports this constant, and it is not what core reads: core uses its
/// own `shareableTextNormalisationScopeKey`
/// (`packages/compendium_core/lib/src/storage/database.dart`). It is kept
/// because `test/data/settings_classification_test.dart` only recognises
/// declarations named `k…Key`, so this is the one declaration that walk sees
/// for the classified key `__shareable_text_normalisation_scope__`. Deleting it
/// makes that key's entry in `settingsClassifications` read as stale.
const String kShareableTextNormalisationScopeKey =
    '__shareable_text_normalisation_scope__';
