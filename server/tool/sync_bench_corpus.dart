// A reproducible library of canonical record blobs for the blob-batch
// measurements (spec §5.2 `POST /v1/blobs/batch`). Not shipped; run by
// `blob_batch_cost_bench.dart` and `attach_bench_server.dart`.
//
// Every blob goes through the app's own outbound path: an archive-shaped body
// is decoded to its entity with `decodeSyncRecordEntity`, then re-encoded with
// `syncRecordBlobForEntity`, so field order, optional-field nulls and
// canonical JSON are exactly what a device uploads. The figures are the
// structured (non-`custom`) parses in the figure-text corpus golden — real
// figure text from real dances, parsed by the shipping importer — and the
// first dance is the seeded Baby Rose (David Kaynor), verbatim.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';

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
List<BenchBlob> buildBenchLibrary(
  int records, {
  required String repositoryRoot,
  int seed = 1,
}) {
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
  final blobs = <BenchBlob>[];

  BenchBlob encode(SyncRecordKind kind, Map<String, Object?> body) {
    final entity = decodeSyncRecordEntity(kind, body);
    final blob = syncRecordBlobForEntity(
      kind,
      entity,
      updatedAt: at,
      existenceAt: at,
    )!;
    return BenchBlob(kind, blob.id, encodeSyncRecordBlobUtf8(blob));
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
    blobs.add(
      encode(SyncRecordKind.choreographer, {
        'id': 'bench-ch-$i',
        'name':
            '${given[random.nextInt(given.length)]} '
            '${surnames[random.nextInt(surnames.length)]}',
        'deceased': false,
      }),
    );
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
    blobs.add(
      encode(SyncRecordKind.tag, {
        'id': 'bench-tag-$i',
        'name': '${tagNames[i % tagNames.length]} ${i ~/ tagNames.length}',
      }),
    );
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
    blobs.add(encode(SyncRecordKind.dance, body));
  }
  for (var i = 0; i < programs; i++) {
    final slots = 12 + random.nextInt(8);
    blobs.add(
      encode(SyncRecordKind.program, {
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
      }),
    );
  }
  return blobs;
}

/// The library's manifest, as a peer named [deviceId] would publish it.
Uint8List benchManifest(
  List<BenchBlob> blobs, {
  required String deviceId,
  required String epoch,
}) {
  final records = <SyncRecordKind, Map<String, String>>{};
  for (final blob in blobs) {
    (records[blob.kind] ??= {})[blob.id] = blob.hash;
  }
  return encodeSyncManifestUtf8(
    SyncManifest(
      deviceId: deviceId,
      epoch: epoch,
      writtenAt: DateTime.utc(2026, 9, 1, 12),
      records: records,
    ),
  );
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
