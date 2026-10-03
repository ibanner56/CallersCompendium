import 'package:meta/meta.dart';
import 'package:unorm_dart/unorm_dart.dart';

import '../model/dance.dart';
import '../model/enums.dart';
import '../serialization/archive_entity_codec.dart';

const _choreographyFields = [
  'form',
  'formation',
  'progression',
  'phraseStructure',
  'figures',
  'hook',
  'callingNotes',
  'difficultyLevelId',
  'mixedLevel',
  'mixer',
  'tunes',
  // Without these, a dance whose transcription or tune list could not be
  // decoded fingerprints as `figures: []` / `tunes: []` — identical to a dance
  // that genuinely has none. Two dances with different content would then match
  // as the same choreography, and `autoResolveAmbiguous` links them confidently
  // with no user present. "Cannot read it" must not compare equal to "it is
  // empty", here least of all: this fingerprint decides identity.
  //
  // `figuresRaw` is included for the same reason and closes the same hole for
  // #1382's case, which shipped without it.
  'figuresRaw',
  'tunesRaw',
];

/// Returns the intrinsic choreography values shared by import and sync dedupe.
///
/// [body] is an archive-shaped dance body, including a sync body after its
/// shareable projection. Identity, provenance, timestamps, collections, and
/// other device-local metadata are deliberately excluded. The ordered list
/// keeps the field contract in one place while callers choose the equality or
/// hashing strategy appropriate to their boundary.
List<Object?> choreographyFingerprint(Map<String, Object?> body) => [
  for (final field in _choreographyFields) body[field],
];

