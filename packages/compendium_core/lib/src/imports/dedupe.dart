import 'package:meta/meta.dart';
import 'package:unorm_dart/unorm_dart.dart';

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
  const DedupeCandidate({
    required this.danceId,
    required this.score,
    this.confident = false,
  });

  final String danceId;
  final double score;

  /// Whether this candidate is a **confident match**: normalized titles are
  /// exactly equal AND the tokenized author sets intersect (issue #685's
  /// dedupe sanity check). A confident candidate is always included in
  /// [DedupeIndex.fuzzyMatches] regardless of [DedupeIndex.defaultThreshold]
  /// — inconsistent author-string tokenization across sources must never be
  /// able to silently drop an exact-title, shared-author pair to [isNew].
  ///
  /// This is the seam issue #686 builds its figure-diff "variation?" prompt
  /// on top of — it reads [confident]/[DedupeVerdict.hasConfidentMatch]
  /// without needing to touch this file's scoring logic.
  final bool confident;

  @override
  String toString() =>
      'DedupeCandidate($danceId, ${(score * 100).toStringAsFixed(0)}%'
      '${confident ? ', confident' : ''})';
}

/// What the deduplicator decided for a record. One of three shapes:
/// - [isNew]: no existing match — import as a fresh dance.
/// - [reimport]: matched by exact `(source, externalId)` — update that dance
///   (refreshes provenance, enables diff). This is the only verdict the
///   pipeline acts on automatically.
/// - [ambiguous]: fuzzy title/author matches found — the pipeline surfaces the
///   [candidates] and the caller must supply a [DedupeResolution]
///   (link/duplicate/skip). Nothing is mutated without that resolution. A
///   candidate may be [DedupeCandidate.confident] — see
///   [hasConfidentMatch].
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

  /// Whether any [candidates] entry is a [DedupeCandidate.confident] match
  /// (exact-title + shared-author, regardless of author-string formatting).
  ///
  /// Non-interactive callers (issue #685 Option 2 — e.g. the program-import
  /// resolver) use this to guarantee they never silently duplicate a
  /// confident match; #686 reuses it as the trigger for its figure-diff
  /// "variation?" prompt. `false` for [isNew] (candidates is always empty
  /// there — a confident candidate can never fail to be surfaced, see
  /// [DedupeIndex.fuzzyMatches]) and for [reimport].
  bool get hasConfidentMatch => candidates.any((c) => c.confident);

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

  /// Import as a new, distinct dance that is a **figure-level variation**
  /// of [DedupeResolution.targetDanceId] (issue #686): the confident
  /// title+author match's figures differ from the incoming record's
  /// figures (see `figureCanonicalKey`/`diffFigures` in `figure_diff.dart`),
  /// so this is a genuinely different choreography under the same/similar
  /// name rather than a duplicate. Distinct from [duplicate] (which carries
  /// no relationship back to the near-match) so the pipeline can optionally
  /// record a [DedupeResolution.linkBack] `relatedDance` link between the
  /// two dances.
  variation,
}

/// A caller's resolution for one ambiguous record. [targetDanceId] is required
/// for [DedupeResolutionKind.link] and [DedupeResolutionKind.variation], and
/// ignored otherwise. [linkBack] only applies to [DedupeResolutionKind.variation].
@immutable
class DedupeResolution {
  const DedupeResolution._(
    this.kind,
    this.targetDanceId, {
    this.linkBack = false,
  });

  factory DedupeResolution.link(String targetDanceId) =>
      DedupeResolution._(DedupeResolutionKind.link, targetDanceId);

  factory DedupeResolution.duplicate() =>
      const DedupeResolution._(DedupeResolutionKind.duplicate, null);

  factory DedupeResolution.skip() =>
      const DedupeResolution._(DedupeResolutionKind.skip, null);

  /// Import as a new dance that is a variation of [targetDanceId] (issue
  /// #686). When [linkBack] is true (the default — both the interactive
  /// "Import as a variation" prompt and the non-interactive program-import
  /// auto-import path default it on), the pipeline creates a symmetric
  /// [DanceLinkKind.relatedDance]-equivalent pair of links between the new
  /// dance and [targetDanceId] so the relationship is visible from either
  /// dance's detail screen.
  factory DedupeResolution.variation(
    String targetDanceId, {
    bool linkBack = true,
  }) => DedupeResolution._(
    DedupeResolutionKind.variation,
    targetDanceId,
    linkBack: linkBack,
  );

  final DedupeResolutionKind kind;
  final String? targetDanceId;
  final bool linkBack;
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
  /// [threshold] — **plus** any confident match (see [DedupeCandidate.confident])
  /// even when its score would otherwise fall under [threshold]. An
  /// exact-normalized-title + overlapping-tokenized-author pair is therefore
  /// *guaranteed* to be surfaced (never silently dropped to [isNew]),
  /// independent of how [threshold] is tuned.
  List<DedupeCandidate> fuzzyMatches(
    String title,
    Iterable<String> authorNames, {
    double threshold = defaultThreshold,
  }) {
    final nTitle = normalizeTitle(title);
    final nAuthors = authorNames.map(normalizeAuthor).toSet()..remove('');
    final out = <DedupeCandidate>[];
    for (final e in _entries) {
      final eTitle = normalizeTitle(e.title);
      final eAuthors = e.authorNames.map(normalizeAuthor).toSet()..remove('');
      final score = _combinedScore(nTitle, nAuthors, eTitle, eAuthors);
      final confident =
          nTitle.isNotEmpty &&
          nTitle == eTitle &&
          nAuthors.isNotEmpty &&
          eAuthors.isNotEmpty &&
          nAuthors.intersection(eAuthors).isNotEmpty;
      if (score >= threshold || confident) {
        out.add(
          DedupeCandidate(
            danceId: e.danceId,
            score: score,
            confident: confident,
          ),
        );
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

/// Normalizes a dance title for comparison: NFC-composed, lowercased, diacritics
/// folded, punctuation dropped, whitespace collapsed, and a single leading
/// article (`the`/`a`/`an`) removed.
String normalizeTitle(String title) {
  var s = _foldDiacritics(title.toLowerCase());
  s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^(the|a|an)\s+'), '');
  return s;
}

/// Normalizes an author name for comparison: NFC-composed, lowercased, diacritics
/// folded, punctuation dropped, whitespace collapsed.
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
  // Compose decomposed input before the legacy fold table sees combining marks.
  for (final ch in nfc(s).split('')) {
    buf.write(_diacriticFolds[ch] ?? ch);
  }
  return buf.toString();
}
