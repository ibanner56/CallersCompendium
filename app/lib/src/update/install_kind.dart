/// How the running copy of the app was installed, so the updater only offers
/// what that copy can actually do (PLAT-5, PLAT-6).
///
/// The manifest describes the *sideloaded* release channel: an installer per
/// desktop OS, a sideload APK, and nothing for iOS. A copy installed any other
/// way cannot be updated from it, so the updater has to know the difference.
/// Detection is local and read-only; nothing here is transmitted anywhere
/// (ADR-002 §5).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_manifest.dart';

/// Set to `true` by the release workflow's Google Play `appbundle` build only,
/// so a Play install can tell itself apart from the sideload APK. Everything
/// else, including the signed sideload APK and local builds, leaves it off.
const bool kPlayStoreBuild = bool.fromEnvironment(
  'CALLERS_COMPENDIUM_PLAY_BUILD',
);

/// The file Inno Setup writes beside the installed executable. The installer
/// (`packaging/windows/CallersCompendium.iss`) leaves the uninstaller in the app folder (no UninstallFilesDir), so
/// the first uninstaller is always this one; the portable zip has none.
const String kWindowsUninstallerName = 'unins000.exe';

enum InstallKind {
  /// The sideloaded release channel (Windows installer, Linux AppImage, macOS
  /// dmg or zip, Android APK): the updater works as designed.
  standard,

  /// Installed from an app store (TestFlight, App Store or Google Play). The
  /// store updates it, so the app never offers an update; it only reads the
  /// release information for an end-of-support date.
  store,

  /// Unpacked from the Windows zip or the Linux tar.gz. The update is a new
  /// archive, which the app does not install; it points to the release.
  portable,
}

/// Detects how [platform] was installed.
///
/// * iOS is always [InstallKind.store]: there is no other way to run the app.
/// * Android is [InstallKind.store] when built for Google Play ([playBuild]).
/// * Windows is [InstallKind.portable] when there is no Inno uninstaller
///   beside the executable.
/// * Linux is [InstallKind.portable] unless the AppImage runtime set
///   `APPIMAGE`, which is how the tar.gz is told from the AppImage.
/// * macOS is always [InstallKind.standard]: the dmg and the zip both hold the
///   same `.app`.
///
/// Every input is injectable for tests; the defaults read the real process.
InstallKind detectInstallKind({
  required UpdatePlatform platform,
  bool playBuild = kPlayStoreBuild,
  Map<String, String>? environment,
  String? resolvedExecutable,
  bool Function(String path)? fileExists,
}) {
  switch (platform) {
    case UpdatePlatform.ios:
      return InstallKind.store;
    case UpdatePlatform.android:
      return playBuild ? InstallKind.store : InstallKind.standard;
    case UpdatePlatform.macos:
      return InstallKind.standard;
    case UpdatePlatform.linux:
      final appImage = (environment ?? Platform.environment)['APPIMAGE'];
      return appImage != null && appImage.isNotEmpty
          ? InstallKind.standard
          : InstallKind.portable;
    case UpdatePlatform.windows:
      final executable = resolvedExecutable ?? Platform.resolvedExecutable;
      final uninstaller = p.windows.join(
        p.windows.dirname(executable),
        kWindowsUninstallerName,
      );
      final exists = fileExists ?? (path) => File(path).existsSync();
      return exists(uninstaller) ? InstallKind.standard : InstallKind.portable;
  }
}

/// Where a store copy's end-of-support "Get update" goes (maintainer decision,
/// 2026-10-30). iOS has only the TestFlight public link (no App Store listing
/// exists yet, `docs/dev/store-submission/app-store.md`); Android is the Play
/// listing for the app's package id (`app/android/app/build.gradle.kts`).
/// Swap these when a public listing exists.
const String kTestFlightUrl = 'https://testflight.apple.com/join/REgW311w';
const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=org.callerscompendium.compendiumApp';

/// The store listing for [platform], or `null` where there is no store build.
String? storeListingUrlFor(UpdatePlatform platform) => switch (platform) {
  UpdatePlatform.ios => kTestFlightUrl,
  UpdatePlatform.android => kPlayStoreUrl,
  _ => null,
};
