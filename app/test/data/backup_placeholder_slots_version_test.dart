import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// A placeholder slot's saved-search reference (#2338) raises the backup
/// envelope to v3 ([backupSchemaVersionPlaceholderSlots]), so a build that
/// reads no such field refuses the backup instead of restoring the slot as a
/// plain note.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime.utc(2026, 10, 1);

  Program program({String? placeholderSearchId}) => Program(
    id: 'p1',
    title: 'Family night',
    slots: [
      ProgramSlot(
        id: 's1',
        position: 0,
        text: 'Easy family opener',
        placeholderSearchId: placeholderSearchId,
      ),
    ],
    createdAt: created,
    updatedAt: created,
  );

  BackupDocument doc(List<Program> programs) => BackupDocument(
    createdAt: created,
    core: CompendiumArchive(exportedAt: created, programs: programs),
  );

  test('a program without a placeholder stays v1', () {
    expect(requiredBackupVersion(doc([program()])), backupSchemaVersionBase);
  });

  test('a placeholder raises the envelope to v3, one this build restores', () {
    expect(
      requiredBackupVersion(doc([program(placeholderSearchId: 'search-1')])),
      backupSchemaVersionPlaceholderSlots,
    );
    expect(backupSchemaVersionPlaceholderSlots, 3);
    expect(
      backupSchemaVersionPlaceholderSlots,
      lessThanOrEqualTo(backupSchemaVersion),
    );
  });

  test('an exported backup keeps the placeholder through a restore', () async {
    final source = openTestRepositories();
    await source.programs.create(program(placeholderSearchId: 'search-1'));
    final json = await BackupService(source).exportToJson();
    final container = jsonDecode(json) as Map<String, Object?>;
    final payload =
        jsonDecode(container['payload']! as String) as Map<String, Object?>;
    expect(payload['backupVersion'], backupSchemaVersionPlaceholderSlots);

    final target = openTestRepositories();
    final outcome = await BackupService(target).restoreFromJson(json);
    expect(outcome.applied, isTrue);
    final slot = (await target.programs.getById('p1'))!.slots.single;
    expect(slot.text, 'Easy family opener');
    expect(slot.placeholderSearchId, 'search-1');
  });
}
