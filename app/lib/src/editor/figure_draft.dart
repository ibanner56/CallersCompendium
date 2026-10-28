// Editor model: the mutable working draft for a single figure in the dance
// editor. Extracted from figure_list_editor.dart so model consumers (codec,
// snapshot, controller, settings) can depend on the model without importing
// the large widget file. Pure data — no Flutter/UI dependencies.

import 'package:compendium_core/compendium_core.dart';

/// Mutable working state for a single figure while it is being edited in the
/// dance editor. Committed to immutable figures on save via [toFigures]: the
/// one figure [toFigure] builds, or a compound placeholder's expansion.
class FigureDraft {
  FigureDraft({
    String? id,
    this.move,
    Map<String, Object?>? params,
    this.note = '',
    this.progression = false,
    this.schemaVersion = figureSchemaVersion,
    this.beatsTouched = false,
    this.assumedSubject = false,
    this.customOrigin = CustomOrigin.userEntered,
    this.walkthroughOverride,
    this.wordingOverride,
    this.meanwhileSides,
    this.modifierFigures,
    this.compound,
  }) : id = id ?? uuidV4(),
       params = params ?? <String, Object?>{};

  /// Seeds a draft from an existing figure, keeping its params/note/flags.
  ///
  /// [beatsTouched] is set only when the loaded figure carries an explicit
  /// `beats` value — that authored count is user-owned and never auto-filled
  /// over (see [beatsTouched]). A figure with no `beats` (older/partial data)
  /// stays untouched so it can still adopt the taxonomy default on the next
  /// resync rather than remaining stuck at 0.
  ///
  /// [assumedSubject] is preserved so an imported figure whose subject the
  /// parser DEFAULTED (#460) keeps its non-authoritative marker across an
  /// open/save round-trip; it is cleared the moment the user explicitly picks a
  /// move or edits the subject, which makes the subject a stated choice.
  ///
  /// When [figure] is a structural container, the draft is seeded from
  /// [Figure.subFigures] while preserving its container kind.
  factory FigureDraft.fromFigure(Figure figure) => FigureDraft(
    move: figure.move,
    params: Map<String, Object?>.of(figure.params),
    note: figure.note ?? '',
    progression: figure.progression,
    schemaVersion: figure.schemaVersion,
    beatsTouched: figure.params.containsKey('beats'),
    assumedSubject: figure.assumedSubject,
    customOrigin: figure.customOrigin,
    walkthroughOverride: figure.walkthroughOverride,
    wordingOverride: figure.wordingOverride,
    meanwhileSides: figure.isMeanwhile
        ? [for (final side in figure.subFigures) FigureDraft.fromFigure(side)]
        : null,
    modifierFigures: figure.isModifier
        ? [for (final child in figure.subFigures) FigureDraft.fromFigure(child)]
        : null,
  );

  /// Seeds a draft from a figure parsed out of a free-text entry line (#419).
  ///
  /// The parser leaves `beats` absent when the line states no count, so that
  /// the count is derived on read. A draft reads [beats] straight from its
  /// params and would show 0, so each ordinary structured figure (and each
  /// such child of a meanwhile/modifier container) has its params filled from
  /// [Taxonomy.effectiveParams], `beats` included, the way picking a move in
  /// the editor does. [beatsTouched] stays false for a derived count, so a
  /// later param change still re-derives it; a stated count stays touched.
  /// Customs and a container's own shared count are left as parsed.
  factory FigureDraft.fromFreeTextFigure(Figure figure, Taxonomy taxonomy) {
    final draft = FigureDraft.fromFigure(figure);
    _fillDerivedParams(draft, figure, taxonomy);
    return draft;
  }

  static void _fillDerivedParams(
    FigureDraft draft,
    Figure figure,
    Taxonomy taxonomy,
  ) {
    if (figure.isContainer) {
      final children = figure.isMeanwhile
          ? draft.meanwhileSides
          : draft.modifierFigures;
      final sources = figure.subFigures;
      if (children == null || children.length != sources.length) return;
      for (var i = 0; i < children.length; i++) {
        _fillDerivedParams(children[i], sources[i], taxonomy);
      }
      return;
    }
    if (figure.isCustom || figure.params.containsKey('beats')) return;
    draft.params
      ..clear()
      ..addAll(taxonomy.effectiveParams(figure));
    draft.beatsTouched = false;
  }

  /// Stable identity for widget keys across reorders/rebuilds.
  final String id;

  /// Canonical move (or alias) id, or `null` until the user picks one.
  String? move;
  final Map<String, Object?> params;
  String note;
  bool progression;
  final int schemaVersion;

