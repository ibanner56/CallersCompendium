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
/// applied. Immutable; the term matcher is precomputed once per instance and
/// reused across every [scrub] call (see [_termsPattern]).
class CrashRedactor {
  CrashRedactor({
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
  // URI, so app-symbol stack frames survive. Directory segments may contain
  // spaces (a home dir like `/Users/Jane Doe/...` must not leak the username by
  // stopping at the first space); only `/`, line breaks, `:` and `)` end a
  // segment. The trailing basename stops at whitespace so surrounding prose is
  // not swallowed, and any `:line:col` ref is left outside the match.
  static final RegExp _posixPath = RegExp(
    r'(?<![\w:/])/(?:[^/\r\n:)]+/)+[^/\s:)]*',
  );

  // Windows drive paths, either separator: `C:\Users\me\x.dart` or
  // `C:/Users/me/x.dart`. The leading lookbehind keeps a URI scheme letter
  // (the `p` in `http://`) from being mistaken for a drive letter. Directory
  // segments may contain spaces; the basename stops at whitespace.
  static final RegExp _windowsPath = RegExp(
    r'(?<![A-Za-z0-9])[A-Za-z]:[\\/](?:[^\\/\r\n:)]+[\\/])*[^\\/\s:)]*',
  );

  // UNC paths (`\\server\share\file.dart`). Directory segments may contain
  // spaces; the basename stops at whitespace so trailing prose isn't swallowed.
  // The whole path collapses to its basename, dropping the (potentially
  // sensitive) server/share.
  static final RegExp _uncPath = RegExp(
    r'\\\\(?:[^\\/\r\n:)]+[\\/])*[^\\/\s:)]*',
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
  ///
  /// Uses a single precomputed matcher ([_termsPattern]) so the cost is one pass
  /// over [input] regardless of how many terms there are — with a large
  /// collection (tens of thousands of dances) and two scrubs per retained
  /// record, a per-term rescan would be prohibitively slow.
  String redactTerms(String input) {
    final pattern = _termsPattern;
    if (pattern == null) return input;
    return input.replaceAll(pattern, contentPlaceholder);
  }

  /// A single alternation regex over every eligible term, or `null` when there
  /// is nothing to redact. Built once per instance (the export path reuses one
  /// redactor across all records). Terms are de-duplicated and sorted
  /// longest-first so that, at any position, the longest matching term wins and
  /// a title containing a shorter title is redacted whole.
  late final RegExp? _termsPattern = _buildTermsPattern();

  RegExp? _buildTermsPattern() {
    if (userContentTerms.isEmpty) return null;
    final terms =
        userContentTerms
            .map((t) => t.trim())
            .where((t) => t.length >= minTermLength)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    if (terms.isEmpty) return null;
    return RegExp(terms.map(RegExp.escape).join('|'), caseSensitive: false);
  }

  /// Collapses absolute filesystem paths to [pathPlaceholder], keeping the file
  /// basename (e.g. `/Users/me/app/main.dart` → `<path>/main.dart`). Handles
  /// `file://` URIs, POSIX paths, Windows drive paths (either separator), and
  /// UNC paths.
  String redactPaths(String input) {
    var out = input.replaceAllMapped(_fileUri, (m) => _collapse(m[0]!, '/'));
    out = out.replaceAllMapped(_uncPath, (m) => _collapse(m[0]!, r'\'));
    out = out.replaceAllMapped(_windowsPath, (m) => _collapseWindows(m[0]!));
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

  // A Windows match may use either separator (`C:\...` or `C:/...`); collapse on
  // whichever it actually contains so the basename is found correctly.
  static String _collapseWindows(String path) =>
      _collapse(path, path.contains(r'\') ? r'\' : '/');

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
