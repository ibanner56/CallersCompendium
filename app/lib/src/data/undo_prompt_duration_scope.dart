import 'package:flutter/widgets.dart';

/// Persisted-settings key for how long the Undo prompt stays on screen. Stored
/// as an `int` number of seconds; [kUndoPromptUntilDismissed] (`0`) means it
/// stays until the user closes it. Unset means [kUndoPromptDefaultSeconds].
const String kUndoPromptSecondsKey = 'undo_prompt_seconds';

/// The stored value for "stay until I close it".
const int kUndoPromptUntilDismissed = 0;

/// How long the Undo prompt stays when the user has not chosen.
const int kUndoPromptDefaultSeconds = 10;

/// The timed choices offered in Settings, in seconds, shortest first. The
/// settings list adds [kUndoPromptUntilDismissed] after them.
const List<int> kUndoPromptSecondOptions = <int>[2, 5, 10, 15];

/// Maps a stored value to one of the offered choices: a choice or
/// [kUndoPromptUntilDismissed] as stored, anything else (absent, wrong type,
/// a number no version offers) to [kUndoPromptDefaultSeconds].
int undoPromptSecondsFromStored(Object? stored) =>
    stored is int &&
        (stored == kUndoPromptUntilDismissed ||
            kUndoPromptSecondOptions.contains(stored))
    ? stored
    : kUndoPromptDefaultSeconds;

/// Exposes the Undo prompt's duration setting as a live [ValueNotifier] of
/// seconds.
///
/// Mounted **above** `MaterialApp`, unlike the app's other preference scopes,
/// because `showUndoSnackBar` reads it from the `ScaffoldMessenger`'s context,
/// and `MaterialApp` builds its `ScaffoldMessenger` above
/// `MaterialApp.builder`, where the other scopes are folded in.
class UndoPromptDurationScope extends InheritedNotifier<ValueNotifier<int>> {
  const UndoPromptDurationScope({
    super.key,
    required ValueNotifier<int> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// The chosen duration, or `null` for "until I close it", read once: it
  /// registers **no** rebuild dependency, because the prompt reads it from the
  /// `ScaffoldMessenger`'s context at the moment it is shown, outside any
  /// build. [kUndoPromptDefaultSeconds] when there is no scope (focused widget
  /// tests), as when the user has not chosen.
  static Duration? read(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<UndoPromptDurationScope>();
    final seconds = scope?.notifier?.value ?? kUndoPromptDefaultSeconds;
    return seconds == kUndoPromptUntilDismissed
        ? null
        : Duration(seconds: seconds);
  }

  /// The stored number of seconds, for the settings control. Registers a
  /// rebuild dependency.
  static int secondsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<UndoPromptDurationScope>()
          ?.notifier
          ?.value ??
      kUndoPromptDefaultSeconds;

  /// The underlying notifier, so Settings can change the value. Does not
  /// register a rebuild dependency.
  static ValueNotifier<int> notifierOf(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<UndoPromptDurationScope>();
    if (scope == null) {
      throw FlutterError(
        'UndoPromptDurationScope.notifierOf() called with a context that has '
        'no UndoPromptDurationScope ancestor.',
      );
    }
    return scope.notifier!;
  }
}
