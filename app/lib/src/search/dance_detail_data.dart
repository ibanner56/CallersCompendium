import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

import '../data/venue_label.dart';

/// A resolved custom-field row for display: the definition's [label] paired
/// with its already-formatted [value].
typedef CustomFieldDisplay = ({String label, String value});

/// Fully-hydrated data for the dance detail screen (`docs/design/ux.md` §2):
/// the [dance] plus the resolved author/tag names, formatted custom fields,
/// related-dance titles, cited sources, calling history, and the cross-
/// reference [DanceTitleLinker] used to link mentions of other dances.
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
    required this.callingHistory,
    required this.crossRefLinker,
    this.halfCallingStats = HalfCallingStats.empty,
    this.venueLabelsByProgramId = const {},
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;

  /// The dance's tags as `(id, name)` pairs, in [Dance.tagIds] order, for tags
  /// whose name resolves. Carries the id (unlike [tagNames]) so a tapped tag
  /// chip can drive the Collection's id-based tag filter (issue #414). Empty in
  /// the online-preview constructors (an un-imported dance has no tags to
  /// filter the local collection by).
  final List<({String id, String name})> tags;
  final List<CustomFieldDisplay> customFields;

  /// Maps targetDanceId → title for relatedDance links whose target exists.
  /// Missing entries indicate the target dance has been deleted/purged.
  final Map<String, String> relatedDanceTitles;

  /// Maps sourceId → the cited [PublishedSource] for each of the dance's
  /// [SourceCitation]s (missing entries indicate a purged source).
  final Map<String, PublishedSource> sourcesById;

  /// Programs that include this dance (derived query over program slots),
  /// most-recent first. Populated as soon as a program contains the dance;
  /// `performedAt` may be null until the separate "mark performed" path lands.
  final List<DanceCallingRecord> callingHistory;

  /// Matches other dances' titles inside this dance's free text (hook /
  /// calling notes) so they can render as tappable cross-reference links.
  final DanceTitleLinker crossRefLinker;

  /// First/second-half positional calling stats for this dance (issue #378),
  /// derived across every program that includes it. Defaults to
  /// [HalfCallingStats.empty] so the online-preview constructors need no
  /// changes; only [load] populates it via the repository. Respects
  /// [performedOnly] the same way [callingHistory] does.
  final HalfCallingStats halfCallingStats;

  /// Maps programId → the venue label to show for that program's calling-history
  /// row: the linked [Venue]'s display name when the program's `venueId`
  /// resolves, otherwise its free-text `venue`. Resolved in the app layer from
  /// the [DanceCallingRecord]'s `venueId` + `venue` against the venue catalogue
  /// (no per-program hydration). Defaults to `const {}` so the online-preview
  /// constructors need no changes; only [load] populates it. Rows fall back to
  /// the record's free-text `venue` for any program missing here.
  final Map<String, String?> venueLabelsByProgramId;

  /// Hydrates the detail data for the dance identified by [danceId] from
  /// [repos], returning `null` when no such dance exists. [performedOnly]
  /// filters the calling history to performed slots (ROADMAP G.2). Behaviour
  /// mirrors the previous inline load in `dance_detail_screen.dart`.
  static Future<DanceDetailData?> load(
    CompendiumRepositories repos,
    String danceId, {
    required bool performedOnly,
  }) async {
    final dance = await repos.dances.getById(danceId);
    if (dance == null) return null;

    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final fieldDefs = await repos.customFieldDefs.listAll();
    final choreographerNames = {for (final c in choreographers) c.id: c.name};
    final tagNames = {for (final t in tags) t.id: t.name};
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

    final callingHistory = await repos.programs.callingHistoryForDance(
      danceId,
      performedOnly: performedOnly,
    );

    // Resolve each calling-history program's venue label in the app layer.
    // Each [DanceCallingRecord] now carries both the program's free-text `venue`
    // and its linked `venueId`, so we only need the venue catalogue (one query)
    // — no per-program hydration — to apply the same [resolveVenueLabel]
    // fallback used elsewhere. Keeps venue resolution app-layer only.
    final venueLabelsByProgramId = <String, String?>{};
    if (callingHistory.isNotEmpty) {
      final venues = await repos.venues.listAll();
      final venuesById = {for (final v in venues) v.id: v};
      for (final record in callingHistory) {
        venueLabelsByProgramId[record.programId] = resolveVenueLabelParts(
          record.venueId,
          record.venue,
          venuesById,
        );
      }
    }

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
          if (tagNames[id] != null) (id: id, name: tagNames[id]!),
      ],
      customFields: [
        for (final value in dance.customFields)
          if (defsById[value.fieldId] case final def?)
            (label: def.label, value: _formatFieldValue(value.value)),
      ],
      relatedDanceTitles: relatedDanceTitles,
      sourcesById: sourcesById,
      callingHistory: callingHistory,
      crossRefLinker: crossRefLinker,
      halfCallingStats: await repos.programs.halfCallingStatsForDance(
        danceId,
        performedOnly: performedOnly,
      ),
      venueLabelsByProgramId: venueLabelsByProgramId,
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
