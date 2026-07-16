import 'package:compendium_app/src/data/backup_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('backupReminderCadenceFromStored', () {
    test('recognizes each token', () {
      expect(backupReminderCadenceFromStored('off'), BackupReminderCadence.off);
      expect(
        backupReminderCadenceFromStored('weekly'),
        BackupReminderCadence.weekly,
      );
      expect(
        backupReminderCadenceFromStored('monthly'),
        BackupReminderCadence.monthly,
      );
    });

    test('falls back to off for null / garbage', () {
      expect(backupReminderCadenceFromStored(null), BackupReminderCadence.off);
      expect(backupReminderCadenceFromStored(42), BackupReminderCadence.off);
      expect(
        backupReminderCadenceFromStored('weekLY'),
        BackupReminderCadence.off,
      );
    });
  });

  group('lastBackupAtFromStored', () {
    test('parses an ISO string to UTC', () {
      final at = lastBackupAtFromStored('2026-07-15T00:00:00.000Z');
      expect(at, DateTime.utc(2026, 7, 15));
      expect(at!.isUtc, isTrue);
    });

    test('returns null for unset / unparseable', () {
      expect(lastBackupAtFromStored(null), isNull);
      expect(lastBackupAtFromStored('not-a-date'), isNull);
      expect(lastBackupAtFromStored(123), isNull);
    });
  });

  group('isBackupOverdue', () {
    final now = DateTime.utc(2026, 7, 15);

    test('off is never overdue, even with no backup', () {
      expect(
        isBackupOverdue(
          cadence: BackupReminderCadence.off,
          lastBackupAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('on with no backup ever is overdue', () {
      expect(
        isBackupOverdue(
          cadence: BackupReminderCadence.weekly,
          lastBackupAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('weekly: overdue only after more than 7 days', () {
      expect(
        isBackupOverdue(
          cadence: BackupReminderCadence.weekly,
          lastBackupAt: now.subtract(const Duration(days: 5)),
          now: now,
        ),
        isFalse,
      );
      expect(
        isBackupOverdue(
          cadence: BackupReminderCadence.weekly,
          lastBackupAt: now.subtract(const Duration(days: 8)),
          now: now,
        ),
        isTrue,
      );
    });

    test('monthly: overdue only after more than 30 days', () {
      expect(
        isBackupOverdue(
          cadence: BackupReminderCadence.monthly,
          lastBackupAt: now.subtract(const Duration(days: 20)),
          now: now,
        ),
        isFalse,
      );
      expect(
        isBackupOverdue(
          cadence: BackupReminderCadence.monthly,
          lastBackupAt: now.subtract(const Duration(days: 31)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
