import 'package:compendium_core/compendium_core.dart';

/// Sort options surfaced in the Collection UI (`docs/design/ux.md` §1). Maps
/// onto the core [SearchSort] allow-list. [relevance] is only offered when the
/// query is a bare full-text search (`docs/design/search.md` decision 6);
/// `recentlyEdited` stays out of the UI to avoid a confusing
/// "added" vs "edited" pair, though it remains available in core.
enum CollectionSort { relevance, title, author, recentlyAdded, lastCalled }

extension CollectionSortX on CollectionSort {
  String get label => switch (this) {
    CollectionSort.relevance => 'Best match',
    CollectionSort.title => 'Title',
    CollectionSort.author => 'Author',
    CollectionSort.recentlyAdded => 'Recently added',
    CollectionSort.lastCalled => 'Last called',
  };

  SearchSort get searchSort => switch (this) {
    CollectionSort.relevance => SearchSort.relevance,
    CollectionSort.title => SearchSort.title,
    CollectionSort.author => SearchSort.author,
    CollectionSort.recentlyAdded => SearchSort.recentlyAdded,
    CollectionSort.lastCalled => SearchSort.lastCalled,
  };
}

/// Resolves a persisted settings value (the [CollectionSort] `.name`) into a
/// [CollectionSort] usable as the Collection list's default sort (ROADMAP G.6a).
///
/// Returns `null` — so callers fall back to their historical default (`title`)
/// — for `null`, a non-string, an unrecognized name, or [CollectionSort.relevance]
/// (relevance is only meaningful for a bare full-text query, never as a saved
/// default; see `docs/design/search.md` decision 6).
CollectionSort? collectionSortFromName(Object? stored) {
  if (stored is! String) return null;
  for (final sort in CollectionSort.values) {
    if (sort.name == stored && sort != CollectionSort.relevance) return sort;
  }
  return null;
}

/// The user's one-tap facet selections. Every facet is multi-select: within a
/// single facet the selected leaves are OR-ed ("has any of these tags"), and
/// distinct facets are AND-ed ("this form AND one of these tags") — the
/// confirmed decision 7 semantics, applied uniformly.
class FacetSelections {
  final Set<DanceForm> forms = {};
  final Set<FormationShape> formations = {};
  final Set<Progression> progressions = {};
  final Set<DanceStatus> statuses = {};
  final Set<DanceLevel> levels = {};

  /// Mixed-level facet: `null` = unselected, `true`/`false` = filter to that
  /// flag. Kept separate from [levels] because "mixed" spans the ordered scale
  /// (mirrors the core [MixedLevelFilter] being distinct from [LevelFilter]).
  bool? mixedLevel;

  /// Mixer facet: `null` = unselected, `true` = show mixers only.
  /// Kept separate from formations for the same reason [mixedLevel] is
  /// separate from [levels]: mixer-ness is orthogonal to shape (issue #732,
  /// mirrors core [MixerFilter]). Only `true` is offered in the UI (tri-state
  /// null / show-mixers-only; "show non-mixers" is not offered).
  bool? mixer;

  /// Minimum-rating facet: `null` = unselected, otherwise a floor on the closed
  /// `1..5` scale that emits a [RatingFilter] (`rating >= minRating`; unrated
  /// dances are excluded). Single-valued (a floor, not a multi-select set).
  int? minRating;

  final Set<String> authorIds = {};
  final Set<String> tagIds = {};

  /// Selected source facet: ids of cited [PublishedSource]s the user picked,
  /// each emitted as an identity-based [SourceIdFilter]. Multi-select, OR-ed
  /// within the facet — a pick-a-source chooser mirroring the Author facet
  /// (which is likewise id-based via [AuthorFilter]). Kept by id (not title)
  /// so duplicate/prefix titles or title-vs-author collisions never over-match.
  final Set<String> sourceIds = {};

  /// Selected `choice` custom-field values, keyed by field id → chosen values
  /// (OR-within a field).
  final Map<String, Set<String>> choiceValues = {};

