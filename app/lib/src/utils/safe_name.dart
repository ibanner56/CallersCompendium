/// Filename- and print-job-name sanitization for untrusted titles.
///
/// Dance/program titles can be imported or shared and therefore contain
/// arbitrary characters (path separators, control characters, ...). Any export
/// path that turns such a title into a file name or a `Printing.layoutPdf`
/// print-job `name:` must reduce it to a safe, uniform character set first
/// (issue #468). This is the single source of truth for that idiom, previously
/// duplicated inline across the export and update-download paths.
library;

/// Every character *outside* the safe set `[A-Za-z0-9._-]` (ASCII letters,
/// digits, dot, underscore, hyphen). Anything else — path separators,
/// whitespace, control characters — is replaced with `_`.
final RegExp _unsafeNameChars = RegExp(r'[^A-Za-z0-9._-]');

/// Leading/trailing dots and underscores, stripped so a sanitized name can
/// never be `.`, `..`, or a hidden dotfile.
final RegExp _leadingTrailingSeparators = RegExp(r'^[._]+|[._]+$');

/// Matches at least one alphanumeric character — used to decide whether a
/// sanitized name still carries meaningful content or should fall back.
final RegExp _hasAlphanumeric = RegExp(r'[A-Za-z0-9]');

/// Replaces every character outside `[A-Za-z0-9._-]` in [value] with `_`.
///
/// Low-level building block shared by [sanitizeExportName] and by the
/// program-share-bundle / update-download file-name derivations, so every path
/// applies the identical canonical idiom.
String replaceUnsafeNameChars(String value) =>
    value.replaceAll(_unsafeNameChars, '_');

/// Produces a filesystem- and print-job-safe name from an untrusted [raw]
/// title.
///
/// Hardening, in order:
/// 1. trims surrounding whitespace,
/// 2. replaces every character outside `[A-Za-z0-9._-]` with `_` (path
///    separators, spaces, control characters, ...),
/// 3. strips leading/trailing dots and underscores so the result can never be
///    `.`, `..`, or a hidden dotfile, and
/// 4. falls back to [fallback] when no alphanumeric content remains (empty,
///    all-whitespace, or all-illegal input).
///
/// The [fallback] is **not** trusted either: it is run through the identical
/// sanitization, so a caller-supplied default that carries unsafe characters
/// (e.g. `'Programming matrix'`, which contains a space) can never leak them
/// into the returned name. If the sanitized fallback is itself empty of
/// alphanumeric content, the stable `'export'` default is used, so this
/// function's promise — the result is always within `[A-Za-z0-9._-]` and never
/// `.`/`..`/a dotfile — holds unconditionally.
///
/// This is the sanitizer every user-facing export/print name should flow
/// through, so imported/shared titles are handled uniformly (issue #468).
String sanitizeExportName(String raw, {String fallback = 'export'}) {
  final sanitized = _stripToSafeName(raw);
  if (sanitized.contains(_hasAlphanumeric)) return sanitized;
  final sanitizedFallback = _stripToSafeName(fallback);
  return sanitizedFallback.contains(_hasAlphanumeric)
      ? sanitizedFallback
      : 'export';
}

/// Trims [value], replaces every unsafe character with `_`, and strips
/// leading/trailing dots/underscores. Shared by [sanitizeExportName] for both
/// the raw title and the fallback so neither can bypass the safe-set guarantee.
String _stripToSafeName(String value) => replaceUnsafeNameChars(
  value.trim(),
).replaceAll(_leadingTrailingSeparators, '');
