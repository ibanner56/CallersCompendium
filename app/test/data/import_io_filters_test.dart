import 'package:compendium_app/src/data/import_io.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('import file-type filters', () {
    // file_selector_linux turns each extension into a GTK `*.<ext>` pattern,
    // and GTK patterns are case-sensitive; this mirrors that matching.
    bool gtkMatches(XTypeGroup g, String name) =>
        g.extensions!.any((e) => name.endsWith('.$e'));

    const usrNames = ['SeedTest.USR', 'seedtest.usr', 'CallersCompanion2.USR'];
    const shareNames = ['a.ccshare', 'a.CCSHARE', 'a.json', 'a.JSON'];

    test('on Linux the .USR filter shows upper- and lower-case files', () {
      final g = importUsrTypeGroup(isLinux: true);
      for (final n in usrNames) {
        expect(gtkMatches(g, n), isTrue, reason: n);
      }
    });

    test('on Linux the share filter shows upper- and lower-case files', () {
      final g = importJsonTypeGroup(isLinux: true);
      for (final n in shareNames) {
        expect(gtkMatches(g, n), isTrue, reason: n);
      }
    });

    test('off Linux the extension lists are unchanged', () {
      expect(importUsrTypeGroup(isLinux: false).extensions, ['usr']);
      expect(importJsonTypeGroup(isLinux: false).extensions, [
        'ccshare',
        'json',
      ]);
    });

    test('the filters still reject unrelated files on Linux', () {
      expect(gtkMatches(importUsrTypeGroup(isLinux: true), 'a.txt'), isFalse);
      expect(gtkMatches(importJsonTypeGroup(isLinux: true), 'a.usr'), isFalse);
    });
  });
}
