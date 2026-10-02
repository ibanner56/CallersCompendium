import 'dart:io';

import 'package:compendium_app/src/data/app_database.dart';
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
}
