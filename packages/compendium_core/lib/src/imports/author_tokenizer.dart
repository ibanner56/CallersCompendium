import '../util/text_sanitizer.dart';
import 'structured_draft.dart';

/// Caps applied by [splitAuthorNames] to bound untrusted input (issue #685).
///
/// Import sources are untrusted remote/local text (ContraDB, The Caller's Box,
/// Caller's Companion exports) — a hostile or malformed record could otherwise
/// carry an arbitrarily long author field or an absurd number of conjunctions.
/// Both caps are enforced by truncation (never a thrown exception); an
/// over-limit record surfaces a single non-fatal [ImportIssue] instead.
class AuthorSplitLimits {
  const AuthorSplitLimits({
    this.maxFieldLength = 500,
    this.maxAuthorsPerRecord = 20,
  });

  /// Maximum length (in UTF-16 code units) of a single raw field *before* it
  /// is split. Longer fields are truncated to this length first.
  final int maxFieldLength;

  /// Maximum number of author names returned for one [splitAuthorNames] call
  /// (i.e. across every raw field passed in, combined). Extra names beyond
  /// this are dropped.
  final int maxAuthorsPerRecord;
}

/// Name-suffix tokens that must stay attached to the *preceding* name rather
/// than being read as a new author when they immediately follow a comma
/// (`"Jane Doe, Jr."` is one author, not two). Compared case-insensitively,
/// with an optional trailing `.` ignored.
const Set<String> _nameSuffixes = {'jr', 'sr', 'ii', 'iii', 'iv'};

/// The bounded-alternation delimiter regex used after the comma/suffix pass.
/// Every alternative is a literal or a `\b`-anchored literal word — there is
/// no repetition operator applied to input text, so this cannot exhibit
/// catastrophic backtracking (ReDoS-safe by construction) regardless of how
/// pathological the input is.
final RegExp _otherDelimiters = RegExp(
  r'/|&|\+|;|\band\b|\bwith\b',
  caseSensitive: false,
);

/// Splits one or more raw author-field strings into individual display
/// names, using the ONE canonical delimiter/suffix policy shared by every
/// import adapter (issue #685's core fix).
///
/// [rawFields] is either a single combined choreographer string (ContraDB) or
/// an array of per-author fields (The Caller's Box `Authors[]`, Caller's
/// Companion `Author1`/`Author2`) — each field is independently split and the
/// results are combined, de-duplicated, and capped.
///
/// Delimiter policy (documented trade-off): splits on `/`, `&`, `+`, `;`, and
/// the *words* `and` / `with` (case-insensitive, word-boundary — so `Andy`
/// and `Withers` are not touched). A `,` is treated as a delimiter too,
/// **except** when the fragment immediately after it looks like a name
/// suffix (`Jr`/`Sr`/`II`/`III`/`IV`, with or without a trailing `.`), in
/// which case the suffix is re-attached to the preceding name instead of
/// starting a new one. This is a conservative heuristic, not a full name
/// parser: a legitimate two-part credit that happens to look like "Name,
/// Word" where Word coincidentally matches a suffix token is rare enough
/// that this trade-off is accepted per the issue.
///
/// Every returned name has already been sanitized with
/// [sanitizeImportedText] (preserving the existing bidi/zero-width-spoofing
/// defenses from #444/#611) and trimmed; blanks are dropped. The combined
/// list is de-duplicated case/whitespace-insensitively (first-seen casing
/// wins) and capped by [limits]. Truncation (either a too-long field or too
/// many combined authors) never throws — it appends one non-fatal
/// [ImportIssue] to [issues] (when provided) per triggered cap.
///
/// The raw, un-split field(s) are never touched by this function — adapters
/// keep the verbatim source string in `RawRecord`/provenance, so nothing is
/// lost even though this function only returns the tokenized names.
List<String> splitAuthorNames(
  Iterable<String?> rawFields, {
  List<ImportIssue>? issues,
  AuthorSplitLimits limits = const AuthorSplitLimits(),
}) {
  var fieldTruncated = false;
  final combined = <String>[];
  final seen = <String>{};

  for (final rawField in rawFields) {
    if (rawField == null) continue;
    var field = rawField.trim();
    if (field.isEmpty) continue;
    if (field.length > limits.maxFieldLength) {
      field = field.substring(0, limits.maxFieldLength);
      fieldTruncated = true;
    }

    for (final commaPart in _splitOnCommaWithSuffixProtection(field)) {
      for (final piece in commaPart.split(_otherDelimiters)) {
        final clean = sanitizeImportedText(
          piece.trim(),
          allowLineBreaks: false,
        ).trim();
        if (clean.isEmpty) continue;
        final key = clean.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        if (seen.add(key)) {
          combined.add(clean);
        }
      }
    }
  }

  var countTruncated = false;
  var result = combined;
  if (combined.length > limits.maxAuthorsPerRecord) {
    result = combined.sublist(0, limits.maxAuthorsPerRecord);
    countTruncated = true;
  }

  if (issues != null) {
    if (fieldTruncated) {
      issues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'author_field_truncated',
          message:
              'An author field exceeded the safe length and was truncated '
              'before splitting; some trailing text may have been lost.',
        ),
      );
    }
    if (countTruncated) {
      issues.add(
        const ImportIssue(
          severity: ImportIssueSeverity.warning,
          code: 'author_count_capped',
          message:
              'More author names were found than the safe per-record limit; '
              'the extras were dropped.',
        ),
      );
    }
  }

  return result;
}

/// Splits [field] on `,`, except when the fragment immediately following a
/// comma is a name suffix (`Jr`/`Sr`/`II`/`III`/`IV`), in which case the
/// suffix is re-attached to the previous part. Uses a plain (non-regex)
/// `String.split` for the comma pass itself, so this stage cannot backtrack
/// regardless of input.
///
/// Handles the compound case where a suffix is followed by further content
/// on the same comma-fragment (e.g. `"Doe, Jr. and Bob Smith"`): only the
/// leading suffix token is peeled off and re-attached; anything after it
/// stays in that fragment for the caller's subsequent delimiter split.
List<String> _splitOnCommaWithSuffixProtection(String field) {
  final rawParts = field.split(',');
  if (rawParts.length == 1) return rawParts;

  final out = <String>[rawParts.first];
  for (var i = 1; i < rawParts.length; i++) {
    final part = rawParts[i];
    final trimmedLeading = part.trimLeft();
    final (suffix, rest) = _peekLeadingSuffix(trimmedLeading);
    if (suffix != null && out.isNotEmpty) {
      out[out.length - 1] = '${out.last.trimRight()}, $suffix';
      if (rest.trim().isNotEmpty) {
        out.add(rest);
      }
    } else {
      out.add(part);
    }
  }
  return out;
}

/// If [text] starts with a recognized name-suffix token (optionally followed
/// by a `.`), returns `(suffixTokenAsWritten, remainderAfterSuffix)`;
/// otherwise returns `(null, text)`. Matching is a fixed-string comparison of
/// the leading word (no regex) so this cannot backtrack.
(String?, String) _peekLeadingSuffix(String text) {
  var end = 0;
  while (end < text.length && _isWordChar(text.codeUnitAt(end))) {
    end++;
  }
  if (end == 0) return (null, text);
  final word = text.substring(0, end);
  if (!_nameSuffixes.contains(word.toLowerCase())) return (null, text);

  var rest = text.substring(end);
  var written = word;
  if (rest.startsWith('.')) {
    written = '$word.';
    rest = rest.substring(1);
  }
  return (written, rest);
}

bool _isWordChar(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
    (codeUnit >= 0x61 && codeUnit <= 0x7A); // a-z
