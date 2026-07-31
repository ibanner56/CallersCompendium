import 'package:meta/meta.dart';

import '../model/enums.dart';

/// One existing dance as seen by the deduplicator: enough to match a candidate
/// import against, without loading the whole [Dance]. Built by the pipeline
/// from the current collection (title + author names + provenance key).
@immutable
class DedupeEntry {
  DedupeEntry({
    required this.danceId,
    required this.title,
    Iterable<String> authorNames = const [],
    this.source,
    this.externalId,
  }) : authorNames = List.unmodifiable(authorNames);

  final String danceId;
  final String title;

  /// Display names of the dance's authors (not ids) — names are what match
  /// across sources.
  final List<String> authorNames;

  /// Provenance source of this dance, if imported.
  final ProvenanceSource? source;

  /// Provenance external id of this dance, if imported.
  final String? externalId;
}

/// A fuzzy-match candidate: an existing dance and how strongly it matches the
/// record being imported (`0.0..1.0`).
@immutable
class DedupeCandidate {
  const DedupeCandidate({required this.danceId, required this.score});

  final String danceId;
  final double score;

  @override
  String toString() =>
      'DedupeCandidate($danceId, ${(score * 100).toStringAsFixed(0)}%)';
}

/// What the deduplicator decided for a record. One of three shapes:
/// - [isNew]: no existing match — import as a fresh dance.
/// - [reimport]: matched by exact `(source, externalId)` — update that dance
///   (refreshes provenance, enables diff). This is the only verdict the
///   pipeline acts on automatically.
/// - [ambiguous]: fuzzy title/author matches found — the pipeline surfaces the
///   [candidates] and the caller must supply a [DedupeResolution]
///   (link/duplicate/skip). Nothing is mutated without that resolution.
@immutable
class DedupeVerdict {
  const DedupeVerdict._({
    required this.kind,
    this.targetDanceId,
    this.candidates = const [],
  });

  factory DedupeVerdict.isNew() =>
      const DedupeVerdict._(kind: DedupeKind.isNew);

  factory DedupeVerdict.reimport(String danceId) =>
      DedupeVerdict._(kind: DedupeKind.reimport, targetDanceId: danceId);

  factory DedupeVerdict.ambiguous(List<DedupeCandidate> candidates) =>
      DedupeVerdict._(
        kind: DedupeKind.ambiguous,
        candidates: List.unmodifiable(candidates),
      );

  final DedupeKind kind;

  /// The existing dance to update, for [DedupeKind.reimport].
  final String? targetDanceId;

  /// Fuzzy candidates, best first, for [DedupeKind.ambiguous].
  final List<DedupeCandidate> candidates;

  bool get isNewDance => kind == DedupeKind.isNew;
  bool get isReimport => kind == DedupeKind.reimport;
  bool get isAmbiguous => kind == DedupeKind.ambiguous;

  @override
  String toString() => switch (kind) {
    DedupeKind.isNew => 'DedupeVerdict.new',
    DedupeKind.reimport => 'DedupeVerdict.reimport($targetDanceId)',
    DedupeKind.ambiguous => 'DedupeVerdict.ambiguous($candidates)',
  };
}

enum DedupeKind { isNew, reimport, ambiguous }

/// How the caller chose to resolve an [DedupeKind.ambiguous] verdict.
enum DedupeResolutionKind {
  /// Treat the import as an update to an existing dance ([targetDanceId]).
  link,

  /// Import as a new, separate dance despite the near-match.
  duplicate,

  /// Do not import this record.
  skip,
}

/// A caller's resolution for one ambiguous record. [targetDanceId] is required
/// for [DedupeResolutionKind.link] and ignored otherwise.
@immutable
class DedupeResolution {
  const DedupeResolution._(this.kind, this.targetDanceId);

  factory DedupeResolution.link(String targetDanceId) =>
      DedupeResolution._(DedupeResolutionKind.link, targetDanceId);

  factory DedupeResolution.duplicate() =>
      const DedupeResolution._(DedupeResolutionKind.duplicate, null);

  factory DedupeResolution.skip() =>
      const DedupeResolution._(DedupeResolutionKind.skip, null);

  final DedupeResolutionKind kind;
  final String? targetDanceId;
}

/// An in-memory index of the existing collection that answers dedupe queries.
///
/// Pure: it holds a snapshot of [DedupeEntry]s and does no I/O, so it is fully
/// unit-testable without a database. The pipeline builds one from the live
/// collection before a batch, then reuses it across the batch.
class DedupeIndex {
  DedupeIndex(
    Iterable<DedupeEntry> entries, {
    Map<String, String> choreographerIdByNormalizedName = const {},
  }) : _entries = List.unmodifiable(entries),
       choreographerIdByNormalizedName = Map.unmodifiable(
         choreographerIdByNormalizedName,
       ) {
    for (final e in _entries) {
      final ext = e.externalId;
      if (e.source != null && ext != null) {
        _byExternalKey['${e.source!.name}\u0000$ext'] = e.danceId;
      }
    }
  }

