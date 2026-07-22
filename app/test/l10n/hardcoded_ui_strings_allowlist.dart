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
  // Dance editor (whole directory) + its entry screen.
  'src/screens/dance_editor/dance_editor_form.dart',
  'src/screens/dance_editor/editor_fields.dart',
  'src/screens/dance_editor/lingo_discouraged_hint.dart',
  'src/screens/dance_editor/links_editor.dart',
  'src/screens/dance_editor/name_picker.dart',
  'src/screens/dance_editor/source_citations_editor.dart',
  'src/screens/dance_editor_screen.dart',
  'src/screens/dance_detail_screen.dart',
  // Secondary / feature screens.
  'src/screens/contradb_program_import_screen.dart',
  'src/screens/custom_fields_screen.dart',
  'src/screens/dialect_editor_screen.dart',
  // Settings general (data-management) section: Library/Performance/
  // Calling-history/Accessibility toggles, Deleted-items, Import, and the full
  // Backup/Restore flow. NOTE for L6: the Backup/Restore snackbars carry the
  // CWE-209 catch-and-log requirement (clean localized message + debugPrint the
  // raw error) — do not interpolate caught exceptions into UI text.
  'src/screens/settings/general_section.dart',
  // Formation-colours screen: L5 landed its formationShapeLabel helper-swap;
  // its own screen prose is deferred to L6.
  'src/screens/formation_colors_screen.dart',
  'src/screens/recently_deleted_screen.dart',
  'src/screens/reparse_custom_figures_screen.dart',
  'src/screens/theme_editor_screen.dart',
  'src/screens/user_guide/user_guide_screen.dart',
  // Large global-chrome widgets: L5 landed their facet helper-swaps; their own
  // prose is deferred to L6 (coordinator split).
  'src/update/update_banner.dart',
  'src/widgets/collection_picker.dart',
  'src/widgets/command_palette.dart',
  // Editor dialogs & figure editors.
  'src/widgets/choreographer_details_dialog.dart',
  'src/widgets/published_source_details_dialog.dart',
  'src/widgets/figure_list_editor.dart',
  'src/widgets/figure_param_editors.dart',
  // Feature surfaces merged from main (venue management + crash diagnostics)
  // AFTER the L5 partition was fixed — deferred to L6 with the other
  // feature-specific screens. NOTE for L6: diagnostics_section's export/clear
  // snackbars and crash_fallback carry the CWE-209 catch-and-log requirement
  // (clean localized message + debugPrint the raw error) — do not interpolate
  // caught exceptions into UI text.
  'src/diagnostics/crash_fallback.dart',
  'src/screens/settings/diagnostics_section.dart',
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
