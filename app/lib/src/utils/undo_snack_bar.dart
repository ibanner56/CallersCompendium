import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/undo_prompt_duration_scope.dart';
import '../diagnostics/error_log.dart';
import '../theme/app_spacing.dart';

/// Shows the app-wide "Undo" prompt as a **transient** SnackBar.
///
/// Every undoable action in the app used to build a bare
/// `SnackBar(action: SnackBarAction(...))`. In Flutter 3.44.6 the `SnackBar`
/// constructor computes `persist = persist ?? action != null`, so any snackbar
/// with an action defaults to `persist: true` — and the scaffold's auto-dismiss
/// timer bails out (`if (snackBar.persist) return;`) for persisting snackbars.
/// The prompts therefore never went away, stacked on rapid actions, and sat over
/// the bottom navigation/controls (issue #463).
///
/// Routing every undo site through this helper fixes all of that centrally:
/// - [messenger].clearSnackBars() first, so rapid successive undoable actions
///   replace rather than stack.
/// - [SnackBarBehavior.floating] so the prompt floats above bottom-anchored
///   controls instead of covering them.
/// - a bounded duration so it auto-dismisses on its own: [duration] when the
///   caller passes one, otherwise the user's "Undo prompt" setting
///   ([UndoPromptDurationScope], read from [messenger]'s context).
/// - the prompt **stays while a mouse hovers it or keyboard focus is inside
///   it** (the Undo button, or the close button), and its full time starts
///   again once the pointer and focus have both left.
/// - **every key press starts its full time again**, so a keyboard user
///   tabbing toward Undo is not timed out mid-reach, however many stops lie
///   between the control that acted and the prompt (forty-odd on a long
///   list); its time runs out only once they have pressed nothing for that
///   long.
/// - **Ctrl-Z (Cmd-Z) presses its Undo** from anywhere, so a keyboard user
///   need not reach it at all: a key that nothing nearer the focus takes
///   ([FocusManager.addLateKeyEventHandler]). A text field keeps Ctrl-Z for
///   its own typing, and a page that binds the key itself (the dance
///   editor's own undo) keeps it too. Only the most recent prompt answers it.
/// - no time limit at all when assistive technology is active
///   ([accessibleNavigation]: screen-reader users keep as long as they need to
///   reach the action) or when the user chose "Until I close it"; such a prompt
///   shows a close button so it can still be put away.
///
/// The timing is this helper's own rather than the scaffold's: the snackbar is
/// shown with `persist: true`, so the scaffold's timer never fires, and the
/// prompt's content runs a timer it can pause. As the scaffold's did, it
/// starts once the prompt has finished coming in. The scaffold's
/// `_accessibleNavigation` handling only chooses jump-vs-animated *exit*; it
/// never stopped the auto-dismiss timer by itself, which is why persistence
/// has always had to be expressed here.
///
/// Takes a [ScaffoldMessengerState] (not a [BuildContext]) because several
/// callers capture the messenger up-front and only show the prompt after an
/// async gap / navigation that may have unmounted the originating widget.
/// Callers should likewise capture [accessibleNavigation] (via
/// `MediaQuery.accessibleNavigationOf(context)`) and [undoLabel] (via
/// `AppLocalizations.of(context).commonUndo`) before that gap.
///
/// [onUndo] may be async. It runs once the prompt has already closed, so a
/// failure has nowhere to surface unless this helper puts it somewhere: an
/// exception (sync or async) is logged and reported with a plain snackbar
/// reading [undoFailedMessage], rather than escaping to the zone log while the
/// caller believes the action was undone (audit FAIL-6). An Undo that can say
/// more about its own failure reports it itself and does not throw.
///
/// [key] is forwarded to the [SnackBar] and [actionKey] to its
/// [SnackBarAction], so existing widget-test keys are kept. [onVisible] is
/// forwarded to the [SnackBar]: it runs once the prompt has come in, and
/// again for each copy the messenger builds (see [_UndoPromptHold]).
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required String undoLabel,
  required FutureOr<void> Function() onUndo,
  required String undoFailedMessage,
  required bool accessibleNavigation,
  Key? key,
  Key? actionKey,
  Duration? duration,
  List<Widget> extraActions = const [],
  VoidCallback? onVisible,
}) {
  final chosen = duration ?? UndoPromptDurationScope.read(messenger.context);
  final timeout = accessibleNavigation ? null : chosen;
  final hold = _UndoPromptHold(messenger, timeout);
  void undo() => unawaited(_runUndo(messenger, onUndo, undoFailedMessage));
  messenger.clearSnackBars();
  final keys = _UndoPromptKeys(messenger, hold, undo);
  final controller = messenger.showSnackBar(
    SnackBar(
      key: key,
      content: _UndoPromptContent(
        message: message,
        hold: hold,
        extraActions: extraActions,
      ),
      behavior: SnackBarBehavior.floating,
      // Never read by the scaffold (persist is true); kept truthful for
      // anything that inspects the widget.
      duration: timeout ?? const Duration(seconds: kUndoPromptDefaultSeconds),
      persist: true,
      onVisible: onVisible,
      showCloseIcon: timeout == null,
      action: SnackBarAction(key: actionKey, label: undoLabel, onPressed: undo),
    ),
  );
  unawaited(
    controller.closed.then((_) {
      hold.close();
      keys.dispose();
    }),
  );
  return controller;
}

