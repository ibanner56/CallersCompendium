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
            r'(?<![\w])(?:' + keys.map(RegExp.escape).join('|') + r')(?![\w])',
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
      for (final m in pattern.allMatches(text)) (text: m[0]!, start: m.start),
    ];
  }
}
