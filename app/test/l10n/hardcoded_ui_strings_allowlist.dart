/// Deferral manifest for [no_hardcoded_ui_strings_test.dart] (the L5 i18n
/// regression guard).
///
/// Every path here is a `lib/`-relative Dart file that still contains
/// user-facing string literals the guard would otherwise flag. The guard skips
/// these files wholesale; every other file under `lib/src/` must be free of
/// hardcoded user-facing prose.
///
/// This is a **ratchet**: the list only ever shrinks. As a later localization
/// layer (L6) extracts a file's strings, it removes that file from this list,
/// which re-arms the guard for that file forever. The guard also fails if a
/// listed file no longer exists or no longer has any flagged literal, so the
/// manifest can't silently rot.
///
/// Two buckets:
///   * **L6 (deferred UI):** feature-specific editor and secondary screens that
///     the next layer will localize. These come off the list as L6 lands.
///   * **Permanent (non-UI / by-design English):** export-body builders and
///     enum `label`/`description` catalogs (proper nouns, community theme
///     names, notation) that are intentionally not localized. See
///     `docs/dev/localization.md`.
library;

/// Files the guard skips. Paths are POSIX, relative to `app/lib/`.
const Set<String> hardcodedUiStringAllowlist = <String>{
  // ---- L6-deferred UI (feature-specific editor & secondary surfaces) ----
  // Venue management feature surfaces merged from main AFTER the L5 partition
  // was fixed — deferred to a sibling L6 sub-PR with the settings surfaces.
  'src/screens/venue_editor_sheet.dart',
  'src/screens/venue_manager_screen.dart',
  'src/widgets/venue_picker.dart',

  // ---- Permanent deferrals (non-UI / by-design English) ----
  // Data/service-layer curated messages: no enum discriminator, need a typed
  // error-code refactor before they can be localized (separate follow-up).
  'src/data/backup_document.dart',
  'src/data/callersbox_online.dart',
  'src/data/contradb_online.dart',
  // Exported-document body builders (PDF): field-name labels stay English
  // pending a product decision on whether exports follow the UI language.
  'src/export/dance_pdf.dart',
  'src/export/program_matrix_pdf.dart',
  'src/export/program_pdf.dart',
};
