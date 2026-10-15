import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('dance_repository.dart imports nothing from lib/src/imports/', () {
    // The storage layer must not depend on the imports layer: the reparse is
    // injected by the caller (`FigureReparser`), so the repository never names
    // `imports/`. Counting rule: every line that begins an `import` (or
    // `export`) directive, after leading whitespace, whose URI contains an
    // `imports/` path segment. Comments and strings that merely mention the
    // directory do not start with the keyword, so they are not counted.
    final source = File(
      'lib/src/storage/repositories/dance_repository.dart',
    ).readAsStringSync();
    final directive = RegExp(
      r'''^\s*(?:import|export)\s+['"](?:[^'"]*/)?imports/[^'"]*['"]''',
      multiLine: true,
    );
    expect(
      directive.allMatches(source).map((m) => m.group(0)!.trim()),
      isEmpty,
    );
  });
}
