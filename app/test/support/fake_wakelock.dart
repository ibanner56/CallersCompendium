import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// In-memory fake for [WakelockPlusPlatformInterface] used by widget tests.
///
/// `wakelock_plus` routes through a platform channel. The production
/// [PerformWakelockMixin] swallows the resulting `MissingPluginException`, so a
/// fake isn't needed to keep a pumped Perform screen from crashing — it's here
/// so tests can *assert* enable/disable behavior (and to avoid unhandled
/// channel errors leaking into other test contexts). Extending the platform
/// interface (rather than `implements`) satisfies `PlatformInterface.verify`,
/// so no mockito/`isMock` backdoor is needed.
///
/// Records the current lock state and every toggle so tests can assert that the
/// wake-lock is enabled while a Perform view is shown and disabled after it is
/// dismissed.
class FakeWakelockPlus extends WakelockPlusPlatformInterface {
  bool isEnabled = false;
  final List<bool> toggles = <bool>[];

  @override
  Future<void> toggle({required bool enable}) async {
    isEnabled = enable;
    toggles.add(enable);
  }

  @override
  Future<bool> get enabled async => isEnabled;
}

/// Installs a [FakeWakelockPlus] as the active platform implementation and
/// registers an [addTearDown] that restores the previous instance. Returns the
/// fake so tests can inspect enable/disable state. Call from `setUp`.
///
/// `WakelockPlus` resolves its backend through the `@visibleForTesting`
/// top-level [wakelockPlusPlatformInstance] (bound once, then cached), so that
/// — rather than `WakelockPlusPlatformInterface.instance` — is what must be
/// overridden for the fake to receive calls across every test.
FakeWakelockPlus installFakeWakelock() {
  final previous = wakelockPlusPlatformInstance;
  final fake = FakeWakelockPlus();
  wakelockPlusPlatformInstance = fake;
  addTearDown(() {
    wakelockPlusPlatformInstance = previous;
  });
  return fake;
}
