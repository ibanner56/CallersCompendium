import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/licenses.dart';

/// Every bundled font's licence text must reach the in-app licence page.
///
/// The OFL requires the licence to travel with each bundled font. Adding a
/// `assets/fonts/<Family>-OFL.txt` file is not enough: it must also be declared
/// under `flutter/assets` in `pubspec.yaml` (else `rootBundle` cannot load it)
/// and listed in `_bundledFontLicenses` (else `showLicensePage` never shows
/// it). Nothing else checks either, so a new font could ship without its
/// licence. `licenses_notice_test.dart` covers the ported-code notices.
///
/// Like that file, this one uses plain `test`s: enumerating `LicenseRegistry`
/// after `testWidgets` cases have run can hang on the asset loads.
String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `flutter test` runs from `app/`, where `assets/` and `pubspec.yaml` live.
  final licenseFiles =
      Directory('assets/fonts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('-OFL.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  String assetPath(File f) => 'assets/fonts/${f.uri.pathSegments.last}';

  test('there are bundled font licence files to check', () {
    // A wrong working directory would make the loops below vacuous.
    expect(licenseFiles, isNotEmpty);
  });

  test('every font licence file is declared in pubspec.yaml', () {
    final declared = File('pubspec.yaml')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('- assets/'))
        .map((l) => l.substring(2).trim())
        .toSet();
    for (final file in licenseFiles) {
      expect(declared, contains(assetPath(file)), reason: file.path);
    }
  });

  test('every font licence file is registered with the licence page', () async {
    LicenseRegistry.reset();
    resetBundledLicensesForTest();
    registerBundledLicenses();

    // Real LicenseRegistry and rootBundle, so an undeclared asset fails too.
    final entries = await LicenseRegistry.licenses.toList().timeout(
      const Duration(seconds: 20),
    );
    final registered = [
      for (final e in entries)
        _collapse(e.paragraphs.map((p) => p.text).join(' ')),
    ];
    for (final file in licenseFiles) {
      expect(
        registered,
        contains(_collapse(file.readAsStringSync())),
        reason: '${assetPath(file)} has no _bundledFontLicenses entry',
      );
    }
  });
}
