import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _applicationName = "Caller's Compendium";
const _bundleName = 'Caller’s Compendium';

void main() {
  test('macOS bundle and release packaging use the display name', () {
    expect(
      File('macos/Runner/Info.plist').readAsStringSync(),
      contains('<key>CFBundleDisplayName</key>\n\t<string>$_applicationName</string>'),
    );
    expect(
      File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync(),
      contains('PRODUCT_NAME = $_bundleName'),
    );
    expect(
      File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      contains('path = "$_bundleName.app"'),
    );
    expect(
      File('macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme')
          .readAsStringSync(),
      contains('BuildableName = "$_bundleName.app"'),
    );
    expect(
      File('../.github/workflows/release.yml').readAsStringSync(),
      contains('Release/$_bundleName.app'),
    );
  });
}