  /// Whether the user has explicitly taken ownership of the `beats` value.
  ///
  /// Beats are auto-filled from the taxonomy: picking a move seeds the move's
  /// canonical default and clears this flag. Once the user edits the beats
  /// field directly (or the draft is seeded from a loaded figure that already
  /// carries an explicit `beats` via [FigureDraft.fromFigure]), this becomes
  /// `true` and the editor stops auto-filling beats so a manual override is
  /// never silently overwritten. (Exception: toggling a `balance` flag shifts
  /// the count by 4 either way; see core's `applyParamChange`.)
  bool beatsTouched;

  /// Whether this figure's subject was ASSUMED by the import parser (the source
  /// omitted it) rather than stated (#460). Carried through the editor so an
  /// open/save round-trip preserves the provenance marker; the editor clears it
  /// as soon as the user picks a move or edits the `who` param, since either is
  /// an explicit, authoritative choice of subject.
  bool assumedSubject;

  /// How this figure originated when it is a [customMove] custom (see
  /// [CustomOrigin]). Carried through the editor so a custom figure produced by
  /// the opt-in free-text entry path (or an import) that the parser could not
  /// map keeps its [CustomOrigin.importGap] flag across open/save and
  /// undo/autosave round-trips — which is what keeps it showing the #398
  /// parser-gap marker and eligible for the reparse-customs upgrade (#419/#417).
  /// Only meaningful when the draft is a custom; explicitly choosing a move or
  /// authoring a custom in the structured editor resets it to
  /// [CustomOrigin.userEntered] (a stated, user-authored choice).
  CustomOrigin customOrigin;

  /// The per-dance, per-figure-instance **walkthrough snippet override** (#411):
  /// the step text to use for THIS occurrence, taking precedence over the global
  /// snippet library default (keyed by figure signature). `null` means "no
  /// override" — the figure falls back to the library default when a walkthrough
  /// is assembled. Holds ONLY the per-dance override; "use everywhere" edits
  /// update the library and leave this `null`.
  String? walkthroughOverride;

  /// The per-dance, per-figure-instance display wording override. `null` means
  /// the figure uses the renderer's normal wording.
  String? wordingOverride;

  /// Non-`null` ⇒ this draft is a **meanwhile group** (#590/#593): the
  /// concurrent sides being authored, in order. `move`/most `params` are
  /// unused for a group — `params['beats']` instead holds the single SHARED
  /// beat count for the whole group (read via [beats], same as any other
  /// draft). `null` (the default) means an ordinary, non-grouped figure —
  /// today's ubiquitous case.
  ///
  /// A child may itself carry the one legal opposite container kind.
  List<FigureDraft>? meanwhileSides;

  /// Non-null when this draft is a modifier container. The first child is the
  /// core figure; later children are modifiers.
  List<FigureDraft>? modifierFigures;

  /// Non-null when this row is one of the user's own compound figures (#709),
  /// picked in the dance editor and not yet expanded. A placeholder exists only
  /// in the editor and its autosave draft: [toFigures] expands it into the
  /// figures it stands for when the dance is built, so it never reaches stored
  /// dance data. While it is set, [move] is null and [params] holds nothing.
  CompoundPlaceholder? compound;

  /// Whether this draft is a compound placeholder; see [compound].
  bool get isCompoundPlaceholder => compound != null;

  /// Whether this draft is a meanwhile group. Mirrors [Figure.isMeanwhile].
  bool get isMeanwhileGroup => meanwhileSides != null;

  /// Whether this draft is a modifier group. Mirrors [Figure.isModifier].
  bool get isModifierGroup => modifierFigures != null;

  /// Whether this draft is either structural container kind.
  bool get isContainerDraft => isMeanwhileGroup || isModifierGroup;

  /// Whether any descendant of this draft is a structural container.
  bool get hasNestedContainer {
    final children = meanwhileSides ?? modifierFigures;
    return children?.any(
          (child) => child.isContainerDraft || child.hasNestedContainer,
        ) ??
        false;
  }

  /// Whether this draft can be a direct child of the requested container kind.
  ///
  /// Structural children must alternate kinds and may not introduce a third
  /// container level.
  ///
  /// A compound placeholder never can: it stands for several figures, which
  /// are not one side or one modifier child (#709).
  bool canNestInContainer({required bool modifierParent}) {
    if (isCompoundPlaceholder) return false;
    if (!isContainerDraft) return true;
    final oppositeKind = modifierParent ? isMeanwhileGroup : isModifierGroup;
    return oppositeKind && !hasNestedContainer;
  }

