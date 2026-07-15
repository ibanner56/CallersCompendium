import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device screen awake for the lifetime of a Perform view
/// (`docs/design/ux.md` §5; ROADMAP 5.2). A caller often props a tablet across
/// the room, so the screen must not auto-sleep while a large-print reading view
/// is on screen — and normal sleep behavior must resume the moment it leaves.
///
/// Mix into a Perform screen's [State]: the wake-lock is enabled in [initState]
/// and disabled in [dispose], so navigating away (pop back to detail/editor)
/// reliably releases it.
///
/// The wake-lock is a best-effort enhancement. [WakelockPlus] calls are guarded
/// so a `MissingPluginException` or an unsupported platform is a silent no-op
/// rather than an error surfaced in the reading view. Only [Exception]s are
/// swallowed — a Dart [Error] (a programming mistake) is left to surface.
///
/// The [T] type parameter is required so the `on State<T>` constraint binds to
/// each concrete `State<ConcreteScreen>`; dropping it (`on State`) resolves to
/// `State<StatefulWidget>`, which the concrete states do not implement.
mixin PerformWakelockMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    _setWakelock(true);
  }

  @override
  void dispose() {
    _setWakelock(false);
    super.dispose();
  }

  Future<void> _setWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } on Exception catch (_) {
      // Best-effort only: never let a plugin/platform *exception* crash the
      // Perform view. Dart `Error`s are intentionally not swallowed.
    }
  }
}
