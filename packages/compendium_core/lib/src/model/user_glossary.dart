import 'package:meta/meta.dart';

/// The kinds of entry a user's own glossary holds (#709, #1023).
///
/// Stored by [name]. Only [compound] is written today; [term] and
/// [customFigure] are reserved for #1023 so the table needs no change when
/// they arrive. A stored kind this build does not know is kept, not dropped
/// (see [UserGlossaryEntry.kind]).
enum UserGlossaryEntryKind {
  /// A named sequence of bundled figures with parameters (#709). Its payload
  /// is a `CompoundDefinition`.
  compound,

  /// A term with no figure, such as a Caller's Companion `Term` row (#1023).
  term,

  /// A user-defined figure with a text rendering formula (#1023).
  customFigure,
}

/// One entry of the user's own glossary (#709): the glossary fields every
/// entry carries, plus a kind-specific [payload].
///
/// Text fields hold canonical role tokens (`role1s`), written through the
/// user-glossary canonicalizer and rendered in the active dialect for
/// display, as the shipped definitions are.
@immutable
class UserGlossaryEntry {
  UserGlossaryEntry({
    required this.id,
    required this.kindName,
    required this.name,
    required this.definition,
    required this.description,
    List<String> keywords = const [],
    this.notes,
    this.payload,
    required this.createdAt,
  }) : keywords = List.unmodifiable(keywords);

  /// A UUID. The name is display data, not identity.
  final String id;

  /// The stored kind, kept as written so an entry of a kind this build does
  /// not know survives untouched.
  final String kindName;

  final String name;
  final String definition;
  final String description;

  /// Optional extra words the entry is found by.
  final List<String> keywords;

  final String? notes;

  /// The kind-specific payload as stored JSON (a `CompoundDefinition`'s
  /// `toJson()` for [UserGlossaryEntryKind.compound]); decoded by the reader.
  final Object? payload;

  /// When the entry was first created. Stable across edits, so of two entries
  /// sharing a name the later-created one is the one flagged for rename. The
  /// flag is the maintainer's (#709 consolidated spec, decision 6); judging
  /// "newer" by creation time is the implementer's choice, so an edit cannot
  /// change which one is flagged.
  final DateTime createdAt;

  /// The kind, or null when [kindName] is one this build does not know.
  UserGlossaryEntryKind? get kind {
    for (final kind in UserGlossaryEntryKind.values) {
      if (kind.name == kindName) return kind;
    }
    return null;
  }

  UserGlossaryEntry copyWith({
    String? name,
    String? definition,
    String? description,
    List<String>? keywords,
    String? notes,
    bool clearNotes = false,
    Object? payload,
  }) => UserGlossaryEntry(
    id: id,
    kindName: kindName,
    name: name ?? this.name,
    definition: definition ?? this.definition,
    description: description ?? this.description,
    keywords: keywords ?? this.keywords,
    notes: clearNotes ? null : (notes ?? this.notes),
    payload: payload ?? this.payload,
    createdAt: createdAt,
  );
}

/// A user's note on a shipped figure (#709), keyed by the shipped move or
/// alias id. Text holds canonical role tokens.
@immutable
class FigureNote {
  const FigureNote({required this.figureId, required this.notes});

  final String figureId;
  final String notes;
}
