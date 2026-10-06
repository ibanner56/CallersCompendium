import 'dart:io';

import 'package:compendium_app/src/data/app_database.dart';
import 'package:compendium_app/src/data/migration_guard.dart';
import 'package:compendium_core/compendium_core.dart'
    show kCompendiumSchemaVersion;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// Distinct Documents / support / cache locations, so a resolved path says which
/// provider it came from. [documents] null models Linux without xdg-user-dirs
/// (`path_provider` throws [MissingPlatformDirectoryException]).
class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider({
    required this.documents,
    required this.support,
    required this.cache,
  });

  final String? documents;
  final String support;
  final String cache;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;

  @override
  Future<String?> getApplicationSupportPath() async => support;

  @override
  Future<String?> getApplicationCachePath() async => cache;
}

void main() {
  late Directory root;
  late String documents;
  late String support;
  late String cache;
  late PathProviderPlatform original;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_database_test');
    documents = p.join(root.path, 'Documents');
    support = p.join(root.path, 'Roaming', 'Banner', 'Compendium');
    cache = p.join(root.path, 'Local', 'Banner', 'Compendium');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(
      documents: documents,
      support: support,
      cache: cache,
    );
  });

  tearDown(() {
    PathProviderPlatform.instance = original;
    root.deleteSync(recursive: true);
  });

  const name = '$kDatabaseName.sqlite';

  test('Windows keeps the database in LocalAppData, never Documents or '
      'Roaming', () async {
    final file = await resolveDatabaseFile(operatingSystem: 'windows');
    expect(file.path, p.join(cache, name));
    expect(p.isWithin(documents, file.path), isFalse);
    expect(p.isWithin(support, file.path), isFalse);
  });

  test('Linux keeps the database in the application support directory, '
      'never Documents', () async {
    final file = await resolveDatabaseFile(operatingSystem: 'linux');
    expect(file.path, p.join(support, name));
    expect(p.isWithin(documents, file.path), isFalse);
  });

  test('Linux without a Documents directory resolves the same path', () async {
    PathProviderPlatform.instance = _FakePathProvider(
      documents: null,
      support: support,
      cache: cache,
    );
    final locations = await resolveDatabaseLocations(operatingSystem: 'linux');
    expect(locations.primary.path, support);
    expect(locations.legacy, isEmpty);
  });

  test('legacy locations: Documents on Linux; Documents and Roaming on '
      'Windows; none elsewhere', () async {
    final linux = await resolveDatabaseLocations(operatingSystem: 'linux');
    expect(linux.legacy.map((d) => d.path), [documents]);
    final windows = await resolveDatabaseLocations(operatingSystem: 'windows');
    expect(windows.legacy.map((d) => d.path), [documents, support]);
    for (final os in ['macos', 'android', 'ios']) {
      final locations = await resolveDatabaseLocations(operatingSystem: os);
      expect(locations.primary.path, documents, reason: os);
      expect(locations.legacy, isEmpty, reason: os);
    }
  });

  test('a reset leaves nothing at the primary path, reopens the same path and '
      'leaves the legacy file alone', () async {
    final legacy = File(p.join(documents, name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [1]);
    final selected = await resolveDatabaseFile(operatingSystem: 'linux');
    selected.createSync(recursive: true);
    selected.writeAsBytesSync(const [2]);

    final result = await performReset(dbFile: selected);

    expect(result, isA<ResetComplete>());
    final reopened = await resolveDatabaseFile(operatingSystem: 'linux');
    expect(reopened.path, selected.path);
    // No placeholder: a leftover empty primary file would trip the
    // relocation's bothExist guard if a legacy database later reappears.
    expect(reopened.existsSync(), isFalse);
    expect(legacy.readAsBytesSync(), const [1]);
  });

  test('after a reset a reappearing legacy database relocates instead of '
      'tripping bothExist', () async {
    final selected = await resolveDatabaseFile(operatingSystem: 'linux');
    selected.createSync(recursive: true);
    expect(await performReset(dbFile: selected), isA<ResetComplete>());
    final legacy = File(p.join(documents, name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [1]);

    expect(
      await relocateLegacyDatabase(target: selected, legacy: [legacy]),
      isTrue,
    );
    expect(selected.readAsBytesSync(), const [1]);
  });

  // The startup preflight is the only caller of relocateLegacyDatabase. Every
  // other test drives the relocation directly, and startup_sequence_test
  // injects its own preflight, so without these an upgrade that silently
  // stopped moving the library (every Windows/Linux user opening an empty one,
  // then blocked on bothExist next launch) would stay green.
  for (final (os, primary) in [
    ('linux', () => support),
    ('windows', () => cache),
  ]) {
    test('the startup preflight moves a $os library out of Documents before '
        'anything opens it', () async {
      final legacy = File(p.join(documents, name));
      legacy.parent.createSync(recursive: true);
      final db = sql.sqlite3.open(legacy.path);
      try {
        db.execute('CREATE TABLE t (v TEXT)');
        db.execute("INSERT INTO t (v) VALUES ('kept')");
        db.execute('PRAGMA user_version = $kCompendiumSchemaVersion');
      } finally {
        db.close();
      }

      await runMigrationPreflightForApp(
        runningSchemaVersion: kCompendiumSchemaVersion,
        operatingSystem: os,
      );

      final moved = File(p.join(primary(), name));
      expect(moved.existsSync(), isTrue, reason: 'library not at the new path');
      expect(legacy.existsSync(), isFalse, reason: 'library left in Documents');
      final reopened = sql.sqlite3.open(moved.path);
      try {
        expect(reopened.select('SELECT v FROM t').single['v'], 'kept');
      } finally {
        reopened.close();
      }
    });
  }
}
