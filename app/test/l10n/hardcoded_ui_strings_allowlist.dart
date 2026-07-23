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
/// The remaining entries are all **permanent, non-UI / by-design English**:
/// data/service-layer curated messages awaiting a typed-error refactor, and the
/// English export-document (PDF) body builders. See `docs/dev/localization.md`
/// for the full rationale and the other English-by-design surfaces that are not
/// guard-flagged (so not listed here) — `import_io` exception messages /
/// `ImportSource.label`, and the diagnostics-log export body.
library;

/// Files the guard skips. Paths are POSIX, relative to `app/lib/`.
const Set<String> hardcodedUiStringAllowlist = <String>{
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
