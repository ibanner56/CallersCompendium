import 'dart:io';

import 'package:compendium_core/compendium_core.dart';
import 'package:compendium_app/src/data/seed_service.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'support/test_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // The checked-in seed asset, read straight from disk for the behavior tests
  // so they exercise real archive JSON without depending on the asset bundle.
  // Resolved against both the app package root (the cwd under `flutter test`)
  // and the repo root, so the suite passes whether run as `cd app && flutter
  // test` or `flutter test app/test/...` from the repository root.
  final seedJson = _readSeedAsset();
  Future<String> fakeLoader(String key) async {
    expect(key, kBabyRoseSeedAsset);
    return seedJson;
  }

  late CompendiumRepositories repos;
  setUp(() {
    repos = openTestRepositories();
  });
  tearDown(() => repos.db.close());

  Future<List<({String id, String title})>> allDances() =>
      repos.dances.listIdsAndTitles(includeDeleted: true);

  test(
    'fresh empty first run seeds exactly one dance and sets the latch',
    () async {
      await SeedService(repos, assetLoader: fakeLoader).ensureSeeded();

      final dances = await allDances();
      expect(dances, hasLength(1));
      expect(dances.single.title, 'The Baby Rose');

      final authors = await repos.choreographers.listAll();
      expect(authors.map((a) => a.name), contains('David Kaynor'));

      expect(await repos.settings.contains(kInitialSeedCompletedKey), isTrue);
    },
  );

  test('second launch does not add another dance', () async {
    final service = SeedService(repos, assetLoader: fakeLoader);
    await service.ensureSeeded();
    await service.ensureSeeded();

    expect(await allDances(), hasLength(1));
  });

  test('deleting the seed then relaunching does not re-add it', () async {
    final service = SeedService(repos, assetLoader: fakeLoader);
    await service.ensureSeeded();

    final seeded = (await allDances()).single;
    await repos.dances.hardDelete([seeded.id]);
    expect(await allDances(), isEmpty);

    // Relaunch: the latch is set, so seeding is a no-op even though the
    // collection is now empty again.
    await service.ensureSeeded();
    expect(await allDances(), isEmpty);
  });

  test('an already-populated first run is not injected into', () async {
    // Simulate an upgrade from a build without seeding: the collection already
    // has a user's dance and the latch is unset.
    final now = DateTime.utc(2026, 1, 1);
    await repos.dances.create(
      Dance(
        id: 'user-dance',
        title: 'A User Dance',
        createdAt: now,
        updatedAt: now,
      ),
    );

    await SeedService(repos, assetLoader: fakeLoader).ensureSeeded();

    final dances = await allDances();
    expect(dances, hasLength(1));
    expect(dances.single.title, 'A User Dance');
    // The latch is still set so the check never runs again.
    expect(await repos.settings.contains(kInitialSeedCompletedKey), isTrue);
  });

  test('a failed seed does not set the latch (so it can retry)', () async {
    Future<String> failingLoader(String key) async =>
        throw StateError('asset missing');

    await expectLater(
      SeedService(repos, assetLoader: failingLoader).ensureSeeded(),
      throwsA(isA<StateError>()),
    );

    expect(await allDances(), isEmpty);
    expect(await repos.settings.contains(kInitialSeedCompletedKey), isFalse);
  });

  test('loads the real bundled asset and seeds the faithful dance', () async {
    // Uses the default rootBundle loader against the asset declared in
    // pubspec.yaml — proves the asset is bundled and decodes on-device.
    await SeedService(repos).ensureSeeded();

    final dances = await repos.dances.listAll();
    expect(dances, hasLength(1));
    final dance = dances.single;
    expect(dance.title, 'The Baby Rose');
    expect(dance.formation.shape, FormationShape.dupleImproper);
    expect(dance.provenance?.source, ProvenanceSource.contradb);
    expect(dance.figures, hasLength(6));
    expect(dance.figures.first.move, 'swing');
    expect(dance.figures.last.progression, isTrue);
  });
}

/// Reads the checked-in seed asset regardless of the test runner's working
/// directory: `flutter test` sets the cwd to the app package, but running
/// `flutter test app/test/...` from the repo root does not. Tries the package
/// root first, then the repo-root-prefixed path.
String _readSeedAsset() {
  const relative = 'assets/seed/baby_rose.json';
  for (final path in <String>[relative, 'app/$relative']) {
    final file = File(path);
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail(
    'Could not locate seed asset "$relative" from '
    '${Directory.current.path}',
  );
}