  /// Selected `boolean` custom-field values, keyed by field id → true/false.
  final Map<String, bool> booleanValues = {};

  /// Selected `text` custom-field filters, keyed by field id.
  /// [TextFacetState.op] is either [CustomFieldOp.contains] or
  /// [CustomFieldOp.equals]; [TextFacetState.value] is the query string.
  final Map<String, TextFacetState> textValues = {};

  /// Selected `number` custom-field filters, keyed by field id.
  /// [NumberFacetState.op] selects the operator; [NumberFacetState.lo] is
  /// always the primary value; [NumberFacetState.hi] is only used for
  /// [CustomFieldOp.between].
  final Map<String, NumberFacetState> numberValues = {};

  bool get isEmpty =>
      forms.isEmpty &&
      formations.isEmpty &&
      progressions.isEmpty &&
      statuses.isEmpty &&
      levels.isEmpty &&
      mixedLevel == null &&
      mixer == null &&
      minRating == null &&
      authorIds.isEmpty &&
      tagIds.isEmpty &&
      sourceIds.isEmpty &&
      choiceValues.values.every((s) => s.isEmpty) &&
      booleanValues.isEmpty &&
      textValues.values.every((s) => !s.isEffective) &&
      numberValues.values.every((s) => !s.isEffective);

  void clear() {
    forms.clear();
    formations.clear();
    progressions.clear();
    statuses.clear();
    levels.clear();
    mixedLevel = null;
    mixer = null;
    minRating = null;
    authorIds.clear();
    tagIds.clear();
    sourceIds.clear();
    choiceValues.clear();
    booleanValues.clear();
    textValues.clear();
    numberValues.clear();
  }
}

/// The user's "By phrase" selections — a Caller's Box-style per-phrase figure
/// search. For each canonical section label (the standard 4 phrases A1/A2/B1/B2,
/// but keyed generically so any [PhraseStructure] works) the caller lists moves
/// that MUST occur in that phrase ([match]) and moves that must NOT ([exclude]).
///
/// Semantics (folded in [buildCollectionFilter]):
/// - within one phrase, every [match] move must be present (AND);
/// - within one phrase, no [exclude] move may be present (each negated);
/// - across phrases, all constraints AND together;
/// - an empty phrase imposes no constraint.
///
/// Moves are stored as canonical move ids (the same ids the Advanced builder's
/// "has figure" rows use), so they compile straight to [FigureLeaf]s.
class ByPhraseSelections {
  /// Section label → moves that MUST occur in that phrase.
  final Map<String, List<String>> match = {};

  /// Section label → moves that must NOT occur in that phrase.
  final Map<String, List<String>> exclude = {};

  bool get isEmpty =>
      match.values.every((m) => m.isEmpty) &&
      exclude.values.every((m) => m.isEmpty);

  void clear() {
    match.clear();
    exclude.clear();
  }
}

/// Immutable state for a text custom-field facet filter.
class TextFacetState {
  const TextFacetState({required this.op, required this.value});

  /// Either [CustomFieldOp.contains] or [CustomFieldOp.equals].
  final CustomFieldOp op;

  /// The text to match against.
  final String value;

  /// True when this state would actually produce a [CustomFieldFilter] branch
  /// in [buildCollectionFilter] (i.e. the value is non-empty after trimming).
  bool get isEffective => value.trim().isNotEmpty;
}

/// Immutable state for a number custom-field facet filter.
class NumberFacetState {
  const NumberFacetState({required this.op, required this.lo, this.hi});

  /// One of [CustomFieldOp.eq], [CustomFieldOp.lt], [CustomFieldOp.gt], or
  /// [CustomFieldOp.between].
  final CustomFieldOp op;

  /// The primary operand (always required).
  final num lo;

  /// The upper bound for [CustomFieldOp.between] (required only for that op).
  final num? hi;

