import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:compendium_app/src/data/archive_intake_service.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_repositories.dart';

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
  late CompendiumRepositories repos;

  ArchiveIntakeService service({
    ArchiveByteReader? readBytes,
    int maxBytes = kMaxIncomingArchiveBytes,
  }) => ArchiveIntakeService(
    repositories: repos,
    readBytes: readBytes,
    maxBytes: maxBytes,
    now: () => DateTime.utc(2026, 7, 18),
  );

  setUp(() => repos = openTestRepositories());

  group('valid bundle', () {
    test(
      'imports the program + dances and returns the program to open',
      () async {
        final result = await service().importBytes(_bytes(_validBundleJson()));

        expect(result.isImported, isTrue);
        expect(result.programId, isNotNull);

        final programs = await repos.programs.listAll();
        expect(programs, hasLength(1));
        expect(programs.single.id, result.programId);
        expect(programs.single.title, 'Spring Fling');

        final dances = await repos.dances.listAll();
        expect(dances.map((d) => d.title), contains('Simplicity Swing'));
      },
    );

    test('reads from a path via the injected reader, then imports', () async {
      final json = _validBundleJson();
      final result = await service(
        readBytes: (path) async => _bytes(json),
      ).importFromPath('/anywhere/bundle.json');

      expect(result.isImported, isTrue);
      expect(await repos.programs.listAll(), hasLength(1));
    });
  });

  group('rejected gracefully (never throws, no writes)', () {
    test('malformed (not JSON) is rejected', () async {
      final result = await service().importBytes(_bytes('this is not json'));

      expect(result.isRejected, isTrue);
      expect(result.message, isNotNull);
      expect(await repos.programs.listAll(), isEmpty);
      expect(await repos.dances.listAll(), isEmpty);
    });

    test('a non-object JSON root is rejected', () async {
      final result = await service().importBytes(_bytes('[1, 2, 3]'));

      expect(result.isRejected, isTrue);
      expect(await repos.programs.listAll(), isEmpty);
    });

    test('empty file is rejected', () async {
      final result = await service().importBytes(Uint8List(0));
      expect(result.isRejected, isTrue);
    });

    test('a well-formed archive with no content is rejected', () async {
      final json = encodeArchive(
        CompendiumArchive(exportedAt: DateTime.utc(2026)),
      );
      final result = await service().importBytes(_bytes(json));

      expect(result.isRejected, isTrue);
      expect(await repos.programs.listAll(), isEmpty);
    });

    test('oversized bytes are rejected', () async {
      // maxBytes tiny; the valid bundle exceeds it.
      final result = await service(
        maxBytes: 8,
      ).importBytes(_bytes(_validBundleJson()));

      expect(result.isRejected, isTrue);
      expect(await repos.programs.listAll(), isEmpty);
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
      ).importFromPath('/anywhere/huge.json');

      expect(readCalled, isTrue);
      expect(result.isRejected, isTrue);
      expect(await repos.programs.listAll(), isEmpty);
    });

    test('a newer-schema archive is refused with a clear message', () async {
      final json = _validBundleJson(schemaVersion: archiveSchemaVersion + 1);
      final result = await service().importBytes(_bytes(json));

      expect(result.isRejected, isTrue);
      expect(result.message, contains('newer version'));
      expect(await repos.programs.listAll(), isEmpty);
    });

    test('an unreadable file path is rejected gracefully', () async {
      final result = await service(
        readBytes: (path) async => throw const FileSystemException('nope'),
      ).importFromPath('/missing.json');

      expect(result.isRejected, isTrue);
    });
  });
}
