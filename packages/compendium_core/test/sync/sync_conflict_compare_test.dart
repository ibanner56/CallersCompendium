import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  group('compareSyncCollection', () {
    test('dialects match by name and split into only-here, only-there, '
        'changed and same', () {
      final diff = compareSyncCollection(
        'custom_dialects',
        [
          {
            'name': 'Larks/Robins',
            'moves': {'swing': 'swing'},
          },
          {'name': 'Mine only', 'moves': <String, String>{}},
          {'name': 'Shared', 'moves': <String, String>{}},
        ],
        [
          {
            'name': 'Larks/Robins',
            'moves': {'swing': 'twirl'},
          },
          {'name': 'Theirs only', 'moves': <String, String>{}},
          {'name': 'Shared', 'moves': <String, String>{}},
        ],
      )!;

      expect(diff.onlyLocal.map((e) => e.label), ['Mine only']);
      expect(diff.onlyOther.map((e) => e.label), ['Theirs only']);
      expect(diff.changed.map((c) => c.local.label), ['Larks/Robins']);
      expect(diff.same, 1);
      expect(diff.isEmpty, isFalse);
    });

    test('themes match by id, so a rename is a change, not a swap', () {
      final diff = compareSyncCollection(
        'custom_themes',
        [
          {'id': 't1', 'name': 'Old name', 'roles': <String, Object?>{}},
        ],
        [
          {'id': 't1', 'name': 'New name', 'roles': <String, Object?>{}},
        ],
      )!;

      expect(diff.onlyLocal, isEmpty);
      expect(diff.onlyOther, isEmpty);
      expect(diff.changed.single.local.label, 'Old name');
      expect(diff.changed.single.other.label, 'New name');
    });

    test('shorthands match by normalized token and are labelled by the '
        'token as typed', () {
      final diff = compareSyncCollection(
        'shorthand_mappings',
        [
          {'token': 'BS', 'figures': <Object?>[]},
        ],
        [
          {'token': ' bs ', 'figures': <Object?>[]},
          {
            'token': 'nbs',
            'figures': <Object?>[
              {'move': 'swing'},
            ],
          },
        ],
      )!;

      expect(diff.same, 0, reason: 'the stored token text differs');
      expect(diff.changed.single.local.label, 'BS');
      expect(diff.onlyOther.single.label, 'nbs');
    });

    test('snippets match by figure signature and have no label of their '
        'own', () {
      final diff = compareSyncCollection(
        'walkthrough_snippets',
        {
          'version': 2,
          'snippets': {'swing(who=partner)': 'Swing your partner'},
        },
        {
          'version': 2,
          'snippets': {
            'swing(who=partner)': 'Partner swing',
            'circle(where=left)': 'Circle left',
          },
        },
      )!;

      expect(diff.changed.single.local.value, 'Swing your partner');
      expect(diff.changed.single.other.value, 'Partner swing');
      expect(diff.onlyOther.single.key, 'circle(where=left)');
      expect(diff.onlyOther.single.label, isNull);
    });

    test('a version this device never had reads as entirely only on the '
        'other device', () {
      final diff = compareSyncCollection('custom_dialects', null, [
        {'name': 'A'},
        {'name': 'B'},
      ])!;

      expect(diff.onlyOther.map((e) => e.key), ['A', 'B']);
      expect(diff.onlyLocal, isEmpty);
    });

    test('returns null for a key that is not a collection, or a value not '
        'shaped like one', () {
      expect(compareSyncCollection('theme_mode', 'dark', 'light'), isNull);
      expect(
        compareSyncCollection('custom_dialects', 'x', <Object?>[]),
        isNull,
      );
    });
  });

  group('syncDifferingFields', () {
    test('lists the fields that differ, in order, ignoring identity and '
        'timestamps', () {
      expect(
        syncDifferingFields(
          {
            'id': 'a',
            'title': 'Same',
            'figures': [1],
            'notes': 'x',
            'updatedAt': '2026-10-01',
          },
          {
            'id': 'a',
            'title': 'Same',
            'figures': [2],
            'tags': ['t'],
            'updatedAt': '2026-10-02',
          },
        ),
        ['figures', 'notes', 'tags'],
      );
    });

    test('a field one version lacks compares as empty', () {
      expect(syncDifferingFields({'notes': null}, {}), isEmpty);
      expect(syncDifferingFields(null, {'notes': 'x'}), ['notes']);
    });
  });

  group('syncUserVisibleBody', () {
    // Spec §6.7: comparing what a user is shown draws only on the part this
    // build syncs. A kind with no list of shown fields shows every synced
    // field, so a part kept for a newer version must not count as one.
    for (final (kind, body) in [
      (SyncRecordKind.publishedSource, {'title': 'Source', 'year': 1990}),
      (SyncRecordKind.difficultyLevel, {'label': 'Easy', 'position': 0}),
      (SyncRecordKind.customFieldDef, {'key': 'level', 'label': 'Level'}),
    ]) {
      test('a kept part of a ${kind.name} is not shown', () {
        final withKept = {...body, 'addedLater': 'x'};

        expect(
          syncUserVisibleBody(kind, withKept),
          syncUserVisibleBody(kind, body),
        );
        expect(
          syncUserVisibleContentHash(kind, withKept),
          syncUserVisibleContentHash(kind, body),
        );
        expect(
          syncDifferingFields(
            syncUserVisibleBody(kind, withKept),
            syncUserVisibleBody(kind, {...body, 'addedLater': 'y'}),
          ),
          isEmpty,
        );
      });
    }

    test('a field this build syncs still counts', () {
      expect(
        syncUserVisibleBody(SyncRecordKind.publishedSource, {
          'id': 's1',
          'title': 'Source',
          'addedLater': 'x',
        }),
        {'title': 'Source'},
      );
    });

    test('a setting kept whole shows nothing, and a synced one shows its value '
        'but not a kept part of it', () {
      expect(
        syncUserVisibleBody(SyncRecordKind.setting, {
          'value': 1,
        }, settingsKey: 'a_setting_added_later'),
        isEmpty,
      );
      expect(
        syncUserVisibleBody(SyncRecordKind.setting, {
          'value': ['a'],
          'addedLater': 'x',
        }, settingsKey: 'custom_dialects'),
        {
          'value': ['a'],
        },
      );
    });
  });

  group('combineSyncCollection', () {
    test("keeps snippets from both in the library's own shape", () {
      final combined = combineSyncCollection(
        'walkthrough_snippets',
        {
          'version': 2,
          'snippets': {'a': 'Mine', 'shared': 'Mine too'},
        },
        {
          'version': 2,
          'snippets': {'b': 'Theirs', 'shared': 'Theirs too'},
        },
        takeOtherFor: {'shared'},
      )!;

      expect(combined.value, {
        'version': 2,
        'snippets': {'a': 'Mine', 'shared': 'Theirs too', 'b': 'Theirs'},
      });
      expect(combined.count, 3);
      expect(combined.overLimit, isFalse);
    });

    test('snippets saved under an older signature scheme match, and combine, '
        'under the current one', () {
      final mine = {
        'version': 2,
        'snippets': {'circle(where=left)': 'Circle left, mine'},
      };
      final theirs = {
        'version': 1,
        'snippets': {
          'circle(dir=left)': 'Circle left, theirs',
          'swing(who=partner)': 'Swing your partner',
        },
      };

      final diff = compareSyncCollection('walkthrough_snippets', mine, theirs)!;
      expect(diff.changed.single.local.key, 'circle(where=left)');
      expect(diff.onlyOther.single.key, 'swing(who=partner)');

      final combined = combineSyncCollection(
        'walkthrough_snippets',
        mine,
        theirs,
        takeOtherFor: {'circle(where=left)'},
      )!;
      expect(combined.value, {
        'version': kFigureSnippetSignatureVersion,
        'snippets': {
          'circle(where=left)': 'Circle left, theirs',
          'swing(who=partner)': 'Swing your partner',
        },
      });
      // Read back as the library loads it, every snippet is still reachable.
      final library = WalkthroughSnippetLibrary.fromJson(
        combined.value! as Map<String, Object?>,
      );
      expect(library.snippets.keys, {
        'circle(where=left)',
        'swing(who=partner)',
      });
    });

    test('keeps the alternatives both libraries retained for a signature', () {
      final combined = combineSyncCollection(
        'walkthrough_snippets',
        {
          'version': 2,
          'snippets': {'swing(who=partner)': 'A'},
          'conflicts': {
            'swing(who=partner)': ['A', 'B'],
          },
        },
        {
          'version': 2,
          'snippets': {'swing(who=partner)': 'A'},
          'conflicts': {
            'swing(who=partner)': ['A', 'C'],
          },
        },
      )!;

      expect((combined.value! as Map)['conflicts'], {
        'swing(who=partner)': ['A', 'B', 'C'],
      });
    });

    test("reports a combination over the library's limit", () {
      final combined = combineSyncCollection(
        'shorthand_mappings',
        [
          for (var i = 0; i < maxShorthandMappings; i++)
            {'token': 'mine$i', 'figures': <Object?>[]},
        ],
        [
          {'token': 'theirs', 'figures': <Object?>[]},
        ],
      )!;

      expect(combined.count, maxShorthandMappings + 1);
      expect(combined.overLimit, isTrue);
    });

    test('themes have no limit', () {
      expect(syncCollectionLimit('custom_themes'), isNull);
    });
  });
}
