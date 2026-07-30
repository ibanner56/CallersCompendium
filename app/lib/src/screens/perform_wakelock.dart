import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device screen awake for the lifetime of a Perform view
/// (`docs/design/ux.md` §5; ROADMAP 5.2). A caller often props a tablet across
/// the room, so the screen must not auto-sleep while a large-print reading view
/// is on screen — and normal sleep behavior must resume the moment it leaves.
///
/// Mix into a Perform screen's [State] alongside [WidgetsBindingObserver]:
///
/// ```dart
/// class _MyScreenState extends State<MyScreen>
///     with WidgetsBindingObserver, PerformWakelockMixin { ... }
/// ```
///
/// The wake-lock is enabled in [initState] and disabled in [dispose], so
/// navigating away (pop back to detail/editor) reliably releases it. Because
/// the OS drops an app's wake-lock while it is backgrounded, the mixin also
/// registers as a [WidgetsBindingObserver] and **re-asserts** the wake-lock in
/// [didChangeAppLifecycleState] when the app returns to
/// [AppLifecycleState.resumed] — otherwise a caller who briefly backgrounds the
/// app mid-gig would find the screen able to sleep again.
///
/// The wake-lock is a best-effort enhancement. [WakelockPlus] calls are guarded
/// so a `MissingPluginException` or an unsupported platform does not crash the
/// reading view — but, unlike the previous implementation, failures are **not
/// swallowed silently**: they are logged via [debugPrint] (a developer-facing
/// sink; deliberately not a user toast, which would be noise on a stage) so a
/// wake-lock that never engages is diagnosable. Only [Exception]s are caught —
/// a Dart [Error] (a programming mistake) is left to surface.
///
/// The [T] type parameter is required so the `on State<T>` constraint binds to
/// each concrete `State<ConcreteScreen>`; dropping it (`on State`) resolves to
/// `State<StatefulWidget>`, which the concrete states do not implement.
mixin PerformWakelockMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setWakelock(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setWakelock(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The platform releases the wake-lock while the app is backgrounded, so
    // re-assert it whenever we come back to the foreground and this Perform
    // view is still on screen (initState/dispose alone never re-fires here).
    if (state == AppLifecycleState.resumed && mounted) {
      _setWakelock(true);
    }
  }

  Future<void> _setWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } on Exception catch (error, stackTrace) {
      // Best-effort only: never let a plugin/platform *exception* crash the
      // Perform view. Log (don't swallow) so a wake-lock that never engages is
      // diagnosable; a user-facing toast would be noise on a stage. Dart
      // `Error`s are intentionally not caught.
      if (kDebugMode) {
        debugPrint(
          'PerformWakelockMixin: failed to '
          '${enable ? 'enable' : 'disable'} wake-lock: $error\n$stackTrace',
        );
      }
    }
  }
}
