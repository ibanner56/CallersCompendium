import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show DriftSqlType;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_package_root.dart';
import 'test_database.dart';

// These are shareable strings with a constrained representation or a
// deliberately different normalization seam. New fields are checked by
// default; adding an exemption requires naming its reason here.
const _normalisationExemptions = <String, String>{
  'dances.form': 'enum value',
  'dances.formation_shape': 'enum value',
  'dances.progression': 'enum value',
  'dances.phrase_structure': 'canonical phrase value',
  'dances.status': 'enum value',
  'dances.level': 'enum value',
  'dances.composed_on': 'canonical partial date',
  'dances.revised_on': 'canonical partial date',
  'dance_links.kind': 'enum value',
  'provenance.source': 'enum value',
  'program_provenance.source': 'enum value',
  'venue_provenance.source': 'enum value',
  'programs.status': 'enum value',
  'custom_field_defs.type': 'enum value',
  'custom_field_defs.choices_json':
      'choice strings are normalized before JSON encoding',
};

typedef _ShareableFields = Map<String, Map<String, Set<String>>>;

void main() {
  test(
    'all discovered shareable persistence calls wrap their text inputs',
    () async {
      final root = await packageRootPath();
      final db = openTestDatabase();
      addTearDown(db.close);
      final fields = _discoverShareableFields(root, db);
      expect(fields['ProgramSlotsCompanion'], contains('text_'));
      final repositoryRoot = Directory(
        p.join(root, 'lib', 'src', 'storage', 'repositories'),
      );

      final violations = <String>[];
      for (final entity
          in repositoryRoot.listSync(recursive: true).whereType<File>()) {
        if (!entity.path.endsWith('.dart')) continue;
        violations.addAll(
          _unwrappedShareableCalls(
            entity.readAsStringSync(),
            fields,
            sourceName: p.relative(entity.path, from: root),
          ),
        );
      }
      expect(violations, isEmpty);

      final settings = File(
        p.join(
          root,
          'lib',
          'src',
          'storage',
          'repositories',
          'settings_repository.dart',
        ),
      ).readAsStringSync();
      expect(settings, contains('normalizeShareableJson(value)'));
    },
  );

  test(
    'discovery reports an unlisted writer for a live shareable field',
    () async {
      final root = await packageRootPath();
      final db = openTestDatabase();
      addTearDown(db.close);
      final fields = _discoverShareableFields(root, db);
      final tempRoot = await Directory.systemTemp.createTemp(
        'normalisation-structure-',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final writer = File(
        p.join(
          tempRoot.path,
          'lib',
          'src',
          'storage',
          'repositories',
          'future_repository.dart',
        ),
      )..createSync(recursive: true);
      writer.writeAsStringSync('''
import 'package:drift/drift.dart';

void save(String value) {
  DancesCompanion.insert(title: Value(value));
}
''');

      final violations = _unwrappedShareableCalls(
        writer.readAsStringSync(),
        fields,
        sourceName: p.relative(writer.path, from: tempRoot.path),
      );
      expect(
        violations,
        contains(contains('future_repository.dart: DancesCompanion.title')),
      );
    },
  );

  test('detects an unwrapped companion insert and update', () {
    const source = '''
DancesCompanion.insert(title: normalizeShareableText(value));
DancesCompanion.insert(title: value);
DancesCompanion(title: Value(value));
''';
    final fields = <String, Map<String, Set<String>>>{
      'DancesCompanion': {
        'title': {'normalizeShareableText'},
      },
    };
    expect(_unwrappedShareableCalls(source, fields), hasLength(2));
  });

  test('detects an unwrapped raw SQL shareable write', () {
    const source = '''
await db.customUpdate('UPDATE dances SET title = ? WHERE id = ?');
await db.customUpdate('UPDATE \$table SET title = ? WHERE id = ?');
''';
    final fields = <String, Map<String, Set<String>>>{
      'DancesCompanion': {
        'title': {'normalizeShareableText'},
      },
    };
    expect(_unwrappedShareableCalls(source, fields), hasLength(2));
  });

  test('does not trust an unrelated normalized local', () {
    const source = '''
final text = normalizeShareableText(value);
DancesCompanion.insert(title: Value(text));
''';
    final fields = <String, Map<String, Set<String>>>{
      'DancesCompanion': {
        'title': {'normalizeShareableText'},
      },
    };
    expect(_unwrappedShareableCalls(source, fields), hasLength(1));
  });
}

_ShareableFields _discoverShareableFields(String root, CompendiumDatabase db) {
  final aliases = _readColumnAliases(
    File(
      p.join(root, 'lib', 'src', 'storage', 'tables.dart'),
    ).readAsStringSync(),
  );
  final fields = <String, Map<String, Set<String>>>{};
  for (final table in db.allTables) {
    final primaryKeys = table.$primaryKey.map((column) => column.name).toSet();
    for (final column in table.$columns) {
      final key = '${table.actualTableName}.${column.name}';
      final classification = fieldClassifications[key];
      if (column.type != DriftSqlType.string ||
          classification?.egress != EgressClass.shareable ||
          classification!.isIdentity ||
          primaryKeys.contains(column.name) ||
          _normalisationExemptions.containsKey(key)) {
        continue;
      }
      final dartField = aliases[key] ?? _camelCase(column.name);
      final companion = '${_pascalCase(table.actualTableName)}Companion';
      final normalizer = column.name.endsWith('_json')
          ? 'normalizeShareableJsonText'
          : 'normalizeShareableText';
      fields.putIfAbsent(companion, () => {})[dartField] = {normalizer};
      // VenueRepository deliberately uses its small nullable wrapper.
      if (companion == 'VenuesCompanion' ||
          companion == 'VenueProvenanceCompanion') {
        fields[companion]![dartField]!.add('_normalize');
      }
    }
  }
  return fields;
}

Map<String, String> _readColumnAliases(String source) {
  final aliases = <String, String>{};
  final classes = RegExp(
    r'class\s+(\w+)\s+extends\s+Table\s*\{',
  ).allMatches(source);
  for (final declaration in classes) {
    final body = _balancedBlock(source, declaration.end - 1);
    final table = _snakeCase(declaration.group(1)!);
    for (final getter in RegExp(
      r'(?:\w+)Column\s+get\s+(\w+)\s*=>\s*(.*?);',
      dotAll: true,
    ).allMatches(body)) {
      final dartField = getter.group(1)!;
      final named = RegExp(
        r"\.named\('([^']+)'\)",
      ).firstMatch(getter.group(2)!);
      aliases['$table.${named?.group(1) ?? _snakeCase(dartField)}'] = dartField;
    }
  }
  return aliases;
}

List<String> _unwrappedShareableCalls(
  String source,
  _ShareableFields fields, {
  String sourceName = '<source>',
}) {
  final violations = <String>[];
  final companionCalls = RegExp(
    r'\b([A-Z]\w+Companion)(?:\.(?:insert|update))?\(',
  );
  for (final match in companionCalls.allMatches(source)) {
    final companion = match.group(1)!;
    final expected = fields[companion];
    if (expected == null) continue;
    final call = _callBody(source, match.end - 1);
    for (final entry in expected.entries) {
      final argument = _argumentBody(call, entry.key);
      if (argument == null) continue;
      if (!entry.value.any(argument.contains)) {
        violations.add('$sourceName: $companion.${entry.key}');
      }
    }
  }

  final rawWrites = [
    ...RegExp(
      r"(?:customUpdate|customStatement)\(\s*'(.*?)'",
      caseSensitive: false,
      dotAll: true,
    ).allMatches(source),
    ...RegExp(
      r'''(?:customUpdate|customStatement)\(\s*"(.*?)"''',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(source),
  ];
  for (final match in rawWrites) {
    final sql = match.group(1)!;
    if (!RegExp(
      r'^\s*(?:insert\s+into|update)\b',
      caseSensitive: false,
    ).hasMatch(sql)) {
      continue;
    }
    for (final entry in fields.entries) {
      final table = _snakeCase(entry.key.replaceFirst('Companion', ''));
      for (final field in entry.value.keys) {
        final sqlField = _snakeCase(field.replaceFirst(RegExp(r'_+$'), ''));
        if (RegExp(
          '\\b$table\\b[\\s\\S]*\\b$sqlField\\b',
          caseSensitive: false,
        ).hasMatch(sql)) {
          violations.add('$sourceName: raw $table.$sqlField');
        }
        if (sql.contains(r'$') &&
            RegExp('\\b$sqlField\\s*=', caseSensitive: false).hasMatch(sql) &&
            !_hasRawWriteException(source, match.start)) {
          violations.add('$sourceName: raw dynamic $sqlField');
        }
      }
    }
    if (sql.contains(r'$column') &&
        !_hasRawWriteException(source, match.start)) {
      violations.add('$sourceName: raw dynamic shareable field');
    }
  }
  return violations;
}

bool _hasRawWriteException(String source, int offset) {
  final start = offset > 500 ? offset - 500 : 0;
  return source
      .substring(start, offset)
      .contains('normalization-structure-exempt:');
}

String _balancedBlock(String source, int openBrace) {
  var depth = 0;
  var quote = '';
  var escaped = false;
  var lineComment = false;
  var blockComment = false;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (lineComment) {
      if (char == '\n') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (char == '*' && next == '/') {
        blockComment = false;
      }
      continue;
    }
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
    if (char == '/' && next == '/') {
      lineComment = true;
      continue;
    }
    if (char == '/' && next == '*') {
      blockComment = true;
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
    } else if (char == '{') {
      depth++;
    } else if (char == '}' && --depth == 0) {
      return source.substring(openBrace + 1, i);
    }
  }
  throw StateError('unclosed block at offset $openBrace');
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
  final start = RegExp('\\b${RegExp.escape(field)}\\s*:').firstMatch(call);
  if (start == null) return null;
  final valueStart = start.end;
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

String _pascalCase(String value) => value
    .split('_')
    .map((part) => part[0].toUpperCase() + part.substring(1))
    .join();

String _camelCase(String value) {
  final pascal = _pascalCase(value);
  return pascal[0].toLowerCase() + pascal.substring(1);
}

String _snakeCase(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .toLowerCase();
