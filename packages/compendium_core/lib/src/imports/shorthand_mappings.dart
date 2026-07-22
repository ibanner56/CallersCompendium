import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/figure.dart';
import '../serialization/figure_codec.dart';
import '../taxonomy/taxonomy.dart';
import '../validation/validation.dart';

/// Upper bound on how many shorthand mappings we will decode from persisted
/// config. The store is user-editable and plausibly shareable, so it is treated
/// as untrusted input (OWASP bounded-input posture, mirroring the dialect /
/// formation-color decode guards): a payload claiming more than this many
/// entries is truncated rather than driving unbounded work. Comfortably beyond
/// any realistic personal shorthand vocabulary.
const int maxShorthandMappings = 500;

/// Upper bound on the length of a single shorthand token (after trimming). A
/// token is a short mnemonic ("bns", "nbr bal swing") typed as a whole line, so
/// a real token is at most a few words; anything longer is treated as
/// malformed/hostile and its mapping is dropped. Also enforced by the editor so
/// the two never disagree.
const int maxShorthandTokenLength = 64;

/// Upper bound on how many target figures a single shorthand may expand to. A
/// shorthand is a mini-macro for a short sequence (commonly one or two
/// figures); this bounds a corrupt/hostile mapping from claiming an enormous
/// expansion while still comfortably covering any real combo.
const int maxShorthandTargetFigures = 64;

/// Normalizes a shorthand token (or a candidate free-text line) for matching
/// and uniqueness: trimmed of surrounding whitespace and lowercased. Matching
/// is deliberately case-insensitive + trim-insensitive (issue #420) while the
/// original casing is preserved elsewhere for display.
String normalizeShorthandToken(String token) => token.trim().toLowerCase();

const ListEquality<Object?> _figuresEquality = ListEquality<Object?>();

/// One user-defined shorthand mapping: a [token] (a short mnemonic typed as a
/// whole free-text line) that expands to an ORDERED list of [figures] (issue
/// #420). A shorthand may be a mini-macro — mapping to one OR MORE figures — so
/// a single token can drop in a short sequence.
///
/// The original [token] casing is preserved for display; matching uses
/// [normalizedToken]. The [figures] list is unmodifiable.
@immutable
class ShorthandMapping {
  ShorthandMapping({required this.token, required List<Figure> figures})
    : figures = List.unmodifiable(figures);

  /// The user-entered token, with original casing preserved for display.
  final String token;

  /// The ordered figure(s) this token expands to. Never empty for a mapping
  /// that survives [ShorthandMappings.decode] (an empty expansion is corrupt
  /// and dropped).
  final List<Figure> figures;

  /// The trimmed + lowercased token used for matching and uniqueness.
  String get normalizedToken => normalizeShorthandToken(token);

  /// Serializes the mapping: the display token plus its ordered figures encoded
  /// with the shared [figureToJson] format so the target round-trips exactly
  /// like a hand-built figure.
  Map<String, Object?> toJson() => {
    'token': token,
    'figures': [for (final f in figures) figureToJson(f)],
  };

  @override
  bool operator ==(Object other) =>
      other is ShorthandMapping &&
      other.token == token &&
      _figuresEquality.equals(other.figures, figures);

  @override
  int get hashCode => Object.hash(token, _figuresEquality.hash(figures));

  @override
  String toString() => 'ShorthandMapping($token → ${figures.length} figure(s))';
}

/// A user's ordered collection of shorthand → figure(s) mappings, plus the pure
/// resolution used by the free-text entry path (issue #420). Flutter-free.
///
/// Shipped with ZERO built-in mappings ([empty]). Persisted as user config and
/// therefore treated as untrusted input on decode: [decode] is bounded,
/// never-throws, validates every target figure against the shipped taxonomy,
/// and drops any corrupt/partial mapping entirely so it can never yield a
/// fabricated figure — the same posture as the import and dialect decode paths.
@immutable
class ShorthandMappings {
  ShorthandMappings(List<ShorthandMapping> mappings)
    : mappings = List.unmodifiable(mappings),
      _byNormalizedToken = _indexByToken(mappings);

  /// Builds a normalized-token → figures index, keeping the FIRST mapping when
  /// two entries share a normalized token (matching [decode]'s dedupe rule so a
  /// programmatically-constructed instance resolves identically).
  static Map<String, List<Figure>> _indexByToken(
    List<ShorthandMapping> mappings,
  ) {
    final index = <String, List<Figure>>{};
    for (final m in mappings) {
      index.putIfAbsent(m.normalizedToken, () => m.figures);
    }
    return index;
  }

  /// The mappings in display/insertion order. Unmodifiable.
  final List<ShorthandMapping> mappings;