  /// The draft's beat count. A compound placeholder's is the count its
  /// expansion last had ([CompoundPlaceholder.beats]).
  int get beats => compound?.beats ?? (params['beats'] as int?) ?? 0;

  /// Returns an independent copy with a FRESH [id] (the stable-identity
  /// contract: a duplicate is a distinct row) and every other field copied
  /// verbatim — the `params` map is deep-copied, and provenance/ownership flags
  /// ([assumedSubject], [beatsTouched]) are carried over so a duplicate behaves
  /// exactly like its source. Centralizing cloning here keeps the duplicate
  /// paths (dance editor and settings template) from silently dropping
  /// newly-added fields — the bug that lost [assumedSubject] on duplicate (#460).
  FigureDraft clone() => FigureDraft(
    move: move,
    params: Map<String, Object?>.of(params),
    note: note,
    progression: progression,
    schemaVersion: schemaVersion,
    beatsTouched: beatsTouched,
    assumedSubject: assumedSubject,
    customOrigin: customOrigin,
    walkthroughOverride: walkthroughOverride,
    wordingOverride: wordingOverride,
    meanwhileSides: meanwhileSides
        ?.map((side) => side.clone())
        .toList(growable: true),
    modifierFigures: modifierFigures
        ?.map((child) => child.clone())
        .toList(growable: true),
    compound: compound?.copy(),
  );

  /// Whether this draft holds any content worth preserving even though it
  /// has no [move] chosen yet (used by [toFigure] to decide whether an
  /// in-progress meanwhile side should be best-effort materialized rather
  /// than silently dropped — see [_bestEffortFigure]). A freshly-added blank
  /// placeholder side (no note, no params, no walkthrough override) has
  /// nothing to lose and is the only case still skipped.
  bool get _hasUnsavedContent =>
      note.trim().isNotEmpty ||
      params.isNotEmpty ||
      walkthroughOverride != null ||
      wordingOverride != null;

  /// Whether this is a row with no [move] but a note, such as one whose Move
  /// box was cleared while retyping. [toFigures] keeps the note as a custom
  /// figure rather than dropping the row and its note, as [toFigure] does for
  /// such a side (#679 review). [toFigure] itself still returns null for it,
  /// because callers read that as "no move chosen yet".
  bool get keepsNoteWithoutMove =>
      move == null &&
      compound == null &&
      !isContainerDraft &&
      note.trim().isNotEmpty;

  /// Best-effort immutable figure for a meanwhile side that has no [move]
  /// chosen yet but does have [_hasUnsavedContent] (#679 review): rather than
  /// silently dropping the side out of the persisted container — losing the
  /// user's partial authoring the moment an autosave/undo snapshot fires —
  /// represent it as a [customMove] figure carrying whatever was entered so
  /// far, except [wordingOverride]: a custom figure never renders one, so it is
  /// not carried (see [toFigure]). Never called for a side whose [toFigure] already succeeds.
  ///
  /// [canonicalizeNote] mirrors the parameter of the same name on [toFigure]
  /// — see its doc comment for why this is a callback rather than a direct
  /// dialect dependency.
  Figure _bestEffortFigure(String Function(String) canonicalizeNote) {
    final trimmedNote = canonicalizeNote(note);
    return Figure(
      schemaVersion: schemaVersion,
      move: customMove,
      params: _canonicalParams(customMove, canonicalizeNote),
      note: trimmedNote.isEmpty ? null : trimmedNote,
      progression: progression,
      customOrigin: customOrigin,
      assumedSubject: false,
      walkthroughOverride: walkthroughOverride,
    );
  }

  /// Copy of [params] for persistence. A custom figure's `params['text']` is
  /// figure-like (one line beside structured figures), so it goes through the
  /// same [canonicalizeNote] chokepoint as [note], unlike the dance-level prose
  /// fields, which stay verbatim (#613). Re-saving already-canonical text is
  /// idempotent (DIA-02).
  Map<String, Object?> _canonicalParams(
    String moveId,
    String Function(String) canonicalizeNote,
  ) {
    final copy = Map<String, Object?>.of(params);
    // A use of one of the user's own figures (#1023) keeps its line as the
    // figure rendered it, canonical already: canonicalizing it again could
    // change it, and a changed line no longer matches its check.
    if (moveId == customMove &&
        copy['text'] is String &&
        userFigureUseOf(Figure(move: customMove, params: copy))?.attached !=
            true) {
      final text = copy['text']! as String;
      if (text.isNotEmpty) {
        copy['text'] = canonicalizeNote(text);
      }
    }
    return copy;
  }

