import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `data/` and `sync/` are lower layers than `screens/`; nothing in them may
/// import upwards. This seeds the app layering check (audit finding C1), kept
/// to these two directories so the allow-list is empty and the check is exact.
void main() {
  for (final dir in ['lib/src/data', 'lib/src/sync']) {
    test('$dir has no imports of ../screens/', () {
      final offenders = <String>[];
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(
            r'''^\s*(import|export)\s+['"](\.\./)+screens/''',
          ).hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  }
}
