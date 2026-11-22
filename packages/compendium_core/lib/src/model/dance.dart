import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../validation/validation.dart';
import 'custom_field.dart';
import 'dance_link.dart';
import 'difficulty_level.dart';
import 'enums.dart';
import 'figure.dart';
import 'figure_source.dart';
import 'tunes_source.dart';
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

/// Upper bound on the length of [Dance.meter] and [Dance.musicalKey], in
/// UTF-16 code units. Each is a short label ("3/2", "G minor"), so the bound
/// is small; it is enforced softly, as [kMaxWalkthroughLength] is: the archive
/// decoder clamps a longer value rather than rejecting the dance.
const int kMaxMusicLabelLength = 100;

/// Upper bound on the length of one of [Dance.alternateTitles], in UTF-16
/// code units, enforced softly as [kMaxMusicLabelLength] is: the archive and
/// sync decoders clamp a longer title rather than rejecting the dance.
const int kMaxAlternateTitleLength = 512;

/// Upper bound on how many [Dance.alternateTitles] a dance keeps. A dance
/// rarely has more than two other names; the bound only stops a hostile file
/// from carrying an unbounded list. Decoders keep the first this many.
const int kMaxAlternateTitles = 20;

/// Upper bound on the length of [Dance.barnesReference], in UTF-16 code
/// units, enforced softly as [kMaxMusicLabelLength] is.
const int kMaxBarnesReferenceLength = 100;

/// [titles] as [Dance.alternateTitles] holds them: each trimmed with its
/// runs of whitespace (line breaks included) made one space, then the empty
/// ones and the repeats of an earlier one dropped, in the order given.
///
/// A line break can never survive, which is what lets storage keep the list
/// as one line per title.
List<String> normalizeAlternateTitles(Iterable<String> titles) {
  final seen = <String>{};
  return [
    for (final title in titles)
      if (title.replaceAll(_alternateTitleWhitespace, ' ').trim() case final t
          when t.isNotEmpty && seen.add(t))
        t,
  ];
}

final RegExp _alternateTitleWhitespace = RegExp(r'\s+');

/// [titles] as the `dances.alternate_titles` column stores them: one per
/// line. Safe because a normalized title holds no line break.
String alternateTitlesColumnText(List<String> titles) =>
    normalizeAlternateTitles(titles).join('\n');