  /// True when this state would actually produce a [CustomFieldFilter] branch
  /// in [buildCollectionFilter] (i.e. non-between ops are always effective;
  /// between is only effective once [hi] is also set).
  bool get isEffective => op != CustomFieldOp.between || hi != null;
}

/// OR-combines [leaves] into a single [DanceFilter]: `null` for none, the leaf
/// itself for one, an [OrFilter] for many. Used to fold a multi-select facet
/// down to one branch of the top-level `AND`.
DanceFilter? orGroup(List<DanceFilter> leaves) => switch (leaves.length) {
  0 => null,
  1 => leaves.single,
  _ => OrFilter(leaves),
};

/// Builds the composed [DanceFilter] for a Collection search: the full-text
/// query, the facet selections, and the (optional) Advanced tree, AND-ed into
/// one flat tree. Returns `AndFilter([])` (match-all) when nothing is set.
///
/// [defs] supplies the custom-field definitions the facet selections refer to
/// (needed to build the typed [CustomFieldFilter] leaves).
DanceFilter buildCollectionFilter({
  required String ftsText,
  required FacetSelections facets,
  required List<CustomFieldDef> defs,
  FullTextScope scope = FullTextScope.omni,
  ByPhraseSelections? byPhrase,
  BuilderGroup? advancedRoot,
}) {
  final branches = <DanceFilter>[];

  final text = ftsText.trim();
  if (text.isNotEmpty) {
    branches.add(FullTextFilter(text, scope: scope));
  }

  void addOr(List<DanceFilter> leaves) {
    final g = orGroup(leaves);
    if (g != null) branches.add(g);
  }

  addOr([for (final f in facets.forms) FormFilter(f)]);
  addOr([for (final s in facets.formations) FormationFilter(s)]);
  addOr([for (final p in facets.progressions) ProgressionFilter(p)]);
  addOr([for (final s in facets.statuses) StatusFilter(s)]);
  addOr([for (final l in facets.levels) LevelFilter(l)]);
  if (facets.mixedLevel != null) {
    branches.add(MixedLevelFilter(facets.mixedLevel!));
  }
  if (facets.mixer != null) {
    branches.add(MixerFilter(facets.mixer!));
  }
  if (facets.minRating != null) {
    branches.add(RatingFilter(facets.minRating!));
  }
  addOr([for (final id in facets.authorIds) AuthorFilter(id)]);
  addOr([for (final id in facets.tagIds) TagFilter(id)]);
  addOr([for (final id in facets.sourceIds) SourceIdFilter(id)]);

  final defsById = {for (final d in defs) d.id: d};
  facets.choiceValues.forEach((fieldId, values) {
    final def = defsById[fieldId];
    if (def == null || values.isEmpty) return;
    addOr([
      for (final v in values) CustomFieldFilter(def, CustomFieldOp.is_, v),
    ]);
  });
  facets.booleanValues.forEach((fieldId, value) {
    final def = defsById[fieldId];
    if (def == null) return;
    branches.add(CustomFieldFilter(def, CustomFieldOp.is_, value));
  });
  facets.textValues.forEach((fieldId, state) {
    final def = defsById[fieldId];
    if (def == null || !state.isEffective) return;
    branches.add(CustomFieldFilter(def, state.op, state.value.trim()));
  });
  facets.numberValues.forEach((fieldId, state) {
    final def = defsById[fieldId];
    if (def == null || !state.isEffective) return;
    if (state.op == CustomFieldOp.between) {
      branches.add(
        CustomFieldFilter(def, CustomFieldOp.between, [state.lo, state.hi!]),
      );
    } else {
      branches.add(CustomFieldFilter(def, state.op, state.lo));
    }
  });

  final advanced = advancedRoot?.toFilter();
  if (advanced != null) branches.add(advanced);

  // By-phrase constraints (Caller's Box style): each "match" move must occur in
  // its phrase (a positive sectioned FigureFilter); each "do not match" move
  // must be absent (the same sectioned leaf, negated). Empty phrases add
  // nothing. All fold into the top-level AND alongside every other facet.
  if (byPhrase != null) {
    void addFigure(String section, String move, {required bool negate}) {
      final id = move.trim();
      if (id.isEmpty) return;
      final DanceFilter leaf = FigureFilter(FigureLeaf(id, section: section));
      branches.add(negate ? NotFilter(leaf) : leaf);
    }

    byPhrase.match.forEach((section, moves) {
      for (final move in moves) {
        addFigure(section, move, negate: false);
      }
    });
    byPhrase.exclude.forEach((section, moves) {
      for (final move in moves) {
        addFigure(section, move, negate: true);
      }
    });
  }

  if (branches.isEmpty) return const AndFilter([]);
  if (branches.length == 1) {
    final only = branches.single;
    // A lone OR/AND branch is already a valid top-level filter; a lone leaf is
    // too. Return it directly rather than wrapping in a redundant AND.
    return only;
  }
  return AndFilter(branches);
}

