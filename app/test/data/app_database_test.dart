import 'dart:io';

import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  late Directory root;
  late Directory documents;
  late Directory support;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_database_test');
    documents = Directory(p.join(root.path, 'documents'))..createSync();
    support = Directory(p.join(root.path, 'support'))..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  const name = '$kDatabaseName.sqlite';

  test('uses the Documents directory when it resolves and no support '
      'database exists', () async {
    final file = await resolveDatabaseFile(
      documentsDirectory: () async => documents,
      supportDirectory: () async => support,
    );
    expect(file.path, p.join(documents.path, name));
  });

  test('falls back to the support directory when Documents cannot be '
      'resolved', () async {
    final file = await resolveDatabaseFile(
      documentsDirectory: () async => throw MissingPlatformDirectoryException(
        'Unable to get application documents directory',
      ),
      supportDirectory: () async => support,
    );
    expect(file.path, p.join(support.path, name));
  });

  test('keeps using a database that already lives in the support '
      'directory', () async {
    File(p.join(support.path, name)).writeAsBytesSync(const [0]);
    final file = await resolveDatabaseFile(
      documentsDirectory: () async => documents,
      supportDirectory: () async => support,
    );
    expect(file.path, p.join(support.path, name));
  });

  test('a reset keeps selecting the support database when a Documents '
      'database also exists', () async {
    File(p.join(documents.path, name)).writeAsBytesSync(const [1]);
    File(p.join(support.path, name)).writeAsBytesSync(const [2]);
    Future<File> resolve() => resolveDatabaseFile(
      documentsDirectory: () async => documents,
      supportDirectory: () async => support,
    );

    final selected = await resolve();
    final result = await performReset(dbFile: selected, keepPath: true);

    expect(result, isA<ResetComplete>());
    final reopened = await resolve();
    expect(reopened.path, p.join(support.path, name));
    expect(reopened.lengthSync(), 0);
    expect(File(p.join(documents.path, name)).readAsBytesSync(), const [1]);
  });
}
