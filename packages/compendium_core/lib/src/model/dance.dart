import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'custom_field.dart';
import 'dance_link.dart';
import 'enums.dart';
import 'figure.dart';
import 'formation.dart';
import 'phrase_structure.dart';
import 'provenance.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// A dance transcription — the central entity of the collection.
///
/// Hard invariants (thrown at construction): non-empty title, parseable
/// phrase structure. The figure list may be empty (metadata-only stubs are
/// legitimate imports). Softer, musical concerns surface via [validate].
@immutable
class Dance {
  Dance({
    required this.id,
    required this.title,
    List<String> authorIds = const [],
    this.form = DanceForm.contra,
    this.formation = const Formation(FormationShape.dupleImproper),
    this.progression = Progression.single,
    String phraseStructure = '',
    List<Figure> figures = const [],
    this.hook = '',
    this.callingNotes = '',
    this.status = DanceStatus.active,
    List<String> tunes = const [],
    List<CustomFieldValue> customFields = const [],
    List<String> tagIds = const [],
    List<DanceLink> links = const [],
    this.provenance,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  }) : authorIds = List.unmodifiable(authorIds),
       // Parse eagerly so an invalid structure fails at construction.
       phraseStructure = PhraseStructure.parse(phraseStructure),
       figures = List.unmodifiable(figures),
       tunes = List.unmodifiable(tunes),
       customFields = List.unmodifiable(customFields),
       tagIds = List.unmodifiable(tagIds),
       links = List.unmodifiable(links) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must be non-empty');
    }
  }

  final String id;
  final String title;

  /// Ordered Choreographer ids ("Traditional"/"Unknown" are real rows).
  final List<String> authorIds;
  final DanceForm form;
  final Formation formation;
  final Progression progression;
  final PhraseStructure phraseStructure;

  /// The transcription: an ordered figure list (may be empty for stubs).
  final List<Figure> figures;

  /// One-line "why call this" description.
  final String hook;

  /// Teaching/history notes; dialect-aware free text.
  final String callingNotes;
  final DanceStatus status;
  final List<String> tunes;
  final List<CustomFieldValue> customFields;
  final List<String> tagIds;
  final List<DanceLink> links;
  final Provenance? provenance;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft delete marker; program slots referencing a deleted dance stay
  /// valid and render a tombstone in the UI.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// Figures annotated with derived phrase labels (A1, B2, …).
  List<SectionedFigure> get sectionedFigures =>
      deriveSections(figures, phraseStructure);

  /// Runs warning-level validation (e.g. phrase overflow). Structural
  /// invariants are enforced at construction and never appear here.
  List<ValidationIssue> validate() {
    final issues = <ValidationIssue>[];
    deriveSections(figures, phraseStructure, issues: issues);
    return issues;
  }

  Dance copyWith({
    String? title,
    List<String>? authorIds,
    DanceForm? form,
    Formation? formation,
    Progression? progression,
    String? phraseStructure,
    List<Figure>? figures,
    String? hook,
    String? callingNotes,
    DanceStatus? status,
    List<String>? tunes,
    List<CustomFieldValue>? customFields,
    List<String>? tagIds,
    List<DanceLink>? links,
    Provenance? provenance,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Dance(
    id: id,
    title: title ?? this.title,
    authorIds: authorIds ?? this.authorIds,
    form: form ?? this.form,
    formation: formation ?? this.formation,
    progression: progression ?? this.progression,
    phraseStructure: phraseStructure ?? this.phraseStructure.raw,
    figures: figures ?? this.figures,
    hook: hook ?? this.hook,
    callingNotes: callingNotes ?? this.callingNotes,
    status: status ?? this.status,
    tunes: tunes ?? this.tunes,
    customFields: customFields ?? this.customFields,
    tagIds: tagIds ?? this.tagIds,
    links: links ?? this.links,
    provenance: provenance ?? this.provenance,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  /// A duplicate with a new identity, suitable for "duplicate dance":
  /// same content, fresh id/timestamps, provenance dropped (the copy is the
  /// user's own editable record).
  Dance duplicate({required String newId, required DateTime now}) => Dance(
    id: newId,
    title: title,
    authorIds: authorIds,
    form: form,
    formation: formation,
    progression: progression,
    phraseStructure: phraseStructure.raw,
    figures: figures,
    hook: hook,
    callingNotes: callingNotes,
    status: status,
    tunes: tunes,
    customFields: customFields,
    tagIds: tagIds,
    links: links,
    createdAt: now,
    updatedAt: now,
  );

  @override
  bool operator ==(Object other) =>
      other is Dance &&
      other.id == id &&
      other.title == title &&
      _listEq.equals(other.authorIds, authorIds) &&
      other.form == form &&
      other.formation == formation &&
      other.progression == progression &&
      other.phraseStructure == phraseStructure &&
      _listEq.equals(other.figures, figures) &&
      other.hook == hook &&
      other.callingNotes == callingNotes &&
      other.status == status &&
      _listEq.equals(other.tunes, tunes) &&
      _listEq.equals(other.customFields, customFields) &&
      _listEq.equals(other.tagIds, tagIds) &&
      _listEq.equals(other.links, links) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, title, updatedAt);

  @override
  String toString() => 'Dance($title)';
}