/// Whether a search made of [ftsText] + [facets] + [advancedRoot] is a **bare**
/// full-text search — the only case where FTS `relevance` sort is meaningful
/// (`docs/design/search.md` decision 6).
bool isBareFullText({
  required String ftsText,
  required FacetSelections facets,
  FullTextScope scope = FullTextScope.omni,
  ByPhraseSelections? byPhrase,
  BuilderGroup? advancedRoot,
}) =>
    ftsText.trim().isNotEmpty &&
    scope == FullTextScope.omni &&
    ftsQueryScalarLength(ftsText) <= 2 &&
    facets.isEmpty &&
    (byPhrase == null || byPhrase.isEmpty) &&
    (advancedRoot == null || advancedRoot.toFilter() == null);

// ---------------------------------------------------------------------------
// Advanced query-builder node model.
//
// A small *mutable* tree the Advanced panel edits in place; each node knows how
// to fold itself into an immutable [DanceFilter] / [FigureQuery]. Nodes with
// nothing filled in fold to `null` and are skipped, so a half-built row never
// breaks the search.
// ---------------------------------------------------------------------------

/// How a [BuilderGroup] combines its children, in plain language for the UI.
enum GroupKind { all, any, none }

extension GroupKindX on GroupKind {
  String get label => switch (this) {
    GroupKind.all => 'All of',
    GroupKind.any => 'Any of',
    GroupKind.none => 'None of',
  };
}

/// A node in the Advanced builder tree.
sealed class BuilderNode {
  BuilderNode({String? id}) : id = id ?? _nextId();

  /// Stable identity for widget keys and removal.
  final String id;

  static int _counter = 0;
  static String _nextId() => 'n${_counter++}';

  /// Folds this node to a [DanceFilter], or `null` if incomplete/empty.
  DanceFilter? toFilter();
}

/// A node that folds to a [FigureQuery], used as a [BuilderThen] operand and
/// as a child of a [BuilderFigureGroup]. Either a single [BuilderFigure] leaf
/// or a boolean group of figure leaves ([BuilderFigureGroup]).
///
/// Sealed so the UI can exhaustively switch over it.
sealed class BuilderFigureNode {
  /// Stable identity for widget keys.
  String get id;

  /// Folds this node to a [FigureQuery], or `null` if incomplete/empty.
  FigureQuery? toFigureQuery();
}

/// A boolean group: all-of (`AND`), any-of (`OR`), or none-of (`NOT` over the
/// OR of its children).
class BuilderGroup extends BuilderNode {
  BuilderGroup({
    this.kind = GroupKind.all,
    List<BuilderNode>? children,
    super.id,
  }) : children = children ?? [];

  GroupKind kind;
  final List<BuilderNode> children;

  @override
  DanceFilter? toFilter() {
    final parts = [for (final c in children) ?c.toFilter()];
    if (parts.isEmpty) return null;
    final one = parts.length == 1;
    return switch (kind) {
      GroupKind.all => one ? parts.single : AndFilter(parts),
      GroupKind.any => one ? parts.single : OrFilter(parts),
      GroupKind.none => NotFilter(one ? parts.single : OrFilter(parts)),
    };
  }
}

