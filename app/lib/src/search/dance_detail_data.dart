import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import 'coalesce_trailing.dart';

/// A resolved custom-field row for display: the definition's [label] paired
/// with its already-formatted [value].
typedef CustomFieldDisplay = ({String label, String value});

/// Fully-hydrated data for the dance detail screen (`docs/design/ux.md` §2):
/// the [dance] plus the resolved author/tag names, formatted custom fields,
/// related-dance titles, cited sources, and the cross-reference
/// [DanceTitleLinker] used to link mentions of other dances.
///
/// Deliberately does NOT carry the calling history or its half-calling stats.
/// Those are program-derived, so they went stale on every program-side write
/// while everything here changes only with the dance; the detail screen's
/// `CallingHistorySection` watches them directly instead (issue #768). Loading
/// them here as well would re-run those queries on every dance-side reload for
/// a widget that ignores the result.
///
/// Extracted from `dance_detail_screen.dart`'s inline `_load()` so the load
/// logic is widget-independent and unit-testable without pumping a widget,
/// mirroring the [CollectionData] pattern in `collection_data.dart`. Behaviour
/// is identical to the previous private `_DanceDetail` + inline hydration.
class DanceDetailData {
  DanceDetailData({
    required this.dance,
    required this.authorNames,
    required this.tagNames,
    this.tags = const [],
    required this.customFields,
    required this.relatedDanceTitles,
    required this.sourcesById,
    required this.crossRefLinker,
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;

  /// The dance's tags as `(id, name, color)` triples, in [Dance.tagIds] order,
  /// for tags whose name resolves. Carries the id (unlike [tagNames]) so a
  /// tapped tag chip can drive the Collection's id-based tag filter
  /// (issue #414), and the user's chosen chip colour (issue #786), which is
  /// `null` for a tag with no colour assigned. Empty in the online-preview
  /// constructors (an un-imported dance has no tags to filter the local
  /// collection by).
  final List<({String id, String name, int? color})> tags;
  final List<CustomFieldDisplay> customFields;

  /// Maps targetDanceId → title for relatedDance links whose target exists.
  /// Missing entries indicate the target dance has been deleted/purged.
  final Map<String, String> relatedDanceTitles;

  /// Maps sourceId → the cited [PublishedSource] for each of the dance's
  /// [SourceCitation]s (missing entries indicate a purged source).
  final Map<String, PublishedSource> sourcesById;

  /// Matches other dances' titles inside this dance's free text (hook /
  /// calling notes) so they can render as tappable cross-reference links.
  final DanceTitleLinker crossRefLinker;

  /// The window used to collapse a burst of writes into one reload.
  ///
  /// Measured against the burst this consumer actually faces, not chosen for a
  /// frame budget — see [CoalesceTrailing] for why a window is required at all
  /// rather than being an optimisation.
  ///
  /// The burst here is **not** a batch of edits to the dance being shown; it is
  /// a batch of edits to *other* dances. Batch tagging in the Collection writes
  /// one dance per transaction in a loop, so tagging 50 dances is 50 commits on
  /// `dances`, and every one of them wakes this stream even though at most one
  /// touched the record on screen. Uncoalesced that is 50 full [load] runs — a
  /// fan-out across five repositories each time — behind a screen whose visible
  /// content changed at most once.
  ///
  /// 24 ms, matching the figure measured for the same 50-write batch shape on
  /// the Collection's own snapshot: inter-commit gaps of median 1.46 ms, p90
  /// 1.66 ms, max 2.36 ms on in-memory sqlite in a debug build, so the window
  /// is about 10x the widest observed gap. The measurement is of the *writer*,
  /// which is the same writer for both consumers; it is quoted rather than
  /// cited because a number that lives in another file is one this file cannot
  /// keep true.
  ///
  /// ## It is not the only thing bounding reloads, and that was measured
  ///
  /// A subscriber that maps each wake to an async load also pauses the source
  /// while that load runs, and drift collapses the updates that arrive during
  /// the pause into a single re-run on resume. So backpressure supplies a bound
  /// of its own, before this constant does anything.
  ///
  /// The figures, for a 10-write burst on in-memory sqlite in a debug build,
  /// stated as numbers so that deleting this window is a decision about a known
  /// cost rather than about a description:
  ///
  /// | burst shape | window | no window |
  /// |---|---|---|
  /// | writes awaited one at a time — the batch-tag loop's shape | **1** | **2** |
  /// | writes issued together (`Future.wait`) | 1 | 1 |
  ///
  /// So what this constant buys, on the shape the app actually produces, is the
  /// difference between one re-read and two — not between one and ten. Ten was
  /// the intuition it was nearly justified with, and it is wrong: backpressure
  /// had already collapsed the burst to two before the window saw it.
  ///
  /// The second row is the reason the first is not stated more strongly.
  /// Concurrent writes commit close enough together that drift dispatches them
  /// as one update, so there is nothing left for a window to collapse. A window
  /// cannot beat a burst the database has already merged.
  ///
  /// `dance_detail_data_watch_test.dart` asserts the first row as a strict
  /// inequality, so removing the transformer fails a test rather than quietly
  /// leaving these figures equal.
  ///
  /// Both directions of error, since an unexplained constant invites deletion:
  ///
  /// - **Too short** — it stops collapsing and the batch leaks reloads,
  ///   proportionally rather than off a cliff: a burst emits roughly
  ///   `gap / window` of its writes.
  /// - **Too long** — the tail of a burst takes longer to settle. A single
  ///   write is never delayed in either direction, because the leading edge
  ///   emits immediately; the window is only ever paid by a burst.
  ///
  /// An under-sized window costs extra loads, never correctness: every emit
  /// re-runs [load] in full, so each one carries a complete, self-consistent
  /// record.
  static const coalesceWindow = Duration(milliseconds: 24);

  /// A live [DanceDetailData] for [danceId], re-read whenever anything the
  /// dance's own record is built from changes (issue #768). Emits `null` when
  /// the dance does not exist, or has been deleted while this stream is open.
  ///
  /// ## Why this re-reads the whole record rather than streaming its parts
  ///
  /// [load] composes a fan-out across five repositories into one immutable
  /// value. Streaming each part and recombining would emit once per part per
  /// write and could render a half-updated record — an author list from before
  /// an edit beside a title from after it. Re-running the load on a single
  /// change signal keeps the value atomic and leaves [load] the only place the
  /// composition is expressed.
  ///
  /// Deliberately no query count: [load] resolves related-dance titles and
  /// cited sources with `Future.wait` over however many the dance links, and
  /// skips both entirely when it links none, so the statement count is a
  /// property of the data rather than a constant.
  ///
  /// ## What this stream deliberately does not carry
  ///
  /// Nothing program-derived. [DanceDetailData] omits calling history and its
  /// stats for that reason, and the watched set behind this stream omits
  /// `programs` and `program_slots` to match — so adding a dance to a program
  /// does not re-run this fan-out. A consumer that renders program-derived data
  /// too subscribes to it separately, at the granularity that data changes.
  ///
  /// Nothing from `settings`, either. A preference read is not part of the
  /// record, and the table is written on a debounce by an unrelated editor's
  /// autosave, so a watcher over it would wake this load twice a second while
  /// someone types elsewhere in the app.
  ///
  /// Emits an initial value immediately, so a subscriber renders without
  /// waiting for a write.
  static Stream<DanceDetailData?> watch(
    CompendiumRepositories repos,
    String danceId, {
    Duration coalesce = coalesceWindow,
  }) => repos
      .watchDanceSources()
      .transform(CoalesceTrailing<void>(coalesce))
      .asyncMap((_) => load(repos, danceId));

  /// Hydrates the detail data for the dance identified by [danceId] from
  /// [repos], returning `null` when no such dance exists.
  static Future<DanceDetailData?> load(
    CompendiumRepositories repos,
    String danceId,
  ) async {
    final dance = await repos.dances.getById(danceId);
    if (dance == null) return null;

    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final fieldDefs = await repos.customFieldDefs.listAll();
    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};
    final tagsById = {for (final t in tags) t.id: t};
    final defsById = {for (final d in fieldDefs) d.id: d};

    // Resolve titles for relatedDance links in parallel. Deduplicate via a
    // set, then materialize to a list so the id↔result association is an
    // explicit, O(1) positional index (rather than relying on set iteration
    // order and O(n) elementAt).
    final relatedDanceTitles = <String, String>{};
    final targetIds = dance.links
        .where(
          (l) => l.kind == LinkKind.relatedDance && l.targetDanceId != null,
        )
        .map((l) => l.targetDanceId!)
        .toSet()
        .toList();
    if (targetIds.isNotEmpty) {
      final fetched = await Future.wait(
        targetIds.map((id) => repos.dances.getById(id)),
      );
      for (final (i, related) in fetched.indexed) {
        if (related != null) {
          relatedDanceTitles[targetIds[i]] = related.title;
        }
      }
    }

    // Resolve the cited published sources (deduplicated) for display.
    final sourcesById = <String, PublishedSource>{};
    final citedSourceIds = dance.sourceCitations.map((c) => c.sourceId).toSet();
    if (citedSourceIds.isNotEmpty) {
      final fetched = await Future.wait(
        citedSourceIds.map((id) => repos.publishedSources.getById(id)),
      );
      for (final source in fetched) {
        if (source != null) sourcesById[source.id] = source;
      }
    }

    // Candidate cross-reference targets: every other non-deleted dance's title.
    // Loaded via the lightweight id+title query (no per-dance hydration).
    final titlePairs = await repos.dances.listIdsAndTitles();
    final crossRefLinker = DanceTitleLinker.build(
      titlePairs,
      excludeId: dance.id,
    );

    return DanceDetailData(
      dance: dance,
      authorNames: [
        for (final id in dance.authorIds)
          if (choreographerNames[id] != null) choreographerNames[id]!,
      ],
      tagNames: [
        for (final id in dance.tagIds)
          if (tagNames[id] != null) tagNames[id]!,
      ],
      tags: [
        for (final id in dance.tagIds)
          if (tagsById[id] != null)
            (id: id, name: tagsById[id]!.name, color: tagsById[id]!.color),
      ],
      customFields: [
        for (final value in dance.customFields)
          if (defsById[value.fieldId] case final def?)
            (label: def.label, value: _formatFieldValue(value.value)),
      ],
      relatedDanceTitles: relatedDanceTitles,
      sourcesById: sourcesById,
      crossRefLinker: crossRefLinker,
    );
  }
}

String _formatFieldValue(Object value) {
  if (value is bool) return value ? 'Yes' : 'No';
  return value.toString();
}

/// Indexes other dances' titles so they can be recognised inside this dance's
/// free text (hook / calling notes) and rendered as tappable cross-reference
/// links.
///
/// Matching is case-insensitive, on word boundaries (a title inside a larger
/// word is not matched), and longest-title-wins when several candidate titles
/// could match at the same position. Titles are treated as literal text
/// (regex-special characters are escaped).
class DanceTitleLinker {
  DanceTitleLinker._(this._pattern, this._idByNormalizedTitle);