  final Map<String, List<Figure>> _byNormalizedToken;

  /// The empty store — the shipped default (no built-in mappings).
  static final ShorthandMappings empty = ShorthandMappings(const []);

  /// Whether there are no mappings.
  bool get isEmpty => mappings.isEmpty;

  /// Resolves a whole [line] to its mapped figures, or `null` on a miss.
  ///
  /// Matching is WHOLE-LINE, EXACT-TOKEN only (no mid-line/substring
  /// substitution): the line is trimmed + lowercased and looked up against the
  /// mapping tokens. On a hit a fresh (mutable) copy of the ordered figures is
  /// returned so the caller can insert/mutate them freely; on a miss `null` is
  /// returned and the caller falls through to the normal parser.
  List<Figure>? resolve(String line) {
    final key = normalizeShorthandToken(line);
    if (key.isEmpty) return null;
    final figures = _byNormalizedToken[key];
    return figures == null ? null : List<Figure>.of(figures);
  }

  /// Serializes the whole store to a JSON-encodable list (one object per
  /// mapping) for persistence.
  List<Object?> toJson() => [for (final m in mappings) m.toJson()];

  /// Encodes the store to a compact JSON string for the settings table.
  String encode() => jsonEncode(toJson());

  /// Decodes a persisted store defensively, NEVER throwing (issue #420 OWASP
  /// guard). [stored] may be the already-decoded JSON value (a `List`) or the
  /// raw JSON string; anything else — or malformed JSON — yields [empty].
  ///
  /// Each mapping is validated all-or-nothing against [taxonomy]:
  /// - the entry must be a `Map` with a non-empty, trimmed token no longer than
  ///   [maxShorthandTokenLength]; case-insensitive duplicate tokens keep the
  ///   FIRST occurrence and drop the rest;
  /// - `figures` must be a non-empty `List` no longer than
  ///   [maxShorthandTargetFigures], and EVERY figure must decode structurally
  ///   AND pass [Taxonomy.validateFigure] with no error-severity issues
  ///   (unknown move, unknown/extra param key, out-of-range or non-conforming
  ///   value all reject);
  /// - if ANY figure in a mapping is invalid, the WHOLE mapping is ignored so a
  ///   corrupt/partial mapping never produces a fabricated figure;
  /// - at most [maxShorthandMappings] mappings are kept.
  static ShorthandMappings decode(
    Object? stored, {
    required Taxonomy taxonomy,
  }) {
    Object? raw = stored;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return empty;
      }
    }
    if (raw is! List) return empty;

    final result = <ShorthandMapping>[];
    final seenTokens = <String>{};
    for (final entry in raw) {
      if (result.length >= maxShorthandMappings) break;
      final mapping = _decodeMapping(entry, taxonomy: taxonomy);
      if (mapping == null) continue;
      // Case-insensitive uniqueness: keep the first mapping for a token.
      if (!seenTokens.add(mapping.normalizedToken)) continue;
      result.add(mapping);
    }
    return ShorthandMappings(result);
  }

  /// Decodes and validates one mapping entry, or returns `null` when the entry
  /// is unusable. Never throws.
  static ShorthandMapping? _decodeMapping(
    Object? entry, {
    required Taxonomy taxonomy,
  }) {
    if (entry is! Map) return null;

    final rawToken = entry['token'];
    if (rawToken is! String) return null;
    final token = rawToken.trim();
    if (token.isEmpty || token.length > maxShorthandTokenLength) return null;

    final rawFigures = entry['figures'];
    if (rawFigures is! List) return null;
    if (rawFigures.isEmpty || rawFigures.length > maxShorthandTargetFigures) {
      return null;
    }

    final figures = <Figure>[];
    for (final rawFigure in rawFigures) {
      final figure = _decodeFigure(rawFigure, taxonomy: taxonomy);
      // All-or-nothing: one bad figure drops the whole mapping so a partial
      // expansion can never be fabricated.
      if (figure == null) return null;
      figures.add(figure);
    }
    return ShorthandMapping(token: token, figures: figures);
  }

  /// Structurally decodes one figure and validates it against [taxonomy],
  /// returning `null` on any structural error, any decode throw, or any
  /// error-severity validation issue (unknown move, unknown param, out-of-range
  /// / non-conforming value). Never throws.
  static Figure? _decodeFigure(Object? raw, {required Taxonomy taxonomy}) {
    if (raw is! Map) return null;
    Figure figure;
    try {
      figure = figureFromJson(raw.cast<String, Object?>());
    } catch (_) {
      return null;
    }
    final issues = taxonomy.validateFigure(figure);
    final hasError = issues.any((i) => i.severity == ValidationSeverity.error);
    return hasError ? null : figure;
  }
}
