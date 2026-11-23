import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A program's times (#2350) are stamped by the core archive version
/// ([archiveSchemaVersionProgramTimes]), which the backup's `core` section
/// carries. Builds up to 0.10.0 read core archives up to v7 and flag a newer
/// one as newer than they support, so they refuse to replace-restore a backup
/// holding times instead of dropping them.
void main() {
  final created = DateTime.utc(2026, 10, 1);

  Program program({int? arrivalMinute}) => Program(
    id: 'p1',
    title: 'Saturday',
    arrivalMinute: arrivalMinute,
    createdAt: created,
    updatedAt: created,
  );

  Map<String, Object?> core(Program p) =>
      backupToJson(
            BackupDocument(
              createdAt: created,
              core: CompendiumArchive(exportedAt: created, programs: [p]),
            ),
          )['core']!
          as Map<String, Object?>;

  test('a backup with a time stamps its core archive v8', () {
    expect(
      core(program(arrivalMinute: 1110))['schemaVersion'],
      archiveSchemaVersionProgramTimes,
    );
  });

  test('a backup without times keeps the lower stamp', () {
    expect(
      core(program())['schemaVersion'] as int,
      lessThan(archiveSchemaVersionProgramTimes),
    );
  });

  test('times round-trip through a backup', () {
    final decoded = decodeBackup(
      encodeBackupPayload(
        BackupDocument(
          createdAt: created,
          core: CompendiumArchive(
            exportedAt: created,
            programs: [
              program(
                arrivalMinute: 1110,
              ).copyWith(startMinute: 1170, endMinute: 60, lessonMinute: 1140),
            ],
          ),
        ),
      ),
    );
    final p = decoded.document!.core.programs.single;
    expect(p.startMinute, 1170);
    expect(p.endMinute, 60);
    expect(p.lessonMinute, 1140);
    expect(p.arrivalMinute, 1110);
  });
}