/// The titles a `dances.alternate_titles` value holds, normalized; `''` holds
/// none. Plain text, so no stored value can fail to read.
List<String> alternateTitlesFromColumnText(String text) =>
    text.isEmpty ? const [] : normalizeAlternateTitles(text.split('\n'));

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
    List<String> alternateTitles = const [],
    List<String> authorIds = const [],
    this.form = DanceForm.contra,
    Formation formation = const Formation(FormationShape.dupleImproper),
    this.progression = Progression.single,
    String phraseStructure = '',
    List<Figure> figures = const [],
    FigureSource? figuresSource,
    this.hook = '',
    this.callingNotes = '',
    this.walkthrough = '',
    this.meter = '',
    this.musicalKey = '',
    this.barnesReference = '',
    this.status = DanceStatus.active,
    String? difficultyLevelId,
    DifficultyLevel? level,
    this.mixedLevel = false,
    this.mixer = false,
    this.rating,
    List<String> tunes = const [],
    TunesSource? tunesSource,
    List<CustomFieldValue> customFields = const [],
    List<String> tagIds = const [],
    List<DanceLink> links = const [],
    List<SourceCitation> sourceCitations = const [],
    this.provenance,
    this.composedOn,
    List<String> interpreterIds = const [],
    this.interpretedOn,
    this.revisedOn,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  }) : difficultyLevelId = difficultyLevelId ?? level?.id,
       // The improper flag means something only in a form that has it
       // ([formHasImproperFlag]); elsewhere it is cleared, so a contra dance
       // never stores, sends or shows it, whatever it was built from.
       formation = formation.improper && !formHasImproperFlag(form)
           ? formation.copyWith(improper: false)
           : formation,
       alternateTitles = List.unmodifiable(
         normalizeAlternateTitles(alternateTitles),
       ),
       authorIds = List.unmodifiable(authorIds),
       interpreterIds = List.unmodifiable(interpreterIds),
       // Parse eagerly so an invalid structure fails at construction.
       phraseStructure = PhraseStructure.parse(phraseStructure),
       // [figuresSource] wins when given: it is how the storage layer carries a
       // transcription it could not decode. Callers pass one or the other, never
       // both — asserted rather than silently preferring one, because a caller
       // that passes both has a bug in its own reasoning about which is real.
       assert(
         figuresSource == null || figures.isEmpty,
         'pass figures or figuresSource, not both',
       ),
       figuresSource = figuresSource ?? DecodedFigures(figures),
       // Same contract as [figuresSource]: the storage layer passes a
       // [TunesSource] when it holds text it could not decode; ordinary callers
       // pass a list. Never both.
       assert(
         tunesSource == null || tunes.isEmpty,
         'pass tunes or tunesSource, not both',
       ),
       tunesSource = tunesSource ?? DecodedTunes(tunes),
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

  /// Other names the dance is known by ("Monymusk" for "Money Musk"), in the
  /// order entered; empty when it has none. Normalized at construction
  /// ([normalizeAlternateTitles]): no blank titles, no repeats, no line
  /// breaks. Shown under the title and found by a title search.
  final List<String> alternateTitles;

  /// Ordered Choreographer ids ("Traditional"/"Unknown" are real rows).
  final List<String> authorIds;
  final DanceForm form;

  /// The dance's formation. Its [Formation.improper] is always `false` for a
  /// form without the flag ([formHasImproperFlag]): the constructor clears
  /// it, so moving a dance from ECD to contra drops the mark.
  final Formation formation;
  final Progression progression;
  final PhraseStructure phraseStructure;

  /// The transcription. A [FigureSource] rather than a `List<Figure>` so that
  /// the case where the stored value cannot be decoded has a representation no
  /// reader can silently ignore — see [FigureSource] for why a plain list (or a
  /// list-returning shortcut on this class) would be unsafe.
  final FigureSource figuresSource;

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

  /// The tune's written meter, as free text ("3/2", "6/8"), or `''` when not
  /// given (ADR-006 §12, F3). Shown and searched, never computed with: the
  /// beats per bar that timing uses live in [phraseStructure].
  final String meter;

  /// The tune's key, as free text ("G minor", "D"), or `''` when not given
  /// (ADR-006 §12, F3).
  final String musicalKey;

  /// Where the tune is printed in the Barnes books, as free text with the
  /// book and page in one value ("BIII p. 92"), or "NiB" for a tune Not in
  /// Barnes; `''` when not given. Never parsed: shown, printed and searched
  /// as typed.
  final String barnesReference;
  final DanceStatus status;

  /// ID of the selected [DifficultyLevel], or `null` when unspecified.
  ///
  /// The vocabulary lives in `difficulty_levels`, so renaming or reordering a
  /// level never changes the dance's persisted reference. Distinct from
  /// [mixedLevel].
  final String? difficultyLevelId;

  /// Compatibility projection for the former enum API.
  ///
  /// Custom IDs are intentionally not synthesized into a label-bearing value;
  /// callers that need the configured vocabulary must read
  /// [CompendiumRepositories.difficultyLevels].
  @Deprecated('Use difficultyLevelId and DifficultyLevelRepository.')
  DifficultyLevel? get level => switch (difficultyLevelId) {
    DifficultyLevel.beginnerId => DifficultyLevel.beginner,
    DifficultyLevel.intermediateId => DifficultyLevel.intermediate,
    DifficultyLevel.advancedId => DifficultyLevel.advanced,
    _ => null,
  };

  /// Marks an event/dance that spans the difficulty scale rather than sitting
  /// at a single [difficultyLevelId]. Kept separate from the selected level.
  final bool mixedLevel;

  /// Whether this is a **mixer**: a dance in which you change partners each
  /// time through, ending with a new partner.
  ///
  /// Modelled as a boolean **orthogonal to [formation]**, not as a
  /// [FormationShape] value, because mixer-ness and formation are genuinely
  /// independent — the same argument as [mixedLevel] being a separate flag.
  /// This was measured, not assumed. Over The Caller's Box mirror
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

  /// Suggested tune names, or the stored text when it could not be decoded.
  /// See [TunesSource] for why this is not a plain list.
  final TunesSource tunesSource;
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

  /// Ordered Choreographer ids of the people who *interpreted* the dance:
  /// reconstructed it from its original publication, as ECD dances often
  /// are (ADR-006). Drawn from the same people list as [authorIds]; empty
  /// when nobody is credited. Stored for every form.
  final List<String> interpreterIds;

  /// When the dance was interpreted, at whatever precision is known, like
  /// [composedOn]; `null` when unknown.
  final PartialDate? interpretedOn;

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
  /// An undecodable transcription has no figures to label, so this is empty
  /// rather than throwing. Surfacing that state to the user is deliberately not
  /// done here — see [FigureSource].
  List<SectionedFigure> get sectionedFigures => switch (figuresSource) {
    DecodedFigures(:final figures) => deriveSections(figures, phraseStructure),
    UnreadableFigures() => const [],
  };

  /// Runs warning-level validation (e.g. phrase overflow). Structural
  /// invariants are enforced at construction and never appear here.
  List<ValidationIssue> validate() {
    final issues = <ValidationIssue>[];
    switch (figuresSource) {
      case DecodedFigures(:final figures):
        deriveSections(figures, phraseStructure, issues: issues);
      // Nothing to derive, and deliberately no issue raised: `validate` reports
      // warnings about content the user can act on in the editor, and an
      // undecodable transcription is not that. Telling the user about it is its
      // own piece of work.
      case UnreadableFigures():
        break;
    }
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
  /// pass `clearDifficultyLevel: true` to set [difficultyLevelId] back to
  /// `null`. A set clear flag
  /// **wins** over any value passed for the same field, so
  /// `copyWith(difficultyLevelId: 'difficulty-advanced',
  /// clearDifficultyLevel: true)` clears it. The
  /// same holds for `clearComposedOn` / `clearInterpretedOn` /
  /// `clearRevisedOn` / `clearRating` /
  /// `clearProvenance`.
  Dance copyWith({
    String? title,
    List<String>? alternateTitles,
    List<String>? authorIds,
    DanceForm? form,
    Formation? formation,
    Progression? progression,
    String? phraseStructure,
    List<Figure>? figures,
    String? hook,
    String? callingNotes,
    String? walkthrough,
    String? meter,
    String? musicalKey,
    String? barnesReference,
    DanceStatus? status,
    String? difficultyLevelId,
    @Deprecated('Use difficultyLevelId.') DifficultyLevel? level,
    bool clearDifficultyLevel = false,
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
    List<String>? interpreterIds,
    PartialDate? interpretedOn,
    bool clearInterpretedOn = false,
    PartialDate? revisedOn,
    bool clearRevisedOn = false,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Dance(
    id: id,
    title: title ?? this.title,
    alternateTitles: alternateTitles ?? this.alternateTitles,
    authorIds: authorIds ?? this.authorIds,
    form: form ?? this.form,
    formation: formation ?? this.formation,
    progression: progression ?? this.progression,
    phraseStructure: phraseStructure ?? this.phraseStructure.raw,
    // An explicit `figures:` replaces the transcription outright. With none,
    // the existing source is carried through **whole** — including an
    // undecodable one, whose stored bytes must survive an edit to any other
    // field. Re-encoding it here would be the silent data loss this type
    // exists to prevent.
    figures: figures ?? const [],
    figuresSource: figures == null ? figuresSource : null,
    hook: hook ?? this.hook,
    callingNotes: callingNotes ?? this.callingNotes,
    walkthrough: walkthrough ?? this.walkthrough,
    meter: meter ?? this.meter,
    musicalKey: musicalKey ?? this.musicalKey,
    barnesReference: barnesReference ?? this.barnesReference,
    status: status ?? this.status,
    difficultyLevelId: clearDifficultyLevel
        ? null
        : (difficultyLevelId ?? level?.id ?? this.difficultyLevelId),
    mixedLevel: mixedLevel ?? this.mixedLevel,
    mixer: mixer ?? this.mixer,
    rating: clearRating ? null : (rating ?? this.rating),
    // An explicit `tunes:` replaces the list outright; with none, the existing
    // source is carried through whole, including an undecodable one whose
    // stored bytes must survive an edit to any other field.
    tunes: tunes ?? const [],
    tunesSource: tunes == null ? tunesSource : null,
    customFields: customFields ?? this.customFields,
    tagIds: tagIds ?? this.tagIds,
    links: links ?? this.links,
    sourceCitations: sourceCitations ?? this.sourceCitations,
    provenance: clearProvenance ? null : (provenance ?? this.provenance),
    composedOn: clearComposedOn ? null : (composedOn ?? this.composedOn),
    interpreterIds: interpreterIds ?? this.interpreterIds,
    interpretedOn: clearInterpretedOn
        ? null
        : (interpretedOn ?? this.interpretedOn),
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
  /// copy legitimately references the same related dance as the original —
  /// and so is its [DanceLink.transitive] flag, so a copy of a grouped dance
  /// is a member of the same group rather than holding plain one-way links.
  ///
  /// [newTitle] replaces the title (for the "(copy)" wording); omitted, the
  /// copy keeps the original's, and a caller that wants a different one passes
  /// it here rather than updating the copy afterwards, which would be a second
  /// write that can fail between the two.
  Dance duplicate({
    required String newId,
    required DateTime now,
    String? newTitle,
    String Function()? newLinkId,
  }) {
    final genLinkId = newLinkId ?? uuidV4;
    return Dance(
      id: newId,
      title: newTitle ?? title,
      alternateTitles: alternateTitles,
      authorIds: authorIds,
      form: form,
      formation: formation,
      progression: progression,
      phraseStructure: phraseStructure.raw,
      // Carried through whole: a copy of a dance whose transcription cannot be
      // read still holds that transcription.
      figuresSource: figuresSource,
      hook: hook,
      callingNotes: callingNotes,
      walkthrough: walkthrough,
      meter: meter,
      musicalKey: musicalKey,
      barnesReference: barnesReference,
      status: status,
      difficultyLevelId: difficultyLevelId,
      mixedLevel: mixedLevel,
      mixer: mixer,
      rating: rating,
      // Carried through whole: a copy keeps a tune list that cannot be read.
      tunesSource: tunesSource,
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
            transitive: link.transitive,
          ),
      ],
      sourceCitations: sourceCitations,
      composedOn: composedOn,
      interpreterIds: interpreterIds,
      interpretedOn: interpretedOn,
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
      _listEq.equals(other.alternateTitles, alternateTitles) &&
      _listEq.equals(other.authorIds, authorIds) &&
      other.form == form &&
      other.formation == formation &&
      other.progression == progression &&
      other.phraseStructure == phraseStructure &&
      other.figuresSource == figuresSource &&
      other.hook == hook &&
      other.callingNotes == callingNotes &&
      other.walkthrough == walkthrough &&
      other.meter == meter &&
      other.musicalKey == musicalKey &&
      other.barnesReference == barnesReference &&
      other.status == status &&
      other.difficultyLevelId == difficultyLevelId &&
      other.mixedLevel == mixedLevel &&
      other.mixer == mixer &&
      other.rating == rating &&
      other.tunesSource == tunesSource &&
      _listEq.equals(other.customFields, customFields) &&
      _listEq.equals(other.tagIds, tagIds) &&
      _listEq.equals(other.links, links) &&
      _listEq.equals(other.sourceCitations, sourceCitations) &&
      other.composedOn == composedOn &&
      _listEq.equals(other.interpreterIds, interpreterIds) &&
      other.interpretedOn == interpretedOn &&
      other.revisedOn == revisedOn &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, title, updatedAt);

  @override
  String toString() => 'Dance($title)';
}
