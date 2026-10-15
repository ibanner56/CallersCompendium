// Writes a reproducible library of canonical record blobs for the blob-batch
// measurements (sync spec §5.2 `POST /v1/blobs/batch`), read by
// `server/tool/blob_batch_cost_bench.dart` and
// `server/tool/attach_bench_server.dart`. Not shipped. Run from
// `packages/compendium_core/`:
//
//     dart run tool/sync_bench_corpus.dart --records 1000 --out corpus.json
//
// The blobs are what a real device publishes: the records are written to an
// in-memory database through the repositories, and the blobs and hashes are
// read back from `CompendiumSyncStorage.snapshot()`, the publication path a
// pass uploads from. So a device that attaches to this library and applies it
// re-derives the same hashes and uploads nothing back. The figures are the
// structured (non-`custom`) parses in the figure-text corpus golden — real
// figure text parsed by the shipping importer — and the first dance is the
// seeded Baby Rose (David Kaynor), verbatim.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';

Future<void> main(List<String> arguments) async {
  String option(String name) {
    final index = arguments.indexOf('--$name');
    if (index < 0 || index + 1 >= arguments.length) {
      throw ArgumentError('--$name is required');
    }
    return arguments[index + 1];
  }

  final out = option('out');
  final library = await buildBenchLibrary(
    int.parse(option('records')),
    repositoryRoot: Directory.current.parent.parent.path,
  );
  File(out).writeAsStringSync(
    jsonEncode({
      'records': [
        for (final blob in library)
          {
            'kind': blob.kind.name,
            'id': blob.id,
            'hash': blob.hash,
            'blob': base64.encode(blob.bytes),
          },
      ],
    }),
  );
  stdout.writeln('wrote ${library.length} records to $out');
}

/// One record's canonical blob and its manifest address.
final class BenchBlob {
  BenchBlob(this.kind, this.id, this.bytes) : hash = sha256Hex(bytes);

  final SyncRecordKind kind;
  final String id;
  final Uint8List bytes;
  final String hash;
}

