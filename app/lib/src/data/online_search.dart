import 'package:compendium_core/compendium_core.dart';

import '../search/dance_detail_data.dart';
import 'import_io.dart' show CallersBoxPhraseQuery;

/// Which online search source a query/result/preview belongs to.
///
/// Both online sources (The Caller's Box and ContraDB) are exposed through the
/// same source-neutral seam ([OnlineSearchService]); this enum is the single
/// place that carries their per-source differences — the selector [label] and
/// the [supportsByPhrase] capability that gates the by-phrase panel (ContraDB
/// search is title-only). The user-facing per-source attribution line is
/// localized separately by `onlineSourceAttribution` in `online_search_labels`.
enum OnlineSource {
  callersBox(label: "Caller's Box", supportsByPhrase: true),
  contraDb(label: 'ContraDB', supportsByPhrase: false);

  const OnlineSource({required this.label, required this.supportsByPhrase});

  /// Short name for the source selector (e.g. the SegmentedButton segment).
  final String label;

  /// Whether this source accepts by-phrase figure criteria. The Caller's Box
  /// maps by-phrase onto its own "search by phrase" fields; ContraDB's public
  /// search API is title-only, so its by-phrase panel is hidden.
  final bool supportsByPhrase;
}

/// A source-neutral online search result row.
///
/// The pure per-source parsers (`parseCallersBoxSearchResults` /
/// `parseContraDbSearchResults`) still produce their own value types; each
/// [OnlineSearchService] maps them onto this shared shape so the widget layer
/// (`OnlineResultTile`) and the screen state are source-agnostic. The [id]
/// bridges search → import (the source's per-dance URL is built from it).
class OnlineSearchResultRow {
  const OnlineSearchResultRow({
    required this.source,
    required this.id,
    required this.name,
    required this.author,
    required this.formation,
  });

  /// Which source this row came from (drives the attribution line).
  final OnlineSource source;

  /// The source's dance id (numeric string); bridges to the import URL.
  final String id;

  /// Dance title.
  final String name;

  /// Choreographer / author; may be empty.
  final String author;

  /// Formation / start type; may be empty.
  final String formation;

  @override
  bool operator ==(Object other) =>
      other is OnlineSearchResultRow &&
      other.source == source &&
      other.id == id &&
      other.name == name &&
      other.author == author &&
      other.formation == formation;

  @override
  int get hashCode => Object.hash(source, id, name, author, formation);

  @override
  String toString() =>
      'OnlineSearchResultRow(source: $source, id: $id, name: $name, '
      'author: $author, formation: $formation)';
}

/// A source-neutral online search request.
///
/// [title] is the substring/title query. [phrases] carries by-phrase figure
/// criteria for sources that support them ([OnlineSource.supportsByPhrase]);
/// title-only sources ignore it.
class OnlineSearchQuery {
  const OnlineSearchQuery({required this.title, this.phrases});

  final String title;
  final CallersBoxPhraseQuery? phrases;
}

/// What a direct online import ended up doing (drives the result snackbar).
enum OnlineImportKind {
  /// A brand-new dance was written to the collection.
  created,

  /// The exact online dance was already imported before; nothing written.
  alreadyInCollection,

  /// A confident title+author match exists in the collection with differing
  /// figures; nothing was written. The caller must show a resolution dialog
  /// and retry [OnlineSearchService.import] with [ambiguousResolution] set
  /// (issue #797). [OnlineImportResult.danceId] holds the existing dance's id
  /// so the dialog can display its title.
  needsConfirmation,
}

/// Outcome of [OnlineSearchService.import].
class OnlineImportResult {
  const OnlineImportResult({
    required this.kind,
    required this.title,
    this.danceId,
    this.danceCount = 1,
  });

  final OnlineImportKind kind;
  final String title;

  /// Id of the imported dance for [OnlineImportKind.created], or the id of the
  /// existing matching dance for [OnlineImportKind.alreadyInCollection] when it
  /// can be resolved. `null` when no dance id is available.
  final String? danceId;

  /// Number of dances this import created or matched. Always `1` for the
  /// single-dance online-preview flow; the UI auto-opens the imported dance
  /// ONLY when this is exactly `1`.
  final int danceCount;
}

/// An online dance loaded for preview in the detail pane, plus the planned
/// import decision so the Import button can commit it without re-fetching.
class OnlinePreview {
  const OnlinePreview({
    required this.result,
    required this.detail,
    required this.plan,
  });

  final OnlineSearchResultRow result;

  /// Detail data for the (non-persisted) online dance, ready for
  /// `DanceDetailScreen.preview`.
  final DanceDetailData detail;

  /// The dedup-aware plan (draft + verdict) for this dance.
  final ImportRecordPlan plan;

  /// Whether the exact online dance is already in the local collection (an
  /// exact `(source, externalId)` re-import match).
  bool get alreadyInCollection => plan.verdict.kind == DedupeKind.reimport;
}

/// Source-neutral contract for an online search + direct-import source.
///
/// Both `CallersBoxOnline` and `ContraDbOnline` implement this so the screen /
/// shell can drive either interchangeably: run a [search], [loadPreview] a
/// tapped row, then [import] the previewed plan.
abstract interface class OnlineSearchService {
  /// Which source this service talks to.
  OnlineSource get source;

  /// Searches the source and returns source-neutral result rows. Throws a
  /// `UrlFetchException` (message safe to show) on any fetch failure or when
  /// there is nothing to search.
  Future<List<OnlineSearchResultRow>> search(OnlineSearchQuery query);

  /// Fetches the tapped [result]'s full record and builds an [OnlinePreview]
  /// (detail data + dedupe plan). Throws a `UrlFetchException` on a fetch
  /// failure or when the dance can't be parsed.
  Future<OnlinePreview> loadPreview(
    CompendiumRepositories repos,
    OnlineSearchResultRow result, {
    DateTime? now,
  });

  /// Commits [plan] into the local collection (dedup-aware, single dance).
  ///
  /// Returns [OnlineImportKind.needsConfirmation] without writing anything
  /// when a confident title+author match already exists with differing figures
  /// and no [ambiguousResolution] has been supplied. The caller must show a
  /// resolution dialog and retry with [ambiguousResolution] set (issue #797).
  Future<OnlineImportResult> import(
    CompendiumRepositories repos,
    ImportRecordPlan plan, {
    DateTime? now,
    DedupeResolution? ambiguousResolution,
  });
}