/// The one timer of one Undo prompt, shared by every copy of its content.
///
/// The messenger builds a snackbar into every Scaffold it serves, including
/// those of routes under the current one, so a prompt can have several
/// copies at once; and a later prompt with the same key reuses the earlier
/// one's widget state. The timer therefore belongs to the prompt (one
/// `showUndoSnackBar` call), not to a copy: it runs while at least one copy
/// is built (only the snackbar at the head of the queue is) and has finished
/// coming in, and pauses while any visible copy is hovered or holds focus.
/// Whenever it starts again, it starts from the full time.
class _UndoPromptHold {
  _UndoPromptHold(this.messenger, this.timeout);

  final ScaffoldMessengerState messenger;

  /// `null`: the prompt never times out.
  final Duration? timeout;

  final Set<Object> _copies = {};
  final Set<Object> _holders = {};
  Timer? _timer;
  bool _closed = false;

  bool get _held => _holders.isNotEmpty;

  /// The copy [who] has been built and has come in: the prompt is showing, so
  /// its time runs.
  void attach(Object who) {
    if (_copies.add(who) && _copies.length == 1) _restart();
  }

  /// The copy [who] has gone. With no copy left (the prompt moving between
  /// Scaffolds, or the whole tree going away) the time stops.
  void detach(Object who) {
    _copies.remove(who);
    setHeld(who, held: false);
    if (_copies.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Records whether the copy [who] is hovered or holds focus. The full time
  /// starts again once no copy does.
  void setHeld(Object who, {required bool held}) {
    final wasHeld = _held;
    if (held) {
      _holders.add(who);
    } else {
      _holders.remove(who);
    }
    if (_held == wasHeld) return;
    if (_held) {
      _timer?.cancel();
      _timer = null;
    } else {
      _restart();
    }
  }

  /// A key was pressed somewhere: someone at a keyboard is still on their way,
  /// so a running time starts again from the full time. A held or not yet
  /// started time is left alone.
  void keyPressed() {
    if (_timer != null) _restart();
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    final timeout = this.timeout;
    if (timeout == null || _closed || _copies.isEmpty || _held) return;
    _timer = Timer(timeout, _expire);
  }

  void _expire() {
    _timer = null;
    if (_closed || _held || !messenger.mounted) return;
    // A copy is built, and only the snackbar at the head of the queue is;
    // not closed means it is still that snackbar.
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
  }
}

/// The keyboard's way to one Undo prompt, for as long as it shows: any key
/// press starts its time again ([_UndoPromptHold.keyPressed]), and Ctrl-Z
/// (Cmd-Z) that nothing nearer the focus took presses its Undo.
class _UndoPromptKeys {
  _UndoPromptKeys(this.messenger, this.hold, this.undo) {
    _current = this;
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    FocusManager.instance.addLateKeyEventHandler(_onUnhandledKey);
  }

  /// The prompt shown last. An earlier one still closing, or one shown by
  /// another messenger, does not answer the key.
  static _UndoPromptKeys? _current;

  static const _undoKeys = [
    SingleActivator(LogicalKeyboardKey.keyZ, control: true),
    SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
  ];

  final ScaffoldMessengerState messenger;
  final _UndoPromptHold hold;
  final VoidCallback undo;
  bool _disposed = false;

  /// Sees every key before anything handles it, and never claims one.
  bool _onAnyKey(KeyEvent event) {
    if (event is! KeyUpEvent) hold.keyPressed();
    return false;
  }

  /// Called only for a key no focus node handled: a text field's own
  /// Ctrl-Z, or a page's, never reaches here.
  KeyEventResult _onUnhandledKey(KeyEvent event) {
    if (_disposed || !identical(_current, this)) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (!_undoKeys.any((key) => key.accepts(event, keyboard))) {
      return KeyEventResult.ignored;
    }
    // A text field with nothing to undo lets the key through; it is still
    // the field's key, not the prompt's.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    if (!messenger.mounted) return KeyEventResult.ignored;
    dispose();
    // As the Undo button does: the prompt closes, then the undo runs. This
    // prompt is the head of the queue until it closes (the helper cleared
    // the queue to show it), and it has not closed.
    messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
    undo();
    return KeyEventResult.handled;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    FocusManager.instance.removeLateKeyEventHandler(_onUnhandledKey);
    if (identical(_current, this)) _current = null;
  }
}

/// The prompt's message, reporting to its [_UndoPromptHold] whether the
/// pointer is over this copy or focus is inside it.
///
/// Lives in the content because a [SnackBar] takes no wrapper: the content is
/// the only widget of ours inside it. It therefore watches the whole snackbar
/// (the Undo button included) from outside the widget tree: hover through a
/// global pointer route tested against the snackbar's bounds, and focus
/// through [FocusManager]. A copy on a route that is not showing
/// ([TickerMode] off) never holds the prompt.
class _UndoPromptContent extends StatefulWidget {
  const _UndoPromptContent({
    required this.message,
    required this.hold,
    this.extraActions = const [],
  });

  final String message;

  /// Buttons shown after the message, for a prompt that needs more than its
  /// one Undo action (the startup calendar message's Show and Review, #2353).
  final List<Widget> extraActions;
  final _UndoPromptHold hold;

  @override
  State<_UndoPromptContent> createState() => _UndoPromptContentState();
}

class _UndoPromptContentState extends State<_UndoPromptContent> {
  bool _hovered = false;
  bool _focused = false;
  bool _visible = true;
  bool _listening = false;

  /// The [SnackBar]'s element, found once mounted: its render box is what a
  /// pointer is tested against, and focus inside it holds the prompt.
  Element? _snackBar;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(_UndoPromptContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A later prompt with the same key reuses this state: report to its hold
    // from now on, and stop holding the old one.
    if (!identical(oldWidget.hold, widget.hold)) {
      oldWidget.hold.detach(this);
      _snackBar = null;
      _attach();
    }
  }

  void _attach() {
    final timed = widget.hold.timeout != null;
    if (timed && !_listening) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      FocusManager.instance.addListener(_onFocusChanged);
      _listening = true;
    } else if (!timed && _listening) {
      _stopListening();
    }
    _attachWhenShown();
    _report();
  }

  /// The animation of the entrance this copy is waiting out, if any.
  Animation<double>? _entrance;

  /// Attaches to the hold once the snackbar has finished coming in, as the
  /// scaffold's own timer did: the time is the time the prompt is fully on
  /// screen, which matters at the shortest choice (2 s, of which the entrance
  /// would otherwise take a quarter of a second).
  void _attachWhenShown() {
    _stopWaitingForEntrance();
    final snackBar = _findSnackBar()?.widget;
    final animation = snackBar is SnackBar ? snackBar.animation : null;
    if (animation == null || animation.isCompleted) {
      widget.hold.attach(this);
      return;
    }
    _entrance = animation..addStatusListener(_onEntrance);
  }

  void _onEntrance(AnimationStatus status) {
    if (!status.isCompleted) return;
    _stopWaitingForEntrance();
    if (mounted) widget.hold.attach(this);
  }

  void _stopWaitingForEntrance() {
    _entrance?.removeStatusListener(_onEntrance);
    _entrance = null;
  }

  void _stopListening() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    FocusManager.instance.removeListener(_onFocusChanged);
    _listening = false;
  }

