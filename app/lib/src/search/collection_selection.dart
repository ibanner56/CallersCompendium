/// The Collection's multi-select set, and the policy for how it relates to the
/// list on screen (design note N4, `docs/design/bulk-selection.md`).
///
/// The set is deliberately **not** tied to the visible rows: a search that hides
/// a selected dance leaves it selected, so a caller can build a selection across
/// several searches (N4-1). Every batch action therefore acts on [ids], and the
/// screen shows how many of them [notShown] in the current results.
///
/// Pure Dart, so the policy is unit-tested without a widget tree.
class CollectionSelection {
  // Insertion-ordered, so a snapshot keeps tap order.
  final Set<String> _ids = {};

  /// The selected ids, as a copy the caller may keep or mutate. Batch handlers
  /// take one before they await, so a search that finishes mid-write cannot
  /// change what is being written.
  Set<String> snapshot() => Set<String>.of(_ids);

  int get length => _ids.length;
  bool get isEmpty => _ids.isEmpty;
  bool get isNotEmpty => _ids.isNotEmpty;
  bool contains(String id) => _ids.contains(id);

  /// Selects [id], or deselects it if it was selected.
  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
  }

  void add(String id) => _ids.add(id);

  void clear() => _ids.clear();

  /// How many selected ids are absent from [shown], the ids of the rows the
  /// list is showing.
  int notShown(Set<String> shown) =>
      _ids.fold(0, (n, id) => shown.contains(id) ? n : n + 1);

  /// Whether [shown] is non-empty and every id in it is selected.
  bool coversAll(Iterable<String> shown) =>
      shown.isNotEmpty && shown.every(_ids.contains);

  /// Selects every id in [shown]. Selections outside [shown] are kept.
  void selectAll(Iterable<String> shown) => _ids.addAll(shown);

  /// Deselects every id in [shown]. Selections outside [shown] are kept: they
  /// are the hidden rows [deselectNotShown] is for.
  void deselectAll(Iterable<String> shown) => _ids.removeAll(shown);

  /// Drops every selected id that is not in [shown], keeping the rest.
  void deselectNotShown(Set<String> shown) =>
      _ids.removeWhere((id) => !shown.contains(id));

  /// Drops ids that no longer name a dance in [existing] (deleted here or
  /// synced away). Those are not "hidden", they are gone: left in, the title
  /// would count dances that do not exist. Returns whether anything was dropped.
  bool reconcile(Set<String> existing) {
    final before = _ids.length;
    _ids.removeWhere((id) => !existing.contains(id));
    return _ids.length != before;
  }
}