/// Returns the same choreography fingerprint for a model used by imports.
///
/// Building the archive-shaped body here keeps import matching in lockstep
/// with the body Device Sync groups, rather than maintaining a second field
/// list or figure serialization.
///
/// The collections are emptied first. None of them appears in
/// [_choreographyFields], and encoding them is not free of consequence:
/// `archiveCustomFieldValueToJson` throws [ArchiveEncodingException] on a
/// non-finite number, which would turn this predicate — called in a candidate
/// loop that does not expect it to throw — into an abort. Dropping them also
/// keeps the per-comparison cost to the fields actually compared.
List<Object?> choreographyFingerprintForDance(Dance dance) =>
    choreographyFingerprint(
      archiveDanceToJson(
        dance.copyWith(
          customFields: const [],
          links: const [],
          sourceCitations: const [],
          clearProvenance: true,
        ),
        const {},
        includeOptionalFields: true,
      ),
    );

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
/// collection before a batch, then reuses it across the batch. Each entry's
/// title and author names are normalized once, at construction, so a query
/// only normalizes its own inputs.
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
      final nTitle = normalizeTitle(e.title);
      // Never `''`: an empty normalized title is never scored, so it must not
      // be reachable through the exact-title map either.
      if (nTitle.isNotEmpty) {
        (_byNormalizedTitle[nTitle] ??= []).add(_normalized.length);
      }
      _normalized.add((
        danceId: e.danceId,
        normalizedTitle: nTitle,
        normalizedAuthors: e.authorNames.map(normalizeAuthor).toSet()
          ..remove(''),
      ));
    }
  }

  final List<DedupeEntry> _entries;

  /// Normalized title and author set per entry, parallel to [_entries]. An
  /// empty `normalizedTitle` marks an entry that is never scored.
  final List<_NormalizedEntry> _normalized = [];
  final Map<String, String> _byExternalKey = {};

  /// Normalized (non-empty) title → ascending indices into [_normalized] of
  /// the entries carrying it. Every [DedupeCandidate.confident] match comes
  /// from here, since confidence requires an exact normalized-title match.
  final Map<String, List<int>> _byNormalizedTitle = {};

  /// Snapshot of every choreographer at the time this index was built
  /// (normalized name → id), incidentally captured from the same collection
  /// load that produced [_entries]'s author names. Lets [ImportPipeline.commit]
  /// reuse this instead of a second `listAll()` — see
  /// [ImportPipeline.buildDedupeIndex] and [ImportPipeline.commit].
  final Map<String, String> choreographerIdByNormalizedName;

  /// The precomputed normalized form of every entry; exists so tests can pin
  /// the shape without reaching into private state.
  @visibleForTesting
  List<
    ({String danceId, String normalizedTitle, Set<String> normalizedAuthors})
  >
  get normalizedEntriesForTesting => List.unmodifiable(_normalized);

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
  ///
  /// An empty normalized title ([normalizeTitle] folds every non-Latin or
  /// punctuation-only title to `''`) never matches, at any [threshold]:
  /// [_similarity] scores an empty side `0.0`, but [_combinedScore] still adds
  /// an author-only contribution when both sides declare authors, which a
  /// caller-supplied `threshold` of `0` (or as high as `0.2`) would surface as
  /// a candidate despite the titles carrying no identity signal at all. A
  /// query or candidate with an empty normalized title is therefore skipped
  /// before scoring, independent of tuning.
  List<DedupeCandidate> fuzzyMatches(
    String title,
    Iterable<String> authorNames, {
    double threshold = defaultThreshold,
  }) {
    final nTitle = normalizeTitle(title);
    final nAuthors = authorNames.map(normalizeAuthor).toSet()..remove('');
    if (nTitle.isEmpty) return const [];
    final out = <DedupeCandidate>[];
    // Entries sharing the query's normalized title are always scored: they are
    // the only possible confident matches. They are visited in entry order,
    // merged into the scan below, so the candidate order (and thus the order of
    // equal scores after the sort) is exactly that of a plain scan.
    final exact = _byNormalizedTitle[nTitle] ?? const <int>[];
    var nextExact = 0;
    // Length bound for every other entry. Levenshtein distance is at least the
    // length difference, so with la = |nTitle|, lb = |eTitle| and
    // d = |la - lb|, `titleSim = 1 - dist / max(la, lb) <= 1 - d / max(la, lb)`
    // (floating-point division and subtraction are monotone, so this holds for
    // the computed values too). The combined score is then at most
    // `titleSim * 0.8 + 0.2` when both author sets are non-empty (Jaccard is at
    // most 1) and exactly `titleSim` otherwise. A pair whose bound is under
    // [threshold] could never have reached it, and is not confident (its
    // titles differ), so skipping it cannot change the result.
    final queryHasAuthors = nAuthors.isNotEmpty;
    for (var i = 0; i < _normalized.length; i++) {
      final e = _normalized[i];
      final eTitle = e.normalizedTitle;
      if (eTitle.isEmpty) continue;
      final eAuthors = e.normalizedAuthors;
      if (nextExact < exact.length && exact[nextExact] == i) {
        nextExact++;
      } else {
        final la = nTitle.length;
        final lb = eTitle.length;
        final diff = la > lb ? la - lb : lb - la;
        final maxLen = la > lb ? la : lb;
        final titleBound = 1.0 - diff / maxLen;
        final bound = queryHasAuthors && eAuthors.isNotEmpty
            ? titleBound * 0.8 + 1.0 * 0.2
            : titleBound;
        if (bound < threshold) continue;
      }
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
  ///
  /// [priorExternalIds] are keys an earlier adapter version recorded the same
  /// record under (`RawRecord.priorExternalIds`); each is tried, in order, only
  /// when [externalId] itself has no match, so a library that imported under
  /// the old key still gets a [DedupeKind.reimport] rather than a duplicate.
  DedupeVerdict verdictFor({
    required ProvenanceSource source,
    String? externalId,
    Iterable<String> priorExternalIds = const [],
    required String title,
    Iterable<String> authorNames = const [],
    double threshold = defaultThreshold,
  }) {
    final exact = findByExternalId(source, externalId);
    if (exact != null) return DedupeVerdict.reimport(exact);
    for (final prior in priorExternalIds) {
      final legacy = findByExternalId(source, prior);
      if (legacy != null) return DedupeVerdict.reimport(legacy);
    }
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

typedef _NormalizedEntry = ({
  String danceId,
  String normalizedTitle,
  Set<String> normalizedAuthors,
});

final RegExp _nonAlphanumericRe = RegExp(r'[^a-z0-9\s]');
final RegExp _whitespaceRe = RegExp(r'\s+');
final RegExp _leadingArticleRe = RegExp(r'^(the|a|an)\s+');

/// Normalizes a dance title for comparison: NFC-composed, lowercased, diacritics
/// folded, punctuation dropped, whitespace collapsed, and a single leading
/// article (`the`/`a`/`an`) removed.
String normalizeTitle(String title) {
  var s = _foldDiacritics(title.toLowerCase());
  s = s.replaceAll(_nonAlphanumericRe, ' ');
  s = s.replaceAll(_whitespaceRe, ' ').trim();
  s = s.replaceFirst(_leadingArticleRe, '');
  return s;
}

/// Normalizes an author name for comparison: NFC-composed, lowercased, diacritics
/// folded, punctuation dropped, whitespace collapsed.
String normalizeAuthor(String name) {
  var s = _foldDiacritics(name.toLowerCase());
  s = s.replaceAll(_nonAlphanumericRe, ' ');
  return s.replaceAll(_whitespaceRe, ' ').trim();
}

/// Jaccard similarity of two string sets (`0.0..1.0`); empty∩empty is 1.0.
double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final inter = a.intersection(b).length;
  final union = a.union(b).length;
  return union == 0 ? 0.0 : inter / union;
}

/// Normalized Levenshtein similarity (`0.0..1.0`) between two strings.
///
/// An empty side scores 0.0 *before* the equality check: [normalizeTitle]
/// folds every non-Latin or punctuation-only title to `''`, and `'' == ''`
/// would otherwise score two unrelated dances 1.0 — making every such dance
/// an "ambiguous" match for every other one. An empty normalized title carries
/// no identity signal, so it is not scored at all.
double _similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0.0;
  if (a == b) return 1.0;
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
