import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// The user's own glossary in a backup (#709): `app.glossary`, its
/// conditional v2 envelope, and a restore that leaves it alone when the file
/// does not describe it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime.utc(2026, 10, 14, 9);
  const stamp = '"createdAt":"2026-10-15T00:00:00.000Z"';

  UserGlossaryEntry entry(String id, {String name = 'grand right and left'}) =>
      UserGlossaryEntry(
        id: id,
        kindName: 'compound',
        name: name,
        definition: 'Pull by alternating hands around the ring.',
        description: 'Four pull-bys.',
        keywords: const ['grl'],
        notes: 'from my cards',
        payload: const {
          'params': <Object?>[],
          'figures': <Object?>[],
          'bindings': <Object?>[],
        },
        createdAt: created,
      );

  Map<String, Object?> entryJson(String id, {String name = 'GRL'}) => {
    'id': id,
    'kind': 'compound',
    'name': name,
    'definition': 'd',
    'description': 'x',
    'createdAt': '2026-10-14T09:00:00.000Z',
  };

  String backupWith(Object? glossary) => jsonEncode({
    'backupVersion': 2,
    'createdAt': '2026-10-15T00:00:00.000Z',
    'core': {'dances': <Object?>[]},
    'app': {'glossary': glossary},
  });

  Future<CompendiumRepositories> seeded() async {
    final repos = openTestRepositories();
    await repos.userGlossary.upsert(entry('live'));
    await repos.figureNotes.set('swing', 'role1s on the left');
    return repos;
  }

  Future<List<String>> liveIds(CompendiumRepositories repos) async => [
    for (final e in await repos.userGlossary.listAll()) e.id,
  ];

  Future<List<String>> liveNoteIds(CompendiumRepositories repos) async => [
    for (final n in await repos.figureNotes.listAll()) n.figureId,
  ];

  test('entries and notes round-trip through a replace restore', () async {
    final source = await seeded();
    final json = await BackupService(source).exportToJson();

    final target = openTestRepositories();
    final outcome = await BackupService(target).restoreFromJson(json);

    expect(outcome.applied, isTrue);
    final restored = (await target.userGlossary.getById('live'))!;
    expect(restored.name, 'grand right and left');
    expect(restored.kind, UserGlossaryEntryKind.compound);
    expect(restored.keywords, ['grl']);
    expect(restored.notes, 'from my cards');
    expect(restored.payload, {
      'params': <Object?>[],
      'figures': <Object?>[],
      'bindings': <Object?>[],
    });
    expect(restored.createdAt, created);
    expect(
      (await target.figureNotes.get('swing'))!.notes,
      'role1s on the left',
    );
  });

  group('the envelope version', () {
    test('a backup without glossary data is still written as v1, with no '
        'glossary section', () async {
      final repos = openTestRepositories();
      final doc = await BackupService(repos).buildDocument();
      final json = backupToJson(doc);
      expect(json['backupVersion'], backupSchemaVersionBase);
      expect((json['app']! as Map).keys, ['dialects', 'themes', 'settings']);
    });

    test('a backup with an entry or a note is written as v2', () async {
      final withEntry = openTestRepositories();
      await withEntry.userGlossary.upsert(entry('e'));
      final withNote = openTestRepositories();
      await withNote.figureNotes.set('swing', 'n');
      for (final repos in [withEntry, withNote]) {
        final json = backupToJson(await BackupService(repos).buildDocument());
        expect(json['backupVersion'], backupSchemaVersionGlossary);
        expect((json['app']! as Map)['glossary'], isA<Map<String, Object?>>());
      }
    });

    test('a deleted entry is not carried', () async {
      final repos = await seeded();
      await repos.userGlossary.delete('live');
      final doc = await BackupService(repos).buildDocument();
      expect(doc.glossaryEntries, isEmpty);
    });
  });

  group('restore', () {
    test('a backup made before the glossary leaves live entries and notes '
        'alone', () async {
      final repos = await seeded();
      const json =
          '{"backupVersion":1,$stamp,"core":{"dances":[]},'
          '"app":{"settings":{}}}';

      final outcome = await BackupService(repos).restoreFromJson(json);

      expect(outcome.applied, isTrue);
      expect(await liveIds(repos), ['live']);
      expect(await liveNoteIds(repos), ['swing']);
    });

    test('a section that describes the glossary replaces it, deleting softly '
        'what it lacks', () async {
      final repos = await seeded();
      final json = backupWith({
        'entries': [entryJson('fromBackup')],
        'figureNotes': [
          {'figureId': 'chain', 'notes': 'n'},
        ],
      });

      final outcome = await BackupService(repos).restoreFromJson(json);

      expect(outcome.applied, isTrue);
      expect(await liveIds(repos), ['fromBackup']);
      expect(await liveNoteIds(repos), ['chain']);
      final tombstones = await repos.userGlossary.listAll(includeDeleted: true);
      expect(tombstones.map((e) => e.id), containsAll(['live', 'fromBackup']));
    });

    test('an entry that cannot be read keeps every live entry: nothing is '
        'deleted, and what was read is still added', () async {
      for (final glossary in <Object?>[
        {
          'entries': [entryJson('fromBackup'), 'not an entry'],
          'figureNotes': <Object?>[],
        },
        {
          'entries': [entryJson('fromBackup')],
          'figureNotes': [
            {'figureId': '', 'notes': 'n'},
          ],
        },
        {'entries': 'not a list', 'figureNotes': <Object?>[]},
        {
          'entries': [entryJson('fromBackup')],
        },
      ]) {
        final repos = await seeded();

        final outcome = await BackupService(
          repos,
        ).restoreFromJson(backupWith(glossary));

        expect(outcome.applied, isTrue, reason: '$glossary');
        expect(outcome.errors, isNotEmpty, reason: '$glossary');
        expect(await liveIds(repos), contains('live'), reason: '$glossary');
        final entries = (glossary! as Map)['entries'];
        if (entries is List && entries.first is Map) {
          expect(
            await liveIds(repos),
            contains('fromBackup'),
            reason: '$glossary',
          );
        }
        expect(await liveNoteIds(repos), ['swing'], reason: '$glossary');
      }
    });

    test('an entry over a bound is skipped, reported as an error, and its live '
        'copy kept', () async {
      final repos = await seeded();
      final json = backupWith({
        'entries': [
          entryJson('live', name: 'x' * (maxUserGlossaryNameLength + 1)),
        ],
        'figureNotes': <Object?>[],
      });

      final outcome = await BackupService(repos).restoreFromJson(json);

      expect(outcome.applied, isTrue);
      // Errors, not warnings: the restore reports skipped problems from its
      // errors, and never shows its warnings.
      expect(
        outcome.errors.map((e) => (e.entityType, e.entityId)),
        contains(('glossaryEntry', 'live')),
      );
      expect(
        (await repos.userGlossary.getById('live'))!.name,
        'grand right and left',
      );
    });

    test('an id, kind or figure id sync could not carry is skipped and '
        'reported, and the rest of the restore still applies (#709)', () async {
      final repos = await seeded();
      final long = 'x' * (maxUserGlossaryNameLength + 1);
      const decomposed = 'cafe\u0301';
      final outcome = await BackupService(repos).restoreFromJson(
        backupWith({
          'entries': [
            entryJson(long),
            {...entryJson('badKind'), 'kind': long},
            {...entryJson('nfdKind'), 'kind': decomposed},
            entryJson('fromBackup'),
          ],
          'figureNotes': [
            {'figureId': long, 'notes': 'A note.'},
            {'figureId': 'swing', 'notes': 'role1s on the left'},
          ],
        }),
      );

      expect(outcome.applied, isTrue);
      expect(
        outcome.errors.map((e) => (e.entityType, e.entityId)),
        containsAll([
          ('glossaryEntry', long),
          ('glossaryEntry', 'badKind'),
          ('glossaryEntry', 'nfdKind'),
          ('figureNote', long),
        ]),
      );
      expect(await liveIds(repos), ['fromBackup']);
      expect(await liveNoteIds(repos), ['swing']);
    });

    test('a payload that cannot be stored is skipped the same way, and the '
        'rest of the restore still applies', () async {
      final repos = await seeded();
      // A bare backup (no container) can carry a number JSON cannot encode
      // back: 1e999 decodes as infinity.
      final json = backupWith({
        'entries': [
          {...entryJson('live'), 'payload': '__payload__'},
          entryJson('fromBackup'),
        ],
        'figureNotes': <Object?>[],
      }).replaceFirst('"__payload__"', '{"x": 1e999}');

      final outcome = await BackupService(repos).restoreFromJson(json);

      expect(outcome.applied, isTrue);
      expect(outcome.settingsFailed, isFalse);
      expect(
        outcome.errors.map((e) => (e.entityType, e.entityId)),
        contains(('glossaryEntry', 'live')),
      );
      expect(await liveIds(repos), containsAll(['live', 'fromBackup']));
      expect(
        (await repos.userGlossary.getById('live'))!.name,
        'grand right and left',
      );
    });

    test('a note with no visible text is unreadable, so the live note is '
        'kept', () async {
      final repos = await seeded();
      final json = backupWith({
        'entries': <Object?>[],
        'figureNotes': [
          {'figureId': 'swing', 'notes': '\u200B'},
        ],
      });

      final outcome = await BackupService(repos).restoreFromJson(json);

      expect(outcome.applied, isTrue);
      expect(
        (await repos.figureNotes.get('swing'))!.notes,
        'role1s on the left',
      );
      expect(await liveIds(repos), ['live'], reason: 'nothing deleted');
    });

    test('the glossary is applied whole or not at all: a store failure part '
        'way through undoes its deletions too', () async {
      final repos = await seeded();
      // The second entry's insert fails, after the replace has deleted the
      // live entry the backup lacks and written the first.
      await repos.db.customStatement(
        "CREATE TRIGGER boom BEFORE INSERT ON user_glossary_entries "
        "WHEN NEW.id = 'boom' BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      final json = backupWith({
        'entries': [entryJson('fromBackup'), entryJson('boom')],
        'figureNotes': <Object?>[],
      });

      final outcome = await BackupService(repos).restoreFromJson(json);

      expect(outcome.applied, isTrue, reason: 'the core committed');
      expect(outcome.settingsFailed, isTrue);
      expect(await liveIds(repos), ['live'], reason: 'nothing half-applied');
      expect(await liveNoteIds(repos), ['swing']);
    });

    test('a merge restore adds and updates, and deletes nothing', () async {
      final repos = await seeded();
      final json = backupWith({
        'entries': [entryJson('fromBackup')],
        'figureNotes': [
          {'figureId': 'chain', 'notes': 'n'},
        ],
      });

      final outcome = await BackupService(
        repos,
      ).restoreFromJson(json, mode: RestoreMode.merge);

      expect(outcome.applied, isTrue);
      expect(await liveIds(repos), unorderedEquals(['live', 'fromBackup']));
      expect(await liveNoteIds(repos), ['chain', 'swing']);
    });

    test('retrying the settings apply replaces the glossary as the restore '
        'would, in the mode it ran in', () async {
      final json = backupWith({
        'entries': [entryJson('fromBackup')],
        'figureNotes': <Object?>[],
      });

      final replaced = await seeded();
      await BackupService(
        replaced,
      ).retryApplySettings(json, mode: RestoreMode.replace);
      expect(await liveIds(replaced), ['fromBackup']);

      final merged = await seeded();
      await BackupService(
        merged,
      ).retryApplySettings(json, mode: RestoreMode.merge);
      expect(await liveIds(merged), unorderedEquals(['live', 'fromBackup']));
    });
  });

  group('decode', () {
    test('an absent section is reported as absent, not as empty', () {
      final read = decodeBackup(
        '{"backupVersion":1,$stamp,"core":{"dances":[]},"app":{}}',
      );
      expect(read.hasGlossarySection, isFalse);
      expect(read.glossaryComplete, isTrue);
    });

    test('entries and notes are bounded', () {
      final read = decodeBackup(
        backupWith({
          'entries': [
            for (var i = 0; i <= kMaxBackupGlossaryEntries; i++)
              entryJson('e$i'),
          ],
          'figureNotes': [
            for (var i = 0; i <= kMaxBackupFigureNotes; i++)
              {'figureId': 'f$i', 'notes': 'n'},
          ],
        }),
      );
      expect(
        read.document.glossaryEntries,
        hasLength(kMaxBackupGlossaryEntries),
      );
      expect(read.document.figureNotes, hasLength(kMaxBackupFigureNotes));
      expect(read.glossaryComplete, isFalse);
      expect(read.errors.map((e) => e.entityType).toSet(), {
        'glossaryEntry',
        'figureNote',
      });
    });

    test('a malformed entry is dropped without throwing', () {
      for (final bad in <Object?>[
        null,
        5,
        {...entryJson('a'), 'id': ''},
        {...entryJson('a'), 'kind': 3},
        {...entryJson('a'), 'createdAt': 'yesterday'},
        {...entryJson('a'), 'keywords': 'grl'},
        {...entryJson('a'), 'notes': 4},
      ]) {
        final read = decodeBackup(
          backupWith({
            'entries': [bad],
            'figureNotes': <Object?>[],
          }),
        );
        expect(read.document.glossaryEntries, isEmpty, reason: '$bad');
        expect(read.glossaryComplete, isFalse, reason: '$bad');
      }
    });

    test('a v2 backup is not newer than this build', () {
      final read = decodeBackup(
        backupWith({'entries': <Object?>[], 'figureNotes': <Object?>[]}),
      );
      expect(read.newerSchema, isFalse);
    });
  });
}
