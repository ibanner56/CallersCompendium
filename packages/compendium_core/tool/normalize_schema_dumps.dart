// Prepares `drift_schemas/` dumps for `drift_dev schema generate`.
//
// Run from the package root:
//
//     dart run tool/normalize_schema_dumps.dart <input-dir> <output-dir>
//
// ## Why this step exists
//
// A schema dump taken from a database file (see `drift_schemas/README.md`) is
// reverse-engineered from SQL alone, so it can only guess the *Dart* getter
// name for each column: it derives one from the column's SQL name. That loses
// any deliberate rename in `lib/src/storage/tables.dart`, and one of ours is
// load-bearing:
//
//     TextColumn get text_ => text().nullable().named('text')();
//
// The getter is `text_` precisely because `Table` already declares
// `ColumnBuilder<String> text()`. A generated schema class that declares a
// `text` member while extending `Table` does not compile:
//
//     Error: Can't declare a member that conflicts with an inherited one.
//
// drift's main table writer honours the source declaration and emits `text_`
// (see `late final GeneratedColumn<String> text_` in `database.g.dart`); the
// schema writer, working from SQL, does not. So the dumps are left exactly as
// `drift_dev schema dump` wrote them — they stay a faithful record of what the
// database contained — and the Dart getter names are restored here, on a copy,
// on the way into code generation.
//
// ## Why it fails rather than guessing
//
// The override table below is keyed to `tables.dart` and has to be kept in
// step with it. Rather than trust that it will be, this tool rejects any
// column whose derived getter name collides with a `Table` member and has no
// override: a future `real`, `boolean` or `dateTime` column would otherwise
// regenerate silently into code that does not compile.
import 'dart:convert';
import 'dart:io';

/// Column getter names that differ from the name derived from SQL.
///
/// Keyed by `<sql table>.<sql column>`, valued with the Dart getter declared in
/// `lib/src/storage/tables.dart`. Keep in step with any `.named(...)` override
/// there.
const Map<String, String> getterNameOverrides = {
  // `TextColumn get text_ => text().nullable().named('text')();`
  'program_slots.text': 'text_',
};

/// Members of drift's `Table` that a generated column field cannot shadow.
///
/// These are the column-builder factories declared on `Table`; a generated
/// schema class extends `Table`, so a field of the same name is a compile
/// error.
const Set<String> reservedTableMembers = {
  'integer',
  'int64',
  'text',
  'boolean',
  'dateTime',
  'real',
  'blob',
  'sqliteAny',
  'customType',
};

int _normalizeFile(File source, Directory outputDir) {
  final decoded = jsonDecode(source.readAsStringSync()) as Map<String, Object?>;
  final entities = decoded['entities'] as List<Object?>;
  var rewritten = 0;
  final problems = <String>[];

  for (final entity in entities) {
    final data = (entity! as Map<String, Object?>)['data']!;
    final table = data as Map<String, Object?>;
    final tableName = table['name'] as String?;
    final columns = table['columns'] as List<Object?>?;
    if (tableName == null || columns == null) continue;

    for (final column in columns) {
      final columnData = column! as Map<String, Object?>;
      final columnName = columnData['name'] as String;
      final getter = columnData['getter_name'] as String?;
      final override = getterNameOverrides['$tableName.$columnName'];

      if (override != null) {
        if (getter != override) {
          columnData['getter_name'] = override;
          rewritten++;
        }
        continue;
      }

      if (getter != null && reservedTableMembers.contains(getter)) {
        problems.add(
          '$tableName.$columnName would generate a `$getter` member, which '
          'collides with Table.$getter(). Add an entry to '
          'getterNameOverrides matching the getter declared in tables.dart.',
        );
      }
    }
  }

  if (problems.isNotEmpty) {
    for (final problem in problems) {
      stderr.writeln('error: ${source.path}: $problem');
    }
    return -1;
  }

  final target = File('${outputDir.path}/${source.uri.pathSegments.last}');
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
  );
  return rewritten;
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/normalize_schema_dumps.dart <input> <output>',
    );
    exitCode = 2;
    return;
  }

  final inputDir = Directory(args[0]);
  if (!inputDir.existsSync()) {
    stderr.writeln('no such directory: ${inputDir.path}');
    exitCode = 2;
    return;
  }
  final outputDir = Directory(args[1])..createSync(recursive: true);

  final sources =
      inputDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (sources.isEmpty) {
    stderr.writeln('no schema dumps found in ${inputDir.path}');
    exitCode = 2;
    return;
  }

  var total = 0;
  for (final source in sources) {
    final rewritten = _normalizeFile(source, outputDir);
    if (rewritten < 0) {
      exitCode = 1;
      return;
    }
    total += rewritten;
  }

  stdout.writeln(
    'Normalized ${sources.length} schema dumps into ${outputDir.path} '
    '($total getter name(s) restored).',
  );
}
