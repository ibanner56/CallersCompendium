import 'dart:convert';

import 'package:compendium_app/src/data/display_defaults.dart';
import 'package:compendium_app/src/data/tag_edits.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// The Tags manager's edits and the import-tags setting they rewrite in the
/// same transaction (`docs/design/tags-and-people.md` T2, "The import-tags
/// setting").
void main() {
  // Ids sort in this order, so the surviving id of a merge is easy to read.
  const a = '00000000-0000-4000-8000-00000000000a';
  const b = '00000000-0000-4000-8000-00000000000b';
  const c = '00000000-0000-4000-8000-00000000000c';
  final t0 = DateTime.utc(2026, 10, 1);

  late CompendiumRepositories repos;

  setUp(() => repos = openTestRepositories());

  Future<void> tag(String id, String name) async {
    // ignore: unused_result
    await repos.tags.upsert(
      Tag(id: id, name: name),
      at: t0,
    );
  }

  Future<void> dance(String id, List<String> tags) => repos.dances.create(
    Dance(
      id: id,
      title: 'Dance $id',
      tagIds: tags,
      createdAt: t0,
      updatedAt: t0,
    ),
  );

  Future<void> setImportTags(List<String> names) => repos.settings.set(
    kDefaultImportTagNamesKey,
    encodeDefaultImportTagNames(names),
  );

  // Decoded raw, not through `tryDecodeDefaultImportTagNames`, which drops
  // duplicates itself and would hide a rewrite that kept two.
  Future<List<String>?> importTags() async {
    final stored = await repos.settings.get(kDefaultImportTagNamesKey);
    return stored == null
        ? null
        : List<String>.from(jsonDecode(stored as String) as List);
  }

  Future<Set<String>> tagsOf(String danceId) async =>
      (await repos.dances.getById(danceId))!.tagIds.toSet();

  test('a rename replaces the old name in place', () async {
    await tag(a, 'Flowing');
    await setImportTags(['Contra', 'Flowing', 'Easy']);

    await renameTag(repos, a, 'Flowy');

    expect(await importTags(), ['Contra', 'Flowy', 'Easy']);
  });

  test(
    'a merge replaces every merged name with the result and keeps one',
    () async {
      await tag(a, 'Flowy');
      await tag(b, 'Flowing');
      await setImportTags(['Flowing', 'Easy', 'Flowy']);

      final edit = await mergeTags(repos, intoId: a, otherIds: [b]);

      expect(await importTags(), ['Flowy', 'Easy']);
      expect(edit.liveDanceCount, 0);
    },
  );

  test(
    'a merge under a typed name writes that name, whichever id survives',
    () async {
      // The user renamed c ("Old") to "Flowy", which two case variants hold,
      // and chose b to merge into; the surviving id is a, the smallest, so the
      // name is read back from a.
      await tag(a, 'flowy');
      await tag(b, 'FLOWY');
      await tag(c, 'Old');
      await setImportTags(['Old', 'flowy', 'FLOWY']);

      await mergeTags(repos, intoId: b, otherIds: [a, c], name: 'Flowy');

      expect((await repos.tags.getById(a))!.name, 'Flowy');
      expect(await importTags(), ['Flowy']);
    },
  );

  test(
    'a delete drops the name, and Undo restores it with the dances',
    () async {
      await tag(a, 'Bouncey');
      await tag(b, 'Easy');
      await dance('live', [a, b]);
      await dance('trashed', [a]);
      await repos.dances.softDelete('trashed', at: t0);
      await setImportTags(['Bouncey', 'Easy']);

      final edit = await deleteTag(repos, a);

      expect(
        edit.liveDanceCount,
        1,
        reason: 'the trashed dance is not counted',
      );
      expect(await importTags(), ['Easy']);
      expect(await tagsOf('live'), {b});

      await undoTagEdit(repos, edit);

      expect(await importTags(), ['Bouncey', 'Easy']);
      expect(await tagsOf('live'), {a, b});
      expect((await repos.tags.getById(a))?.name, 'Bouncey');
    },
  );

  test('Undo leaves a setting changed since the edit alone', () async {
    await tag(a, 'Bouncey');
    await setImportTags(['Bouncey', 'Easy']);
    final edit = await deleteTag(repos, a);

    // The user, or a sync pass, changed the setting after the delete.
    await setImportTags(['Contra']);
    await undoTagEdit(repos, edit);

    expect(await importTags(), ['Contra']);
    expect(await repos.tags.getById(a), isNotNull, reason: 'the tag is back');
  });

  test('a setting that does not name the tag is not rewritten', () async {
    await tag(a, 'Bouncey');
    await setImportTags(['Easy']);
    final before = await repos.settings.get(kDefaultImportTagNamesKey);

    await deleteTag(repos, a);

    expect(await repos.settings.get(kDefaultImportTagNamesKey), before);
  });

  test('an unreadable setting is left as it is', () async {
    await tag(a, 'Bouncey');
    final unreadable = jsonEncode({'not': 'a list'});
    await repos.settings.set(kDefaultImportTagNamesKey, unreadable);

    await renameTag(repos, a, 'Bouncy');

    expect(await repos.settings.get(kDefaultImportTagNamesKey), unreadable);
  });

  test('a rename onto a live name writes nothing, setting included', () async {
    await tag(a, 'Flowy');
    await tag(b, 'Flowing');
    await setImportTags(['Flowing']);

    await expectLater(
      renameTag(repos, b, 'flowy'),
      throwsA(isA<ReferenceNameTakenException>()),
    );

    expect(await importTags(), ['Flowing']);
    expect((await repos.tags.getById(b))!.name, 'Flowing');
  });

  test('Undo of a rename and of a merge puts the setting back', () async {
    await tag(a, 'Flowy');
    await tag(b, 'Flowing');
    await setImportTags(['Flowing', 'Easy', 'Flowy']);

    final renamed = await renameTag(repos, b, 'Flowish');
    expect(await importTags(), ['Flowish', 'Easy', 'Flowy']);
    await undoTagEdit(repos, renamed);
    expect(await importTags(), ['Flowing', 'Easy', 'Flowy']);

    final merged = await mergeTags(repos, intoId: a, otherIds: [b]);
    expect(await importTags(), ['Flowy', 'Easy']);
    await undoTagEdit(repos, merged);
    expect(await importTags(), ['Flowing', 'Easy', 'Flowy']);
    expect((await repos.tags.listAll()).map((t) => t.name), [
      'Flowing',
      'Flowy',
    ]);
  });

  test('a failed setting write rolls the tag edit back too', () async {
    final failer = _FailSettingsWrite();
    final failing = CompendiumRepositories(
      openWidgetTestDatabase(
        executor: NativeDatabase.memory().interceptWith(failer),
      ),
      contraTaxonomy,
    );
    // ignore: unused_result
    await failing.tags.upsert(
      Tag(id: a, name: 'Bouncey'),
      at: t0,
    );
    await failing.dances.create(
      Dance(
        id: 'one',
        title: 'One',
        tagIds: const [a],
        createdAt: t0,
        updatedAt: t0,
      ),
    );
    await failing.settings.set(
      kDefaultImportTagNamesKey,
      encodeDefaultImportTagNames(['Bouncey']),
    );
    failer.armed = true;

    await expectLater(deleteTag(failing, a), throwsA(anything));

    expect(failer.fired, isTrue, reason: 'the injected failure must fire');
    expect(await failing.tags.getById(a), isNotNull);
    expect((await failing.dances.getById('one'))!.tagIds, [a]);
  });
}

/// Fails every write to `settings` once [armed], so the setting rewrite fails
/// after the tag edit inside the same transaction has succeeded.
class _FailSettingsWrite extends drift.QueryInterceptor {
  bool armed = false;
  bool fired = false;

  bool _hit(String statement) =>
      armed && RegExp(r'\bsettings\b').hasMatch(statement);

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_hit(statement)) {
      fired = true;
      throw Exception('injected settings write failure');
    }
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (_hit(statement)) {
      fired = true;
      throw Exception('injected settings write failure');
    }
    return executor.runUpdate(statement, args);
  }
}
