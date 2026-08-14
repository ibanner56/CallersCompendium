import 'package:compendium_core/compendium_core.dart';

import 'coalesce_trailing.dart';

/// The reference/vocabulary data `DanceEditorScreen` needs beside its own
/// draft: every choreographer, tag, dance (for the related-dance picker and
/// link titles) and published source, plus id→name/record lookups derived
/// from them.
///
/// Extracted from `dance_editor_screen.dart`'s inline `_load()` so the load
/// logic is widget-independent and unit-testable without pumping a widget,
/// mirroring the [DanceDetailData] pattern in `dance_detail_data.dart`.
/// Composed as one atomic value for the same reason as that type: recombining
/// independently-streamed parts could render a half-updated screen (an author
/// list from before an edit beside a dance list from after it).
///
/// Deliberately does NOT carry anything the editor treats as draft state —
/// `fieldDefs` (custom field definitions) or the dance being edited itself.
/// Those are loaded once by the screen and handed to `DanceEditorController`,
/// which owns the mutable working draft; re-seeding either from a stream
/// would duplicate controllers or discard in-progress edits (issue #768).
class DanceEditorReferenceData {
  DanceEditorReferenceData({
    required this.choreographers,
    required this.tags,
    required this.dances,
    required this.publishedSources,
  });

  final List<Choreographer> choreographers;
  final List<Tag> tags;

  /// Every non-deleted dance. Feeds the related-dance picker (which needs the
  /// full set) and [danceNamesById] (link display titles); there is no
  /// narrower read that serves the picker.
  final List<Dance> dances;
  final List<PublishedSource> publishedSources;

  Map<String, String> get choreographerNames => {
    for (final c in choreographers) c.id: c.name,
  };

  Map<String, String> get tagNames => {for (final t in tags) t.id: t.name};

  Map<String, String> get danceNamesById => {
    for (final d in dances) d.id: d.title,
  };

  Map<String, PublishedSource> get sourcesById => {
    for (final s in publishedSources) s.id: s,
  };

  /// The window used to collapse a burst of writes into one reload.
  ///
  /// Matches [DanceDetailData.coalesceWindow]: both consumers watch
  /// [CompendiumRepositories.watchDanceSources], and the batch shape that
  /// justifies the window (a Collection batch-tag loop writing one dance per
  /// commit) is the same writer for both. See that constant for the measured
  /// figures; quoted rather than duplicated in comments because a number that
  /// lives in another file is one this file cannot keep true.
  static const coalesceWindow = Duration(milliseconds: 24);

  /// A live [DanceEditorReferenceData], re-read whenever anything the editor's
  /// reference data is built from changes (issue #768). Reuses
  /// [CompendiumRepositories.watchDanceSources] rather than a dedicated
  /// sentinel: the editor's read set — choreographers, tags, dances, published
  /// sources — is entry-for-entry identical to that method's declared set
  /// (including its omission of `programs`/`program_slots`, since the editor
  /// renders nothing program-derived, and `venues`, since a dance record
  /// carries none). A second sentinel reading the same table set would add a
  /// new `StreamKey` collision surface for no additional coverage.
  ///
  /// Emits an initial value immediately, so a subscriber renders without
  /// waiting for a write.
  static Stream<DanceEditorReferenceData> watch(
    CompendiumRepositories repos, {
    Duration coalesce = coalesceWindow,
  }) => repos
      .watchDanceSources()
      .transform(CoalesceTrailing<void>(coalesce))
      .asyncMap((_) => load(repos));

  /// Loads the current reference data from [repos].
  static Future<DanceEditorReferenceData> load(
    CompendiumRepositories repos,
  ) async {
    final choreographers = await repos.choreographers.listAll();
    final tags = await repos.tags.listAll();
    final dances = await repos.dances.listAll();
    final publishedSources = await repos.publishedSources.listAll();
    return DanceEditorReferenceData(
      choreographers: choreographers,
      tags: tags,
      dances: dances,
      publishedSources: publishedSources,
    );
  }
}
