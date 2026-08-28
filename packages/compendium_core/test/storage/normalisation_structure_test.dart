import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';

const _shareableCompanions = [
  'ChoreographersCompanion.insert',
  'CustomFieldDefsCompanion.insert',
  'DancesCompanion.insert',
  'ProgramsCompanion.insert',
  'PublishedSourcesCompanion.insert',
  'TagsCompanion.insert',
  'VenuesCompanion.insert',
];

void main() {
  test('all shareable persistence calls wrap their text inputs', () async {
    final root = await packageRootPath();
    const repositoryFiles = [
      'lib/src/storage/repositories/choreographer_repository.dart',
      'lib/src/storage/repositories/custom_field_repository.dart',
      'lib/src/storage/repositories/dance_repository.dart',
      'lib/src/storage/repositories/program_repository.dart',
      'lib/src/storage/repositories/published_source_repository.dart',
      'lib/src/storage/repositories/settings_repository.dart',
      'lib/src/storage/repositories/tag_repository.dart',
      'lib/src/storage/repositories/venue_repository.dart',
    ];

    for (final relativePath in repositoryFiles) {
      final source = File(p.join(root, relativePath)).readAsStringSync();
      expect(
        _hasUnwrappedShareableCall(source),
        isFalse,
        reason:
            '$relativePath has a shareable persistence call without '
            'normalizeShareableText',
      );
      if (relativePath.endsWith('settings_repository.dart')) {
        expect(
          source,
          contains('normalizeShareableJson(value)'),
          reason: 'settings writes must normalize shareable JSON values',
        );
      }
    }
  });

  test('detects an additional direct persistence bypass', () {
    const source = '''
DancesCompanion.insert(title: normalizeShareableText(value));
DancesCompanion.insert(title: value);
''';
    expect(_hasUnwrappedShareableCall(source), isTrue);
  });
}

bool _hasUnwrappedShareableCall(String source) {
  for (final companion in _shareableCompanions) {
    final starts = _occurrences(source, '$companion(').toList();
    for (final start in starts) {
      final callNormalizes = _callBody(
        source,
        start,
      ).contains('normalizeShareableText');
      final singlePrecomputedValue =
          starts.length == 1 && source.contains('normalizeShareableText(');
      if (!callNormalizes && !singlePrecomputedValue) return true;
    }
  }
  return false;
}

Iterable<int> _occurrences(String source, String needle) sync* {
  var offset = 0;
  while (true) {
    final index = source.indexOf(needle, offset);
    if (index < 0) return;
    yield index + needle.length - 1;
    offset = index + needle.length;
  }
}

String _callBody(String source, int openParen) {
  var depth = 0;
  var quote = '';
  var escaped = false;
  for (var i = openParen; i < source.length; i++) {
    final char = source[i];
    if (quote.isNotEmpty) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == quote) {
        quote = '';
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
    } else if (char == '(') {
      depth++;
    } else if (char == ')' && --depth == 0) {
      return source.substring(openParen, i + 1);
    }
  }
  throw StateError('unclosed call at offset $openParen');
}
