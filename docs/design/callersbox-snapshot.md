# Design: CallersBox snapshot format & hosting

*Roadmap item 1.13 · v0.1 (2026-07-10). The maintainer-relations step is a
prerequisite: confirm rehosting terms with Chris Page & Michael Dyck before
the snapshot URL is publicized (see research/callersbox.md §Permissions).*

## Artifact layout

A snapshot release consists of two files at stable URLs:

```
https://<host>/callersbox/manifest-latest.json          ← small, checked for updates
https://<host>/callersbox/callersbox-snapshot-YYYY-MM-DD.ndjson.gz
```

### manifest-latest.json
```json
{
  "schemaVersion": 1,
  "source": "thecallersbox",
  "snapshotDate": "2026-07-10",
  "danceCount": 12345,
  "url": ".../callersbox-snapshot-2026-07-10.ndjson.gz",
  "sha256": "<hex of the .gz>",
  "bytes": 12345678,
  "generator": "merge script name+version",
  "notes": "e.g. permission tiers included, known gaps"
}
```

### Snapshot body
- **NDJSON**: one TCB dance JSON object per line (verbatim as served by
  `dance.php?id=N&format=JSON`), sorted by numeric ID, UTF-8, gzip-9.
  ~17k dances ≈ a few tens of MB compressed — fine for a one-shot download.
- Verbatim payloads keep the pipeline honest: all interpretation happens in
  the app's import parser (design/imports.md), so parser improvements apply
  retroactively without re-crawling.
- Include `Permission: "full"` dances; optionally include `"search"`-tier
  records (their `phrases` are empty as served) for metadata-stub import.
  Never include reconstructed figures for non-full dances.

## Producing a snapshot (maintainer workflow)

From a directory of per-dance `NNNN.json` files:

```bash
DATE=$(date +%F)
ls *.json | sort -n | xargs -I{} jq -c . {} > callersbox-snapshot-$DATE.ndjson
gzip -9 -k callersbox-snapshot-$DATE.ndjson
SHA=$(shasum -a 256 callersbox-snapshot-$DATE.ndjson.gz | cut -d' ' -f1)
# fill manifest fields; danceCount:
wc -l < callersbox-snapshot-$DATE.ndjson
```

Validation before publishing (script to live in `tools/snapshot/`):
- every line parses as JSON and has `ID`, `Name`, `Permission`;
- IDs unique and ascending; count matches manifest;
- flag lines where `Permission` ∉ {full, search}.

## Hosting requirements

- Plain HTTPS static hosting (personal server is fine); support `ETag`/
  `Last-Modified` so the app can poll `manifest-latest.json` cheaply.
- Keep previous snapshots online (dated filenames make this automatic) for
  reproducibility and rollback.
- If the URL moves, app setting allows custom snapshot URL (also enables
  community mirrors and testing).

## App-side update flow

1. On demand (and optionally on launch, throttled), GET manifest-latest.
2. If `snapshotDate` newer than `snapshots.source='callersbox'` row: download,
   verify sha256, stream-parse NDJSON through the import pipeline.
3. Re-import diffs by TCB ID: new dances added; changed dances surface in the
   review queue (user data is never silently overwritten); deletions are
   reported but never auto-delete local data.

## Legal/courtesy checklist (before first public release)

- [ ] Maintainer agreement on redistribution and cadence (they may prefer to
      publish an official dump we mirror).
- [ ] Attribution text in-app and in the manifest.
- [ ] Honor permission tiers exactly; document takedown process (author asks →
      dance removed from next snapshot; app removes stubs on update).
- [ ] Decide whether HTML-only `License` (CC-BY-NC) values should be merged in
      as a supplemental field in a future schemaVersion.
