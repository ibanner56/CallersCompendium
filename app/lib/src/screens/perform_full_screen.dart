import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../diagnostics/error_log.dart';
import 'perform_card.dart' show PerformMenuAction;

/// How a platform takes Perform full screen (PLAT-9; `docs/design/ux.md` §5).
enum PerformFullScreenSupport {
  /// Nothing to do: web, where the browser owns the page.
  none,

  /// Phones and tablets: Perform hides the status and navigation bars for as
  /// long as it is on screen. There is no toggle.
  immersive,

  /// Desktop: the caller toggles window full screen from the toolbar or the
  /// keyboard (F11; Ctrl-Cmd-F on macOS).
  window,
}

/// The platform calls behind [PerformFullScreenMixin], kept behind one seam so
/// widget tests can install a fake with [performFullScreenBackend].
abstract class PerformFullScreenBackend {
  const PerformFullScreenBackend();

  PerformFullScreenSupport get support;

  /// Hides ([on]) or restores the system bars. [PerformFullScreenSupport.immersive]
  /// only.
  Future<void> setImmersive(bool on);

  /// Whether the window is full screen now, by whatever means it got there.
  /// [PerformFullScreenSupport.window] only.
  Future<bool> isWindowFullScreen();

  /// Enters ([on]) or leaves window full screen.
  /// [PerformFullScreenSupport.window] only.
  Future<void> setWindowFullScreen(bool on);

  /// Calls [onChanged] whenever the window enters or leaves full screen,
  /// including through the OS's own control (the macOS green button, or the
  /// menu item B29 adds). Returns the function that stops watching.
  /// [PerformFullScreenSupport.window] only.
  VoidCallback watchWindowFullScreen(ValueChanged<bool> onChanged);
}

/// The production backend: `SystemChrome` on phones, `window_manager` on
/// desktop. Chooses by [defaultTargetPlatform], so a test that overrides the
/// target platform without installing a fake reaches the real plugin calls,
/// which fail in a test and are logged rather than thrown.
class PlatformPerformFullScreenBackend extends PerformFullScreenBackend {
  const PlatformPerformFullScreenBackend();

  @override
  PerformFullScreenSupport get support {
    if (kIsWeb) return PerformFullScreenSupport.none;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS => PerformFullScreenSupport.immersive,
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => PerformFullScreenSupport.window,
      TargetPlatform.fuchsia => PerformFullScreenSupport.none,
    };
  }

  @override
  Future<void> setImmersive(bool on) => on
      // Sticky: a swipe from the edge shows the bars briefly, then they hide
      // again, so a caller who brushes the edge mid-dance is not left with
      // the notification shade over the card.
      ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
      // Every overlay showing is the engine's own default, which the app never
      // changes anywhere else, so this restores the state Perform found.
      : SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );

  @override
  Future<bool> isWindowFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setWindowFullScreen(bool on) => windowManager.setFullScreen(on);

  @override
  VoidCallback watchWindowFullScreen(ValueChanged<bool> onChanged) {
    final listener = _FullScreenWindowListener(onChanged);
    windowManager.addListener(listener);
    return () => windowManager.removeListener(listener);
  }
}

class _FullScreenWindowListener with WindowListener {
  _FullScreenWindowListener(this._onChanged);

  final ValueChanged<bool> _onChanged;

  @override
  void onWindowEnterFullScreen() => _onChanged(true);

  @override
  void onWindowLeaveFullScreen() => _onChanged(false);
}

/// The backend every Perform view uses. Tests replace it and restore it in a
/// tear-down.
@visibleForTesting
PerformFullScreenBackend performFullScreenBackend =
    const PlatformPerformFullScreenBackend();

/// Toggles window full screen in a Perform view. Bound to F11, or Ctrl-Cmd-F on
/// macOS, by [PerformFullScreenMixin.buildPerformFullScreenShortcuts]; a
/// toolbar button or a menu item can invoke it through the view's actions from
/// inside the view. Does nothing where full screen is not a toggle.
class TogglePerformFullScreenIntent extends Intent {
  const TogglePerformFullScreenIntent();
}