/// A "has figure" row: a move (required), an optional section, and optional
/// named params. Folds to a [FigureFilter] leaf, or a [FigureLeaf] when used as
/// a [ThenFilter] operand (via [BuilderFigureNode]).
class BuilderFigure extends BuilderNode implements BuilderFigureNode {
  BuilderFigure({
    this.move,
    this.section,
    Map<String, Object?>? params,
    super.id,
  }) : params = params ?? {};

  String? move;
  String? section;
  final Map<String, Object?> params;

  bool get isComplete => (move ?? '').trim().isNotEmpty;

  Map<String, Object?> get _cleanParams => {
    for (final e in params.entries)
      if (e.value != null) e.key: e.value,
  };

  @override
  FigureLeaf? toFigureQuery() => isComplete
      ? FigureLeaf(move!.trim(), params: _cleanParams, section: section)
      : null;

  @override
  DanceFilter? toFilter() {
    final leaf = toFigureQuery();
    return leaf == null ? null : FigureFilter(leaf);
  }
}

/// A "then" sequence row: figure [before] occurs earlier than figure [after].
/// Folds to a [ThenFilter]; needs both sides complete.
///
/// Each side is a [BuilderFigureNode] — either a single [BuilderFigure] (the
/// default) or a [BuilderFigureGroup] for richer "any of / all of / none of
/// these figures" operands.
class BuilderThen extends BuilderNode {
  BuilderThen({BuilderFigureNode? before, BuilderFigureNode? after, super.id})
    : before = before ?? BuilderFigure(),
      after = after ?? BuilderFigure();

  BuilderFigureNode before;
  BuilderFigureNode after;

  @override
  DanceFilter? toFilter() {
    final b = before.toFigureQuery();
    final a = after.toFigureQuery();
    return (b == null || a == null) ? null : ThenFilter(b, a);
  }
}

/// A boolean group of [BuilderFigureNode]s that folds to a [FigureQuery]:
///
/// - [GroupKind.all]  → [FigureAnd] (all these figure constraints match the same row)
/// - [GroupKind.any]  → [FigureOr]  (any of these figure constraints match the same row)
/// - [GroupKind.none] → [FigureNot] wrapping the effective children
///   ("no figure matching any of these"): [FigureNot] of a [FigureOr] when
///   there are multiple children, or [FigureNot] of the single child directly
///   when only one remains (the single-child optimisation below).
///
/// Incomplete children fold to `null` and are skipped, mirroring how
/// [BuilderGroup] handles [DanceFilter] nodes. A group whose effective
/// children reduce to a single node unwraps the redundant `all`/`any`
/// combinator (and `none` negates that single child directly) — matching
/// [BuilderGroup]'s "single-child" optimisation.
///
/// Children can themselves be [BuilderFigureGroup]s, so the model supports
/// arbitrary nesting; the UI currently exposes one level of nesting.
class BuilderFigureGroup implements BuilderFigureNode {
  BuilderFigureGroup({
    this.kind = GroupKind.any,
    List<BuilderFigureNode>? children,
    String? id,
  }) : id = id ?? _nextId(),
       children = children ?? [];

  static int _counter = 0;
  static String _nextId() => 'fg${_counter++}';

  @override
  final String id;

  GroupKind kind;
  final List<BuilderFigureNode> children;

  @override
  FigureQuery? toFigureQuery() {
    final parts = [for (final c in children) ?c.toFigureQuery()];
    if (parts.isEmpty) return null;
    final one = parts.length == 1;
    return switch (kind) {
      GroupKind.all => one ? parts.single : FigureAnd(parts),
      GroupKind.any => one ? parts.single : FigureOr(parts),
      GroupKind.none => FigureNot(one ? parts.single : FigureOr(parts)),
    };
  }
}
