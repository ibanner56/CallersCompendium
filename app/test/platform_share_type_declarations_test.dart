import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _shareTypeIdentifier = 'org.callerscompendium.compendiumApp.share';

void main() {
  for (final platform in ['ios', 'macos']) {
    group('$platform share type declaration', () {
      late String plist;

      setUpAll(() {
        plist = File('$platform/Runner/Info.plist').readAsStringSync();
      });

      test('keeps the custom share type opaque to generic JSON handlers', () {
        final conformance = RegExp(
          '<key>UTTypeIdentifier</key>\\s*'
          '<string>${RegExp.escape(_shareTypeIdentifier)}</string>.*?'
          '<key>UTTypeConformsTo</key>\\s*<array>(.*?)</array>',
          dotAll: true,
        ).firstMatch(plist)?.group(1);

        expect(conformance, isNotNull);
        expect(conformance, contains('<string>public.data</string>'));
        expect(conformance, isNot(contains('<string>public.json</string>')));
      });

      test('retains the custom and generic JSON document routes', () {
        final compactPlist = plist.replaceAll(RegExp(r'\s+'), '');
        expect(
          compactPlist,
          contains(
            "<key>CFBundleTypeName</key><string>Caller'sCompendiumShare</string>"
            '<key>CFBundleTypeRole</key><string>Viewer</string>'
            '<key>LSHandlerRank</key><string>Owner</string>'
            '<key>LSItemContentTypes</key><array><string>$_shareTypeIdentifier</string>',
          ),
        );
        expect(
          compactPlist,
          contains(
            "<key>CFBundleTypeName</key><string>Caller'sCompendiumArchive</string>"
            '<key>CFBundleTypeRole</key><string>Viewer</string>'
            '<key>LSHandlerRank</key><string>Alternate</string>'
            '<key>LSItemContentTypes</key><array><string>public.json</string>',
          ),
        );
        expect(compactPlist, contains('<string>ccshare</string>'));
        expect(compactPlist, contains('<string>application/json</string>'));
      });
    });
  }
}
