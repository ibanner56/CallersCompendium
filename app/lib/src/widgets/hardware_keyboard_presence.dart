import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether a hardware keyboard is likely attached, so a keyboard-shortcut hint
/// is worth showing.
///
/// Flutter has no "keyboard connected" signal, so this is inferred:
/// - On **macOS, Windows and Linux** a keyboard is assumed.
/// - On **iOS, Android and Fuchsia** (a tablet, usually) none is assumed until
///   a key that only a hardware keyboard sends is pressed, and from then on,
///   for the rest of the run, one is. An iPad with no keyboard therefore shows
///   no "⌘K" hint, and one with a keyboard shows it from the first such key.
///
/// Only a letter, Tab, or a Control, Command (Meta) or Alt key counts. Other
/// key events also reach the app without a keyboard: an on-screen keyboard
/// may send Backspace, Enter, arrows or digits as key events, and Android
/// sends its volume buttons and the system Back button as keys.
///
/// The listener is added when the app shell starts ([ensureListening]), so a
/// key pressed before the rail is first shown still counts.
///
/// The platform is read from the ambient [Theme], as the shortcut hints
/// themselves are, so a platform override in a test or preview reaches it.
abstract final class HardwareKeyboardPresence {
  static final ValueNotifier<bool> _keyPressed = ValueNotifier<bool>(false);
  static bool _listening = false;

  static final Set<LogicalKeyboardKey> _keyboardOnlyKeys = {
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  };

  static bool _onlyFromAKeyboard(LogicalKeyboardKey key) =>
      _keyboardOnlyKeys.contains(key) ||
      (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
          key.keyId <= LogicalKeyboardKey.keyZ.keyId);

  /// Whether [platform] is one where a keyboard is assumed without evidence.
  static bool _assumesKeyboard(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => false,
  };

  static bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        !_keyPressed.value &&
        _onlyFromAKeyboard(event.logicalKey)) {
      _keyPressed.value = true;
    }
    // Observe only: never consume the key.
    return false;
  }

  /// Starts watching for key presses; called once the app shell starts, and
  /// again (harmlessly) by [builder].
  static void ensureListening() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Rebuilds [builder] with whether a hardware keyboard is likely present.
  static Widget builder({
    required Widget Function(BuildContext context, bool present) builder,
  }) {
    ensureListening();
    return ValueListenableBuilder<bool>(
      valueListenable: _keyPressed,
      builder: (context, pressed, _) => builder(
        context,
        pressed || _assumesKeyboard(Theme.of(context).platform),
      ),
    );
  }

  /// Forgets any key press seen, so each test starts from a fresh run. The
  /// test binding also drops every key handler between tests, so the handler
  /// is added again on next use.
  @visibleForTesting
  static void debugReset() {
    _keyPressed.value = false;
    _listening = false;
  }
}
