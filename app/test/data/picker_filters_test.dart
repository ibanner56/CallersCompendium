import 'package:compendium_app/src/data/backup_io.dart';
import 'package:compendium_app/src/diagnostics/crash_log_io.dart';
import 'package:compendium_app/src/export/share_file.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // file_selector_linux turns each extension into a GTK `*.<ext>` pattern and
  // GTK patterns are case-sensitive; this mirrors that matching (#1832).
  bool gtkMatches(XTypeGroup g, String name) =>
      g.extensions!.any((e) => name.endsWith('.$e'));

  void pins(
    String what,
    XTypeGroup Function({bool? isLinux}) build,
    List<String> bare,
    List<String> shown,
    List<String> hidden,
  ) {
    group(what, () {
      test('on Linux lists lower, UPPER and Capitalised spellings', () {
        final g = build(isLinux: true);
        for (final n in shown) {
          expect(gtkMatches(g, n), isTrue, reason: n);
        }
        for (final n in hidden) {
          expect(gtkMatches(g, n), isFalse, reason: n);
        }
      });
      test('off Linux keeps the bare extension list', () {
        expect(build(isLinux: false).extensions, bare);
      });
    });
  }

  pins(
    'backup',
    backupJsonTypeGroup,
    ['json'],
    ['Backup.JSON', 'backup.json', 'Backup.Json'],
    ['backup.txt'],
  );
  pins(
    'diagnostics log',
    crashLogTypeGroup,
    ['log', 'txt'],
    ['crash.LOG', 'crash.log', 'crash.Log', 'crash.TXT', 'crash.txt'],
    ['crash.json'],
  );
  pins(
    'JSON bundle save',
    jsonBundleTypeGroup,
    ['json'],
    ['a.JSON', 'a.json', 'a.Json'],
    ['a.txt'],
  );
  pins(
    'bundle Save As fallback',
    ({bool? isLinux}) => bundleSaveTypeGroup('json', isLinux: isLinux),
    ['json'],
    ['a.JSON', 'a.json', 'a.Json'],
    ['a.txt'],
  );
}
