// Word-boundary term substitution shared by the render and canonicalize
// pipelines. Single-pass (no chained re-replacement), longest-match-first,
// with optional case-insensitive matching and case-preserving output.

/// How the case of a matched span is carried onto its replacement.
enum _Case { lower, title, upper, mixed }

_Case _caseOf(String s) {
  if (s == s.toLowerCase()) return _Case.lower;
  if (s == s.toUpperCase()) return _Case.upper;
  if (s.length > 1 &&
      s[0] == s[0].toUpperCase() &&
      s.substring(1) == s.substring(1).toLowerCase()) {
    return _Case.title;
  }
  return _Case.mixed;
}

String _applyCase(String matched, String replacement) {
  switch (_caseOf(matched)) {
    case _Case.upper:
      return replacement.toUpperCase();
    case _Case.title:
      return replacement.isEmpty
          ? replacement
          : replacement[0].toUpperCase() + replacement.substring(1);
    case _Case.lower:
    case _Case.mixed:
      return replacement;
  }
}

/// Compiled set of `term → replacement` rules.
class Substitutor {
  Substitutor(
    Map<String, String> replacements, {
    this.caseInsensitive = false,
    this.preserveCase = false,
  }) : _map = {
         for (final e in replacements.entries)
           (caseInsensitive ? e.key.toLowerCase() : e.key): e.value,
       } {
    final keys = _map.keys.where((k) => k.isNotEmpty).toList()
      // Longest first so "Larks" wins over "Lark" at the same position.
      ..sort((a, b) => b.length.compareTo(a.length));
    _pattern = keys.isEmpty
        ? null
        : RegExp(
            '(?:' + keys.map(RegExp.escape).join('|') + r')',
            caseSensitive: !caseInsensitive,
          );
  }

  final bool caseInsensitive;
  final bool preserveCase;
  final Map<String, String> _map;
  late final RegExp? _pattern;

  bool get isEmpty => _pattern == null;

  /// Applies all substitutions to [text] in a single left-to-right pass.
  String apply(String text) {
    final pattern = _pattern;
    if (pattern == null || text.isEmpty) return text;
    return text.replaceAllMapped(pattern, (m) {
      if (!_hasWordBoundaries(text, m.start, m.end)) return m[0]!;
      final matched = m[0]!;
      final key = caseInsensitive ? matched.toLowerCase() : matched;
      final replacement = _map[key]!;
      return preserveCase ? _applyCase(matched, replacement) : replacement;
    });
  }

  /// Returns each matched span (value + start offset), for UI highlighting
  /// (the dialect "lingo line").
  List<({String text, int start})> matches(String text) {
    final pattern = _pattern;
    if (pattern == null) return const [];
    return [
      for (final m in pattern.allMatches(text))
        if (_hasWordBoundaries(text, m.start, m.end))
          (text: m[0]!, start: m.start),
    ];
  }
}

bool _hasWordBoundaries(String text, int start, int end) =>
    !_isWordCodePoint(_codePointBefore(text, start)) &&
    !_isWordCodePoint(_codePointAt(text, end));

int? _codePointBefore(String text, int offset) {
  if (offset == 0) return null;
  final low = text.codeUnitAt(offset - 1);
  if (low < 0xDC00 || low > 0xDFFF || offset < 2) return low;
  final high = text.codeUnitAt(offset - 2);
  if (high < 0xD800 || high > 0xDBFF) return low;
  return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
}

int? _codePointAt(String text, int offset) {
  if (offset >= text.length) return null;
  final high = text.codeUnitAt(offset);
  if (high < 0xD800 || high > 0xDBFF || offset + 1 >= text.length) {
    return high;
  }
  final low = text.codeUnitAt(offset + 1);
  if (low < 0xDC00 || low > 0xDFFF) return high;
  return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
}

bool _isWordCodePoint(int? codePoint) {
  if (codePoint == null) return false;
  if ((codePoint >= 0x30 && codePoint <= 0x39) ||
      (codePoint >= 0x41 && codePoint <= 0x5A) ||
      (codePoint >= 0x61 && codePoint <= 0x7A) ||
      codePoint == 0x5F) {
    return true;
  }
  return (codePoint >= 0x00C0 && codePoint <= 0x02AF) ||
      (codePoint >= 0x0300 && codePoint <= 0x036F) ||
      (codePoint >= 0x0370 && codePoint <= 0x052F) ||
      (codePoint >= 0x1E00 && codePoint <= 0x1EFF) ||
      (codePoint >= 0x3040 && codePoint <= 0x30FF) ||
      (codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
      (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
      (codePoint >= 0xAC00 && codePoint <= 0xD7AF) ||
      (codePoint >= 0x10000 && codePoint <= 0x1EFFF);
}
