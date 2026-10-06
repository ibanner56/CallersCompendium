import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/licenses.dart';

/// pdfium's licence notices must reach the in-app licence page on the
/// platforms that ship pdfium.
///
/// The `printing` plugin bundles a prebuilt pdfium (from
/// `bblanchon/pdfium-binaries`, pinned in `packaging/pdfium/pdfium.cmake`)
/// into the Linux and Windows builds only; on Android, iOS and macOS it prints
/// through the platform's own PDF stack. pdfium is not a Dart package, so
/// Flutter's automatic package licences never list it, and its BSD licence
/// requires the notice to travel with the binary (audit finding platform-5).
///
/// `tools/release/test_pdfium_pin.py` checks that the asset is the LICENSE
/// from the pinned release archive; this file checks that the app shows it.
///
/// Plain `test`s, like `licenses_notice_test.dart`: enumerating
/// `LicenseRegistry` after `testWidgets` cases can hang on the asset loads.
const _asset = 'assets/licenses/pdfium-LICENSE.txt';

String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

Future<List<LicenseEntry>> _entriesOn(TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    LicenseRegistry.reset();
    resetBundledLicensesForTest();
    registerBundledLicenses();
    // Real LicenseRegistry and rootBundle, so an undeclared asset fails too.
    return await LicenseRegistry.licenses.toList().timeout(
      const Duration(seconds: 20),
    );
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Iterable<LicenseEntry> _pdfium(List<LicenseEntry> entries) =>
    entries.where((e) => e.packages.any((p) => p.startsWith('PDFium')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the pdfium licence asset is declared in pubspec.yaml', () {
    final declared = File('pubspec.yaml')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.startsWith('- assets/'))
        .map((l) => l.substring(2).trim())
        .toSet();
    expect(declared, contains(_asset));
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    test('the pdfium licence is on the licence page on ${platform.name}',
        () async {
      final matching = _pdfium(await _entriesOn(platform));
      expect(matching, hasLength(1));
      final text = _collapse(
        matching.single.paragraphs.map((p) => p.text).join(' '),
      );
      // The registered text is the whole asset, bundled notices included.
      expect(text, equals(_collapse(File(_asset).readAsStringSync())));
      expect(text, contains('Copyright 2014 PDFium Authors'));
      expect(text, contains('The FreeType Project LICENSE'));
    });
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    test('the pdfium licence is not listed on ${platform.name}, which does '
        'not ship pdfium', () async {
      final entries = await _entriesOn(platform);
      // The other bundled licences are still there: the gate is pdfium's own.
      expect(entries, isNotEmpty);
      expect(_pdfium(entries), isEmpty);
    });
  }
}
