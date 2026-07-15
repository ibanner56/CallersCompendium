import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// In-memory fake for [UrlLauncherPlatform] used by widget/unit tests.
///
/// `url_launcher` routes every launch through [UrlLauncherPlatform.instance];
/// installing this fake lets tests assert which URL was launched (and with
/// which [PreferredLaunchMode]) without a real platform channel. Mirrors the
/// `fake_wakelock.dart` pattern. Uses [MockPlatformInterfaceMixin] with
/// `implements` so it passes [PlatformInterface.verify] without extending the
/// real interface.
class FakeUrlLauncher
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  /// URLs passed to [launchUrl], in call order.
  final List<String> launchedUrls = <String>[];

  /// Launch modes passed to [launchUrl], in call order.
  final List<PreferredLaunchMode> launchedModes = <PreferredLaunchMode>[];

  /// What [launchUrl]/[launch] should return when they don't throw.
  bool launchResult = true;

  /// When set, [launchUrl]/[launch] throw this instead of returning.
  Object? throwOnLaunch;

  /// The most recently launched URL, or `null` if none.
  String? get lastLaunchedUrl =>
      launchedUrls.isEmpty ? null : launchedUrls.last;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    launchedModes.add(options.mode);
    final err = throwOnLaunch;
    if (err != null) throw err;
    return launchResult;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    final err = throwOnLaunch;
    if (err != null) throw err;
    return launchResult;
  }

  @override
  Future<void> closeWebView() async {}

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;
}

/// Installs a [FakeUrlLauncher] as the active platform implementation and
/// registers an [addTearDown] restoring the previous instance. Returns the fake
/// so tests can inspect launched URLs. Call from `setUp` or the test body.
FakeUrlLauncher installFakeUrlLauncher() {
  final previous = UrlLauncherPlatform.instance;
  final fake = FakeUrlLauncher();
  UrlLauncherPlatform.instance = fake;
  addTearDown(() {
    UrlLauncherPlatform.instance = previous;
  });
  return fake;
}
