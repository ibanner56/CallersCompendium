import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_app/src/data/custom_themes_controller.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:compendium_app/src/data/walkthrough_snippet_library_controller.dart';
import 'package:compendium_app/src/data/reduce_motion_scope.dart'
    show kReduceMotionKey;
import 'package:compendium_app/src/screens/settings_screen.dart'
    show
        kSortIgnoreArticlesKey,
        kAppThemeKey,
        kPerformTextScaleKey,
        kSyncDeviceIdKey,
        kSyncIdKey;
import 'package:compendium_app/src/data/soft_delete_retention.dart'
    show kSoftDeleteRetentionKey;
import 'package:compendium_app/src/data/window_service.dart'
    show kWindowFrameKey;
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<void> _seed(CompendiumRepositories repos) async {
  await repos.dances.create(_dance('d1', 'Kept Dance'));
  await repos.settings.set(kCustomDialectsKey, [
    Dialect(name: 'My Dialect').toJson(),
  ]);
  await repos.settings.set(kActiveDialectRefKey, 'My Dialect');
  await repos.settings.set(kCustomThemesKey, [
    const CustomTheme(
      id: 'custom-1',
      name: 'Sunset',
      brightness: Brightness.dark,
      roles: {'primary': 0xFF112233},
    ).toJson(),
  ]);
  await repos.settings.set(kActiveCustomThemeKey, 'custom-1');
  await repos.settings.set(kSortIgnoreArticlesKey, false);
  await repos.settings.set(kWalkthroughSnippetsKey, {
    'snippets': {'swing(who=partners)': 'Swing your partner.'},
  });
  // Device-local / metadata keys that must NOT travel in a backup.
  await repos.settings.set(kWindowFrameKey, 'some-geometry');
  await repos.settings.set(kLastBackupAtKey, '2020-01-01T00:00:00.000Z');
  await repos.settings.set(taxonomyV33CanonicalRebuildDoneKey, 'done');
  await repos.settings.set(kSyncIdKey, 'one-two-three-four');
  await repos.settings.set(kSyncDeviceIdKey, 'device-identifier');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'buildDocument captures app-local pieces and excludes denylisted keys',
    () async {
      final repos = openTestRepositories();
      await _seed(repos);

      final doc = await BackupService(repos).buildDocument();

      expect(doc.core.dances.single.id, 'd1');
      expect(doc.customDialects.single.name, 'My Dialect');
      expect(doc.activeDialectRef, 'My Dialect');
      expect(doc.customThemes.single.id, 'custom-1');
      expect(doc.activeCustomThemeId, 'custom-1');
      expect(doc.settings[kSortIgnoreArticlesKey], false);
      // Denylisted keys are never carried in the settings map.
      expect(doc.settings.containsKey(kWindowFrameKey), isFalse);
      expect(doc.settings.containsKey(kLastBackupAtKey), isFalse);
      expect(
        doc.settings.containsKey(taxonomyV33CanonicalRebuildDoneKey),
        isFalse,
      );
      expect(doc.settings.containsKey(kSyncIdKey), isFalse);
      expect(doc.settings.containsKey(kSyncDeviceIdKey), isFalse);
      expect(doc.settings.containsKey(kCustomDialectsKey), isFalse);
      expect(doc.settings.containsKey(kCustomThemesKey), isFalse);
    },
  );

  test(
    'backup preserves non-shareable custom fields and their values',
    () async {
      final source = openTestRepositories();
      // ignore: unused_result
      await source.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f_shared',
          key: 'region',
          label: 'Region',
          type: CustomFieldType.text,
        ),
      );
      // ignore: unused_result
      await source.customFieldDefs.upsert(
        CustomFieldDef(
          id: 'f_private',
          key: 'organizer_email',
          label: 'Organizer email',
          type: CustomFieldType.text,
          shareable: false,
        ),
      );
      await source.dances.create(
        _dance('custom', 'Custom fields').copyWith(
          customFields: [
            CustomFieldValue(fieldId: 'f_shared', value: 'New England'),
            CustomFieldValue(fieldId: 'f_private', value: 'secret@example.com'),
          ],
        ),
      );

      final json = await BackupService(source).exportToJson();
      final decoded = decodeBackup(json);
      expect(decoded.hasErrors, isFalse);
      final privateDef = decoded.document.core.customFields.singleWhere(
        (field) => field.id == 'f_private',
      );
      expect(privateDef.shareable, isFalse);
      expect(
        decoded.document.core.dances.single.customFields,
        contains(
          CustomFieldValue(fieldId: 'f_private', value: 'secret@example.com'),
        ),
      );

      final target = openTestRepositories();
      final outcome = await BackupService(target).restoreFromJson(json);
      expect(outcome.hasErrors, isFalse);
      expect(
        (await target.customFieldDefs.getById('f_private'))?.shareable,
        isFalse,
      );
      expect(
        (await target.dances.getById('custom'))?.customFields,
        contains(
          CustomFieldValue(fieldId: 'f_private', value: 'secret@example.com'),
        ),
      );
    },
  );

  test(
    'walkthrough snippet library round-trips through backup (#411)',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      final json = await BackupService(source).exportToJson();

      final target = openTestRepositories();
      final outcome = await BackupService(target).restoreFromJson(json);
      expect(outcome.hasErrors, isFalse);

      // The library rides the generic settings map (not denylisted); the
      // controller decodes it defensively on load.
      final controller = WalkthroughSnippetLibraryController(target.settings);
      await controller.load();
      expect(controller.resolve('swing(who=partners)'), 'Swing your partner.');
    },
  );

  test(
    'restore replaces content and re-applies dialects, themes, settings',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      final json = await BackupService(source).exportToJson();

      // A fresh dataset with different, stale data to prove replace clears it.
      final target = openTestRepositories();
      await target.dances.create(_dance('stale', 'Should Be Gone'));
      await target.settings.set(kSortIgnoreArticlesKey, true);

      final outcome = await BackupService(target).restoreFromJson(json);
      expect(outcome.hasErrors, isFalse);

      // Content replaced.
      final dances = await target.dances.listAll();
      expect(dances.map((d) => d.id), ['d1']);

      // App-local pieces re-applied — verify via the real controllers.
      final dialects = DialectLibraryController(target.settings);
      await dialects.load();
      expect(dialects.customDialects.single.name, 'My Dialect');
      expect(dialects.activeName, 'My Dialect');

      final themes = CustomThemesController(target.settings);
      await themes.load();
      expect(themes.themes.single.id, 'custom-1');
      expect(themes.activeId, 'custom-1');

      expect(await target.settings.get(kSortIgnoreArticlesKey), false);
      // Device-local key was neither backed up nor restored.
      expect(await target.settings.get(kWindowFrameKey), isNull);
    },
  );

  test(
    'restore drops invalid settings values, keeps valid ones, and never throws '
    '(issue #609)',
    () async {
      // A backup carrying schema-invalid preference values: a non-string theme,
      // an out-of-range retention day count, and a non-numeric perform scale.
      // These simulate a corrupt / hand-edited / hostile-but-checksum-valid
      // backup. A valid preference rides alongside to prove the good keys still
      // restore.
      final source = openTestRepositories();
      await _seed(source);
      await source.settings.set(kAppThemeKey, 123); // wrong type (want String)
      await source.settings.set(kSoftDeleteRetentionKey, -5); // out of range
      await source.settings.set(kPerformTextScaleKey, 'huge'); // wrong type
      final json = await BackupService(source).exportToJson();

      // Target pre-seeded with stale valid values to prove the bad keys are
      // cleared (fall back to default) rather than left with old data.
      final target = openTestRepositories();
      await target.settings.set(kAppThemeKey, 'dark');
      await target.settings.set(kSoftDeleteRetentionKey, 90);
      await target.settings.set(kPerformTextScaleKey, 2.0);

      final outcome = await BackupService(target).restoreFromJson(json);

      // Restore still succeeds — a corrupt value degrades gracefully, it does
      // not fail the whole restore or throw.
      expect(outcome.applied, isTrue);
      expect(outcome.hasErrors, isFalse);

      // Each invalid key is dropped so its live reader falls back to default.
      expect(await target.settings.get(kAppThemeKey), isNull);
      expect(await target.settings.get(kSoftDeleteRetentionKey), isNull);
      expect(await target.settings.get(kPerformTextScaleKey), isNull);

      // The valid key restored correctly.
      expect(await target.settings.get(kSortIgnoreArticlesKey), false);

      // A non-fatal warning surfaced for each skipped key.
      expect(outcome.warnings.length, greaterThanOrEqualTo(3));
      expect(
        outcome.warnings.where((w) => w.contains(kAppThemeKey)),
        isNotEmpty,
      );
    },
  );

  test(
    'restore preserves a fully valid settings blob unchanged (issue #609)',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      await source.settings.set(kAppThemeKey, 'dark');
      await source.settings.set(kSoftDeleteRetentionKey, 90);
      await source.settings.set(kPerformTextScaleKey, 2.0);
      final json = await BackupService(source).exportToJson();

      final target = openTestRepositories();
      final outcome = await BackupService(target).restoreFromJson(json);

      expect(outcome.applied, isTrue);
      expect(outcome.hasErrors, isFalse);
      // No settings were skipped, so no per-key warnings were raised.
      expect(outcome.warnings, isEmpty);

      // Every valid value round-trips verbatim.
      expect(await target.settings.get(kAppThemeKey), 'dark');
      expect(await target.settings.get(kSoftDeleteRetentionKey), 90);
      expect(await target.settings.get(kPerformTextScaleKey), 2.0);
      expect(await target.settings.get(kSortIgnoreArticlesKey), false);
    },
  );

  test(
    'editor draft keys never travel in a backup and survive a restore',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      // A transient, device-local editor draft on the source device.
      await source.settings.set('editor_draft:new', '{"title":"WIP"}');

      final doc = await BackupService(source).buildDocument();
      // Excluded from export — drafts are neither content nor preferences.
      expect(doc.settings.containsKey('editor_draft:new'), isFalse);

      final json = await BackupService(source).exportToJson();

      final target = openTestRepositories();
      // The target device has its own in-progress draft.
      await target.settings.set('editor_draft:d9', '{"title":"local"}');

      await BackupService(target).restoreFromJson(json);

      // Device-local draft is left untouched by the restore's settings replace.
      expect(await target.settings.get('editor_draft:d9'), '{"title":"local"}');
      // And the source's draft was never written onto the target.
      expect(await target.settings.get('editor_draft:new'), isNull);
    },
  );

  test('program editor draft keys are excluded from backups', () async {
    // The program editor's draft prefix (issue #436) is device-local and
    // transient, same rationale as the dance editor's — it must never travel.
    expect(isBackupEligibleSettingKey('program_editor_draft:new'), isFalse);
    expect(isBackupEligibleSettingKey('program_editor_draft:abc123'), isFalse);

    final source = openTestRepositories();
    await _seed(source);
    await source.settings.set('program_editor_draft:new', '{"title":"WIP"}');

    final doc = await BackupService(source).buildDocument();
    expect(doc.settings.containsKey('program_editor_draft:new'), isFalse);

    final json = await BackupService(source).exportToJson();
    final target = openTestRepositories();
    await target.settings.set('program_editor_draft:p9', '{"title":"local"}');
    await BackupService(target).restoreFromJson(json);

    // The target's own draft survives; the source's draft never lands on it.
    expect(
      await target.settings.get('program_editor_draft:p9'),
      '{"title":"local"}',
    );
    expect(await target.settings.get('program_editor_draft:new'), isNull);
  });

  test(
    'restore removes stale non-denylisted settings absent from the backup',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      final json = await BackupService(source).exportToJson();

      final target = openTestRepositories();
      // A real preference the target turned on that the backup does not carry.
      await target.settings.set(kReduceMotionKey, true);
      // A stale preference key that is NOT present in the backup.
      await target.settings.set('some_stale_pref', 'old-value');

      await BackupService(target).restoreFromJson(json);

      // Replace semantics: keys absent from the backup are cleared, so undoing
      // changes by restoring an older backup doesn't leave stale prefs behind.
      expect(await target.settings.get(kReduceMotionKey), isNull);
      expect(await target.settings.get('some_stale_pref'), isNull);
      // A backed-up preference is present.
      expect(await target.settings.get(kSortIgnoreArticlesKey), false);
    },
  );

  test('recordBackup stamps the last-backup timestamp', () async {
    final repos = openTestRepositories();
    final at = DateTime.utc(2026, 7, 15, 9, 30);

    await BackupService(repos).recordBackup(at);

    expect(
      lastBackupAtFromStored(await repos.settings.get(kLastBackupAtKey)),
      at,
    );
  });

  test(
    'restoring malformed JSON reports errors without touching live data',
    () async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('live', 'Live Dance'));

      final outcome = await BackupService(repos).restoreFromJson('garbage {');

      expect(outcome.hasErrors, isTrue);
      expect(outcome.applied, isFalse);
      // Live content is untouched — a corrupt file must never wipe data.
      final dances = await repos.dances.listAll();
      expect(dances.map((d) => d.id), ['live']);
    },
  );

  test(
    'restoring a backup with no core aborts without wiping live data',
    () async {
      final repos = openTestRepositories();
      await repos.dances.create(_dance('live', 'Live Dance'));

      // Well-formed JSON, but no `core` section — must be treated as fatal.
      final outcome = await BackupService(
        repos,
      ).restoreFromJson('{"backupVersion":1,"app":{"settings":{}}}');

      expect(outcome.applied, isFalse);
      expect(outcome.hasErrors, isTrue);
      final dances = await repos.dances.listAll();
      expect(dances.map((d) => d.id), ['live']);
    },
  );

  test('restore aborts and preserves live data when the core archive has a '
      'decode error', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('live', 'Live Dance'));

    // A well-formed envelope, but a core dance is missing its required
    // `title` — a per-entity decode ERROR (not a forward-compat warning). A
    // replace restore must refuse rather than wipe live data to apply an
    // archive that did not fully decode (issue #430).
    const json =
        '{"backupVersion":1,"createdAt":"2026-07-15T00:00:00.000Z",'
        '"core":{"dances":[{"id":"d1"}]},"app":{}}';

    final outcome = await BackupService(repos).restoreFromJson(json);

    expect(outcome.applied, isFalse);
    expect(outcome.hasErrors, isTrue);
    // Live content is untouched — a partially-decodable backup never wipes it.
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['live']);
  });

  test('REPLACE refuses a forward-compat-incomplete core and preserves live '
      'data (does not wipe or partially apply) (#430)', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Stale Dance'));

    // Two core dances: one valid, one carrying an unknown `status` written by a
    // hypothetical newer app version. The unknown-enum dance is DROPPED at
    // decode, so the archive is incomplete. A destructive replace must refuse
    // rather than wipe the live collection to apply a lossy copy (#430).
    const json =
        '{"backupVersion":1,"createdAt":"2026-07-15T00:00:00.000Z",'
        '"core":{"dances":['
        '{"id":"good","title":"Good","createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"},'
        '{"id":"newer","title":"Newer","status":"from_the_future",'
        '"createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"}'
        ']},"app":{}}';

    final outcome = await BackupService(repos).restoreFromJson(json);

    expect(outcome.applied, isFalse);
    expect(outcome.incompleteCore, isTrue);
    // Live data is untouched — the stale dance survives, the archive's `good`
    // dance never landed.
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['stale']);
  });

  test('REPLACE refuses even when EVERY entity is dropped (would decode to an '
      'empty archive) and leaves live data intact (#430)', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('keep-me', 'Keep Me'));

    // Every dance carries a future enum value, so decoding yields ZERO dances.
    // Without the incomplete-core guard this would sail through the
    // coreHasErrors check and replace would clear the live collection and
    // commit an empty archive — the exact silent wipe #430 must prevent.
    const json =
        '{"backupVersion":1,"createdAt":"2026-07-15T00:00:00.000Z",'
        '"core":{"dances":['
        '{"id":"a","title":"A","status":"from_the_future",'
        '"createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"},'
        '{"id":"b","title":"B","status":"from_the_future",'
        '"createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"}'
        ']},"app":{}}';

    final outcome = await BackupService(repos).restoreFromJson(json);

    expect(outcome.applied, isFalse);
    expect(outcome.incompleteCore, isTrue);
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['keep-me']);
  });

  test('MERGE stays tolerant of a forward-compat drop: keeps survivors and '
      'existing data (drops only the unreadable entity)', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('stale', 'Stale Dance'));

    const json =
        '{"backupVersion":1,"createdAt":"2026-07-15T00:00:00.000Z",'
        '"core":{"dances":['
        '{"id":"good","title":"Good","createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"},'
        '{"id":"newer","title":"Newer","status":"from_the_future",'
        '"createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"}'
        ']},"app":{}}';

    final outcome = await BackupService(
      repos,
    ).restoreFromJson(json, mode: RestoreMode.merge);

    // Merge is additive and tolerant: it applies, keeping the existing `stale`
    // dance and adding the readable `good` one, dropping only `newer`.
    expect(outcome.applied, isTrue);
    expect(outcome.warnings, isNotEmpty);
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id).toSet(), {'stale', 'good'});
  });

  test('REPLACE that fails to write rolls back AND does not mutate app '
      'settings or report success (#430, comment 2)', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('live', 'Live Dance'));
    // A backup-eligible preference the restore must NOT touch if the core
    // restore rolls back.
    await repos.settings.set(kSortIgnoreArticlesKey, false);

    // Core decodes cleanly (no decode error, no dropped enum) so it passes the
    // pre-flight guard and the restore is attempted — but the dance's duplicate
    // authorIds violate the dance_authors primary key, so the write fails and
    // the all-or-nothing replace rolls the whole transaction back. The backup
    // also carries a DIFFERENT value for the preference; because the core
    // restore rolled back, app settings must be left untouched and the outcome
    // must report applied:false.
    const json =
        '{"backupVersion":1,"createdAt":"2026-07-15T00:00:00.000Z",'
        '"core":{"choreographers":[{"id":"c1","name":"Alice"}],'
        '"dances":[{"id":"d1","title":"Dupe","authorIds":["c1","c1"],'
        '"createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"}]},'
        '"app":{"settings":{"$kSortIgnoreArticlesKey":true}}}';

    final outcome = await BackupService(repos).restoreFromJson(json);

    expect(outcome.applied, isFalse);
    expect(outcome.hasErrors, isTrue);
    // Core rolled back: the live dance is intact and the archive's dance never
    // landed.
    final dances = await repos.dances.listAll();
    expect(dances.map((d) => d.id), ['live']);
    // App settings were NOT mutated — the preference keeps its live value.
    expect(await repos.settings.get(kSortIgnoreArticlesKey), false);
  });

  test(
    'settings-apply failure after the core commit keeps the restored core and '
    'reports a retryable settingsFailed instead of throwing (#608)',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      final json = await BackupService(source).exportToJson();

      final target = openTestRepositoriesWithFailingSettings();
      // Stale core data to prove the core replace actually committed.
      await target.repos.dances.create(_dance('stale', 'Should Be Gone'));

      // The settings store throws during _applyAppSettings, AFTER the core has
      // already committed. This must NOT propagate as a total failure.
      final outcome = await BackupService(target.repos).restoreFromJson(json);

      // Core content committed and is kept (no rollback); the outcome reports a
      // retryable settings failure — not a crash, not a silent success.
      expect(outcome.applied, isTrue);
      expect(outcome.settingsFailed, isTrue);
      final dances = await target.repos.dances.listAll();
      expect(dances.map((d) => d.id), ['d1']);
    },
  );

  test('retryApplySettings re-applies settings successfully once the store '
      'recovers, leaving the core intact (#608)', () async {
    final source = openTestRepositories();
    await _seed(source);
    final json = await BackupService(source).exportToJson();

    final target = openTestRepositoriesWithFailingSettings();
    final failed = await BackupService(target.repos).restoreFromJson(json);
    expect(failed.settingsFailed, isTrue);

    // The store recovers; retry re-applies ONLY the settings.
    target.settings.failWrites = false;
    final retried = await BackupService(target.repos).retryApplySettings(json);

    expect(retried.applied, isTrue);
    expect(retried.settingsFailed, isFalse);

    // Settings are now applied — verify via the real controllers + a pref.
    final dialects = DialectLibraryController(target.repos.settings);
    await dialects.load();
    expect(dialects.customDialects.single.name, 'My Dialect');
    expect(dialects.activeName, 'My Dialect');
    expect(await target.repos.settings.get(kSortIgnoreArticlesKey), false);

    // Core was never touched by the retry — the restored dance remains.
    final dances = await target.repos.dances.listAll();
    expect(dances.map((d) => d.id), ['d1']);
  });

  test('retryApplySettings is idempotent — running it twice converges to the '
      'same state (#608)', () async {
    final source = openTestRepositories();
    await _seed(source);
    final json = await BackupService(source).exportToJson();

    final target = openTestRepositoriesWithFailingSettings();
    await BackupService(target.repos).restoreFromJson(json);
    target.settings.failWrites = false;

    final first = await BackupService(target.repos).retryApplySettings(json);
    final second = await BackupService(target.repos).retryApplySettings(json);

    expect(first.settingsFailed, isFalse);
    expect(second.settingsFailed, isFalse);

    // No duplication or drift from the second apply.
    final dialects = DialectLibraryController(target.repos.settings);
    await dialects.load();
    expect(dialects.customDialects.length, 1);
    expect(dialects.customDialects.single.name, 'My Dialect');
    final themes = CustomThemesController(target.repos.settings);
    await themes.load();
    expect(themes.themes.single.id, 'custom-1');
    expect(await target.repos.settings.get(kSortIgnoreArticlesKey), false);
  });

  test(
    'a fully successful restore reports settingsFailed:false (#608)',
    () async {
      final source = openTestRepositories();
      await _seed(source);
      final json = await BackupService(source).exportToJson();

      final target = openTestRepositories();
      final outcome = await BackupService(target).restoreFromJson(json);

      expect(outcome.applied, isTrue);
      expect(outcome.settingsFailed, isFalse);
    },
  );

  test('a pre-core-commit refusal reports settingsFailed:false and applies '
      'nothing (#608)', () async {
    final repos = openTestRepositories();
    await repos.dances.create(_dance('live', 'Live Dance'));
    await repos.settings.set(kSortIgnoreArticlesKey, true);

    final outcome = await BackupService(repos).restoreFromJson('garbage {');

    expect(outcome.applied, isFalse);
    expect(outcome.settingsFailed, isFalse);
    // Nothing touched: live core and settings are unchanged.
    expect((await repos.dances.listAll()).map((d) => d.id), ['live']);
    expect(await repos.settings.get(kSortIgnoreArticlesKey), true);
  });

  test('retryApplySettings refuses a fatal envelope without touching settings '
      '(#608)', () async {
    final repos = openTestRepositories();
    await repos.settings.set(kSortIgnoreArticlesKey, true);

    final outcome = await BackupService(repos).retryApplySettings('garbage {');

    expect(outcome.applied, isFalse);
    expect(outcome.settingsFailed, isFalse);
    // The existing live preference is left untouched.
    expect(await repos.settings.get(kSortIgnoreArticlesKey), true);
  });

  test(
    'retryApplySettings reports integrityFailed (applied:false, not a success) '
    'for a tampered backup and applies nothing (#608)',
    () async {
      final source = openTestRepositories();
      await source.dances.create(_dance('d1', 'Restored Dance'));
      final json = await BackupService(source).exportToJson();

      // Alter the payload without recomputing the checksum — the exact
      // tamper/corruption the SHA-256 guard (#536) catches. This locks the
      // defensive retry branch the UI maps to an integrity error rather than a
      // false "Settings applied." (#644 review).
      final envelope = jsonDecode(json) as Map<String, Object?>;
      envelope['payload'] = (envelope['payload'] as String).replaceFirst(
        'Restored Dance',
        'Tampered Dance',
      );
      final tampered = jsonEncode(envelope);

      final repos = openTestRepositories();
      await repos.settings.set(kSortIgnoreArticlesKey, true);

      final outcome = await BackupService(repos).retryApplySettings(tampered);

      // Nothing applied, and this is NOT a settings-failure retry state — it's a
      // clean integrity refusal the UI reports as an error, never a success.
      expect(outcome.applied, isFalse);
      expect(outcome.settingsFailed, isFalse);
      expect(outcome.integrityFailed, isTrue);
      expect(await repos.settings.get(kSortIgnoreArticlesKey), true);
    },
  );
}
