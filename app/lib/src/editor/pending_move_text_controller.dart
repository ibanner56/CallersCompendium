import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lets the screen around a `FigureListEditor` see, and settle, text typed into
/// a figure's Move box but not yet applied with Enter (AUTH-1).
///
/// Leaving a Move box settles it: an exact move name or shorthand is applied,
/// and anything else goes back to what the row holds. Tapping Save does not
/// reliably take focus from the box, so the dance editor has Save settle it
/// first ([settle]), and counts text that leaving would apply as unsaved
/// ([hasPendingText]), as it does a line in the free-text composer.
///
/// Only the Move box that has focus can hold such text, so the controller
/// serves one box at a time: the one that attached last.
class PendingMoveTextController extends ChangeNotifier {
  VoidCallback? _settle;
  bool _hasPendingText = false;
  bool _disposed = false;

  /// Whether the Move box being typed in holds text that leaving it would
  /// apply: an exact move name or shorthand that is not what the row holds.
  bool get hasPendingText => _hasPendingText;

  /// Settles the Move box being typed in, as leaving it would. Does nothing
  /// when no box is being typed in.
  void settle() => _settle?.call();

  /// Called by a Move box when it takes focus. [settle] applies or reverts
  /// its text.
  void attach(VoidCallback settle) => _settle = settle;

  /// Called by a Move box when it loses focus or goes away, with the [settle]
  /// it attached. A box that took focus since has attached its own, so a
  /// [settle] other than the attached one is ignored.
  void detach(VoidCallback settle) {
    if (_settle != settle) return;
    _settle = null;
    updatePendingText(false);
  }

  /// Called by the attached Move box whenever its text changes.
  void updatePendingText(bool pending) {
    if (_disposed || pending == _hasPendingText) return;
    _hasPendingText = pending;
    // A box can be reset while the tree is being built (its row's move changed
    // under it), and a listener that rebuilds the screen must not do that
    // mid-build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Puts a [PendingMoveTextController] within reach of every Move box below it
/// that settles on blur (`MoveAutocomplete.commitOnBlur`), however deeply the
/// figure rows and their groups' sides are nested: the list a group draws for
/// a group inside it serves its boxes through the enclosing list's scope.
class PendingMoveTextScope extends InheritedWidget {
  const PendingMoveTextScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final PendingMoveTextController controller;

  /// The nearest scope's controller, or null when there is none. Read without
  /// depending on the scope: a box looks it up when it takes focus or its text
  /// changes, never while building.
  static PendingMoveTextController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PendingMoveTextScope>()?.controller;

  @override
  bool updateShouldNotify(PendingMoveTextScope oldWidget) =>
      controller != oldWidget.controller;
}
