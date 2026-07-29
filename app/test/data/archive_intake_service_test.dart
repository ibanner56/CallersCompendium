import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_app/src/data/archive_intake_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

Dance _dance(String id, String title) => Dance(
  id: id,
  title: title,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// A valid share bundle: one program referencing one bundled dance.
String _validBundleJson({int schemaVersion = archiveSchemaVersion}) {
  final archive = CompendiumArchive(
    schemaVersion: schemaVersion,
    exportedAt: DateTime.utc(2026, 7, 15),
    dances: [_dance('d1', 'Simplicity Swing')],
    programs: [
      Program(
        id: 'p1',
        title: 'Spring Fling',
        slots: [ProgramSlot(id: 's1', position: 0, danceId: 'd1')],
        createdAt: DateTime.utc(2026, 4, 1),
        updatedAt: DateTime.utc(2026, 4, 1),
      ),
    ],
  );
  return encodeArchive(archive);
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  // The intake service is a **validation-only** gate (issue #432): it decodes
  // and safety-checks untrusted shared bundles Dart-side, but never writes —
  // the commit is deferred to the review/consent screen. So these tests assert
  // the validated/rejected outcome and the pre-computed entity count, and that
  // nothing ever throws.
  ArchiveIntakeService service({
    ArchiveByteReader? readBytes,
    int maxBytes = kMaxIncomingArchiveBytes,
  }) => ArchiveIntakeService(readBytes: readBytes, maxBytes: maxBytes);

  group('valid bundle', () {
    test('validates and returns the decoded archive + raw json', () async {
      final json = _validBundleJson();
      final result = await service().validateBytes(_bytes(json));

      expect(result.isValidated, isTrue);
      expect(result.isRejected, isFalse);
      expect(result.json, json);
      expect(result.archive, isNotNull);
      expect(result.archive!.programs.single.title, 'Spring Fling');
      expect(
        result.archive!.dances.map((d) => d.title),
        contains('Simplicity Swing'),
      );
    });

    test('reports the pre-render entity count from the decode', () async {
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: [_dance('d1', 'A'), _dance('d2', 'B')],
        choreographers: [Choreographer(id: 'c1', name: 'Cary')],
        programs: [
          Program(
            id: 'p1',
            title: 'Prog',
            slots: const [],
            createdAt: DateTime.utc(2026, 4, 1),
            updatedAt: DateTime.utc(2026, 4, 1),
          ),
        ],
        venues: [Venue(id: 'v1', name: 'Grange')],
      );
      final result = await service().validateBytes(
        _bytes(encodeArchive(archive)),
      );

      expect(result.isValidated, isTrue);
      // 2 dances + 1 choreographer + 1 program + 1 venue.
      expect(result.entityCount, 5);
    });

    test('reads from a path via the injected reader, then validates', () async {
      final json = _validBundleJson();
      final result = await service(
        readBytes: (path) async => _bytes(json),
      ).validateFromPath('/anywhere/bundle.json');

      expect(result.isValidated, isTrue);
      expect(result.archive, isNotNull);
    });

    test('a very large but well-formed archive validates without throwing and '
        'reports a large entity count', () async {
      // Untrusted, adversarial-shaped input: many entities. Validation must
      // stay bounded and never throw; the (large) count is what later drives
      // the soft-cap warning on the review screen.
      const n = 5000;
      final archive = CompendiumArchive(
        exportedAt: DateTime.utc(2026, 7, 15),
        dances: [for (var i = 0; i < n; i++) _dance('d$i', 'Contra No $i')],
      );
      final result = await service().validateBytes(
        _bytes(encodeArchive(archive)),
      );

      expect(result.isValidated, isTrue);
      expect(result.entityCount, n);
    });
  });

  group('rejected gracefully (never throws, decodes to nothing)', () {
    void expectRejected(
      ArchiveIntakeValidation result, {
      ArchiveIntakeRejectionReason? reason,
    }) {
      expect(result.isRejected, isTrue);
      expect(result.isValidated, isFalse);
      expect(result.reason, isNotNull);
      if (reason != null) expect(result.reason, reason);
      expect(result.archive, isNull);
      expect(result.json, isNull);
    }

    test('malformed (not JSON) is rejected', () async {
      expectRejected(
        await service().validateBytes(_bytes('this is not json')),
        reason: ArchiveIntakeRejectionReason.notArchive,
      );
    });

    test('non-UTF-8 bytes are rejected', () async {
      // A hostile/binary payload that is not valid UTF-8 (a lone 0xFF byte and
      // friends). The service must reject it gracefully, not throw.
      expectRejected(
        await service().validateBytes(
          Uint8List.fromList([0xFF, 0xFE, 0x00, 0x80, 0xC0]),
        ),
        reason: ArchiveIntakeRejectionReason.notArchive,
      );
    });

    test('a non-object JSON root is rejected', () async {
      expectRejected(
        await service().validateBytes(_bytes('[1, 2, 3]')),
        reason: ArchiveIntakeRejectionReason.notArchive,
      );
    });

    test('empty file is rejected', () async {
      expectRejected(
        await service().validateBytes(Uint8List(0)),
        reason: ArchiveIntakeRejectionReason.empty,
      );
    });

    test('a well-formed archive with no content is rejected', () async {
      final json = encodeArchive(
        CompendiumArchive(exportedAt: DateTime.utc(2026)),
      );
      expectRejected(
        await service().validateBytes(_bytes(json)),
        reason: ArchiveIntakeRejectionReason.noContent,
      );
    });

    test('oversized bytes are rejected', () async {
      // maxBytes tiny; the valid bundle exceeds it.
      expectRejected(
        await service(maxBytes: 8).validateBytes(_bytes(_validBundleJson())),
        reason: ArchiveIntakeRejectionReason.tooLarge,
      );
    });

    test('an oversized file is rejected without reading it fully', () async {
      var readCalled = false;
      final result = await service(
        maxBytes: 8,
        // The default file reader would throw OversizedArchiveException; here we
        // assert the service surfaces that as a graceful rejection.
        readBytes: (path) async {
          readCalled = true;
          throw const OversizedArchiveException(999999);
        },
      ).validateFromPath('/anywhere/huge.json');

      expect(readCalled, isTrue);
      expectRejected(result, reason: ArchiveIntakeRejectionReason.tooLarge);
    });

    test('a newer-schema archive is refused with a clear reason', () async {
      final json = _validBundleJson(schemaVersion: archiveSchemaVersion + 1);
      final result = await service().validateBytes(_bytes(json));

      expectRejected(result, reason: ArchiveIntakeRejectionReason.newerVersion);
    });

    test('an unreadable file path is rejected gracefully', () async {
      expectRejected(
        await service(
          readBytes: (path) async => throw const FileSystemException('nope'),
        ).validateFromPath('/missing.json'),
        reason: ArchiveIntakeRejectionReason.unreadable,
      );
    });
  });
}
