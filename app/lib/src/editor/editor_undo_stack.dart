import 'editor_snapshot.dart';

/// Maximum number of undo entries to retain in memory.
const kUndoStackMax = 50;

/// In-memory, bounded undo/redo history of [EditorSnapshot] objects.
///
/// The history is a linear list with a current-index cursor:
/// - [push] adds a new snapshot (clearing any redo tail).
/// - [undo] steps the cursor back one and returns the prior snapshot.
/// - [redo] steps the cursor forward one and returns the next snapshot.
///
/// The oldest entries are evicted once [kUndoStackMax] is reached, so the
/// stack never grows beyond that limit.
class EditorUndoStack {
  final _history = <EditorSnapshot>[];
  int _index = -1;

  /// Whether there is a snapshot to undo to (cursor > 0).
  bool get canUndo => _index > 0;

  /// Whether there is a snapshot to redo to (cursor < end of list).
  bool get canRedo => _index < _history.length - 1;

  /// Number of snapshots currently stored.
  int get length => _history.length;

  /// The snapshot at the current cursor position, or `null` if the stack is
  /// empty (should not happen after [push] is called with the initial state).
  EditorSnapshot? get current => _index >= 0 ? _history[_index] : null;

  /// Pushes [snapshot] onto the history at the current position, clearing
  /// any redo tail.  Evicts the oldest entry when the stack is full.
  void push(EditorSnapshot snapshot) {
    // Clear redo history.
    if (_index < _history.length - 1) {
      _history.removeRange(_index + 1, _history.length);
    }

    _history.add(snapshot);

    // Evict oldest when over the limit.
    if (_history.length > kUndoStackMax) {
      _history.removeAt(0);
      // _index stays valid: we removed from the front, so the same logical
      // position is now at _index - 1... but we also just added at the end,
      // so the net effect is: old _index is still pointing to the same entry.
      // Actually: before add, length was kUndoStackMax+1; after removeAt(0)
      // length is kUndoStackMax, and _index = kUndoStackMax - 1 (last entry).
    } else {
      _index++;
    }
  }

  /// Steps the cursor back and returns the snapshot at the new position.
  /// Throws if [canUndo] is false.
  EditorSnapshot undo() {
    if (!canUndo) throw StateError('Nothing to undo');
    _index--;
    return _history[_index];
  }

  /// Steps the cursor forward and returns the snapshot at the new position.
  /// Throws if [canRedo] is false.
  EditorSnapshot redo() {
    if (!canRedo) throw StateError('Nothing to redo');
    _index++;
    return _history[_index];
  }

  /// Resets the stack to empty.
  void clear() {
    _history.clear();
    _index = -1;
  }
}
