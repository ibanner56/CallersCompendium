# Design: Local storage

*Roadmap item 1.12 · v0.1 (2026-07-10). SQLite via drift (ADR-001); schema
lives in the core package; all access through repositories.*

## Approach

- One SQLite database file per profile, in the platform app-data directory;
  user-triggered backup/restore = timestamped JSON export/import (6.6), not
  file copying.
- **Hybrid figure storage** (fixing ContraDB's unqueryable JSON blob):
  1. `dances.figures_json` — authoritative ordered figure list (named params,
     schemaVersion) for lossless load/save.
  2. `dance_figures` — derived, rebuilt on every dance write: one row per
     figure for indexed structural search.
  3. `dance_fts` — FTS5 virtual table over canonical text for full-text search.
  Derived tables are rebuildable from `figures_json` at any time (integrity
  check + repair on migration).

## Tables (abridged)

```sql
dances(id PK, title, form, formation_base, formation_detail, progression,
       phrase_structure, figures_json, hook, calling_notes, status, tunes_json,
       created_at, updated_at, deleted_at, existence_at)
choreographers(id PK, name UNIQUE, website, notes,
               updated_at, deleted_at, existence_at)
dance_authors(dance_id, choreographer_id, position,
             PK(dance_id, choreographer_id),
             UNIQUE(dance_id, position))       -- no ambiguous ordering

dance_figures(dance_id, idx, move, beats, progression, params_json,
              PK(dance_id, idx))              -- derived
CREATE INDEX dance_figures_move ON dance_figures(move);

CREATE VIRTUAL TABLE dance_fts USING fts5(     -- derived; canonical text only
  title, authors, hook, notes, figures_text, custom_values, content='');

programs(id PK, title, event_date, venue, venue_id NULL, notes, status,
         created_at, updated_at, deleted_at,
         existence_at)                         -- venue_id → venues.id (v14)
program_slots(id PK, program_id FK, position, dance_id NULL, text,
              is_alt, performed_at)

venues(id PK, name, address1, address2, city, state_prov, country,
       postal_code, plus4, website, sponsor, event_name, time,
       generic_schedule, price, notes,
       contact1_name, contact1_phone, contact1_email,
       contact2_name, contact2_phone, contact2_email,
       updated_at, deleted_at, existence_at)           -- reusable venue (v14)

custom_field_defs(id PK, key UNIQUE, label, type, choices_json,
                  show_in_list, searchable,
                  updated_at, deleted_at, existence_at)
custom_field_values(dance_id, field_id, value_text, value_num,
                    PK(dance_id, field_id))
tags(id PK, name UNIQUE, color, updated_at, deleted_at, existence_at)
dance_tags(dance_id, tag_id, PK(...))
dance_links(id PK, dance_id, kind, url, target_dance_id, label)
provenance(dance_id PK, source, external_id, imported_at, permission,
           license, source_version)
settings(key PK, value_json,
         updated_at, deleted_at, existence_at)  -- dialects, prefs, source URLs

-- published_sources also carries (updated_at, deleted_at, existence_at); see
-- "The delete model" below for what the three mean and why they are separate.
```

Two pieces of this sketch were built and later removed, both at schema v21:

- `provenance.raw_payload` (and its `program_provenance` twin) stored the
  verbatim imported source record. Nothing ever read it, and for an HTML import
  it held the whole source page, so it was dropped (#781). Re-import dedupes on
  `(source, external_id)` and re-fetches from the source, which needs no stored
  copy.
- A `snapshots(source PK, snapshot_date, manifest_json, imported_at)` table
  recorded the last-imported hosted-archive snapshot so the app could offer
  "update available" prompts. That feature was cut in favour of direct in-app
  import (ROADMAP 6.2/6.3; see `callersbox-snapshot.md`, marked superseded), and
  nothing ever wrote a row, so the table was dropped (#782).

## Search execution

Filter expressions (ContraDB-style composable tree — and/or/no/then/figure/
formation/…, see future search design in Phase 3) compile to SQL:
- structural leaves → `EXISTS (SELECT 1 FROM dance_figures WHERE move=? AND
  params_json ->> '$.who' = ?)` (JSON1 on derived rows),
- text leaves → `dance_fts MATCH ?`,
- `then` (sequence) → self-join on `dance_figures.idx` ordering.
No full-table in-memory scans (ContraDB pitfall #2). Target: <50 ms over
20k dances (TCB-scale) on tablet hardware — benchmarked in CI.

## Migrations

- drift schema versions with stepwise migrations; every migration ships with
  a test that opens a fixture DB from the previous version.
- A **schema floor** (`kMinSupportedSchemaVersion`): versions below it are
  retired — their migration steps, fixtures and `drift_schemas/generated/`
  dumps are
  deleted — and a database stamped below the floor is refused rather than
  partially migrated. See "Retiring a schema version" below.
- `figures_json.schemaVersion` migrates lazily on read + bulk on upgrade.
- Derived tables rebuilt after any migration touching figures.

## Retiring a schema version

`kMinSupportedSchemaVersion`, declared in
[`database.dart`](../../packages/compendium_core/lib/src/storage/database.dart),
is the oldest on-disk version this build can still upgrade. It
is the schema version of the oldest *supported release*, not the oldest version
whose code happens to still exist.

Retiring versions below a new floor means deleting, together:

- the `if (from < N)` steps that can no longer fire (note the off-by-one:
  retiring versions up to and including vX kills steps through `if (from < X+1)`,
  because that step only ever applies to a vX-or-below database),
- the fixtures and generators under `test/storage/fixtures/`,
- the dumps under `drift_schemas/generated/` and their generated classes, and
- the corresponding `migration_test.dart` groups.

**The floor check is not bookkeeping.** Deleting those steps without it would
let a below-floor database open, run only the surviving steps and be stamped at
head while missing everything the deleted steps would have added — silently
corrupt, and permanently mislabelled, since no later migration would ever fire
for it. `onUpgrade` therefore refuses such a file outright, and
`test/storage/schema_floor_test.dart` covers both halves: below-floor is
refused and left untouched, at-floor still migrates to head.

Raising the floor is **user-visible** — databases below it stop opening — so it
belongs in `app/CHANGELOG.md` in user-facing terms, naming the release whose
schema version is being adopted. `tools/ci/check_schema_migration.py` fails any
PR that reintroduces a per-version artefact below the floor.

## Schema version history

`CompendiumDatabase.schemaVersion` (in
[`database.dart`](../../packages/compendium_core/lib/src/storage/database.dart))
is the on-disk schema version, and this is its per-version log. It lives here
rather than on the class because it is a ledger of decisions already shipped:
it constrains nothing on the declaration, and it grows on every bump, so every
reader of that file paid for the whole history. What *does* constrain the
declaration — the four things a bump must ship, and the rule that a bump never
rides a PATCH release — stays there, next to the constant it governs.

**Every bump appends an entry here, in the same PR.**
`tools/ci/check_version_history.py` fails a PR that moves the constant without
adding the matching entry.

### Retired (v1–v19): history only

**v1–v19 are RETIRED** (#837, floor raised past v19 once every tester was
confirmed on `v0.1.0-beta.6`): they predate `v0.1.0-beta.6`, the oldest
supported release, so their migration steps, fixtures and schema dumps have
been deleted and [kMinSupportedSchemaVersion] refuses a database stamped
below v20. Their entries are kept below as history — they explain why later
columns exist and are still referenced by the steps that survive — but there
is no longer any code path that migrates from them.

- v1 (2026-07-10): initial schema — see ["Tables (abridged)"](#tables-abridged)
  above.
- v2 (2026-07-11): section-aware search (`docs/design/search.md`). Adds the
  nullable `dance_figures.section` column plus the `dance_figures_move_
  section` index (the `Then` self-join's `(dance_id, idx)` access is
  already served by the composite primary key's implicit index).
  `onUpgrade` performs the DDL and durably records
  [derivedRebuildRequiredKey]; the derived `section` values are back-filled
  by a post-open integrity pass ([DanceRepository.rebuildAllDerived]) that
  [CompendiumRepositories.ensureMigrated] runs when the marker is set — the
  rebuild needs the taxonomy/renderer, which `MigrationStrategy` can't
  reach.
- v3 (2026-07-13): CC-parity program event metadata (`docs/design/
  domain-model.md` "CC parity backfill"). Adds nullable `programs.band`,
  `programs.caller`, `programs.dancer_level`, `program_slots.guest_caller`,
  and `program_slots.planned_minutes`. All nullable with no back-fill
  (existing rows get NULL); programs/slots do not feed the derived
  `dance_figures`/`dance_fts` indexes, so no derived rebuild is required.
- v4 (2026-07-13): CC-parity dance difficulty (`docs/design/domain-model.md`
  "CC parity backfill", ROADMAP 4b.1). Adds the nullable
  `dances.level` (ordered [DanceLevel], persisted by name) and
  `dances.mixed_level` (bool, defaults `false`) columns. Existing rows get
  `level` NULL / `mixed_level` false. `level`/`mixed_level` are dance-scalar
  metadata, not figure text, so they do not feed the derived
  `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
- v5 (2026-07-13): CC-parity composed/revised dates (`docs/design/
  domain-model.md` "CC parity backfill", ROADMAP 4b.2). Adds the nullable
  `dances.composed_on` and `dances.revised_on` columns, each holding a
  canonical partial-precision [PartialDate] string (`YYYY`/`YYYY-MM`/
  `YYYY-MM-DD`). Existing rows get NULL. These are author/bibliographic
  scalar metadata (distinct from the record stamps `created_at`/
  `updated_at`), not figure text, so they do not feed the derived
  `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
- v6 (2026-07-13): CC-parity dance rating (`docs/design/domain-model.md`
  "CC parity backfill", ROADMAP 4b.3). Adds the nullable `dances.rating`
  column (an `int` star rating validated to `1..5` at the [Dance] boundary;
  `null` = unrated). Existing rows get NULL. `rating` is dance-scalar
  curation metadata, not figure text, so it does not feed the derived
  `dance_figures`/`dance_fts` indexes and no derived rebuild is required.
- v7 (2026-07-14): CC-parity author contact (`docs/design/domain-model.md`
  "CC parity backfill", ROADMAP 4b.4). Adds the nullable
  `choreographers.email` and `choreographers.location` columns plus
  `choreographers.deceased` (bool, defaults `false`). Existing rows get
  email/location NULL and deceased false. Choreographer contact is
  scalar author metadata (not figure text) and choreographers do not feed
  the derived `dance_figures`/`dance_fts` indexes, so no derived rebuild is
  required. (`email`/`location` are private — never emitted in shareable
  exports; see [Choreographer].)
- v8 (2026-07-14): first-class published-source citations
  (`docs/design/domain-model.md` "CC parity backfill", ROADMAP 4b.5).
  Adds two brand-new tables: `published_sources` (a reusable bibliographic
  entity — id/title plus nullable author/year/url/notes) and the ordered
  `dance_sources` join (danceId/sourceId FKs cascade, freeform nullable
  page/number, position). No columns are added to existing tables and no
  data is back-filled (fresh tables start empty). These new tables do NOT
  feed the derived `dance_fts`/`dance_figures` indexes (searchability is
  ROADMAP 4b.5b), so NO derived rebuild is required by this migration.
- v9 (2026-07-14): published-source citations become SEARCHABLE (ROADMAP
  4b.5b). Adds a `sources` column to the `dance_fts` FTS5 virtual table
  holding the searchable text (title + author) of each cited
  [PublishedSources] row. Because an FTS5 table's column set is fixed at
  creation, the migration DROPs and recreates `dance_fts` with the new
  shape; the FTS rows cannot be repopulated in the migration (that needs the
  taxonomy/renderer to re-derive figure text and the repository to join the
  citation → published-source text), so — exactly like the v2
  `dance_figures.section` back-fill — `onUpgrade` durably records
  [derivedRebuildRequiredKey] and [CompendiumRepositories.ensureMigrated]
  performs the full derived rebuild ([DanceRepository.rebuildAllDerived]),
  which repopulates every `dance_fts` row (including the new `sources`
  column) and clears the marker. No table columns are added elsewhere.
- v10 (2026-07-15): program import provenance. Adds one brand-new table
  (`program_provenance`); no columns added to existing tables and no
  back-fill. It does NOT feed the derived `dance_fts`/`dance_figures`
  indexes, so no derived rebuild is required.
- v11 (2026-07-15): CC-parity "hide alternates in set list". Adds a single
  additive boolean column `hide_alternates` on `programs` (defaults false).
  Programs don't feed the derived indexes, so no derived rebuild is required.
- v12 (2026-07-19): issue #290 ocean-wave cleanup — the sanctioned
  canonical-changing migration. The `form_an_ocean_wave` MoveDef was removed
  from the taxonomy, so `onUpgrade` REWRITES every stored figure with
  `move == 'form_an_ocean_wave'` in each `dances.figures_json` blob to
  `pass_the_ocean` (when `passThru` is true — its default) or
  `form_a_short_wave` (when false), dropping `passThru` and carrying the rest.
  This changes those figures' `canonicalText`/FTS, so — like the v2/v9 steps
  — `onUpgrade` durably records [derivedRebuildRequiredKey] and
  [CompendiumRepositories.ensureMigrated] runs the full
  [DanceRepository.rebuildAllDerived] (which regenerates `dance_figures` +
  `dance_fts` from the rewritten `figures_json` through the renderer) and
  clears the marker. The rewrite is parse-never-throw and lossless: any row
  or figure that can't be cleanly remapped is left byte-identical so it falls
  through to the non-destructive unknown-move path (issue #358) at read time,
  never dropped or corrupted.
- v13 (2026-07-22): performance-only index. Adds
  `dance_links_dance_id` (`dance_links(dance_id)`) so the batched link
  hydration in [DanceRepository.listAll] (and the single-id lookup behind
  `getById`) seeks by index instead of full-scanning `dance_links` on every
  `dance_id IN (…)` chunk. Pure DDL: no columns/tables added, no data
  rewritten, and the derived `dance_fts`/`dance_figures` indexes are
  untouched, so no derived rebuild is required.
- v14 (2026-07-22): first-class venue entity. Adds one brand-new table,
  `venues` (a reusable venue — id/name plus 20 nullable address/contact/
  schedule columns, faithful to CC's `Venue` table), and a single nullable
  `programs.venue_id` soft reference to it. Purely additive: `createTable` +
  `addColumn`, no data back-fill (fresh table starts empty; existing
  programs get `venue_id` NULL and keep their free-text `venue` label). The
  free-text `programs.venue` label and the `venue_id` entity link coexist
  non-destructively. `venue_id` is a deliberately un-constrained soft
  reference (no FK) — referential integrity is enforced at the app layer by
  `VenueRepository.delete`'s guard — so this migration adds NO FK and no
  rebuild marker. It DOES add one plain lookup index, `programs_venue_id`
  (see [venueLookupIndexSql]), so that guard's reference-count query stays
  cheap instead of full-scanning `programs`. Venues do NOT feed the derived
  `dance_fts`/`dance_figures` indexes, so NO derived rebuild is required.
- v15 (2026-07-28): dedicated per-dance walkthrough (issue #370). Adds a
  single additive `dances.walkthrough` text column (defaults to `''`) — a
  free-form step-by-step walkthrough, distinct from the short
  `calling_notes`. Purely additive `addColumn`; existing rows get `''` and
  stay valid. It is dance-scalar *content* (not figure text), so it does NOT
  feed the derived `dance_fts`/`dance_figures` indexes and NO derived rebuild
  is required.
- v16 (2026-07-30): performance-only index (issue #627). Adds
  `program_slots_dance_id` (`program_slots(dance_id)`) so the per-dance
  calling-history/stats lookups (`lastCalledByDance`, `countByDance`,
  `callingHistoryForDance`, `halfCallingStatsForDance`,
  `_sortByLastCalled`, `_cleanupDanglingReferences`) seek by index instead
  of full-scanning `program_slots`. Mirrors the v13 `dance_links_dance_id`
  index. Pure DDL: no columns/tables added, no data rewritten, and the
  derived `dance_fts`/`dance_figures` indexes are untouched, so no derived
  rebuild is required.
- v17 (2026-07-30, REVERTED before release): typed-prose canonicalization
  (issue #613). The step routed `hook`/`calling_notes`/`walkthrough` through
  `canonicalizeText`, but that substitution's always-on synonym set includes
  ordinary English words and proper nouns (`man`, `men`, `lady`, `ladies`,
  `lark(s)`, `robin(s)`, …), so across long-form prose it corrupted dance
  titles, tune names and people's names ("Lady of the Lake" → "role2 of the
  Lake"). No released build ever contained it, so no database in the wild
  was rewritten. The version number is retained as a no-op step so v18+
  keep their numbering. Free prose is stored verbatim; figure notes are
  still canonicalized (they carry figure-adjacent modifiers).
- v18 (issue #295): fused-move retirement + figure rewrite. The
  `allemande_orbit` MoveDef was removed from the taxonomy (v19); its stored
  figures are rewritten in each `dances.figures_json` blob to a
  `meanwhile` container `[allemande{who, hand, turn=old inner},
  orbit{who=invert(who), turn=direction derived from hand, amount=old
  outer}]`, carrying the fused figure's `beats` as the shared container
  total. This is a SANCTIONED canonical-changing migration (cf. the v12
  ocean-wave rewrite): rewriting `figures_json` changes those figures'
  derived `canonicalText`/FTS, so it schedules a derived rebuild (marker),
  but only when a figure actually changed. Per-row and per-figure
  parse-never-throw: a blob or entry that can't be cleanly remapped (e.g. a
  wildcard `hand`, or a `who` with no pair-inverse) is left byte-identical,
  falling through to the #358 unknown-move path rather than being
  dropped/corrupted.
- v19 (issue #295): taxonomy move RENAME. `form_a_short_wave` became
  `form_short_waves` at taxonomy v21, so every stored figure with
  `move == 'form_a_short_wave'` in each `dances.figures_json` blob is
  rewritten to the new id — including sides nested inside a `meanwhile`
  container (which the v18 rewrite can itself create). Params are carried
  over untouched: this is purely an identity change. Like v12/v18 it is a
  SANCTIONED canonical-changing migration (the display/canonical text moves
  from "form a wave" to "form short waves"), so it schedules a derived
  rebuild (marker) — but only when a figure actually changed. Per-row and
  per-figure parse-never-throw: a malformed blob or entry is left
  byte-identical, falling through to the #358 unknown-move path. Note the
  historical v12 step still writes the OLD id (it is frozen history); a
  long-hop upgrade from ≤ v11 therefore lands on `form_a_short_wave` at v12
  and is renamed here at v19.

### Supported (v20 and later)

These are the versions a database can still be stamped at, and the steps that
can still fire.

- v20 (gate merge): duplicate-move retirement + figure rewrite. `gate` and
  `rotation_gate` — which both rendered the display name "gate" and showed
  as two identical picker rows — are MERGED into one `gate` move (taxonomy
  v22), and stored figures of BOTH are rewritten in each
  `dances.figures_json` blob onto it. `rotation_gate`'s `who` becomes the
  merged move's **`pair`**, NOT its `who`: TCB's subject names the pairing
  you gate WITH, while ContraDB's `who` names the side that extends a hand
  and backs up (libfigure `figure.js:844`), so reusing the slot would
  silently reinterpret every TCB-imported gate. The legacy `gate`'s `who`,
  `whom` and `face` keep their meaning exactly (`face` was already the
  ENDING facing). Each retired move's own defaults are materialized
  explicitly for omitted params, since the merged move defaults every slot
  to `unspecified`; `beats` is carried verbatim so beat totals are
  unchanged. Recurses into `meanwhile` containers (a TCB `||` line can hold
  two gates), bounded in depth. A SANCTIONED derived-data-changing migration
  (cf. v12, v18, and the v19 wave-move rename): it schedules a derived
  rebuild, but only when a figure actually changed. The rebuild is owed
  because `dance_figures` projects the move id and `params_json` as well as
  the canonical text — `danceIdsWithFigure` queries exactly those two — so
  skipping it would leave structured search matching the RETIRED
  `rotation_gate` id and missing every migrated `gate`. Per-row and per-figure
  parse-never-throw. Chains cleanly after v19 — that step only rewrites the
  `form_a_short_wave` move id and touches no gate figure, and neither step
  adds a column or table, so schema 18/19/20 are structurally identical.
- v21 (issues #781/#782): first structural REMOVAL. Drops
  `provenance.raw_payload` and `program_provenance.raw_payload` (rebuilt via
  `TableMigration`, the portable route that doesn't require SQLite 3.35+
  `DROP COLUMN`) and the unused `snapshots` table. None fed the derived
  `dance_fts`/`dance_figures` indexes, so NO derived rebuild is required.
- v22 (issue #748): adds the derived `dance_figures.group_idx` correlation
  column so the `Then` sequence operator distinguishes a genuine before/after
  pair from two *concurrent* sides of one `meanwhile` container. Previously
  `Then` correlated on `a.idx < b.idx`, but the #590 flattener gives a
  container's sides consecutive `idx` (the `{danceId, idx}` PK forces a
  distinct idx per row), so simultaneous sides looked sequential and
  `Then(X, Y)`/`Then(Y, X)` both matched an `X while Y` container. The signal
  was absent from the index, so this needs a column, not just a query change.
  `group_idx` is shared by every row flattened from one top-level figure and
  monotonic across them; `Then` now correlates on `a.group_idx < b.group_idx`.
  Like the v2 `section` add, existing rows get the column DEFAULT (0) — wrong
  for correlation — so it schedules a derived rebuild (marker) that
  repopulates `group_idx` from `figures_json`.
- v23 (issue #780): adds `custom_field_defs.shareable` — a per-field flag
  controlling whether this field's definition and values may travel in a
  shared archive (file export, share sheet, future sync). Purely additive
  `addColumn`; existing rows get `DEFAULT 1` (shareable = true), preserving
  today's behaviour exactly — every previously-created custom field
  continues to travel in archives. Users opt out per-field via the custom
  fields settings screen. No figure index is involved; no derived rebuild
  is required.
- v24 (issue #732): adds `dances.mixer` — a boolean flag marking a dance in
  which dancers change partners each time through (a "mixer"). Modelled as a
  flag orthogonal to `formation`, not a `FormationShape` value, because the
  two are independent in the corpus (830 Caller's Box mixers, 176 of them in
  non-mixer formations; 628 mixer-named non-mixers, 589 of them Sicilian
  Circles) — see `Dance.mixer`. Purely additive `addColumn`; existing rows
  get `DEFAULT 0` (mixer = false), preserving today's behaviour exactly
  (nothing was a mixer before because the concept could not be expressed).
  No figure index is touched; no derived rebuild is required.

- v25 (issue #898): the Device Sync schema migration. Adds the sync
  timestamp triple — `updated_at`, `deleted_at`, `existence_at` — to every
  syncable kind: twenty columns over eight tables. Six tables (`settings`,
  `choreographers`, `tags`, `published_sources`, `custom_field_defs`,
  `venues`) gain all three; `dances` and `programs` already carried the
  first two and gain only `existence_at`. All are nullable, because SQLite
  cannot ADD COLUMN a NOT NULL column without a *constant* default and no
  constant is a truthful timestamp; the step back-fills every existing row
  instead. `updated_at` is stamped at migration time, while `existence_at`
  takes a single sampled constant T₀ for live rows and the row's own
  `deleted_at` for an already-tombstoned one — and specifically NOT
  `updated_at`, which would make an ordinary content edit read as an
  existence transition and resurrect records on first sync. The same step
  converts the six entity-level hard deletes (`ChoreographerRepository`,
  `TagRepository`, `PublishedSourceRepository`, `CustomFieldDefRepository`,
  `VenueRepository`, `SettingsRepository`) to tombstones, so a deletion
  leaves something a peer can learn from; the `hardDelete` import-undo paths
  stay hard, because a rollback must leave nothing to publish. No figure
  index is touched; no derived rebuild is required. Behaviour-preserving
  from the user's point of view: nothing reads `existence_at` yet.

## The delete model

Every syncable kind — dances, programs, choreographers, tags, published
sources, custom field definitions, venues and settings keys — carries three
timestamps as of schema v25 (issue #898). They answer three different questions
and are deliberately not collapsed into fewer columns:

| Column | Question it answers |
| --- | --- |
| `updated_at` | Which copy's **content** is newer. |
| `deleted_at` | **Retention**: NULL is live, non-NULL is a tombstone and starts the purge / "Recently Deleted" countdown. |
| `existence_at` | Which **existence transition** — live→deleted or deleted→live — happened later. |

`existence_at` is separate from `updated_at` because an ordinary content edit
must not read as an existence transition, and separate from `deleted_at`
because a *revival* has no `deleted_at` to order by: that column is NULL exactly
when the record is live. It is stamped causally, as
`max(localNow, currentExistenceAt + 1 tick)`, so a transition is always strictly
later than the one it supersedes even when the clock has not advanced — delete
and undo inside one second is an ordinary user action, and a tie resolves in
favour of the tombstone. One tick is one **second**, because drift stores
`DateTime` as unix seconds; a smaller increment would round away and the stamp
would tie. See `lib/src/storage/existence.dart`.

Nothing reads `existence_at` yet. It exists for Device Sync (ADR-004), which is
not implemented; the migration that adds it is deliberately behaviour-preserving.

**Deletion is a tombstone, with two named exceptions.** Deleting an entity
writes `deleted_at` and leaves the row on disk, so the deletion is something a
peer can learn from rather than an absence. The exceptions are both erasures
rather than deletions:

- The `hardDelete` / `permanent: true` paths, used only to roll back a
  just-committed import. A rollback treats the import as never having happened,
  so a tombstone would advertise the removal of a record no other device saw.
- `DanceRepository`'s orphaned-reference GC (#462), which runs inside the
  retention purge and collects reusable rows the purge left unreferenced.
  Nobody deleted those; they went away as a side effect.

**Two consequences follow from soft delete, and both are load-bearing:**

- **Reads that join through a soft-deletable parent must filter
  `parent.deleted_at IS NULL`.** A tombstone fires no FK cascade, so the
  `dance_tags`, `custom_field_values`, `dance_sources` and `dance_authors` rows
  a hard delete used to clear now outlive the delete. They are kept
  deliberately — clearing them would mean a revived tag came back with no
  dances — so the reads filter instead. `tags` is the case that bites: it is the
  only converted kind with no referential guard, so a tombstone with live join
  rows is reachable by ordinary use rather than only defensively.
- **The referential guards stay.** Soft delete does not make it safe to remove
  an entity a live record still references, and a tombstone for a still-cited
  entity could not be applied by a peer anyway.

**A tombstone still occupies its UNIQUE natural key.** `choreographers.name`,
`tags.name` and `custom_field_defs.key` are UNIQUE, and drift's upsert targets
the primary key, so re-creating a deleted entity under the same name would hit
the constraint on a row every read filters out — the name looks free and the
insert fails. The upsert therefore *adopts* a tombstoned row holding the
incoming natural key: it writes onto that row's id and returns it. A **live**
row holding the key is left alone and still raises the constraint, exactly as
before. Callers minting a fresh UUID must use the id the upsert returns.

Adoption is **not** revival, and the difference is visible to the user.
Re-writing an entity under *its own* id is "this record is back", and it keeps
its join rows — a revived tag returns with its dances. Adoption is a *new*
entity that happens to want a name a tombstone still holds, so it clears the
adopted row's join rows: before v25 the hard delete had cascaded them away and
the user got an empty tag, and keeping them would mean deleting a tag from two
hundred dances and then re-creating it silently re-tagged all two hundred.
Reusing the old row's id is an implementation detail forced by the foreign keys
and does not leak into what the user sees.

## Durability

- WAL mode; foreign keys ON; nightly-on-launch `PRAGMA quick_check`.
- All writes in transactions via repository layer; dance/program soft deletes
  purge after a configurable retention (default 30 days) via startup sweep. The
  six kinds that became soft-deletable in v25 have no retention sweep yet:
  their tombstones accumulate until Device Sync, which owns retention, adds
  one.

### Migration safety (app-layer preflight)

Before the app opens the drift database it runs a preflight
(`app/lib/src/data/migration_guard.dart`) that reads the file's persisted
`PRAGMA user_version` — via a short-lived, WAL-aware `sqlite3` connection, not
by opening drift — and compares it to the running `kCompendiumSchemaVersion`:

- **Downgrade protection.** If the file's version is *higher* than the running
  schema (it was written by a newer build), the preflight refuses to open it and
  routes to the `AppBootstrap` error screen ("created by a newer version …
  please update the app"). drift is forward-only with no `onDowngrade`, so
  migrating such a file would silently stamp the version down and risk
  corruption; a belt-and-suspenders guard in `MigrationStrategy.onUpgrade`
  (`from > to` throws) backstops any open path that bypasses the preflight.
- **Backup-before-migrate.** If an upgrade is pending (file version < running),
  the preflight first checkpoints the WAL and copies the whole SQLite file to
  `<app-documents>/db_backups/compendium.pre-v<from>-<UTC-timestamp>.sqlite.bak`,
  retaining the newest 5. This is a raw byte snapshot, distinct from the
  user-triggered JSON backup/restore (6.6/G.5): the JSON path is a *logical*
  export through the current-schema repositories and cannot run against a file
  that hasn't been migrated to that schema yet, whereas a byte copy is
  schema-agnostic and the highest-fidelity rollback for a botched migration.

  **If the snapshot fails, the preflight fails closed** (issue #442). A backup
  that cannot be written (disk full, unwritable `db_backups`, checkpoint
  failure) previously logged and migrated anyway; it now instead surfaces a
  blocking consent dialog that explains the data-loss risk and names the likely
  cause (low storage / unwritable backups folder). The user chooses **Quit**
  (the default — abort so they can free space, fix permissions, or take a manual
  backup first) or **Proceed without a backup**. Without an explicit "proceed"
  the migration is aborted (`MigrationSnapshotAborted`, rendered on a
  non-retryable `AppBootstrap` screen, mirroring the downgrade guard) so a failed
  upgrade can never become an unrecoverable one. A successful snapshot is
  unchanged — no prompt.

  **Restoring a pre-migration snapshot:** quit the app, replace the live
  `compendium.sqlite` in the app-documents directory with the chosen
  `.sqlite.bak` (renaming it back to `compendium.sqlite`), and relaunch. Because
  the snapshot is stamped at the older `user_version`, opening it with the build
  that created the backup migrates it forward again; if the migration itself was
  the problem, open it with the matching older app version instead.

