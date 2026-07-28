import 'dart:convert';

import 'package:compendium_app/src/data/backup_document.dart';
import 'package:compendium_app/src/data/custom_theme.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

BackupDocument _sampleDoc() => BackupDocument(
  createdAt: DateTime.utc(2026, 7, 15, 12),
  core: CompendiumArchive(
    exportedAt: DateTime.utc(2026, 7, 15, 12),
    dances: [
      Dance(
        id: 'd1',
        title: 'Full Dance',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
      Dance(
        id: 'd2',
        title: 'Another',
        createdAt: DateTime.utc(2026, 1, 3),
        updatedAt: DateTime.utc(2026, 1, 3),
      ),
    ],
  ),
  customDialects: [Dialect(name: 'My Dialect')],
  activeDialectRef: 'My Dialect',
  customThemes: [
    const CustomTheme(
      id: 'custom-1',
      name: 'Sunset',
      brightness: Brightness.dark,
      roles: {'primary': 0xFF112233},
    ),
  ],
  activeCustomThemeId: 'custom-1',
  settings: {
    'sort_ignore_articles': true,
    'soft_delete_retention_days': 90,
    'date_format': 'ymd',
  },
);

void main() {
  test('backup document round-trips deterministically', () {
    final doc = _sampleDoc();
    final json = encodeBackup(doc);
    final decoded = decodeBackup(json);

    expect(decoded.hasErrors, isFalse);
    expect(decoded.warnings, isEmpty);
    // Re-encoding the decoded document reproduces the exact JSON (identity).
    expect(encodeBackup(decoded.document), json);
  });

  test('decoded document carries every app-local piece', () {
    final decoded = decodeBackup(encodeBackup(_sampleDoc())).document;

    expect(decoded.core.dances.map((d) => d.id), ['d1', 'd2']);
    expect(decoded.customDialects.single.name, 'My Dialect');
    expect(decoded.activeDialectRef, 'My Dialect');
    expect(decoded.customThemes.single.id, 'custom-1');
    expect(decoded.customThemes.single.brightness, Brightness.dark);
    expect(decoded.activeCustomThemeId, 'custom-1');
    expect(decoded.settings['soft_delete_retention_days'], 90);
    expect(decoded.settings['date_format'], 'ymd');
  });

  test('invalid JSON yields a structured error and an empty document', () {
    final decoded = decodeBackup('not json {');
    expect(decoded.hasErrors, isTrue);
    expect(decoded.fatal, isTrue);
    expect(decoded.errors.single.entityType, 'backup');
    expect(decoded.document.core.dances, isEmpty);
    expect(decoded.document.customDialects, isEmpty);
  });

  test('a backup missing its core section is fatal', () {
    final decoded = decodeBackup(
      '{"backupVersion": 1, "app": {"settings": {}}}',
    );
    expect(decoded.fatal, isTrue);
    expect(decoded.errors.any((e) => e.entityType == 'backup'), isTrue);
  });

  test('a non-object core section is fatal', () {
    final decoded = decodeBackup('{"backupVersion": 1, "core": 5}');
    expect(decoded.fatal, isTrue);
  });

  test('a newer backupVersion is read best-effort with a warning', () {
    final decoded = decodeBackup(
      '{"backupVersion": 999, "createdAt": "2026-07-15T00:00:00.000Z", '
      '"core": {}, "app": {}}',
    );
    expect(decoded.hasErrors, isFalse);
    expect(decoded.warnings, isNotEmpty);
    expect(decoded.document.schemaVersion, 999);
  });

  test(
    'a malformed custom-theme entry is skipped and recorded, rest loads',
    () {
      final decoded = decodeBackup(
        '{"backupVersion": 1, "createdAt": "2026-07-15T00:00:00.000Z", '
        '"core": {}, "app": {"themes": {"custom": ['
        '{"id": "ok", "name": "Ok", "brightness": "light", "roles": {}},'
        '{"id": "bad"}'
        ']}}}',
      );
      // The good theme still loads; the malformed one is recorded as an error.
      expect(decoded.document.customThemes.single.id, 'ok');
      expect(decoded.errors.any((e) => e.entityType == 'theme'), isTrue);
      // A per-entity problem is NOT fatal — the rest of the backup is usable.
      expect(decoded.fatal, isFalse);
    },
  );

  test('unknown top-level and app keys are ignored', () {
    final decoded = decodeBackup(
      '{"backupVersion": 1, "createdAt": "2026-07-15T00:00:00.000Z", '
      '"core": {}, "app": {"future": 1}, "extra": true}',
    );
    expect(decoded.hasErrors, isFalse);
    expect(decoded.document.settings, isEmpty);
  });

  group('integrity container (#536)', () {
    test('encodeBackup wraps the document in a SHA-256 checksum container', () {
      final envelope = jsonDecode(encodeBackup(_sampleDoc())) as Map;
      expect(envelope['backupContainer'], backupContainerVersion);
      final checksum = envelope['checksum'] as Map;
      expect(checksum['algorithm'], kBackupChecksumAlgorithm);
      expect(checksum['value'], isA<String>());
      expect((checksum['value'] as String), isNotEmpty);
      // The payload is the bare document JSON string (encodeBackupPayload).
      expect(envelope['payload'], isA<String>());
      expect(envelope['payload'], encodeBackupPayload(_sampleDoc()));
    });

    test('a container round-trips through decodeBackup', () {
      final decoded = decodeBackup(encodeBackup(_sampleDoc()));
      expect(decoded.fatal, isFalse);
      expect(decoded.hasErrors, isFalse);
      expect(decoded.integrityFailed, isFalse);
      expect(decoded.document.core.dances.map((d) => d.id), ['d1', 'd2']);
    });

    test('a tampered payload fails the integrity check (fatal, no data)', () {
      final envelope = jsonDecode(encodeBackup(_sampleDoc())) as Map;
      // Alter the payload without recomputing the checksum.
      envelope['payload'] = (envelope['payload'] as String).replaceFirst(
        'Full Dance',
        'Tampered Dance',
      );
      final decoded = decodeBackup(jsonEncode(envelope));

      expect(decoded.fatal, isTrue);
      expect(decoded.integrityFailed, isTrue);
      expect(decoded.document.core.dances, isEmpty);
    });

    test('a container missing its checksum is refused', () {
      final envelope = jsonDecode(encodeBackup(_sampleDoc())) as Map
        ..remove('checksum');
      final decoded = decodeBackup(jsonEncode(envelope));
      expect(decoded.fatal, isTrue);
      expect(decoded.integrityFailed, isTrue);
    });

    test('a container naming an unsupported algorithm is refused', () {
      final envelope = jsonDecode(encodeBackup(_sampleDoc())) as Map;
      (envelope['checksum'] as Map)['algorithm'] = 'md5';
      final decoded = decodeBackup(jsonEncode(envelope));
      expect(decoded.fatal, isTrue);
      expect(decoded.integrityFailed, isTrue);
    });

    test('a container missing its version is refused (not tamper)', () {
      final envelope = jsonDecode(encodeBackup(_sampleDoc())) as Map
        ..remove('backupContainer');
      final decoded = decodeBackup(jsonEncode(envelope));
      expect(decoded.fatal, isTrue);
      // A version problem is a format refusal, not a failed integrity check.
      expect(decoded.integrityFailed, isFalse);
      expect(decoded.document.core.dances, isEmpty);
    });

    test('a container from a newer version is refused cleanly', () {
      final envelope = jsonDecode(encodeBackup(_sampleDoc())) as Map;
      envelope['backupContainer'] = backupContainerVersion + 1;
      final decoded = decodeBackup(jsonEncode(envelope));
      expect(decoded.fatal, isTrue);
      expect(decoded.integrityFailed, isFalse);
      expect(decoded.document.core.dances, isEmpty);
    });

    test('a legacy bare document (no container) still decodes', () {
      // The payload string is exactly a pre-#536 plain `.json` backup.
      final bare = encodeBackupPayload(_sampleDoc());
      final decoded = decodeBackup(bare);
      expect(decoded.fatal, isFalse);
      expect(decoded.integrityFailed, isFalse);
      expect(decoded.document.core.dances.map((d) => d.id), ['d1', 'd2']);
    });
  });
}
