/// Privacy scrubbing for the local crash log's *exportable* variant (issue
/// #458). Pure Dart (ADR-001) so the security-critical redaction can be
/// exhaustively unit-tested with `dart test`, independent of Flutter.
///
/// The on-device crash log keeps full/raw records — it never leaves the device
/// unless the user explicitly exports it. [CrashRedactor] produces the scrubbed
/// text used for the *default* export: it removes contact PII (emails, phone
/// numbers), collapses absolute filesystem paths to a placeholder (keeping the
/// file basename so a stack frame stays diagnostically useful), and redacts an
/// explicit set of user-content terms (dance / program / figure titles, notes,
/// custom-field values, tag names) supplied by the caller.
///
/// The design is deliberately conservative: when in doubt it over-redacts. A
/// crash log is a diagnostic skeleton, not a data export, so losing a little
/// signal is always preferable to leaking a user's content or contact details.
library;

/// Removes PII and user content from crash-log free text.
///
/// Construct with the set of [userContentTerms] to strip (usually gathered from
/// the local database at export time); the email/phone/path patterns are always
/// applied. Stateless and `const`-constructible.
class CrashRedactor {
  const CrashRedactor({
    this.userContentTerms = const <String>{},
    this.minTermLength = 3,
  });

  /// Exact user-content strings to redact wherever they appear (case-insensitive
  /// substring match). Terms shorter than [minTermLength] are ignored so a
  /// one-or-two-character title can't blank out unrelated text.
  final Set<String> userContentTerms;

  /// User-content terms shorter than this are skipped (see [userContentTerms]).
  final int minTermLength;

  /// Placeholder written in place of a redacted email address.
  static const String emailPlaceholder = '[redacted-email]';

  /// Placeholder written in place of a redacted phone number.
  static const String phonePlaceholder = '[redacted-phone]';

  /// Placeholder written in place of a redacted user-content term.
  static const String contentPlaceholder = '[redacted]';

  /// Directory placeholder substituted for a collapsed absolute path; the file
  /// basename is preserved after it (e.g. `<path>/main.dart`).
  static const String pathPlaceholder = '<path>';

  // Email addresses. Intentionally broad on the local part.
  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
  );

  // Candidate phone-number token: an optional `+` then a run of digits grouped
  // by spaces, dots, hyphens or parentheses. `:` is deliberately excluded from
  // the separators so `file:line:col` refs are never joined into a candidate.
  // Matches are confirmed by digit count in [redactPhones] (7–15 digits), which
  // rejects short version numbers and line/column refs.
  static final RegExp _phoneCandidate = RegExp(
    r'(?<!\w)\+?\d[\d .()\-]{5,}\d(?!\w)',
  );
  static final RegExp _nonDigits = RegExp(r'\D');

  // `file://` URIs.
  static final RegExp _fileUri = RegExp(r'file://(?:/[^\s:)]+)+');

  // POSIX absolute paths (`/a/b/c.dart`). The lookbehind avoids matching the
  // second slash of a scheme (`https://`, `file://`) or a `package:`/`dart:`
  // URI, so app-symbol stack frames survive. Trailing `:line:col` is excluded
  // from the char class, so it stays outside the match and is preserved.
  static final RegExp _posixPath = RegExp(
    r'(?<![\w:/])/(?:[^/\s:)]+/)+[^/\s:)]*',
  );

  // Windows absolute paths (`C:\Users\me\x.dart`).
  static final RegExp _windowsPath = RegExp(
    r'[A-Za-z]:\\(?:[^\\\s:)]+\\)*[^\\\s:)]*',
  );

  /// Applies every redaction pass to [input] and returns the scrubbed text.
  ///
  /// Order matters: user-content terms first (they may themselves contain an
  /// `@` or digits that a later pass would otherwise mangle into a placeholder
  /// that no longer matches the term), then paths (so an email/phone inside a
  /// path is still caught by the following passes), then emails, then phones.
  String scrub(String input) {
    var out = redactTerms(input);
    out = redactPaths(out);
    out = redactEmails(out);
    out = redactPhones(out);
    return out;
  }

  /// Redacts every configured user-content term (case-insensitive) from [input].
  String redactTerms(String input) {
    if (userContentTerms.isEmpty) return input;
    // Longest first so a title that contains a shorter title is redacted whole
    // rather than leaving a dangling fragment.
    final terms =
        userContentTerms
            .map((t) => t.trim())
            .where((t) => t.length >= minTermLength)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    var out = input;
    for (final term in terms) {
      out = out.replaceAll(
        RegExp(RegExp.escape(term), caseSensitive: false),
        contentPlaceholder,
      );
    }
    return out;
  }

  /// Collapses absolute filesystem paths to [pathPlaceholder], keeping the file
  /// basename (e.g. `/Users/me/app/main.dart` → `<path>/main.dart`).
  String redactPaths(String input) {
    var out = input.replaceAllMapped(_fileUri, (m) => _collapse(m[0]!, '/'));
    out = out.replaceAllMapped(_windowsPath, (m) => _collapse(m[0]!, r'\'));
    out = out.replaceAllMapped(_posixPath, (m) => _collapse(m[0]!, '/'));
    return out;
  }

  /// Redacts email addresses from [input].
  String redactEmails(String input) =>
      input.replaceAll(_email, emailPlaceholder);

  /// Redacts phone numbers from [input]. A candidate token is only replaced
  /// when it contains 7–15 digits, so version numbers and `line:col` refs are
  /// left intact.
  String redactPhones(String input) =>
      input.replaceAllMapped(_phoneCandidate, (m) {
        final digitCount = m[0]!.replaceAll(_nonDigits, '').length;
        return (digitCount >= 7 && digitCount <= 15) ? phonePlaceholder : m[0]!;
      });

  static String _collapse(String path, String separator) {
    final trimmed = path.endsWith(separator)
        ? path.substring(0, path.length - separator.length)
        : path;
    final idx = trimmed.lastIndexOf(separator);
    if (idx < 0 || idx == trimmed.length - 1) return pathPlaceholder;
    final basename = trimmed.substring(idx + 1);
    return basename.isEmpty ? pathPlaceholder : '$pathPlaceholder/$basename';
  }
}
