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

  test('every bundled font file has a licence file', () {
    // Start from the fonts, not the licence files: a font added without its
    // licence leaves `licenseFiles` unchanged and would pass every other test
    // here. The licence is `<Family>-OFL.txt`, the family being the filename
    // up to the first `-`; a font subsetted from another family's source
    // names that family explicitly.
    const licenceFamilyAlias = {'ProgramMatrixMarkers': 'NotoSansSymbols2'};
    final fonts = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(fonts, isNotEmpty);
    final licences = licenseFiles.map((f) => f.uri.pathSegments.last).toSet();
    for (final font in fonts) {
      final family = font.split('-').first;
      final licence = '${licenceFamilyAlias[family] ?? family}-OFL.txt';
      expect(licences, contains(licence), reason: '$font has no licence file');
    }
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
