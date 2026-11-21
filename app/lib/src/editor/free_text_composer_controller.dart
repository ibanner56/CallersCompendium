import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lets the screen around a `FigureListEditor` see, and add, a line typed into
/// its free-text composer but not yet added with Enter (#419).
///
/// Such a line is not in the figure drafts, the autosave snapshot or the
/// dirty flag, so without this a Save or Back would lose it without a word.
/// The dance editor counts a pending line as unsaved ([hasPendingLine]) and
/// has Save add it first ([submitPendingLine]).
class FreeTextComposerController extends ChangeNotifier {
  bool Function()? _submit;
  bool _hasPendingLine = false;
  bool _disposed = false;

  /// Whether the composer is open and holds a line that is not blank.
  bool get hasPendingLine => _hasPendingLine;

  /// Adds the pending line exactly as pressing Enter in the composer would.
  /// Returns `true` when no line is left pending afterwards, so the caller may
  /// go on; `false` when a line is still in the box.
  bool submitPendingLine() {
    final submit = _submit;
    if (!_hasPendingLine || submit == null) return true;
    return submit();
  }

  /// Called by the composer's editor when it starts serving this controller.
  /// [submit] adds the pending line and returns whether none is left.
  void attach(bool Function() submit) => _submit = submit;

  /// Called by the composer's editor when it stops serving this controller,
  /// with the [submit] it attached. A replacement editor attaches before the
  /// one it replaces is disposed, so a [submit] other than the attached one
  /// is ignored rather than disconnecting the replacement.
  void detach(bool Function() submit) {
    if (_submit != submit) return;
    _submit = null;
    updatePendingLine(false);
  }

  /// Called by the composer's editor whenever its box changes.
  void updatePendingLine(bool pending) {
    if (_disposed || pending == _hasPendingLine) return;
    _hasPendingLine = pending;
    // The box can be cleared while the tree is being built (the composer
    // closes from `didUpdateWidget`), and a listener that rebuilds the screen
    // must not do that mid-build.
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