/// Builds a library of [records] records: 2% choreographers, 3% tags, 5%
/// programs, the rest dances. Deterministic for a given [seed].
Future<List<BenchBlob>> buildBenchLibrary(
  int records, {
  required String repositoryRoot,
  int seed = 1,
}) async {
  final random = Random(seed);
  final figures = _realFigures(repositoryRoot);
  final seedDance =
      ((jsonDecode(
                        File(
                          '$repositoryRoot/app/assets/seed/baby_rose.json',
                        ).readAsStringSync(),
                      )
                      as Map<String, Object?>)['dances']!
                  as List)
              .single
          as Map<String, Object?>;
  final at = DateTime.utc(2026, 9, 1, 12);
  final choreographers = max(1, records * 2 ~/ 100);
  final tags = max(1, records * 3 ~/ 100);
  final programs = max(1, records * 5 ~/ 100);
  final dances = records - choreographers - tags - programs;
  final database = CompendiumDatabase(NativeDatabase.memory());
  final repositories = CompendiumRepositories(database, contraTaxonomy);
  await repositories.ensureMigrated();

  // Each body is read as the archive importer reads it, then written through
  // the repository, so the database holds exactly what the app would.
  Future<void> encode(SyncRecordKind kind, Map<String, Object?> body) async {
    final entity = decodeSyncRecordEntity(kind, body);
    switch (entity) {
      case Choreographer():
        final _ = await repositories.choreographers.upsert(entity, at: at);
      case Tag():
        final _ = await repositories.tags.upsert(entity, at: at);
      case Dance():
        await repositories.dances.create(entity);
      case Program():
        await repositories.programs.create(entity);
      default:
        throw StateError('unexpected ${entity.runtimeType}');
    }
  }

  const surnames = [
    'Kaynor',
    'Dart',
    'Hinds',
    'Parkes',
    'Bishop',
    'Ross',
    'Wolff',
    'Morse',
    'Hill',
    'Rose',
    'Kirkpatrick',
    'Millstone',
    'Sannella',
    'Cook',
    'Weber',
  ];
  const given = [
    'David',
    'Mary',
    'Tom',
    'Gene',
    'Becky',
    'Chris',
    'Erik',
    'Jim',
    'Lisa',
    'Rick',
    'Ted',
    'Bob',
    'Susan',
    'Joseph',
    'Janet',
    'Larry',
    'Kathy',
  ];
  for (var i = 0; i < choreographers; i++) {
    await encode(SyncRecordKind.choreographer, {
      'id': 'bench-ch-$i',
      // Unique for the first 255: one library cannot hold two
      // choreographers of the same name.
      'name':
          '${given[i % given.length]} '
          '${surnames[(i ~/ given.length) % surnames.length]}',
      'deceased': false,
    });
  }
  const tagNames = [
    'Beginner friendly',
    'Contra corners',
    'Gypsy',
    'Petronella',
    'Mixer',
    'Becket',
    'Triple minor',
    'Zesty',
    'Flowing',
    'Hey for four',
    'Slice',
    'No swing',
    'Long-lines',
    'Down the hall',
    'Square-ish',
  ];
  for (var i = 0; i < tags; i++) {
    await encode(SyncRecordKind.tag, {
      'id': 'bench-tag-$i',
      'name': '${tagNames[i % tagNames.length]} ${i ~/ tagNames.length}',
    });
  }
  final danceIds = <String>[];
  for (var i = 0; i < dances; i++) {
    final body = Map<String, Object?>.of(seedDance);
    final id = 'bench-dance-$i';
    danceIds.add(id);
    body['id'] = id;
    if (i > 0) {
      body['title'] = 'Bench Dance $i';
      body['authorIds'] = ['bench-ch-${random.nextInt(choreographers)}'];
      final count = 6 + random.nextInt(5);
      body['figures'] = [
        for (var f = 0; f < count; f++) figures[random.nextInt(figures.length)],
      ];
      body['tagIds'] = {
        for (var t = 0; t < random.nextInt(3); t++)
          'bench-tag-${random.nextInt(tags)}',
      }.toList();
      body['callingNotes'] = i.isEven
          ? 'Imported from ContraDB.'
          : 'Watch the transition into the swing at bar ${random.nextInt(16)}.';
      body['provenance'] = {
        'source': 'contradb',
        'externalId': '${1000 + i}',
        'importedAt': '2026-09-01T12:00:00.000Z',
        'sourceVersion': 'contradb-html',
      };
    } else {
      body['authorIds'] = ['bench-ch-0'];
    }
    await encode(SyncRecordKind.dance, body);
  }
  for (var i = 0; i < programs; i++) {
    final slots = 12 + random.nextInt(8);
    await encode(SyncRecordKind.program, {
      'id': 'bench-program-$i',
      'title': 'Second Saturday ${i + 1}',
      'eventDate': '2026-0${1 + i % 9}-1${i % 10}T00:00:00.000Z',
      'band': 'The Bench Band',
      'caller': 'Bench Caller',
      'notes': 'Break after slot 7.',
      'status': 'draft',
      'slots': [
        for (var s = 0; s < slots; s++)
          {
            'id': 'bench-program-$i-slot-$s',
            'position': s,
            'danceId': danceIds[random.nextInt(danceIds.length)],
            'isAlt': false,
            'walkthroughMinutes': 3,
            'danceMinutes': 9,
          },
      ],
      'createdAt': '2026-09-01T12:00:00.000Z',
      'updatedAt': '2026-09-01T12:00:00.000Z',
    });
  }
  final publication = (await CompendiumSyncStorage(
    repositories,
  ).snapshot()).publication;
  await database.close();
  return [
    for (final candidate in publication.values)
      if (candidate != null && candidate.address.kind != SyncRecordKind.setting)
        BenchBlob(
          candidate.address.kind,
          candidate.address.recordId,
          encodeSyncRecordBlobUtf8(candidate.blob),
        ),
  ];
}

List<Object?> _realFigures(String repositoryRoot) {
  final figures = <Object?>[];
  final lines = File(
    '$repositoryRoot/packages/compendium_core/test/imports/fixtures/'
    'figure_text_corpus_golden.jsonl',
  ).readAsLinesSync();
  for (final line in lines) {
    final entry = jsonDecode(line) as Map<String, Object?>;
    final fanOut = jsonDecode(entry['fanOut']! as String) as List;
    for (final figure in fanOut) {
      if ((figure as Map)['move'] != 'custom') figures.add(figure);
    }
  }
  return figures;
}
