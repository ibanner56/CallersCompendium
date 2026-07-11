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

/// The user's one-tap facet selections. Every facet is multi-select: within a
/// single facet the selected leaves are OR-ed ("has any of these tags"), and
/// distinct facets are AND-ed ("this form AND one of these tags") — the
/// confirmed decision 7 semantics, applied uniformly.
class FacetSelections {
  final Set<DanceForm> forms = {};
  final Set<FormationShape> formations = {};
  final Set<Progression> progressions = {};
  final Set<DanceStatus> statuses = {};
  final Set<String> authorIds = {};
  final Set<String> tagIds = {};

  /// Selected `choice` custom-field values, keyed by field id → chosen values
  /// (OR-within a field).
  final Map<String, Set<String>> choiceValues = {};

  /// Selected `boolean` custom-field values, keyed by field id → true/false.
  final Map<String, bool> booleanValues = {};

  bool get isEmpty =>
      forms.isEmpty &&
      formations.isEmpty &&
      progressions.isEmpty &&
      statuses.isEmpty &&
      authorIds.isEmpty &&
      tagIds.isEmpty &&
      choiceValues.values.every((s) => s.isEmpty) &&
      booleanValues.isEmpty;

  void clear() {
    forms.clear();
    formations.clear();
    progressions.clear();
    statuses.clear();
    authorIds.clear();
    tagIds.clear();
    choiceValues.clear();
    booleanValues.clear();
  }
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
  BuilderGroup? advancedRoot,
}) {
  final branches = <DanceFilter>[];

  final text = ftsText.trim();
  if (text.isNotEmpty) branches.add(FullTextFilter(text));

  void addOr(List<DanceFilter> leaves) {
    final g = orGroup(leaves);
    if (g != null) branches.add(g);
  }

  addOr([for (final f in facets.forms) FormFilter(f)]);
  addOr([for (final s in facets.formations) FormationFilter(s)]);
  addOr([for (final p in facets.progressions) ProgressionFilter(p)]);
  addOr([for (final s in facets.statuses) StatusFilter(s)]);
  addOr([for (final id in facets.authorIds) AuthorFilter(id)]);
  addOr([for (final id in facets.tagIds) TagFilter(id)]);

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

  final advanced = advancedRoot?.toFilter();
  if (advanced != null) branches.add(advanced);

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
  BuilderGroup? advancedRoot,
}) =>
    ftsText.trim().isNotEmpty &&
    facets.isEmpty &&
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
/// a [ThenFilter] operand.
class BuilderFigure extends BuilderNode {
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
class BuilderThen extends BuilderNode {
  BuilderThen({BuilderFigure? before, BuilderFigure? after, super.id})
    : before = before ?? BuilderFigure(),
      after = after ?? BuilderFigure();

  final BuilderFigure before;
  final BuilderFigure after;

  @override
  DanceFilter? toFilter() {
    final b = before.toFigureQuery();
    final a = after.toFigureQuery();
    return (b == null || a == null) ? null : ThenFilter(b, a);
  }
}
