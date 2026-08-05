import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'custom_field.dart';
import 'dance_link.dart';
import 'enums.dart';
import 'figure.dart';
import 'formation.dart';
import 'partial_date.dart';
import 'phrase_structure.dart';
import 'provenance.dart';
import 'source_citation.dart';
import '../util/uuid.dart';

const ListEquality<Object?> _listEq = ListEquality<Object?>();

/// Upper bound on the length of [Dance.walkthrough], in UTF-16 code units.
///
/// The walkthrough is free text that travels through backup / share / import of
/// files originating on the internet or from other users, so it needs a defence
/// against unbounded input (memory / render-time DoS). The limit is deliberately
/// generous — real walkthroughs run to a few thousand characters — while still
/// bounding a hostile payload. Enforcement is intentionally *soft*: the editor
/// caps input via `maxLength`, and the deserializer **clamps** (truncates)
/// rather than rejecting, consistent with the archive codec's partial-failure
/// tolerance, so an oversized field can never fail an otherwise-valid import.
const int kMaxWalkthroughLength = 20000;

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
    this.walkthrough = '',
    this.status = DanceStatus.active,
    this.level,
    this.mixedLevel = false,
    this.mixer = false,
    this.rating,
    List<String> tunes = const [],
    List<CustomFieldValue> customFields = const [],
    List<String> tagIds = const [],
    List<DanceLink> links = const [],
    List<SourceCitation> sourceCitations = const [],
    this.provenance,
    this.composedOn,
    this.revisedOn,
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
       links = List.unmodifiable(links),
       sourceCitations = List.unmodifiable(sourceCitations) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must be non-empty');
    }
    _validateRating(rating);
  }

  /// Validates the optional [rating]: `null` (unrated) is always allowed;
  /// otherwise it must be an integer star rating on the closed `1..5` scale.
  /// Anything out of range (`0`, `6`, negatives) fails at construction so an
  /// invalid rating can never be persisted.
  static void _validateRating(int? rating) {
    if (rating != null && (rating < 1 || rating > 5)) {
      throw ArgumentError.value(rating, 'rating', 'must be null or 1..5');
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

  /// A free-form, step-by-step **walkthrough** of the dance — descriptions of
  /// each move and the transitions between them — kept deliberately distinct
  /// from the short reminder-style [callingNotes]. Dialect-aware free text
  /// (rendered via the domain renderer's `renderFreeText`), typically long
  /// (hundreds to a few thousand characters). Defaults to `''` (unwritten), so
  /// existing/imported dances stay valid. Plain multi-line text in v1; richer
  /// structure / auto-generation is tracked separately (issue #411).
  final String walkthrough;
  final DanceStatus status;

  /// Difficulty on the ordered [DanceLevel] scale; `null` when unspecified
  /// (existing/imported dances stay valid). Distinct from [mixedLevel].
  final DanceLevel? level;

  /// Marks an event/dance that spans the difficulty scale rather than sitting
  /// at a single [level]. Kept separate from [level] so the ordered scale
  /// stays total for `lte`/`gte` search comparisons.
  final bool mixedLevel;

  /// Whether this is a **mixer**: a dance in which you change partners each
  /// time through, ending with a new partner.
  ///
  /// Modelled as a boolean **orthogonal to [formation]**, not as a
  /// [FormationShape] value, because mixer-ness and formation are genuinely
  /// independent — the same argument the [DanceLevel] doc makes for
  /// [mixedLevel]. This was measured, not assumed. Over The Caller's Box mirror
  /// (24,107 files), 830 dances have `Mixer? = Yes`, yet only 654 of them are in
  /// a mixer-named formation and 176 are in some other formation (Duple Minor –
  /// Improper, Becket, Triplet, Three Facing Three, Circle of Threesomes, …).
  /// Conversely 628 dances *in* a mixer-named formation are NOT mixers — 589 of
  /// them Sicilian Circles. Folding mixer into [FormationShape] would therefore
  /// be wrong in both directions, so it lives here as a flag beside the
  /// formation, exactly as The Caller's Box models it. Defaults to `false`
  /// (existing/imported dances stay valid).
  final bool mixer;

  /// Curatorial star rating on the closed `1..5` scale; `null` when unrated
  /// (existing/imported dances stay valid). A first-class scalar column
  /// (validated at the [Dance] boundary), not an enum and not a custom field —
  /// mirrors the CC-parity `Rating`. Higher is better.
  final int? rating;

  final List<String> tunes;
  final List<CustomFieldValue> customFields;
  final List<String> tagIds;
  final List<DanceLink> links;

  /// Citations of reusable [PublishedSource]s (book/collection provenance with
  /// optional page/number), distinct from bare-URL [links]. Ordered.
  final List<SourceCitation> sourceCitations;
  final Provenance? provenance;

  /// When the dance was *composed* by its author, at whatever precision is
  /// known (year / year+month / full date). Bibliographic/authorship metadata,
  /// deliberately distinct from the record stamp [createdAt]; `null` when
  /// unknown.
  final PartialDate? composedOn;

  /// When the dance was last *revised* by its author, at whatever precision is
  /// known. Distinct from the record stamp [updatedAt]; `null` when unknown.
  final PartialDate? revisedOn;

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
    final composed = composedOn;
    final revised = revisedOn;
    // Warn only when the *latest* the revision could have happened is still
    // strictly before the *earliest* the composition could have happened, so
    // overlapping partial precisions (e.g. composed 1989-03, revised 1989)
    // never trip a false warning.
    if (composed != null &&
        revised != null &&
        revised.latestDay.isBefore(composed.earliestDay)) {
      issues.add(
        ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'revised_before_composed',
          message:
              'Revised date (${revised.serialize()}) is before the composed '
              'date (${composed.serialize()}).',
        ),
      );
    }
    return issues;
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields use the clear-flag pattern (precedent: [clearDeletedAt]):
  /// pass `clearLevel: true` to set [level] back to `null`. A set clear flag
  /// **wins** over any value passed for the same field, so
  /// `copyWith(level: DanceLevel.advanced, clearLevel: true)` clears it. The
  /// same holds for `clearComposedOn` / `clearRevisedOn` / `clearRating` /
  /// `clearProvenance`.
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
    String? walkthrough,
    DanceStatus? status,
    DanceLevel? level,
    bool clearLevel = false,
    bool? mixedLevel,
    bool? mixer,
    int? rating,
    bool clearRating = false,
    List<String>? tunes,
    List<CustomFieldValue>? customFields,
    List<String>? tagIds,
    List<DanceLink>? links,
    List<SourceCitation>? sourceCitations,
    Provenance? provenance,
    bool clearProvenance = false,
    PartialDate? composedOn,
    bool clearComposedOn = false,
    PartialDate? revisedOn,
    bool clearRevisedOn = false,
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
    walkthrough: walkthrough ?? this.walkthrough,
    status: status ?? this.status,
    level: clearLevel ? null : (level ?? this.level),
    mixedLevel: mixedLevel ?? this.mixedLevel,
    mixer: mixer ?? this.mixer,
    rating: clearRating ? null : (rating ?? this.rating),
    tunes: tunes ?? this.tunes,
    customFields: customFields ?? this.customFields,
    tagIds: tagIds ?? this.tagIds,
    links: links ?? this.links,
    sourceCitations: sourceCitations ?? this.sourceCitations,
    provenance: clearProvenance ? null : (provenance ?? this.provenance),
    composedOn: clearComposedOn ? null : (composedOn ?? this.composedOn),
    revisedOn: clearRevisedOn ? null : (revisedOn ?? this.revisedOn),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  /// A duplicate with a new identity, suitable for "duplicate dance":
  /// same content, fresh id/timestamps, provenance dropped (the copy is the
  /// user's own editable record). [composedOn]/[revisedOn]/[rating] are
  /// **carried through**: unlike provenance (which describes an import), they
  /// are authorship/curation metadata about the dance itself, which the copy
  /// shares.
  ///
  /// [DanceLink]s are copied with **freshly generated ids** (via [newLinkId],
  /// which defaults to [uuidV4]): link ids are globally unique primary keys,
  /// so reusing the source's ids would collide when the copy is persisted.
  /// A link's `targetDanceId` (for `relatedDance` links) is preserved — the
  /// copy legitimately references the same related dance as the original.
  Dance duplicate({
    required String newId,
    required DateTime now,
    String Function()? newLinkId,
  }) {
    final genLinkId = newLinkId ?? uuidV4;
    return Dance(
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
      walkthrough: walkthrough,
      status: status,
      level: level,
      mixedLevel: mixedLevel,
      mixer: mixer,
      rating: rating,
      tunes: tunes,
      customFields: customFields,
      tagIds: tagIds,
      links: [
        for (final link in links)
          DanceLink(
            id: genLinkId(),
            kind: link.kind,
            url: link.url,
            targetDanceId: link.targetDanceId,
            label: link.label,
          ),
      ],
      sourceCitations: sourceCitations,
      composedOn: composedOn,
      revisedOn: revisedOn,
      createdAt: now,
      updatedAt: now,
    );
  }

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
      other.walkthrough == walkthrough &&
      other.status == status &&
      other.level == level &&
      other.mixedLevel == mixedLevel &&
      other.mixer == mixer &&
      other.rating == rating &&
      _listEq.equals(other.tunes, tunes) &&
      _listEq.equals(other.customFields, customFields) &&
      _listEq.equals(other.tagIds, tagIds) &&
      _listEq.equals(other.links, links) &&
      _listEq.equals(other.sourceCitations, sourceCitations) &&
      other.composedOn == composedOn &&
      other.revisedOn == revisedOn &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, title, updatedAt);

  @override
  String toString() => 'Dance($title)';
}