  /// [child] of a group whose count is [groupBeats]: a use of one of the
  /// user's own figures (#1023) takes the group's count, the one its side
  /// shows, so a `{beats}` in its wording reads the same in every render of
  /// the dance and in the line it stores.
  static Figure _withGroupBeats(Figure child, int groupBeats) =>
      userFigureUseOf(child)?.attached == true &&
          child.params['beats'] != groupBeats
      ? child.copyWith(params: {...child.params, 'beats': groupBeats})
      : child;

  /// Builds the immutable figure, or `null` when no move is chosen yet (or,
  /// for a structural container, when fewer than 2 children can be
  /// materialized — an in-progress container never corrupts the saved dance; it
  /// simply isn't written until it is ready).
  ///
  /// [canonicalizeNote] is applied to [note] (after trimming, if the default
  /// is used) before it is persisted onto the built [Figure]. This model is
  /// pure data with no [Dialect] dependency (see the file header), so the
  /// canonicalization chokepoint itself lives with the caller — the dance
  /// editor controller passes its own dialect-aware canonicalizer (mirroring
  /// how `hook`/`callingNotes`/`walkthrough` are canonicalized at the same
  /// `buildDance` boundary, issue #613/#715) while the default keeps today's
  /// plain-trim behavior for any other caller.
  ///
  /// A compound placeholder builds the figure it falls back to when it cannot
  /// be expanded ([toFigures] expands it).
  Figure? toFigure({String Function(String) canonicalizeNote = _trimNote}) {
    if (compound case final compound?) {
      return _compoundFallback(compound, canonicalizeNote);
    }
    final children = meanwhileSides ?? modifierFigures;
    if (children != null) {
      // Never silently drop a child that the user has started authoring
      // (#679 review): only a genuinely untouched placeholder side (no move,
      // no note/params/walkthrough override) is skipped. An incomplete nested
      // container cannot be represented as a custom leaf without losing its
      // structure, so it keeps the parent draft editor-only until complete.
      final readyChildren = <Figure>[];
      for (var index = 0; index < children.length; index++) {
        final child = children[index];
        final figure = child.toFigure(canonicalizeNote: canonicalizeNote);
        if (figure != null) {
          readyChildren.add(figure);
        } else if (modifierFigures != null && index == 0) {
          // The first modifier child is the core; skipping it would promote a
          // later child into the core slot when the draft is saved.
          return null;
        } else if (child.isContainerDraft) {
          return null;
        } else if (child._hasUnsavedContent) {
          readyChildren.add(child._bestEffortFigure(canonicalizeNote));
        }
      }
      if (readyChildren.length < 2) return null;
      // Defensive clamp mirroring the codec's untrusted-input behavior: the
      // UI never lets the side count exceed the cap, but this keeps toFigure()
      // from ever throwing even if that invariant is somehow violated.
      final cappedChildren = [
        for (final child
            in readyChildren.length > kMaxMeanwhileSides
                ? readyChildren.sublist(0, kMaxMeanwhileSides)
                : readyChildren)
          _withGroupBeats(child, beats),
      ];
      final trimmedNote = canonicalizeNote(note);
      final extraParams = Map<String, Object?>.of(params)
        ..remove('beats')
        ..remove('figures');
      final rebuilt = modifierFigures != null
          ? Figure.modifier(
              figures: cappedChildren,
              beats: beats,
              extraParams: extraParams,
              note: trimmedNote.isEmpty ? null : trimmedNote,
              progression: progression,
              wordingOverride: _trimOptionalOverride(wordingOverride),
            )
          : Figure.meanwhile(
              figures: cappedChildren,
              beats: beats,
              extraParams: extraParams,
              note: trimmedNote.isEmpty ? null : trimmedNote,
              progression: progression,
              wordingOverride: _trimOptionalOverride(wordingOverride),
            );
      final trimmedWalkthrough = walkthroughOverride?.trim();
      return rebuilt.copyWith(
        schemaVersion: schemaVersion,
        customOrigin: customOrigin,
        assumedSubject: assumedSubject,
        walkthroughOverride:
            trimmedWalkthrough == null || trimmedWalkthrough.isEmpty
            ? null
            : trimmedWalkthrough,
      );
    }
    final id = move;
    if (id == null) return null;
    final trimmedNote = canonicalizeNote(note);
    final trimmedOverride = walkthroughOverride?.trim();
    return Figure(
      schemaVersion: schemaVersion,
      move: id,
      params: _canonicalParams(id, canonicalizeNote),
      note: trimmedNote.isEmpty ? null : trimmedNote,
      progression: progression,
      assumedSubject: assumedSubject,
      customOrigin: customOrigin,
      walkthroughOverride: (trimmedOverride == null || trimmedOverride.isEmpty)
          ? null
          : trimmedOverride,
      // A custom figure renders its own text and never applies a wording
      // override (`renderer.dart`: `figure.isCustom ? null : ...`); the editor
      // offers no field for one, so none is persisted (#1394).
      wordingOverride: id == customMove
          ? null
          : _trimOptionalOverride(wordingOverride),
    );
  }

