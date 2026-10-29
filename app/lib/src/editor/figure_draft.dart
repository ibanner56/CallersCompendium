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
    this.sequenceFigures,
    this.compound,
  }) : id = id ?? uuidV4(),
       params = params ?? <String, Object?>{};

  /// Seeds a draft from an existing figure, keeping its params/note/flags.
  ///
  /// [beatsTouched] is set only when the loaded figure carries an explicit
  /// `beats` value — that authored count is user-owned and never auto-filled
  /// over (see [beatsTouched]). A figure with no `beats` (older/partial data)
  /// stays untouched so it can still adopt the taxonomy default on the next
  /// resync rather than remaining stuck at 0. A group's count is its sides'
  /// to follow ([syncContainerBeats]) unless it differs from what they call
  /// for ([sidesBeats]): a count that matches them, or a group's 0, is not
  /// one the caller typed, so the group keeps following its sides after the
  /// dance is saved and reopened.
  ///
  /// [assumedSubject] is preserved so an imported figure whose subject the
  /// parser DEFAULTED (#460) keeps its non-authoritative marker across an
  /// open/save round-trip; it is cleared the moment the user explicitly picks a
  /// move or edits the subject, which makes the subject a stated choice.
  ///
  /// When [figure] is a structural container, the draft is seeded from
  /// [Figure.subFigures] while preserving its container kind.
  factory FigureDraft.fromFigure(Figure figure) {
    final draft = FigureDraft._fromFigure(figure);
    // AUTH-11: see above.
    if (draft.isContainerDraft) {
      draft.beatsTouched = figure.beats > 0 && figure.beats != draft.sidesBeats;
    }
    return draft;
  }

  factory FigureDraft._fromFigure(Figure figure) => FigureDraft(
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
    sequenceFigures: figure.isSequence
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
  ///
  /// [moveParamDefaults] are the user's Move defaults (DD.3), by move id, as
  /// picking a move applies them (AUTH-7): each fills a parameter the line
  /// did not state, and a stated one (`half hey`, `16 hey`) is kept. A
  /// default count is the user's own, so it is touched. A custom keeps its
  /// text as parsed; a container's sides each take their own move's defaults,
  /// and its own shared count, unstated, follows them
  /// ([syncContainerBeats]).
  factory FigureDraft.fromFreeTextFigure(
    Figure figure,
    Taxonomy taxonomy, {
    Map<String, Map<String, Object?>>? moveParamDefaults,
  }) {
    final draft = FigureDraft.fromFigure(figure);
    _fillDerivedParams(draft, figure, taxonomy, moveParamDefaults);
    return draft;
  }

  static void _fillDerivedParams(
    FigureDraft draft,
    Figure figure,
    Taxonomy taxonomy,
    Map<String, Map<String, Object?>>? moveParamDefaults,
  ) {
    if (figure.isContainer) {
      final children = draft.containerChildren;
      final sources = figure.subFigures;
      if (children == null || children.length != sources.length) return;
      for (var i = 0; i < children.length; i++) {
        _fillDerivedParams(
          children[i],
          sources[i],
          taxonomy,
          moveParamDefaults,
        );
      }
      // A group typed with no count of its own follows its sides (AUTH-11).
      if (draft.beats <= 0) {
        draft.beatsTouched = false;
        draft.syncContainerBeats();
      }
      return;
    }
    final defaults = _unstatedDefaults(figure, taxonomy, moveParamDefaults);
    if (figure.isCustom) {
      // Only a count: the text is what was typed.
      if (defaults['beats'] case final beats?) {
        draft.params['beats'] = beats;
        draft.beatsTouched = true;
      }
      return;
    }
    if (figure.params.containsKey('beats')) {
      draft.params.addAll(defaults);
    } else {
      draft.params
        ..clear()
        ..addAll(
          taxonomy.effectiveParams(
            figure.copyWith(params: {...figure.params, ...defaults}),
          ),
        );
      draft.beatsTouched = defaults.containsKey('beats');
    }
    // A default `who` is the user's stated choice, as picking the move makes
    // it (#460), not one the parser assumed.
    if (defaults.containsKey('who')) draft.assumedSubject = false;
    // As picking the move does (#976): a default `who` brings its hand.
    if (defaults.containsKey('who') &&
        !defaults.containsKey('hand') &&
        !figure.params.containsKey('hand')) {
      seedChainHand(figure.move, draft.params);
    }
  }

  /// The user's Move defaults for [figure]'s move that the line left unstated,
  /// limited to the move's own parameters, as picking it applies them. A
  /// default count goes with the defaults it was saved beside: when the line
  /// states one of them itself (`half hey` against a full-hey default of 16
  /// beats), the count is left to follow what was typed. A subject the parser
  /// assumed ([Figure.assumedSubject], #460) was not stated either.
  static Map<String, Object?> _unstatedDefaults(
    Figure figure,
    Taxonomy taxonomy,
    Map<String, Map<String, Object?>>? moveParamDefaults,
  ) {
    final overrides = moveParamDefaults?[figure.move];
    final schema = taxonomy.resolve(figure.move)?.params;
    if (overrides == null || schema == null) return const {};
    final applicable = {
      for (final entry in overrides.entries)
        if (schema.containsKey(entry.key) && entry.key != 'text')
          entry.key: entry.value,
    };
    bool stated(String key) =>
        figure.params.containsKey(key) &&
        !(key == 'who' && figure.assumedSubject);
    final overruled = applicable.keys.any(
      (key) => key != 'beats' && stated(key),
    );
    return {
      for (final entry in applicable.entries)
        if (!stated(entry.key) && !(entry.key == 'beats' && overruled))
          entry.key: entry.value,
    };
  }

  /// Gives the rows [rows] that replaced the row [replaced], whose move was
  /// retyped, what it had beside its move, as picking a new move keeps them
  /// (AUTH-9): its note goes on the first row, after a note typed with the
  /// line, its walkthrough step too unless that row has one or is a
  /// combination's (which has none of its own), and its progression mark on
  /// the last row, unless a row already has one. This is how a combination's
  /// row passes them on when it expands on Save.
  static void carryRowExtras(FigureDraft replaced, List<FigureDraft> rows) {
    final first = rows.first;
    final note = replaced.note.trim();
    if (note.isNotEmpty) {
      final own = first.note.trim();
      first.note = own.isEmpty ? note : '$own; $note';
    }
    if (replaced.walkthroughOverride case final step?
        when first.walkthroughOverride == null &&
            !first.isCompoundPlaceholder) {
      first.walkthroughOverride = step;
    }
    if (replaced.progression && !rows.any((row) => row.progression)) {
      rows.last.progression = true;
    }
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
  /// carries an explicit `beats` via [FigureDraft.fromFigure], except a group
  /// whose count is 0 or matches what its sides call for ([sidesBeats]),
  /// which keeps following them, AUTH-11), this becomes `true` and the editor
  /// stops auto-filling beats so a manual override is never silently
  /// overwritten. (Exception: toggling a `balance` flag shifts
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
  /// A child may itself be a container of another kind.
  List<FigureDraft>? meanwhileSides;

  /// Non-null when this draft is a modifier container. The first child is the
  /// core figure; later children are modifiers.
  List<FigureDraft>? modifierFigures;

  /// Non-null when this draft is a sequence container: children danced in
  /// order and shown on one line. Unlike the other two kinds, a sequence's
  /// count is not edited on the container: [beats] is the sum of its
  /// children's, and `params['beats']` is not read.
  ///
  /// At most one of [meanwhileSides], [modifierFigures] and [sequenceFigures]
  /// is non-null; [setContainer] keeps it so.
  List<FigureDraft>? sequenceFigures;

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

  /// Whether this draft is a sequence group. Mirrors [Figure.isSequence].
  bool get isSequenceGroup => sequenceFigures != null;

  /// Whether this draft is any structural container kind.
  bool get isContainerDraft => containerKind != null;

  /// The container move id of this draft ([meanwhileMove], [modifierMove] or
  /// [sequenceMove]), or null for an ordinary figure.
  String? get containerKind => isMeanwhileGroup
      ? meanwhileMove
      : isModifierGroup
      ? modifierMove
      : isSequenceGroup
      ? sequenceMove
      : null;

  /// The ordered children of a container draft, or null for an ordinary one.
  List<FigureDraft>? get containerChildren =>
      meanwhileSides ?? modifierFigures ?? sequenceFigures;

  /// Makes this draft a container of [kind] holding [children], or an ordinary
  /// draft when [kind] is null, clearing the other kinds' lists.
  void setContainer(String? kind, List<FigureDraft>? children) {
    meanwhileSides = kind == meanwhileMove ? children : null;
    modifierFigures = kind == modifierMove ? children : null;
    sequenceFigures = kind == sequenceMove ? children : null;
  }

  /// Whether any descendant of this draft is a structural container.
  bool get hasNestedContainer {
    final children = containerChildren;
    return children?.any(
          (child) => child.isContainerDraft || child.hasNestedContainer,
        ) ??
        false;
  }

  /// Whether this draft can be a direct child of a container of [parentKind]
  /// (a container move id).
  ///
  /// A nested container must be of another kind than its parent and may not
  /// introduce a third container level.
  ///
  /// A compound placeholder never can: it stands for several figures, which
  /// are not one side or one modifier child (#709).
  bool canNestInContainer(String parentKind) {
    if (isCompoundPlaceholder) return false;
    final kind = containerKind;
    if (kind == null) return true;
    return kind != parentKind && !hasNestedContainer;
  }

  /// Whether [first] and [second], adjacent rows, can be grouped into a new
  /// container of [kind]. A sequence must also fit in [sequenceBeatLimit]
  /// beats, one phrase of the dance.
  static bool canGroup(
    String kind,
    FigureDraft first,
    FigureDraft second, {
    required int sequenceBeatLimit,
  }) =>
      first.canNestInContainer(kind) &&
      second.canNestInContainer(kind) &&
      (kind != sequenceMove || first.beats + second.beats <= sequenceBeatLimit);

  /// A new container of [kind] holding [first] and [second]. A meanwhile's or
  /// modifier's shared count follows its children until the user types one
  /// ([syncContainerBeats]); a sequence's count is always its children's sum.
  static FigureDraft group(String kind, FigureDraft first, FigureDraft second) {
    final group = FigureDraft()..setContainer(kind, [first, second]);
    if (kind != sequenceMove) {
      group.params['beats'] = first.beats;
      group.syncContainerBeats();
    }
    return group;
  }

  /// Whether this container draft can become a container of [kind] in place:
  /// it is another kind, its children fit [kind]'s cap and none of them is
  /// itself a [kind] container, and, for a sequence, their counts fit in
  /// [sequenceBeatLimit] beats.
  bool canConvertContainerTo(String kind, {required int sequenceBeatLimit}) {
    final children = containerChildren;
    if (children == null || containerKind == kind) return false;
    if (children.length > maxContainerChildren(kind)) return false;
    if (children.any((child) => child.containerKind == kind)) return false;
    return kind != sequenceMove ||
        children.fold(0, (sum, child) => sum + child.beats) <=
            sequenceBeatLimit;
  }

  /// Makes this container draft a [kind] container with the same children.
  /// The shared count then follows the children as for any group
  /// ([syncContainerBeats]); leaving a sequence, whose count nobody typed, it
  /// starts from the total the sequence showed and follows them too.
  /// Callers check [canConvertContainerTo] first.
  void convertContainerTo(String kind) {
    final children = containerChildren;
    if (children == null) return;
    if (isSequenceGroup) {
      params['beats'] = beats;
      beatsTouched = false;
    }
    setContainer(kind, children);
    syncContainerBeats();
  }

  /// The draft's beat count. A compound placeholder's is the count its
  /// expansion last had ([CompoundPlaceholder.beats]); a sequence's is the sum
  /// of its children's ([sequenceFigures]).
  int get beats {
    if (compound case final compound?) return compound.beats;
    if (sequenceFigures case final steps?) {
      return steps.fold(0, (sum, step) => sum + step.beats);
    }
    return (params['beats'] as int?) ?? 0;
  }

  /// The count a group's sides call for (AUTH-11): a modifier group's core's,
  /// since the other figures say how the core is danced, or while the core
  /// has none yet the longest side's; a meanwhile group's longest side's,
  /// since its sides are danced at once. 0 for an ordinary row, for a
  /// sequence (whose count is always its steps' sum, [beats]), or for a group
  /// none of whose sides has a count yet.
  int get sidesBeats {
    final sides = meanwhileSides ?? modifierFigures;
    if (sides == null || sides.isEmpty) return 0;
    if (isModifierGroup && sides.first.beats > 0) return sides.first.beats;
    return sides.fold(
      0,
      (longest, side) => side.beats > longest ? side.beats : longest,
    );
  }

  /// Sets a group's shared count to [sidesBeats], while the caller has not
  /// typed a count of their own ([beatsTouched]) and the sides call for one,
  /// so the group follows its sides (AUTH-11). Returns whether the count
  /// changed. Does nothing for an ordinary row.
  bool syncContainerBeats() {
    if (!isContainerDraft || beatsTouched) return false;
    final derived = sidesBeats;
    if (derived <= 0 || derived == beats) return false;
    params['beats'] = derived;
    return true;
  }

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
    sequenceFigures: sequenceFigures
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

  /// Whether Save leaves this row out although it is more than a blank row
  /// (AUTH-2): a group that is not complete (a meanwhile, modifier or sequence
  /// with fewer than two of its figures filled in, a modifier group with no
  /// Core, or a group holding such a group), or a row with no move that holds
  /// something other than a note. The editor marks the row and lists it under
  /// Warnings. A blank row, with nothing chosen or typed, has nothing to lose
  /// and is not counted.
  bool get isIncomplete =>
      toFigure() == null &&
      !keepsNoteWithoutMove &&
      (isContainerDraft || _hasUnsavedContent);

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
    final children = containerChildren;
    final kind = containerKind;
    if (children != null && kind != null) {
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
      final cap = maxContainerChildren(kind);
      final cappedChildren = readyChildren.length > cap
          ? readyChildren.sublist(0, cap)
          : readyChildren;
      // A sequence's children keep their own counts, which are its total; the
      // other kinds share one count that each child's use takes.
      final groupBeats = kind == sequenceMove
          ? cappedChildren.fold(0, (sum, child) => sum + child.beats)
          : beats;
      final figures = [
        for (final child in cappedChildren)
          kind == sequenceMove ? child : _withGroupBeats(child, groupBeats),
      ];
      final trimmedNote = canonicalizeNote(note);
      final extraParams = Map<String, Object?>.of(params)
        ..remove('beats')
        ..remove('figures');
      final build = switch (kind) {
        modifierMove => Figure.modifier,
        sequenceMove => Figure.sequence,
        _ => Figure.meanwhile,
      };
      final rebuilt = build(
        figures: figures,
        beats: groupBeats,
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
