import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/licenses.dart';

/// The MIT notice for `fmptools` (issue #1392).
///
/// `fmp_reader.dart` and `scsu.dart` describe themselves as ports of the
/// MIT-licensed `fmptools` project, whose license requires its copyright and
/// permission notice to travel with "all copies or substantial portions". The
/// notice therefore has to be present in four places: the bundled asset the
/// in-app license page loads, the repo's `THIRD_PARTY_NOTICES.md`, and the head
/// of each ported source file. The asset is the reference; this test compares
/// the other copies against it, so they cannot drift or be trimmed to the
/// copyright line alone.
///
/// It also asserts the in-app registration. That lives here rather than in
/// `settings_about_test.dart` on purpose: enumerating `LicenseRegistry`
/// after that file's `testWidgets` cases have run hangs on the asset loads
/// (observed: `TimeoutException`), whereas in this file it does not.

/// The repo root: the nearest ancestor of the test's working directory that
/// contains `packages/compendium_core`.
Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (Directory('${dir.path}/packages/compendium_core').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('repo root not found above ${Directory.current.path}');
    }
    dir = parent;
  }
}

/// Strips comment markers and collapses whitespace so a notice wrapped in `//`
/// lines compares equal to the same text in a plain file.
String _normalise(String text) => text
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'^\s*//+ ?'), ''))
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The `//` comment block at the very top of [source]: the lines before the
/// first one that is not a plain `//` comment. `///` doc comments and code end
/// it, so a notice moved below the library doc, or below any declaration, is
/// not in the head of the file.
String _leadingComment(String source) {
  final head = <String>[];
  for (final line in source.split('\n')) {
    if (!line.startsWith('//') || line.startsWith('///')) break;
    head.add(line);
  }
  return head.join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = _repoRoot();

  test('the license registry carries the fmptools MIT notice', () async {
    LicenseRegistry.reset();
    resetBundledLicensesForTest();
    registerBundledLicenses();

    // Load through the real LicenseRegistry and rootBundle, not a fake, so an
    // unregistered entry AND an undeclared asset both fail here.
    final entries = await LicenseRegistry.licenses.toList().timeout(
      const Duration(seconds: 20),
    );
    final fmptools = entries.where(
      (e) => e.packages.contains('fmptools (MIT)'),
    );

    expect(fmptools, hasLength(1));
    final text = fmptools.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('Copyright (c) 2020 Evan Miller'));
    expect(
      text,
      contains('shall be included in all copies or substantial portions'),
    );
  });

  String read(String relative) =>
      File('${root.path}/$relative').readAsStringSync();

  final notice = _normalise(read('app/assets/licenses/fmptools-LICENSE.txt'));

  test('the reference notice is the upstream MIT text', () {
    expect(notice, startsWith('Copyright (c) 2020 Evan Miller'));
    expect(
      notice,
      contains(
        'The above copyright notice and this permission notice shall be '
        'included in all copies or substantial portions of the Software.',
      ),
    );
  });

  test('THIRD_PARTY_NOTICES.md carries the full fmptools notice', () {
    expect(_normalise(read('THIRD_PARTY_NOTICES.md')), contains(notice));
  });

  for (final path in const [
    'packages/compendium_core/lib/src/imports/fmp/fmp_reader.dart',
    'packages/compendium_core/lib/src/imports/fmp/scsu.dart',
  ]) {
    test('$path carries the full fmptools notice in its header', () {
      expect(_normalise(_leadingComment(read(path))), contains(notice));
    });
  }

  test('every source file that calls itself an MIT port carries a notice', () {
    // The next port must not repeat this defect. A file that says it is a port
    // of MIT-licensed code has to carry *an* MIT permission notice; whose notice
    // it is cannot be checked mechanically, so the fmptools text is not
    // required here, only the license's own inclusion clause.
    const inclusionClause =
        'this permission notice shall be included in all copies or substantial '
        'portions of the Software';
    final flagged = <String>[];
    final missing = <String>[];
    final dirs = [
      Directory('${root.path}/app/lib'),
      Directory('${root.path}/packages/compendium_core/lib'),
    ];
    for (final dir in dirs) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = _normalise(
          entity.readAsStringSync().replaceAll('///', '//'),
        );
        if (!RegExp(r'\bport of\b', caseSensitive: false).hasMatch(text) ||
            !RegExp(r'MIT-licensed', caseSensitive: false).hasMatch(text)) {
          continue;
        }
        final relative = entity.path
            .substring(root.path.length + 1)
            .replaceAll(r'\', '/');
        flagged.add(relative);
        if (!text.contains(inclusionClause)) missing.add(relative);
      }
    }
    // Not vacuous: the sweep must at least find the two known ports.
    expect(
      flagged,
      containsAll([
        'packages/compendium_core/lib/src/imports/fmp/fmp_reader.dart',
        'packages/compendium_core/lib/src/imports/fmp/scsu.dart',
      ]),
    );
    expect(missing, isEmpty, reason: 'MIT ports without a notice: $missing');
  });
}