  /// `null` when there are no candidate titles to match.
  final RegExp? _pattern;

  /// Maps a lower-cased title to the id of the dance it refers to. When two
  /// dances share a title the first (title-sorted) one wins — the input is
  /// pre-sorted by title so this is deterministic.
  final Map<String, String> _idByNormalizedTitle;

  /// Builds a linker from `(id, title)` pairs, excluding [excludeId] (never
  /// self-link) and skipping empty / whitespace-only titles.
  factory DanceTitleLinker.build(
    List<({String id, String title})> pairs, {
    required String excludeId,
  }) {
    final idByNormalized = <String, String>{};
    final titles = <String>[];
    for (final pair in pairs) {
      if (pair.id == excludeId) continue;
      final trimmed = pair.title.trim();
      if (trimmed.isEmpty) continue;
      final normalized = trimmed.toLowerCase();
      // First occurrence wins (input is title-sorted → deterministic).
      if (idByNormalized.containsKey(normalized)) continue;
      idByNormalized[normalized] = pair.id;
      titles.add(trimmed);
    }

    if (titles.isEmpty) {
      return DanceTitleLinker._(null, idByNormalized);
    }

    // Longest-first so the alternation prefers the longest match at a given
    // position (Dart's RegExp is leftmost / first-alternative-wins, not POSIX
    // longest). Escape each title so punctuation / regex metacharacters are
    // treated literally.
    titles.sort((a, b) => b.length.compareTo(a.length));
    final alternation = titles.map(RegExp.escape).join('|');
    // Alphanumeric look-arounds give word-boundary behavior that is robust to
    // titles that themselves begin or end with punctuation (plain `\b` is not).
    final pattern = RegExp(
      r'(?<![\p{L}\p{N}])(?:'
      '$alternation'
      r')(?![\p{L}\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
    return DanceTitleLinker._(pattern, idByNormalized);
  }

  /// Splits [text] into inline spans, wrapping each matched dance title in a
  /// tappable link span (via [buildLink]) and leaving all other text plain
  /// (styled with [baseStyle]). Returns a single plain span when nothing
  /// matches so callers can keep rendering unchanged text as-is.
  List<InlineSpan> spansFor(
    String text, {
    required TextStyle? baseStyle,
    required InlineSpan Function(String matchedText, String danceId) buildLink,
  }) {
    final pattern = _pattern;
    if (pattern == null || text.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }

    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      final id = _idByNormalizedTitle[match[0]!.toLowerCase()];
      if (id == null) continue;
      if (match.start > index) {
        spans.add(
          TextSpan(text: text.substring(index, match.start), style: baseStyle),
        );
      }
      spans.add(buildLink(match[0]!, id));
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: baseStyle));
    }
    return spans;
  }

  /// Whether any candidate titles exist (used to short-circuit rendering).
  bool get hasTitles => _pattern != null;
}
