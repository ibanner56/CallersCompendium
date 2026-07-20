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

Figure _fig(String move, {int beats = 8}) =>
    Figure(move: move, params: {'beats': beats});

Dance _danceWith(String id, String title, {List<Figure> figures = const []}) =>
    Dance(
      id: id,
      title: title,
      figures: figures,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

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

    test(
      'a slot whose dance the receiver already has (ambiguous match, no shared '
      'externalId) resolves to the existing dance — no "Dance not imported"',
      () async {
        // Regression for issue #298 lineage: the receiver already holds an
        // independent copy (different id, NO shared externalId) with identical
        // content. Before the fix the ambiguous dance was skipped and the slot
        // degraded to a "Dance not imported (…)" placeholder.
        final figures = [
          _fig('balance_and_swing', beats: 16),
          _fig('circle_left'),
        ];
        await repos.dances.create(
          _danceWith('recv-d1', 'Simplicity Swing', figures: figures),
        );

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          dances: [_danceWith('orig-d1', 'Simplicity Swing', figures: figures)],
          programs: [
            Program(
              id: 'p1',
              title: 'Spring Fling',
              slots: [ProgramSlot(id: 's1', position: 0, danceId: 'orig-d1')],
              createdAt: DateTime.utc(2026, 4, 1),
              updatedAt: DateTime.utc(2026, 4, 1),
            ),
          ],
        );

        final result = await service().importBytes(
          _bytes(encodeArchive(archive)),
        );

        expect(result.isImported, isTrue);
        // No new duplicate; the slot points at the existing dance.
        expect(await repos.dances.listAll(), hasLength(1));
        final program = (await repos.programs.listAll()).single;
        expect(program.slots.single.danceId, 'recv-d1');
        expect(
          result.issues.where(
            (i) => i.code == 'archive_program_unresolved_dance',
          ),
          isEmpty,
        );
      },
    );

    test(
      'a large archive of many ambiguous same-title dances stays bounded and '
      'imports without throwing',
      () async {
        // Untrusted, adversarial-shaped input: many dances all fuzzy-matching
        // existing ones. Auto-resolution must handle every ambiguous record
        // (bounded per candidate) without throwing, and resolve every slot.
        const n = 60;
        final receiver = [
          for (var i = 0; i < n; i++)
            _danceWith(
              'recv-$i',
              'Contra No $i',
              figures: [_fig('circle_left')],
            ),
        ];
        for (final d in receiver) {
          await repos.dances.create(d);
        }

        final archive = CompendiumArchive(
          exportedAt: DateTime.utc(2026, 7, 15),
          dances: [
            for (var i = 0; i < n; i++)
              // Same titles as the receiver but different content -> ambiguous,
              // non-confident -> imported as duplicates.
              _danceWith(
                'orig-$i',
                'Contra No $i',
                figures: [_fig('do_si_do')],
              ),
          ],
          programs: [
            Program(
              id: 'p1',
              title: 'Marathon',
              slots: [
                for (var i = 0; i < n; i++)
                  ProgramSlot(id: 's$i', position: i, danceId: 'orig-$i'),
              ],
              createdAt: DateTime.utc(2026, 4, 1),
              updatedAt: DateTime.utc(2026, 4, 1),
            ),
          ],
        );

        final result = await service().importBytes(
          _bytes(encodeArchive(archive)),
        );

        expect(result.isImported, isTrue);
        // Every slot resolved to a real dance — no placeholders.
        final program = (await repos.programs.listAll()).single;
        expect(program.slots, hasLength(n));
        expect(program.slots.every((s) => s.danceId != null), isTrue);
        expect(
          result.issues.where(
            (i) => i.code == 'archive_program_unresolved_dance',
          ),
          isEmpty,
        );
      },
    );
  });

  group('rejected gracefully (never throws, no writes)', () {
    test('malformed (not JSON) is rejected', () async {
      final result = await service().importBytes(_bytes('this is not json'));

      expect(result.isRejected, isTrue);
      expect(result.message, isNotNull);
      expect(await repos.programs.listAll(), isEmpty);
      expect(await repos.dances.listAll(), isEmpty);
    });

    test('non-UTF-8 bytes are rejected', () async {
      // A hostile/binary payload that is not valid UTF-8 (a lone 0xFF byte and
      // friends). The service must reject it gracefully, not throw.
      final result = await service().importBytes(
        Uint8List.fromList([0xFF, 0xFE, 0x00, 0x80, 0xC0]),
      );

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
