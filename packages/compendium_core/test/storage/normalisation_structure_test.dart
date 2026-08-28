import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';

// Keep this field-specific: one wrapped field must not hide another bypass.
const _shareableTextFields = {
  'ChoreographersCompanion.insert': {
    'name': 'normalizeShareableText',
    'website': 'normalizeShareableText',
    'notes': 'normalizeShareableText',
  },
  'CustomFieldDefsCompanion.insert': {
    'key': 'normalizeShareableText',
    'label': 'normalizeShareableText',
  },
  'DancesCompanion.insert': {
    'title': 'normalizeShareableText',
    'formationDetail': 'normalizeShareableText',
    'figuresJson': 'normalizeShareableJsonText',
    'hook': 'normalizeShareableText',
    'callingNotes': 'normalizeShareableText',
    'walkthrough': 'normalizeShareableText',
    'tunesJson': 'normalizeShareableJsonText',
  },
  'DanceLinksCompanion.insert': {
    'url': 'normalizeShareableText',
    'label': 'normalizeShareableText',
  },
  'ProgramSlotsCompanion.insert': {
    'text_': 'normalizeShareableText',
    'guestCaller': 'normalizeShareableText',
  },
  'ProgramsCompanion.insert': {
    'title': 'normalizeShareableText',
    'venue': 'normalizeShareableText',
    'band': 'normalizeShareableText',
    'caller': 'normalizeShareableText',
    'dancerLevel': 'normalizeShareableText',
    'notes': 'normalizeShareableText',
  },
  'PublishedSourcesCompanion.insert': {
    'title': 'normalizeShareableText',
    'author': 'normalizeShareableText',
    'url': 'normalizeShareableText',
    'notes': 'normalizeShareableText',
  },
  'TagsCompanion.insert': {'name': 'normalizeShareableText'},
  'DanceSourcesCompanion.insert': {
    'page': 'normalizeShareableText',
    'number': 'normalizeShareableText',
  },
  'CustomFieldValuesCompanion.insert': {'valueText': 'normalizeShareableText'},
  'ProvenanceCompanion.insert': {
    'externalId': 'normalizeShareableText',
    'permission': 'normalizeShareableText',
    'license': 'normalizeShareableText',
    'sourceVersion': 'normalizeShareableText',
  },
  'ProgramProvenanceCompanion.insert': {
    'externalId': 'normalizeShareableText',
    'permission': 'normalizeShareableText',
    'license': 'normalizeShareableText',
    'sourceVersion': 'normalizeShareableText',
  },
  'VenuesCompanion.insert': {
    'name': 'normalizeShareableText',
    'website': '_normalize',
    'sponsor': '_normalize',
    'eventName': '_normalize',
    'time': '_normalize',
    'genericSchedule': '_normalize',
    'price': '_normalize',
    'notes': '_normalize',
  },
  'VenueProvenanceCompanion.insert': {
    'externalId': 'normalizeShareableText',
    'permission': '_normalize',
    'license': '_normalize',
    'sourceVersion': '_normalize',
  },
};

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
      expect(_hasUnwrappedShareableCall(source), isFalse, reason: relativePath);
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

  test('detects an unwrapped child-table field', () {
    const source = '''
    ProgramSlotsCompanion.insert(
      text_: Value(normalizeShareableText(value)),
      guestCaller: Value(value),
    );
    ''';
    expect(_hasUnwrappedShareableCall(source), isTrue);
  });

  test('does not trust an unrelated normalized local', () {
    const source = '''
    final text = normalizeShareableText(value);
    DancesCompanion.insert(hook: Value(text));
    ''';
    expect(_hasUnwrappedShareableCall(source), isTrue);
  });
}

bool _hasUnwrappedShareableCall(String source) {
  for (final entry in _shareableTextFields.entries) {
    final companion = entry.key;
    final starts = _occurrences(source, '$companion(').toList();
    for (final start in starts) {
      final call = _callBody(source, start);
      for (final field in entry.value.entries) {
        final argument = _argumentBody(call, field.key);
        if (argument == null) continue;
        final precomputedName = switch (field.key) {
          'key' || 'label' || 'name' => field.key,
          _ => null,
        };
        final precomputed =
            precomputedName != null &&
            argument.contains(precomputedName) &&
            source.contains('final $precomputedName = ${field.value}(');
        if (!argument.contains(field.value) &&
            !(starts.length == 1 && precomputed)) {
          return true;
        }
      }
    }
  }
  return false;
}

Iterable<int> _occurrences(String source, String needle) sync* {
  var offset = 0;
  while (true) {
    final index = source.indexOf(needle, offset);
    if (index < 0) return;
    if (index == 0 || !RegExp(r'[A-Za-z0-9_]').hasMatch(source[index - 1])) {
      yield index + needle.length - 1;
    }
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

String? _argumentBody(String call, String field) {
  final start = call.indexOf('$field:');
  if (start < 0) return null;
  final valueStart = start + field.length + 1;
  var depth = 0;
  var quote = '';
  var escaped = false;
  for (var i = valueStart; i < call.length; i++) {
    final char = call[i];
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
    } else if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char)) {
      if (depth == 0) return call.substring(valueStart, i);
      depth--;
    } else if (char == ',' && depth == 0) {
      return call.substring(valueStart, i);
    }
  }
  return call.substring(valueStart);
}