/// Leaves window full screen in a Perform view, bound to Escape.
///
/// Its action is always enabled and always consumes the key, even when the
/// window is not full screen: Escape must never fall through to an ancestor
/// that would treat it as "back", because leaving Perform takes a deliberate
/// confirmation (`docs/design/ux.md` §5). An overlay inside the view that binds
/// Escape itself, such as the walkthrough, still gets it first.
class ExitPerformFullScreenIntent extends Intent {
  const ExitPerformFullScreenIntent();
}

/// Takes a Perform view full screen (PLAT-9; `docs/design/ux.md` §5) and puts
/// the screen back the way it found it when the view goes.
///
/// - **Phones and tablets** go immersive for as long as the view is mounted:
///   the status and navigation bars hide, and come back on [dispose].
/// - **Desktop** offers a toggle, through [togglePerformFullScreen] and the
///   keys in [buildPerformFullScreenShortcuts]. The view tracks the window's
///   real state, so leaving full screen through the OS updates the toolbar
///   too. On [dispose] the window returns to whatever it was when the view
///   opened: a window that was already full screen stays so, and one the
///   caller took full screen in Perform leaves it.
///
/// A window closed while full screen does not reopen at full-screen size:
/// `WindowService` persists no frame while the window is full screen.
///
/// Platform calls are serialised and best effort, like
/// [PerformWakelockMixin]: an exception is logged and the chain carries on, so
/// a failed enter cannot stop the restore in [dispose].
///
/// Mix into a Perform screen's [State]:
///
/// ```dart
/// class _MyScreenState extends State<MyScreen>
///     with WidgetsBindingObserver, PerformWakelockMixin, PerformFullScreenMixin
/// ```
mixin PerformFullScreenMixin<T extends StatefulWidget> on State<T> {
  late final PerformFullScreenBackend _fullScreenBackend =
      performFullScreenBackend;
  Future<void> _fullScreenOp = Future<void>.value();
  VoidCallback? _stopWatchingFullScreen;

  /// Whether the window was full screen when this view opened; `null` until
  /// the first query answers.
  bool? _fullScreenOnEntry;

  bool _performFullScreen = false;

  /// Whether the window is full screen now. Always false on phones, where
  /// immersive mode is not a toggle.
  bool get performFullScreen => _performFullScreen;

  /// Whether this platform offers a full-screen toggle, so the view shows the
  /// toolbar button.
  bool get canTogglePerformFullScreen =>
      _fullScreenBackend.support == PerformFullScreenSupport.window;

  @override
  void initState() {
    super.initState();
    switch (_fullScreenBackend.support) {
      case PerformFullScreenSupport.none:
        break;
      case PerformFullScreenSupport.immersive:
        _queueFullScreenOp(
          'enter immersive mode',
          () => _fullScreenBackend.setImmersive(true),
        );
      case PerformFullScreenSupport.window:
        _stopWatchingFullScreen = _fullScreenBackend.watchWindowFullScreen(
          _onWindowFullScreenChanged,
        );
        _queueFullScreenOp('read the full-screen state', () async {
          final on = await _fullScreenBackend.isWindowFullScreen();
          _fullScreenOnEntry = on;
          _onWindowFullScreenChanged(on);
        });
    }
  }

  @override
  void dispose() {
    _stopWatchingFullScreen?.call();
    _stopWatchingFullScreen = null;
    switch (_fullScreenBackend.support) {
      case PerformFullScreenSupport.none:
        break;
      case PerformFullScreenSupport.immersive:
        _queueFullScreenOp(
          'leave immersive mode',
          () => _fullScreenBackend.setImmersive(false),
        );
      case PerformFullScreenSupport.window:
        // Queued, so it runs after an entry query or a toggle still in
        // flight, and reads the state they leave behind. A view whose entry
        // query failed does not know what to restore, so it leaves full
        // screen if it is in it: a window stuck full screen after Perform is
        // the worse outcome.
        _queueFullScreenOp('restore the window', () async {
          final restoreTo = _fullScreenOnEntry ?? false;
          if (_performFullScreen != restoreTo) {
            await _fullScreenBackend.setWindowFullScreen(restoreTo);
          }
        });
    }
    super.dispose();
  }

  /// Enters or leaves window full screen. A no-op where
  /// [canTogglePerformFullScreen] is false.
  void togglePerformFullScreen() {
    if (!canTogglePerformFullScreen) return;
    _queueFullScreenOp('toggle full screen', () async {
      if (!mounted) return;
      final on = !_performFullScreen;
      await _fullScreenBackend.setWindowFullScreen(on);
      _onWindowFullScreenChanged(on);
    });
  }

  /// Leaves window full screen if the window is in it.
  void exitPerformFullScreen() {
    if (!canTogglePerformFullScreen) return;
    _queueFullScreenOp('leave full screen', () async {
      if (!mounted || !_performFullScreen) return;
      await _fullScreenBackend.setWindowFullScreen(false);
      _onWindowFullScreenChanged(false);
    });
  }

  /// The toolbar toggle, for the view's inline actions: empty where full
  /// screen is not a toggle.
  List<Widget> get performFullScreenInlineActions => [
    if (canTogglePerformFullScreen)
      IconButton(
        key: const ValueKey('perform-full-screen'),
        tooltip: AppLocalizations.of(context).performFullScreen,
        isSelected: _performFullScreen,
        icon: const Icon(Icons.fullscreen),
        selectedIcon: const Icon(Icons.fullscreen_exit),
        onPressed: togglePerformFullScreen,
      ),
  ];

  /// The same toggle for the narrow-window overflow menu.
  List<PerformMenuAction> get performFullScreenMenuActions => [
    if (canTogglePerformFullScreen)
      PerformMenuAction(
        menuKey: const ValueKey('perform-full-screen-menu'),
        icon: Icons.fullscreen,
        label: AppLocalizations.of(context).performFullScreen,
        toggledOn: _performFullScreen,
        onSelected: togglePerformFullScreen,
      ),
  ];

  /// The keys for this view's full-screen intents, by platform.
  Map<ShortcutActivator, Intent> get _fullScreenShortcuts => {
    if (canTogglePerformFullScreen)
      defaultTargetPlatform == TargetPlatform.macOS
              ? const SingleActivator(
                  LogicalKeyboardKey.keyF,
                  control: true,
                  meta: true,
                )
              : const SingleActivator(LogicalKeyboardKey.f11):
          const TogglePerformFullScreenIntent(),
    const SingleActivator(LogicalKeyboardKey.escape):
        const ExitPerformFullScreenIntent(),
  };

  /// Wraps the view's scaffold so its full-screen keys work wherever focus is
  /// inside it, toolbar included, and so the intents can be invoked from
  /// anywhere below it.
  Widget buildPerformFullScreenShortcuts({required Widget child}) {
    return Shortcuts(
      shortcuts: _fullScreenShortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          TogglePerformFullScreenIntent:
              CallbackAction<TogglePerformFullScreenIntent>(
                onInvoke: (_) {
                  togglePerformFullScreen();
                  return null;
                },
              ),
          ExitPerformFullScreenIntent:
              CallbackAction<ExitPerformFullScreenIntent>(
                onInvoke: (_) {
                  exitPerformFullScreen();
                  return null;
                },
              ),
        },
        child: child,
      ),
    );
  }

  /// Records the window's state. The field is kept even once the view is
  /// unmounted: a toggle that lands after [dispose] queued its restore must
  /// still tell that restore what to undo.
  void _onWindowFullScreenChanged(bool on) {
    if (on == _performFullScreen) return;
    if (mounted) {
      setState(() => _performFullScreen = on);
    } else {
      _performFullScreen = on;
    }
  }

  /// Runs [op] after every operation already queued. Never throws, and
  /// [_fullScreenOp] never completes with an error, so a failure cannot skip
  /// the restore queued by [dispose].
  void _queueFullScreenOp(String what, Future<void> Function() op) {
    _fullScreenOp = _fullScreenOp.then((_) async {
      try {
        await op();
      } on Exception catch (error, stackTrace) {
        // Best effort, like the wake-lock: a missing plugin or a refused
        // platform call must not break the reading view, and a toast would be
        // noise on a stage.
        if (kDebugMode) {
          debugPrint('PerformFullScreenMixin: failed to $what: $error');
        }
        logCaughtError(
          error,
          stackTrace,
          source: 'perform_full_screen._queueFullScreenOp',
        );
      } catch (error, stackTrace) {
        // diagnostics: silent — a Dart `Error` is a programming mistake, so it
        // goes to `FlutterError.reportError` (which the crash reporter
        // records) instead of `logCaughtError`; caught at all only so the
        // chain, and the restore in `dispose`, carry on.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'perform_full_screen',
            context: ErrorDescription('while trying to $what'),
          ),
        );
      }
    });
  }
}