  /// The figures this draft stands for when the dance is built: a compound
  /// placeholder's expansion, or else the one figure [toFigure] builds (none
  /// for a row with nothing chosen yet).
  ///
  /// [resolveCompound] looks a compound up by id, as it is now — an edit made
  /// in the Glossary since the row was picked applies. A placeholder whose
  /// compound is gone, no longer valid, or no longer accepts the row's
  /// arguments becomes one custom figure bearing the compound's name, its last
  /// beat count, and the row's note and progression mark, so the row is not
  /// dropped; the values chosen for its parameters are not kept (#709). The placeholder's [note] goes on
  /// the first expanded figure and its [progression] mark on the last.
  List<Figure> toFigures({
    required CompoundResolver resolveCompound,
    String Function(String) canonicalizeNote = _trimNote,
  }) {
    final compound = this.compound;
    if (compound == null) {
      final figure =
          toFigure(canonicalizeNote: canonicalizeNote) ??
          (keepsNoteWithoutMove ? _bestEffortFigure(canonicalizeNote) : null);
      return [?figure];
    }
    final expanded = expandPlaceholder(compound, resolveCompound);
    if (expanded == null) {
      return [_compoundFallback(compound, canonicalizeNote)];
    }
    final placed = [...expanded];
    final note = canonicalizeNote(this.note);
    if (note.isNotEmpty) {
      final first = placed.first;
      final own = first.note;
      placed[0] = first.copyWith(
        note: own == null || own.isEmpty ? note : '$own; $note',
      );
    }
    if (progression) {
      placed[placed.length - 1] = placed.last.copyWith(progression: true);
    }
    return placed;
  }

  /// The custom figure a placeholder becomes when it cannot be expanded.
  ///
  /// Its text is the compound's stored name, which is already canonical
  /// glossary text: it does not go through [canonicalizeNote], whose rules
  /// differ from glossary canonicalization and would alter it (#709).
  Figure _compoundFallback(
    CompoundPlaceholder compound,
    String Function(String) canonicalizeNote,
  ) {
    final note = canonicalizeNote(this.note);
    return Figure(
      schemaVersion: schemaVersion,
      move: customMove,
      params: {
        ...contraTaxonomy.effectiveParams(Figure(move: customMove)),
        'text': compound.name,
        if (compound.beats > 0) 'beats': compound.beats,
      },
      note: note.isEmpty ? null : note,
      progression: progression,
    );
  }
}

/// Default [FigureDraft.toFigure]/[FigureDraft._bestEffortFigure] note
/// transform: today's plain-trim behavior, used by any caller that doesn't
/// supply a dialect-aware canonicalizer.
String _trimNote(String note) => note.trim();

String? _trimOptionalOverride(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Looks one of the user's compound figures up by its glossary entry id: its
/// definition as it is now, or null when it is gone or no longer decodes.
typedef CompoundResolver = CompoundDefinition? Function(String id);

/// [compound]'s expansion with its arguments, or null when its compound is
/// gone, invalid, or does not accept them.
List<Figure>? expandPlaceholder(
  CompoundPlaceholder compound,
  CompoundResolver resolveCompound,
) {
  final definition = resolveCompound(compound.id);
  if (definition == null) return null;
  final expanded = expandCompound(definition, compound.args, contraTaxonomy);
  return expanded == null || expanded.isEmpty ? null : expanded;
}

/// One of the user's compound figures, as a dance-editor row holds it until
/// the dance is saved (#709).
class CompoundPlaceholder {
  CompoundPlaceholder({
    required this.id,
    required this.name,
    Map<String, Object?>? args,
    this.beats = 0,
  }) : args = args ?? <String, Object?>{};

  /// The compound's glossary entry id ([UserGlossaryEntry.id]).
  final String id;

  /// The compound's name when it was picked, as stored: canonical glossary
  /// text. It is what the row falls back to if the compound is deleted.
  String name;

  /// The value the row gives each of the compound's parameters, by key.
  final Map<String, Object?> args;

  /// The beats of the expansion when the row last expanded, so a fallback, the
  /// phrase labels and the beat total have a count while the compound cannot
  /// be read.
  int beats;

  CompoundPlaceholder copy() => CompoundPlaceholder(
    id: id,
    name: name,
    args: Map<String, Object?>.of(args),
    beats: beats,
  );
}
