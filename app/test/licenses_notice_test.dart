import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/licenses.dart';

/// The third-party notices that travel with the app.
///
/// `fmp_reader.dart` and `scsu.dart` describe themselves as ports of the
/// MIT-licensed `fmptools` project, whose license requires its copyright and
/// permission notice to travel with "all copies or substantial portions"
/// (#1392). The EFF long wordlist compiled into `eff_long_wordlist.dart` is
/// CC BY 3.0, which requires the author, licence and source to be named on
/// every distributed copy. ContraDB's attribution is the one
/// `docs/research/contradb.md` promised for reusing its figure wording.
///
/// Each notice therefore has to be present in several places: the bundled
/// asset the in-app license page loads, the repo's `THIRD_PARTY_NOTICES.md`,
/// and the head of each ported or copied source file. The asset is the
/// reference; this test compares the other copies against it, so they cannot
/// drift or be trimmed to the copyright line alone.
///
/// It also asserts the in-app registration. That lives here rather than in
/// `settings_about_test.dart` on purpose: enumerating `LicenseRegistry`
/// after that file's `testWidgets` cases have run hangs on the asset loads
/// (observed: `TimeoutException`), whereas in this file it does not.

/// One bundled notice and the copies that must equal it.
class _Notice {
  const _Notice({
    required this.name,
    required this.package,
    required this.asset,
    required this.opening,
    required this.mustContain,
    this.sourceHeaders = const [],
  });

  /// Short name for test titles.
  final String name;

  /// The `packages` label `licenses.dart` files the entry under.
  final String package;

  /// Repo-relative path of the reference asset.
  final String asset;

  /// What the normalised reference text starts with.
  final String opening;

  /// Phrases the reference text must carry: the licence's name and URL (or
  /// its own inclusion clause), and the source the attribution names. Because
  /// every other copy is compared against the asset, requiring them here
  /// requires them everywhere; without this the whole licence paragraph could
  /// be dropped from all copies at once with every test green.
  final List<String> mustContain;

  /// Repo-relative source files whose leading `//` comment must carry the full
  /// notice.
  final List<String> sourceHeaders;
}

const List<_Notice> _notices = [
  _Notice(
    name: 'fmptools',
    package: 'fmptools (MIT)',
    asset: 'app/assets/licenses/fmptools-LICENSE.txt',
    opening: 'Copyright (c) 2020 Evan Miller',
    mustContain: [
      'The above copyright notice and this permission notice shall be '
          'included in all copies or substantial portions of the Software.',
    ],
    sourceHeaders: [
      'packages/compendium_core/lib/src/imports/fmp/fmp_reader.dart',
      'packages/compendium_core/lib/src/imports/fmp/scsu.dart',
    ],
  ),
  _Notice(
    name: 'EFF long wordlist',
    package: 'EFF Long Wordlist (CC BY 3.0 US)',
    asset: 'app/assets/licenses/eff-wordlist-NOTICE.txt',
    opening:
        'EFF Long Wordlist Copyright (c) 2016 Electronic Frontier '
        'Foundation',
    // CC BY asks for author, licence and source. The licence is the US port:
    // EFF's copyright page links https://creativecommons.org/licenses/by/3.0/us/
    // for its 3.0 badge, and never pointed at the Unported text.
    mustContain: [
      'Creative Commons Attribution 3.0 United States license (CC BY 3.0 US)',
      'https://creativecommons.org/licenses/by/3.0/us/',
      'Source: https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt',
    ],
    sourceHeaders: [
      'packages/compendium_core/lib/src/sync/eff_long_wordlist.dart',
    ],
  ),
  _Notice(
    name: 'ContraDB',
    package: 'ContraDB (AGPL-3.0)',
    asset: 'app/assets/licenses/contradb-NOTICE.txt',
    opening: 'ContraDB Copyright (c) David Morse and ContraDB contributors',
    mustContain: [
      'GNU Affero General Public License, version 3 (AGPL-3.0)',
      'Source: https://github.com/contradb/contra',
    ],
    // The renderer follows ContraDB's wording but transcribes no code, so no
    // source file carries the notice in its head; the renderer's own comments
    // name the libfigure functions.
  ),
];

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

  String read(String relative) =>
      File('${root.path}/$relative').readAsStringSync();

  test('the license registry carries every bundled notice', () async {
    LicenseRegistry.reset();
    resetBundledLicensesForTest();
    registerBundledLicenses();

    // Load through the real LicenseRegistry and rootBundle, not a fake, so an
    // unregistered entry AND an undeclared asset both fail here.
    final entries = await LicenseRegistry.licenses.toList().timeout(
      const Duration(seconds: 20),
    );

    for (final notice in _notices) {
      final matching = entries.where(
        (e) => e.packages.contains(notice.package),
      );
      expect(matching, hasLength(1), reason: notice.package);
      final text = _normalise(
        matching.single.paragraphs.map((p) => p.text).join('\n'),
      );
      // The registered text is the asset itself, not a summary of it.
      expect(text, equals(_normalise(read(notice.asset))));
    }
  });

  for (final notice in _notices) {
    final reference = _normalise(read(notice.asset));

    test('the ${notice.name} reference notice is the full text', () {
      expect(reference, startsWith(notice.opening));
      for (final phrase in notice.mustContain) {
        expect(reference, contains(phrase));
      }
    });

    test('THIRD_PARTY_NOTICES.md carries the full ${notice.name} notice', () {
      expect(_normalise(read('THIRD_PARTY_NOTICES.md')), contains(reference));
    });

    for (final path in notice.sourceHeaders) {
      test('$path carries the full ${notice.name} notice in its header', () {
        expect(_normalise(_leadingComment(read(path))), contains(reference));
      });
    }
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
