import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/backup_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

/// A program's pay and Perform dialect raise the backup envelope to v2
/// ([backupSchemaVersionProgramPay]), so 0.5.2 to 0.5.4, which read neither,
/// refuse such a backup instead of restoring it without them.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  final created = DateTime.utc(2026, 10, 1);

  Program program({
    String id = 'p1',
    String? dialectName,
    int? payMinorUnits,
    String? payCurrency,
    DateTime? deletedAt,
  }) => Program(
    id: id,
    title: 'Saturday',
    dialectName: dialectName,
    payMinorUnits: payMinorUnits,
    payCurrency: payCurrency,
    createdAt: created,
    updatedAt: created,
    deletedAt: deletedAt,
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
    test('a backup whose programs have no pay and no dialect stays v1', () {
      expect(requiredBackupVersion(doc([program()])), backupSchemaVersionBase);
      expect(requiredBackupVersion(doc(const [])), backupSchemaVersionBase);
    });

    test('pay raises the envelope to v2', () {
      final d = doc([
        program(),
        program(id: 'p2', payMinorUnits: 25000, payCurrency: 'USD'),
      ]);
      expect(requiredBackupVersion(d), backupSchemaVersionProgramPay);
    });

    test('a Perform dialect raises the envelope to v2', () {
      expect(
        requiredBackupVersion(doc([program(dialectName: 'Larks/Ravens')])),
        backupSchemaVersionProgramPay,
      );
    });

    test('a program in the Trash counts: the backup carries it too', () {
      final d = doc([
        program(payMinorUnits: 100, payCurrency: 'USD', deletedAt: created),
      ]);
      expect(requiredBackupVersion(d), backupSchemaVersionProgramPay);
    });

    test('glossary data and pay together stamp v2', () {
      final d = doc(
        [program(payMinorUnits: 100, payCurrency: 'USD')],
        figureNotes: [FigureNote(figureId: 'swing', notes: 'n')],
      );
      expect(requiredBackupVersion(d), backupSchemaVersionGlossary);
    });

    test('v2 is the newest envelope this build reads, so a backup it writes '
        'for pay is one it, and 0.8.0 and later, restore', () {
      expect(backupSchemaVersionProgramPay, backupSchemaVersion);
      expect(backupSchemaVersionProgramPay, backupSchemaVersionGlossary);
    });
  });

  group('an exported backup', () {
    test('of a library with pay is written v2 and replace-restores with its '
        'pay and dialect', () async {
      final source = openTestRepositories();
      await source.programs.create(
        program(
          dialectName: 'Larks/Ravens',
          payMinorUnits: 25000,
          payCurrency: 'USD',
        ),
      );
      final json = await BackupService(source).exportToJson();
      final container = jsonDecode(json) as Map<String, Object?>;
      final payload =
          jsonDecode(container['payload']! as String) as Map<String, Object?>;
      expect(payload['backupVersion'], backupSchemaVersionProgramPay);

      final target = openTestRepositories();
      final outcome = await BackupService(target).restoreFromJson(json);
      expect(outcome.applied, isTrue);
      final restored = (await target.programs.getById('p1'))!;
      expect(restored.payMinorUnits, 25000);
      expect(restored.payCurrency, 'USD');
      expect(restored.dialectName, 'Larks/Ravens');
    });

    test('of a library without pay or dialect is still written v1', () async {
      final repos = openTestRepositories();
      await repos.programs.create(program());
      final json = backupToJson(await BackupService(repos).buildDocument());
      expect(json['backupVersion'], backupSchemaVersionBase);
    });
  });
}
