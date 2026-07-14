import 'package:compendium_core/compendium_core.dart';

/// A minimal, valid [Dance] fixture for storage tests. Override any field
/// via the named parameters.
Dance sampleDance({
  String id = 'dance-1',
  String title = 'Chase the Squirrel',
  List<String> authorIds = const [],
  List<Figure>? figures,
  List<CustomFieldValue> customFields = const [],
  List<String> tagIds = const [],
  List<DanceLink> links = const [],
  List<SourceCitation> sourceCitations = const [],
  Provenance? provenance,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Dance(
    id: id,
    title: title,
    authorIds: authorIds,
    figures:
        figures ??
        [
          Figure(move: 'swing', params: const {'who': 'partners', 'beats': 8}),
          Figure(move: 'balance', params: const {'who': 'neighbors'}),
        ],
    hook: 'A fun beginner dance',
    callingNotes: 'Teach the swing carefully.',
    customFields: customFields,
    tagIds: tagIds,
    links: links,
    sourceCitations: sourceCitations,
    provenance: provenance,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    deletedAt: deletedAt,
  );
}
