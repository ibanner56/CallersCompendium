import 'filter.dart';

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

/// A node in the Advanced builder tree: a group, a "has figure" row, a "has
/// tag" row, or a "then" sequence row.
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

/// The "has tag" rows taken out of an Advanced query while a source that has no
/// tags (ContraDB) is searched, kept so they can be put back.
///
/// A tag row left in the query would keep that search from being sent, so
/// [take] removes every one, at any depth. [restoreInto] returns them, with
/// the tag each had picked, to the group each came from and the position it
/// had, once a source that can carry tags is searched again. A group the user
/// has since deleted sends its rows to the top level instead.
class RemovedTagRows {
  final List<_RemovedTag> _rows = [];

  /// How many rows are being kept.
  int get length => _rows.length;
  bool get isEmpty => _rows.isEmpty;

  /// Removes every "has tag" row from [root], at any depth, and remembers
  /// where each was.
  void take(BuilderGroup root) => _take(root);

  void _take(BuilderGroup group) {
    final kept = <BuilderNode>[];
    for (var i = 0; i < group.children.length; i++) {
      final child = group.children[i];
      if (child is BuilderTag) {
        _rows.add(_RemovedTag(group.id, i, child));
        continue;
      }
      if (child is BuilderGroup) _take(child);
      kept.add(child);
    }
    group.children
      ..clear()
      ..addAll(kept);
  }

  /// Puts every kept row back into [root] and forgets them; returns how many.
  int restoreInto(BuilderGroup root) {
    final count = _rows.length;
    for (final row in _rows) {
      final group = _findGroup(root, row.groupId) ?? root;
      final at = row.index < group.children.length
          ? row.index
          : group.children.length;
      group.children.insert(at, row.node);
    }
    _rows.clear();
    return count;
  }

  /// Forgets the kept rows without restoring them (the query was cleared).
  void clear() => _rows.clear();

  static BuilderGroup? _findGroup(BuilderGroup group, String id) {
    if (group.id == id) return group;
    for (final child in group.children) {
      if (child is BuilderGroup) {
        final found = _findGroup(child, id);
        if (found != null) return found;
      }
    }
    return null;
  }
}

class _RemovedTag {
  const _RemovedTag(this.groupId, this.index, this.node);
  final String groupId;
  final int index;
  final BuilderTag node;
}

/// A "has figure" row: a move, an optional section and optional named params,
/// or, with [isAnyFigure], any figure at all. Folds to a [FigureFilter] over a
/// [FigureLeaf] (or [anyFigure]), and to that query alone when used as a
/// [ThenFilter] operand (via [BuilderFigureNode]).
class BuilderFigure extends BuilderNode implements BuilderFigureNode {
  BuilderFigure({
    this.move,
    this.section,
    Map<String, Object?>? params,
    this.isAnyFigure = false,
    super.id,
  }) : params = params ?? {};

  String? move;
  String? section;
  final Map<String, Object?> params;

  /// Whether this row asks for any figure at all ([anyFigure]) instead of a
  /// move, so "swing, then anything" can be written. Such a row has no move,
  /// section or parameters.
  bool isAnyFigure;

  bool get isComplete => isAnyFigure || (move ?? '').trim().isNotEmpty;

  Map<String, Object?> get _cleanParams => {
    for (final e in params.entries)
      if (e.value != null) e.key: e.value,
  };

  @override
  FigureQuery? toFigureQuery() {
    if (isAnyFigure) return anyFigure;
    return (move ?? '').trim().isNotEmpty
        ? FigureLeaf(move!.trim(), params: _cleanParams, section: section)
        : null;
  }

  @override
  DanceFilter? toFilter() {
    final query = toFigureQuery();
    return query == null ? null : FigureFilter(query);
  }
}

/// A "has tag" row: the dance carries the tag [tagId]. Folds to the same
/// [TagFilter] leaf the Tag facet emits, so an all-of group of tag rows gives
/// "has tag A AND tag B", and tag rows can mix with figure rows in any group.
/// A row with no tag picked folds to `null` and is skipped.
class BuilderTag extends BuilderNode {
  BuilderTag({this.tagId, super.id});

  String? tagId;

  @override
  DanceFilter? toFilter() {
    final id = tagId;
    return (id == null || id.isEmpty) ? null : TagFilter(id);
  }
}

/// A "then" sequence row: figure [after] immediately follows figure [before]
/// (the dance is a loop, so the first figure follows the last).
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
