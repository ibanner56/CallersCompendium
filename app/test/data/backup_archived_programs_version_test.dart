import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// An archived program raises the backup envelope to v3
/// ([backupSchemaVersionArchivedPrograms]), so builds up to 0.10.0, which do
/// not read `archivedAt`, refuse to replace-restore such a backup instead of
/// bringing every archived program back into the Programs list.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime.utc(2026, 10, 1);
  final archivedAt = DateTime.utc(2026, 10, 2, 9);

  Program program({
    String id = 'p1',
    DateTime? archivedAt,
    DateTime? deletedAt,
    int? payMinorUnits,
    String? payCurrency,
  }) => Program(
    id: id,
    title: 'Saturday',
    archivedAt: archivedAt,
    deletedAt: deletedAt,
    payMinorUnits: payMinorUnits,
    payCurrency: payCurrency,
    createdAt: created,
    updatedAt: created,
  );

  BackupDocument doc(
    List<Program> programs, {
    List<FigureNote> figureNotes = const [],
  }) => BackupDocument(
    createdAt: created,
    core: CompendiumArchive(exportedAt: created, programs: programs),
    figureNotes: figureNotes,
  );

  group('requiredBackupVersion', () {
    test('an archived program raises the envelope to v3', () {
      expect(
        requiredBackupVersion(
          doc([program(), program(id: 'p2', archivedAt: archivedAt)]),
        ),
        backupSchemaVersionArchivedPrograms,
      );
      expect(backupSchemaVersionArchivedPrograms, 3);
    });

    test('v3 wins over pay and the glossary', () {
      final d = doc(
        [
          program(archivedAt: archivedAt),
          program(id: 'p2', payMinorUnits: 100, payCurrency: 'USD'),
        ],
        figureNotes: [FigureNote(figureId: 'swing', notes: 'n')],
      );
      expect(requiredBackupVersion(d), backupSchemaVersionArchivedPrograms);
    });

    test('an archived program in the Trash counts: the backup carries it', () {
      expect(
        requiredBackupVersion(
          doc([program(archivedAt: archivedAt, deletedAt: created)]),
        ),
        backupSchemaVersionArchivedPrograms,
      );
    });

    test('no archived program leaves the version where it was', () {
      expect(requiredBackupVersion(doc([program()])), backupSchemaVersionBase);
    });

    test('v3 is the newest envelope this build reads', () {
      expect(backupSchemaVersion, backupSchemaVersionArchivedPrograms);
    });
  });

  group('an exported backup', () {
    test('of a library with an archived program is written v3 and '
        'replace-restores it archived', () async {
      final source = openTestRepositories();
      await source.programs.create(program());
      await source.programs.archive('p1', at: archivedAt);
      final json = await BackupService(source).exportToJson();
      final container = jsonDecode(json) as Map<String, Object?>;
      final payload =
          jsonDecode(container['payload']! as String) as Map<String, Object?>;
      expect(payload['backupVersion'], backupSchemaVersionArchivedPrograms);

      final target = openTestRepositories();
      final outcome = await BackupService(target).restoreFromJson(json);
      expect(outcome.applied, isTrue);
      final restored = (await target.programs.getById('p1'))!;
      expect(restored.archivedAt, archivedAt);
    });

    test(
      'a backup claiming a newer envelope than v3 is still flagged newer',
      () {
        final decoded = decodeBackup(
          '{"backupVersion": ${backupSchemaVersionArchivedPrograms + 1}, '
          '"core": {}, "app": {}}',
        );
        expect(decoded.newerSchema, isTrue);
        final current = decodeBackup(
          '{"backupVersion": $backupSchemaVersionArchivedPrograms, '
          '"core": {}, "app": {}}',
        );
        expect(current.newerSchema, isFalse);
      },
    );
  });
}
