import 'package:compendium_core/compendium_core.dart';

/// A [Dance] plus everything the Collection list needs to render/sort/filter
/// it without re-querying repositories per row (authors and tags resolved
/// to names, last-called date looked up once for the whole list).
class DanceListEntry {
  DanceListEntry({
    required this.dance,
    required this.authorNames,
    required this.tagNames,
    this.tags = const [],
    required this.listCustomFields,
    required this.callCounts,
    this.lastCalled,
  });

  final Dance dance;
  final List<String> authorNames;
  final List<String> tagNames;

  /// The dance's tags as `(id, name, color)` triples, in [Dance.tagIds] order,
  /// for tags whose name resolves. Carries the id (unlike [tagNames]) so a
  /// tapped tag chip in a list row can drive the Collection's id-based tag
  /// filter (issue #414), and the user's chosen chip colour (issue #786), which
  /// is `null` for a tag with no colour assigned.
  final List<({String id, String name, int? color})> tags;

  /// `showInList` custom field values as `label: display value` pairs, in
  /// [CustomFieldDef] declaration order.
  final List<String> listCustomFields;

  /// How many times this dance has been called (all vs. performed-only),
  /// loaded once for the whole list. Drives the "called ×N" chip; the tile
  /// picks the tally matching the active "Require mark-performed" setting.
  final DanceCallCounts callCounts;
  final DateTime? lastCalled;

  String get title => dance.title;
}
