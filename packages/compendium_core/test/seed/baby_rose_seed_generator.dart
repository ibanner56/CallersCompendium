// Deterministic generator for the first-run seed dance asset,
// "The Baby Rose" by David Kaynor.
//
// FIDELITY TO SOURCE (the project's #1 rule): the seed's choreography is NOT
// hand-authored. It is produced by running the real ContraDB import path — the
// exact same `ContraDbHtmlAdapter` + `ImportPipeline` the app uses for a
// user-initiated ContraDB import — over a checked-in capture of the
// authoritative source page:
//
//     https://contradb.com/dances/8
//     (David Kaynor, improper; ContraDB `publish: everywhere`, the most
//      verified/called transcription — see plan / PR description.)
//
// The HTML is captured offline and checked in as
// `tools/seed/fixtures/contradb_dance_8.html`; nothing is fetched here or on
// device. Running the import through the pipeline (rather than assembling the
// archive by hand) guarantees the seed is byte-for-byte what a real import
// would persist.
//
// Determinism: the pipeline's id and clock seams are injected — ids come from a
// stable counter and every timestamp is pinned to [seedTimestamp] — so the
// emitted archive JSON is reproducible. A drift test (`baby_rose_seed_test.dart`)
// re-runs this generator and asserts the output matches the checked-in asset.
import 'dart:convert';

import 'package:compendium_core/compendium_core.dart';
import 'package:drift/native.dart';

/// The authoritative source page for the seed dance.
const String babyRoseSourceUrl = 'https://contradb.com/dances/8';

/// Fixed UTC instant stamped onto every timestamp in the generated archive
/// (dance created/updated, provenance importedAt, and the archive envelope's
/// exportedAt), so regeneration is byte-for-byte reproducible.
final DateTime seedTimestamp = DateTime.utc(2020, 1, 1);

/// Prefix for the deterministic ids assigned to the seeded choreographer and
/// dance, so the checked-in asset is stable across regenerations.
const String seedIdPrefix = 'seed-baby-rose';

/// Runs [sourceHtml] (a capture of [babyRoseSourceUrl]) through the real
/// ContraDB import pipeline into an in-memory database, then exports and
/// encodes the result as canonical, pretty-printed [CompendiumArchive] JSON.
///
/// Throws [StateError] if the import produces no committed dance, so a broken
/// fixture fails loudly at author time rather than silently shipping an empty
/// seed.
Future<String> buildBabyRoseSeedArchiveJson(String sourceHtml) async {
  final db = CompendiumDatabase(NativeDatabase.memory());
  final repos = CompendiumRepositories(db, contraTaxonomy);
  try {
    final pipeline = ImportPipeline(repos.dances, repos.choreographers);
    final batch = await pipeline.plan(
      ContraDbHtmlAdapter(),
      ImportRequest(payload: sourceHtml, uri: babyRoseSourceUrl),
    );
    if (batch.records.isEmpty) {
      throw StateError(
        'ContraDB import produced no records from the seed fixture: '
        '${batch.errors}',
      );
    }

    // Deterministic id seam: `seed-baby-rose-0001`, `-0002`, … The pipeline
    // allocates the choreographer id before the dance id; either way the
    // sequence is stable, which is all the checked-in asset needs.
    var counter = 0;
    String nextId() {
      counter++;
      return '$seedIdPrefix-${counter.toString().padLeft(4, '0')}';
    }

    final session = await pipeline.commit(
      batch,
      now: seedTimestamp,
      newId: nextId,
    );
    final failed = session.records.where((r) => !r.succeeded).toList();
    if (failed.isNotEmpty) {
      throw StateError(
        'Committing the seed dance failed: '
        '${failed.map((r) => r.error?.message).toList()}',
      );
    }

    final archive = await ArchiveExporter(
      repos,
    ).export(exportedAt: seedTimestamp);

    // Drop `provenance.rawPayload` from the shipped seed. A real import stores
    // the raw source page for re-import/diffing, but that is a *local* audit
    // artifact — a checked-in, shipped asset must not embed a full scraped HTML
    // page (it is bloat and a standing secret-leak surface, e.g. the page's CSRF
    // token). Stripping it here means no source markup is shipped at all, so the
    // asset can never carry a secret regardless of the fixture, and regenerating
    // from a re-captured page is stable. The meaningful provenance — source,
    // externalId, importedAt, sourceVersion — is retained.
    final sanitized = CompendiumArchive(
      schemaVersion: archive.schemaVersion,
      exportedAt: archive.exportedAt,
      dances: [for (final d in archive.dances) _withoutRawPayload(d)],
      programs: archive.programs,
      choreographers: archive.choreographers,
      publishedSources: archive.publishedSources,
      customFields: archive.customFields,
      tags: archive.tags,
    );

    // Pretty-print for a reviewable diff. `archiveToJson`/`encodeArchive` already
    // order entities by id and emit keys in a stable order, so decoding then
    // re-indenting stays deterministic while remaining a valid archive the app's
    // `decodeArchive` path accepts unchanged.
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(encodeArchive(sanitized)));
  } finally {
    await db.close();
  }
}

/// Returns [dance] with any `provenance.rawPayload` cleared (all other
/// provenance fields preserved), so the shipped seed carries no scraped source
/// markup.
Dance _withoutRawPayload(Dance dance) {
  final prov = dance.provenance;
  if (prov == null || prov.rawPayload == null) return dance;
  return dance.copyWith(
    provenance: Provenance(
      source: prov.source,
      externalId: prov.externalId,
      importedAt: prov.importedAt,
      permission: prov.permission,
      license: prov.license,
      sourceVersion: prov.sourceVersion,
    ),
  );
}
