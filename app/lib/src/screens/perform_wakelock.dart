import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../diagnostics/error_log.dart';

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
/// Enable and disable are **idempotent and serialised**: the mixin tracks
/// whether it holds the lock and chains every operation behind the previous
/// one. `WakelockPlus.toggle(enable: true)` is not idempotent on every platform
/// (the Linux portal opens a fresh inhibit each time and a single disable closes
/// only the last), so a resume while the lock is held issues nothing, and a
/// dispose while an enable is still in flight disables only after that enable
/// finishes. Backgrounding releases the lock explicitly, so the resume that
/// follows re-acquires it exactly once.
///
/// The wake-lock is a best-effort enhancement. [WakelockPlus] calls are guarded
/// so a `MissingPluginException` or an unsupported platform does not crash the
/// reading view — but, unlike the previous implementation, failures are **not
/// swallowed silently**: they are logged via [debugPrint] (a developer-facing
/// sink; deliberately not a user toast, which would be noise on a stage) so a
/// wake-lock that never engages is diagnosable. A Dart [Error] (a programming
/// mistake in the plugin or here) is not treated as a best-effort failure: it
/// is reported through [FlutterError.reportError], which reaches the crash log
/// as an uncaught error does. Either way the operation chain carries on, so a
/// failure cannot stop a later disable — including the one in [dispose] — from
/// running.
///
/// The [T] type parameter is required so the `on State<T>` constraint binds to
/// each concrete `State<ConcreteScreen>`; dropping it (`on State`) resolves to
/// `State<StatefulWidget>`, which the concrete states do not implement.
mixin PerformWakelockMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  /// Whether this view holds the lock; `null` when an operation failed with an
  /// [Error] and the platform state is unknown, so the next operation in
  /// either direction is issued rather than skipped.
  bool? _wakelockHeld = false;
  Future<void> _wakelockOp = Future<void>.value();

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
    // release it explicitly on `paused` (keeping the held flag in step with
    // the platform) and re-assert it whenever we come back to the foreground
    // and this Perform view is still on screen (initState/dispose alone never
    // re-fires here). A `resumed` while the lock is still held is a no-op.
    if (state == AppLifecycleState.paused) {
      _setWakelock(false);
    } else if (state == AppLifecycleState.resumed && mounted) {
      _setWakelock(true);
    }
  }

  /// Queues [enable] behind any operation in flight. The held check runs when
  /// the operation's turn comes, so two rapid resumes, or a resume racing
  /// [dispose], cannot interleave. Never throws, and [_wakelockOp] never
  /// completes with an error: [_applyWakelock] catches everything, so one
  /// failed operation cannot skip the ones queued after it. Callers do not
  /// await it ([dispose] cannot await).
  void _setWakelock(bool enable) {
    _wakelockOp = _wakelockOp.then((_) => _applyWakelock(enable));
  }

  Future<void> _applyWakelock(bool enable) async {
    if (enable == _wakelockHeld) return;
    try {
      await WakelockPlus.toggle(enable: enable);
      _wakelockHeld = enable;
    } on Exception catch (error, stackTrace) {
      // Best-effort only: never let a plugin/platform *exception* crash the
      // Perform view. Log (don't swallow) so a wake-lock that never engages is
      // diagnosable; a user-facing toast would be noise on a stage. Dart
      // `Error`s are handled separately below.
      if (kDebugMode) {
        debugPrint(
          'PerformWakelockMixin: failed to '
          '${enable ? 'enable' : 'disable'} wake-lock: $error\n$stackTrace',
        );
      }
      logCaughtError(
        error,
        stackTrace,
        source: 'perform_wakelock._setWakelock',
      );
    } catch (error, stackTrace) {
      // diagnostics: silent — a Dart `Error` is a programming mistake, not a
      // best-effort platform failure, so it goes to `FlutterError.reportError`
      // (which the crash reporter's `FlutterError.onError` records) instead of
      // `logCaughtError`; logging it here as well would record it twice. It is
      // caught at all only so it cannot fail `_wakelockOp` and skip every
      // later operation, including the disable on exit (flows-4). Whether the
      // platform changed state is unknown, so the next operation is issued
      // whichever way it goes.
      _wakelockHeld = null;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'perform_wakelock',
          context: ErrorDescription(
            'while trying to ${enable ? 'enable' : 'disable'} the wake-lock',
          ),
        ),
      );
    }
  }
}
