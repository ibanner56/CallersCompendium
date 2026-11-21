import 'package:compendium_app/src/update/install_kind.dart';
import 'package:compendium_app/src/update/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _installedExe = r'C:\Program Files\Caller\compendium_app.exe';
const _portableExe = r'D:\Tools\Caller\compendium_app.exe';

InstallKind _windows(String exe, Set<String> files) => detectInstallKind(
  platform: UpdatePlatform.windows,
  resolvedExecutable: exe,
  fileExists: files.contains,
);

void main() {
  group('detectInstallKind', () {
    test('iOS is always a store build', () {
      expect(
        detectInstallKind(platform: UpdatePlatform.ios),
        InstallKind.store,
      );
    });

    test('Android is a store build only when built for Play', () {
      expect(
        detectInstallKind(platform: UpdatePlatform.android, playBuild: true),
        InstallKind.store,
      );
      expect(
        detectInstallKind(platform: UpdatePlatform.android, playBuild: false),
        InstallKind.standard,
      );
    });

    test('the Play define is off unless the Play build sets it', () {
      // Only release.yml's appbundle step passes CALLERS_COMPENDIUM_PLAY_BUILD.
      expect(kPlayStoreBuild, isFalse);
    });

    test('Windows is portable without an Inno uninstaller beside the exe', () {
      expect(
        _windows(_installedExe, {r'C:\Program Files\Caller\unins000.exe'}),
        InstallKind.standard,
      );
      expect(_windows(_portableExe, {}), InstallKind.portable);
      // An uninstaller elsewhere does not make this copy installed.
      expect(
        _windows(_portableExe, {r'C:\Program Files\Caller\unins000.exe'}),
        InstallKind.portable,
      );
    });

    test('Linux is portable unless the AppImage runtime set APPIMAGE', () {
      expect(
        detectInstallKind(
          platform: UpdatePlatform.linux,
          environment: {'APPIMAGE': '/home/me/Caller.AppImage'},
        ),
        InstallKind.standard,
      );
      expect(
        detectInstallKind(platform: UpdatePlatform.linux, environment: {}),
        InstallKind.portable,
      );
      expect(
        detectInstallKind(
          platform: UpdatePlatform.linux,
          environment: {'APPIMAGE': ''},
        ),
        InstallKind.portable,
      );
    });

    test('macOS is standard: the dmg and the zip hold the same app', () {
      expect(
        detectInstallKind(platform: UpdatePlatform.macos),
        InstallKind.standard,
      );
    });
  });
}