  final List<DedupeEntry> _entries;
  final Map<String, String> _byExternalKey = {};

  /// Snapshot of every choreographer at the time this index was built
  /// (normalized name → id), incidentally captured from the same collection
  /// load that produced [_entries]'s author names. Lets [ImportPipeline.commit]
  /// reuse this instead of a second `listAll()` — see
  /// [ImportPipeline.buildDedupeIndex] and [ImportPipeline.commit].
  final Map<String, String> choreographerIdByNormalizedName;

  /// Default minimum combined similarity for a fuzzy match to be surfaced.
  static const double defaultThreshold = 0.72;

  /// The exact-match dance id for `(source, externalId)`, or `null`.
  String? findByExternalId(ProvenanceSource source, String? externalId) {
    if (externalId == null) return null;
    return _byExternalKey['${source.name}\u0000$externalId'];
  }

  /// Fuzzy matches for a title + author name set, best first, filtered to
  /// [threshold].
  List<DedupeCandidate> fuzzyMatches(
    String title,
    Iterable<String> authorNames, {
    double threshold = defaultThreshold,
  }) {
    final nTitle = normalizeTitle(title);
    final nAuthors = authorNames.map(normalizeAuthor).toSet()..remove('');
    final out = <DedupeCandidate>[];
    for (final e in _entries) {
      final score = _combinedScore(
        nTitle,
        nAuthors,
        normalizeTitle(e.title),
        e.authorNames.map(normalizeAuthor).toSet()..remove(''),
      );
      if (score >= threshold) {
        out.add(DedupeCandidate(danceId: e.danceId, score: score));
      }
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// The full dedupe decision for a record: exact key first, then fuzzy.
  DedupeVerdict verdictFor({
    required ProvenanceSource source,
    String? externalId,
    required String title,
    Iterable<String> authorNames = const [],
    double threshold = defaultThreshold,
  }) {
    final exact = findByExternalId(source, externalId);
    if (exact != null) return DedupeVerdict.reimport(exact);
    final fuzzy = fuzzyMatches(title, authorNames, threshold: threshold);
    return fuzzy.isEmpty
        ? DedupeVerdict.isNew()
        : DedupeVerdict.ambiguous(fuzzy);
  }

  double _combinedScore(
    String titleA,
    Set<String> authorsA,
    String titleB,
    Set<String> authorsB,
  ) {
    final titleSim = _similarity(titleA, titleB);
    // Authors only participate when both sides declare some; otherwise the
    // score is title-only (no penalty for missing author metadata).
    if (authorsA.isEmpty || authorsB.isEmpty) return titleSim;
    final authorSim = _jaccard(authorsA, authorsB);
    return titleSim * 0.8 + authorSim * 0.2;
  }
}

/// Normalizes a dance title for comparison: lowercased, diacritics folded,
/// punctuation dropped, whitespace collapsed, and a single leading article
/// (`the`/`a`/`an`) removed.
String normalizeTitle(String title) {
  var s = _foldDiacritics(title.toLowerCase());
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^(the|a|an)\s+'), '');
  return s;
}

/// Normalizes an author name for comparison: lowercased, diacritics folded,
/// punctuation dropped, whitespace collapsed.
String normalizeAuthor(String name) {
  var s = _foldDiacritics(name.toLowerCase());
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Jaccard similarity of two string sets (`0.0..1.0`); empty∩empty is 1.0.
double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final inter = a.intersection(b).length;
  final union = a.union(b).length;
  return union == 0 ? 0.0 : inter / union;
}

/// Normalized Levenshtein similarity (`0.0..1.0`) between two strings.
double _similarity(String a, String b) {
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  final dist = _levenshtein(a, b);
  final maxLen = a.length > b.length ? a.length : b.length;
  return 1.0 - dist / maxLen;
}

int _levenshtein(String a, String b) {
  final prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final del = prev[j + 1] + 1;
      final ins = curr[j] + 1;
      final sub = prev[j] + cost;
      var m = del < ins ? del : ins;
      if (sub < m) m = sub;
      curr[j + 1] = m;
    }
    for (var k = 0; k <= b.length; k++) {
      prev[k] = curr[k];
    }
  }
  return prev[b.length];
}

const Map<String, String> _diacriticFolds = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

String _foldDiacritics(String s) {
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    buf.write(_diacriticFolds[ch] ?? ch);
  }
  return buf.toString();
}