  @override
  void dispose() {
    if (_listening) _stopListening();
    _stopWaitingForEntrance();
    widget.hold.detach(this);
    super.dispose();
  }

  void _report() =>
      widget.hold.setHeld(this, held: _visible && (_hovered || _focused));

  Element? _findSnackBar() {
    if (_snackBar != null || !mounted) return _snackBar;
    context.visitAncestorElements((element) {
      if (element.widget is SnackBar) {
        _snackBar = element;
        return false;
      }
      return true;
    });
    return _snackBar;
  }

  void _onPointer(PointerEvent event) {
    if (!mounted) return;
    if (event is PointerRemovedEvent) {
      _hovered = false;
      _report();
      return;
    }
    // A hovering pointer (a mouse, or a stylus above the screen), or a mouse
    // dragging with a button down. A touch never hovers, so it never holds.
    final hovering =
        event is PointerHoverEvent ||
        (event is PointerMoveEvent && event.kind == PointerDeviceKind.mouse);
    if (!hovering) return;
    final box = _findSnackBar()?.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    _hovered = (Offset.zero & box.size).contains(local);
    _report();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final snackBar = _findSnackBar();
    final focused = FocusManager.instance.primaryFocus?.context;
    var inside = false;
    if (snackBar != null && focused != null) {
      if (identical(focused, snackBar)) {
        inside = true;
      } else {
        focused.visitAncestorElements((element) {
          if (identical(element, snackBar)) {
            inside = true;
            return false;
          }
          return true;
        });
      }
    }
    _focused = inside;
    _report();
  }

  @override
  Widget build(BuildContext context) {
    // Off on a route that is not showing: that copy is never what the user
    // points at or tabs to.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _visible) {
      _visible = visible;
      // After this build: reporting may restart the hold's timer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _report();
      });
    }
    if (widget.extraActions.isEmpty) return Text(widget.message);
    // Extra buttons sit on the snack bar's inverse surface: drawn in the
    // color its own action uses there, or they would barely read.
    return TextButtonTheme(
      data: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        children: [Text(widget.message), ...widget.extraActions],
      ),
    );
  }
}

Future<void> _runUndo(
  ScaffoldMessengerState messenger,
  FutureOr<void> Function() onUndo,
  String undoFailedMessage,
) async {
  try {
    await onUndo();
  } catch (error, stackTrace) {
    logCaughtError(error, stackTrace, source: 'showUndoSnackBar.onUndo');
    // The screen that offered the Undo may be gone, so there is no widget
    // check here, but the messenger itself must still be mounted: showing a
    // snackbar on a disposed one throws, inside an Undo that has already failed.
    if (!messenger.mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('undo-failed-snackbar'),
          content: Text(undoFailedMessage),
        ),
      );
  }
}
