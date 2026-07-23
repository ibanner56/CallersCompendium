/// Deferral manifest for [no_hardcoded_ui_strings_test.dart] (the i18n
/// regression guard).
///
/// Every path here is a `lib/`-relative Dart file that still contains
/// user-facing string literals the guard would otherwise flag. The guard skips
/// these files wholesale; every other file under `lib/src/` must be free of
/// hardcoded user-facing prose.
///
/// This is a **ratchet**: the list only ever shrinks. The phased UI-string
/// extraction (layers L1–L6) is now **complete**, so the "deferred UI" bucket
/// is empty — only the **permanent** (by-design English) deferrals remain. The
/// guard also fails if a listed file no longer exists or no longer has any
/// flagged literal, so the manifest can't silently rot.
///
/// The remaining entries are all **permanent, by-design English**: the
/// export-document (PDF) body builders, whose field-name labels stay English
/// pending a product decision on whether exports follow the UI language. See
/// `docs/dev/localization.md` for the full rationale and the other
/// English-by-design surfaces that are not guard-flagged (so not listed here) —
/// the diagnostics-log export body.
///
/// The former data/service-layer curated messages (`backup_document`,
/// `callersbox_online`, `contradb_online`, and the related `import_io`
/// exception messages / `ImportSource.label`) have been localized via a
/// typed-error refactor and removed from this list.
library;

/// Files the guard skips. Paths are POSIX, relative to `app/lib/`.
const Set<String> hardcodedUiStringAllowlist = <String>{
  // ---- Permanent deferrals (by-design English) ----
  // Exported-document body builders (PDF): field-name labels stay English
  // pending a product decision on whether exports follow the UI language.
  'src/export/dance_pdf.dart',
  'src/export/program_matrix_pdf.dart',
  'src/export/program_pdf.dart',
};
