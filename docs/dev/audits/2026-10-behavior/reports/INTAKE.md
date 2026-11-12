# INTAKE audit — the first hour, and every way dances come in

## Scope & method

User story: *"I just installed this. I have 300 dances in The Caller's Box / ContraDB /
Caller's Companion / a spreadsheet / text files / a friend's share file. I want them in,
correctly, without duplicates, and I want to understand what didn't come across."*

**Read (docs):** `docs/user/imports.md` (all), `getting-started.md` (all), `sharing.md`
§ dance/program share, `programs.md` § title list / ContraDB, `settings.md` § Import
and Import defaults.

**Read (code), and traced call paths through:**
- Core: `imports/import_pipeline.dart` (all), `dedupe.dart` (verdict model and index),
  `compendium_archive_import.dart` (commit, program/venue rebuild, `_danceIdByOriginalId`),
  `generic_json_adapter.dart` (discover/fetch/parse, `externalIdFor`),
  `callers_companion_usr_import.dart` (commit, venues, `_danceIdByCcRowId`),
  `callers_companion_programs.dart` (unresolved slot), `callers_companion_user_fields.dart`,
  `share_metadata_import.dart` (`_planFields`, `_sameField`), `published_collection.dart` (skim).
- App: `screens/import_review_screen.dart` (plan, adopt, default choices, commit routing,
  result dialog, shared-bundle undo, row UI, Import and edit), `data/import_io.dart`
  (sources, caps), `data/online_search.dart` (`commitPreviewedOnlinePlan`),
  `widgets/online_import_dialogs.dart`, `screens/collection_shell.dart` and
  `dance_list_screen.dart` (online import call sites), `data/program_import_online_resolver.dart`,
  `data/contradb_program_import.dart`, `screens/contradb_program_import_screen.dart`,
  `screens/plaintext_program_import_screen.dart`, `data/archive_intake_service.dart`,
  `main.dart` (incoming file and URL, ECD prompt), `data/seed_service.dart` and
  `assets/seed/baby_rose.json`, `data/dance_reimport.dart` and `screens/dance_reimport_flow.dart`,
  `screens/settings/general_section.dart` (Import entry), `export/dance_share_bundle.dart`
  (what metadata a dance share carries), `dance_detail_screen.dart` (`_ProvenanceLine`),
  `data/collection_facets_scope.dart` (facet list).
- Tests consulted to see whether behaviour is deliberate: `app/test/data/callersbox_online_test.dart`
  and `contradb_online_test.dart` (hand-entered duplicate), `callers_companion_usr_import_test.dart`
  (re-import group).

Nothing was built or run. Every **Traced** finding below was followed through the code
path by reading it; none was executed. Each **Inferred** finding says what was not verified.

### How the intake paths compare (summary)

| Path | Review step | Duplicate handling for a dance you already have from elsewhere | Default import tags | Result / failures shown | Undo |
|---|---|---|---|---|---|
| Import… → Caller's Box / ContraDB link, file, title list | yes | "Possible match", defaults to **Skip** | yes (creates only) | dialog with counts per action + failed records | dialog button, until Done |
| Import… → `.USR` | yes | same | yes | same + programs | same (dances + programs) |
| Import… → `.ccshare`/`.json` **with** tags/fields/level/programs | yes | same | **no** | snackbar "Imported N items", failures not listed | transient snackbar |
| Same file **without** metadata | yes | same | yes | dialog | dialog |
| Same file opened from OS ("Open with"/AirDrop) | yes | same | **no** | snackbar | snackbar |
| Online search → Import (single) | no, preview only | dialog for confident match **from another archive**; a hand-entered or fuzzy match becomes a **silent duplicate** | yes | snackbar "Imported X" | **none** |
| Programs → From ContraDB | no | **always duplicates** unless the exact ContraDB id is already held | **no** | snackbar slot counts | program only; **dances stay** |
| Programs → From title list → Resolve online | no | declines identical, auto-imports variations | **no** | snackbar "Linked N titles" | program only; **dances stay**, even if you back out |
| Dance → Re-import choreography | preview | n/a | n/a | snackbar | **none** |

---

## Findings

### INTAKE-1 — Re-importing a `.USR` (or receiving a program again) replaces program slots for dances you already have with "Dance not imported (…)" notes  · **High** · Traced

**Scenario A (Caller's Companion).** A caller migrates, keeps using Caller's Companion
for a few weeks, then exports a fresh `.USR` and imports it again to pick up new sets.
imports.md also tells people to do exactly this after an incomplete file (lines
356-359: *"import it again; dances you already imported are recognised and offered as
updates"*).
1. Every previously imported dance plans as a `reimport` verdict. The review defaults
   each one to **Skip** so local edits are not overwritten
   (`import_review_screen.dart:1173-1177`).
2. Skipped rows are left out of the commit batch (`_buildCommitBatch`, `:1349-1352`).
3. The program FK map is built only from this commit's session
   (`callers_companion_usr_import.dart:928-937`). Any slot whose dance was skipped
   becomes the text `Dance not imported (Caller's Companion dance #123)`
   (`callers_companion_programs.dart:69-87`).
4. Each existing program is matched by `(callersCompanion, zk_Set_ID)` and **updated
   in place** with those rebuilt slots (`callers_companion_usr_import.dart:335-365`,
   `_rebuildProgramWithId` `slots: src.slots` at `:909`).

**Result:** with the defaults accepted, every existing program loses its links to dances
that are still in the collection. Each such slot shows an opaque id with no title. The
programs are not shown in the review, so the user never sees this coming. The only
warning is "Program notes: N" in the result dialog. Undo works until **Done** is
pressed.

**Scenario B (shared programs).** A friend sends program A (dance X is new, so you
import it). Later they send program B, which also uses X. X plans as `reimport`, which
defaults to **Skip**. Program B's slot becomes `Dance not imported (<sender's uuid>)`
(`compendium_archive_import.dart:104-124`, `_danceIdByOriginalId` `:1058-1080`).
Re-receiving an **updated program A** also overwrites your copy of A in place, including
any slot notes or reorders you made (`:626-672`). That overwrite is never shown or asked
about.

**Scenario C.** Choosing **Import and edit** on a `.USR` row commits that dance alone
(`:1404-1446`), and the later batch excludes the row (`:1348`). The dance's slots in its
Caller's Companion sets then become placeholders too. Shared bundles hide Import and edit
for exactly this reason (`:3523-3539`); `.USR` does not.

**Why it happens:** the core API treats `reimport` as act-automatically, and the core tests
re-import that way (`callers_companion_usr_import_test.dart:637-679` never checks slot
links). The UI defaults the same verdict to Skip, and nothing joins those two layers. No
mode exists that keeps the local dance as it is but still links the slot to it.
**Decision:** a skipped `reimport`, or a confident match, should still resolve slots to
the existing dance (the target id is already on the verdict). Programs updated in place
should be listed in the review.

### INTAKE-2 — A friend's share file is refused outright if a custom field with the same key is set up even slightly differently  · **High** · Traced

**Scenario.** Two callers both migrated from Caller's Companion, so both have a custom
field keyed `card`. The receiver once toggled **Show in list** for it, or turned off
**Include in sharing** to keep their copy private. The sender shares a dance or program.
The receiver reviews it and presses Import, and sees only *"Couldn't complete the import."*

`_sameField` (`share_metadata_import.dart:406-416`) demands an exact match on label,
type, choices, **showInList**, **searchable** and **shareable**. Any mismatch throws
(`:343-348`) during commit (`compendium_archive_import.dart:429`). The whole import is
rolled back, and the generic `importReviewImportError` snackbar is shown
(`import_review_screen.dart:1652-1664`). Three of those properties are the receiver's own
display or privacy preferences, not what the field means. The conflict is not detected at
plan time, so the user reviews every row first and only then fails. sharing.md:76-78
says the import "is refused", but the app never tells the user that this is why, or which
field caused it.
**Decision:** compare only key and type (and choices), or map onto the receiver's field,
and surface any conflict during review.

### INTAKE-3 — Importing a ContraDB program silently duplicates dances you already have  · **High** · Traced

**Scenario.** A caller has 300 dances from The Caller's Box (or typed by hand), then uses
**Programs → From ContraDB** for a 12-dance evening. Each dance is imported through
`contraDb.import(..., ambiguousResolution: DedupeResolution.duplicate())`
(`contradb_program_import.dart:146-156`). A supplied resolution skips both the confident
match check and the possible-match check in `commitPreviewedOnlinePlan`
(`online_search.dart:353`, `:414`), and the record commits as a new dance (`:441-456`).
Only an exact ContraDB-id match (`reimport`) is reused. Result: a second "Chorus Jig" for
every dance the caller already owned from another source, with no prompt. programs.md:116
says each dance "is matched to your collection or imported for you". The plaintext program
path enforces the opposite rule: identical dances are declined, never duplicated
unattended (`program_import_online_resolver.dart:259-263`, "#685 … must never be silently
created"). The ContraDB path's comment calls this "pre-#797 behaviour preserved by
construction".

### INTAKE-4 — Program imports write dances outside review and outside Undo  · **High** · Traced

- **Programs → From title list → Resolve unmatched online** imports dances **at that
  moment**, before the user presses Import (`plaintext_program_import_screen.dart:177-259`,
  calling `_attemptSource` → `pipeline.commit` / `service.import`). Backing out of the
  screen without creating the program leaves those dances in the collection. programs.md:63
  promises "a live preview before anything is saved".
- **Undo** on both program imports runs only `programs.hardDelete([id])`
  (`plaintext_program_import_screen.dart:368-370`, `contradb_program_import_screen.dart:466-468`).
  Every dance the import created stays. programs.md:118 promises "the same **Undo**
  safety net as every other import".
- A ContraDB program resolves and imports every dance *before* the program write
  (`contradb_program_import_screen.dart:366-424`). If that write fails, the user sees
  "couldn't create program" while the dances remain.
- The program title-list path looks up with `requireFigures: false`
  (`program_import_online_resolver.dart:202-213`), so it can import a Caller's Box dance
  that has **no figures**, unattended. The Collection title-list import deliberately
  refuses these (imports.md:204-207).
- None of these paths applies default import tags (documented in settings.md:396-398, so
  a tagging workflow cannot find these dances).

### INTAKE-5 — Online single-dance import: silent duplicates where the batch review would ask, and no Undo at all  · **Medium** · Traced (pinned by tests)

- **Silent duplicate of a hand-entered dance.** You typed "Chorus Jig" yourself, then find
  it in online search and tap Import. Title, author and figures all match, but your dance
  has no provenance, so the "different source" dialog is skipped
  (`online_search.dart:389-405`). The plan then commits as `duplicate()` (`:441-443`). This
  is pinned as intended by `callersbox_online_test.dart:1292-1313` ("falls through to
  duplicate (no prompt)"). The same record in the batch review shows **Possible match**,
  defaulting to Skip.
- Any **non-confident** fuzzy candidate (for example "Rory O'More" against "Rory O More",
  or an author spelled differently) also becomes a silent duplicate on this path. The batch
  review marks it.
- **No Undo.** The result is a plain snackbar (`collection_shell.dart:464-469`,
  `onlineImportMessage` → "Imported X"). That includes the destructive **Same dance
  (update existing)**, which replaces title, figures, notes, tags and rating
  (`online_import_dialogs.dart:79-93`). The confirmation reads the same "Imported X" as a
  plain create.

**Decision:** for a hand-entered match, show the cross-source dialog with neutral
wording, and offer Undo on the snackbar.

### INTAKE-6 — The same share file goes through two different import engines depending on how it arrived and what it carries  · **Medium** · Traced

Routing is decided by content, not by the source the user picked
(`import_review_screen.dart:382-418`, `:1531`):
- A dance file with **no** tags, custom fields, difficulty level or programs, picked via
  Settings → Import…, runs the generic pipeline. Default import tags are applied, and the
  result dialog shows Created / Re-imported / Linked / Skipped and **each failed record**,
  with Undo until Done (`:1629-1650`, `_showResult` `:2130-2321`).
- The same dance after the sender gave it a **level or a tag** (the share always carries
  them: `dance_share_bundle.dart:30-87`), **or any file opened via AirDrop / "Open with"**
  (`main.dart:1166-1176` always seeds `sharedBundle`), runs `CompendiumArchiveImporter`
  instead. Default import tags are **not** applied (`:1932-1953`, no `defaultTagIds`).
  Import and edit is hidden. The outcome is a transient snackbar *"Imported N items"*
  whose N sums dances, programs, tags, sources, fields and figures, and counts
  re-imported or linked dances as "imported" (`:2081-2094`). **Record failures are not
  shown at all.**

settings.md:392-395 says default tags apply to dances you import "from the import
screen". imports.md:263-269 says opening the file directly brings you to "the same review
screen a manual import uses". In both cases the user sees different behaviour depending on
the route and the file's contents, with no visible reason.

### INTAKE-7 — Batch "Re-import onto…" (pick up a correction) erases the caller's own metadata; the narrow choreography refresh does not  · **Medium** · Traced · **Decision**

imports.md:549-555 presents Re-import as the way to "pick up a correction an archive has
made". The commit rebuilds the dance wholesale from the draft
(`import_pipeline.dart:821-835`, `_rebuildWithIdentity` `:1291-1340`). Caller's Box and
ContraDB drafts carry no rating, no tags and no links (only `callingNotes:` is set:
`callersbox_adapter.dart:256`, `contradb_html_adapter.dart:234`). So a correction re-import
wipes:
- your rating;
- **all tags, including the default import tags the app added when it first imported the
  dance** (re-imports never re-add them, `:604-609`);
- video and related-dance links (the other dance keeps its one-sided reciprocal link);
- calling notes, walkthrough and status.

Only custom fields survive. The review shows no diff for re-import rows; `_confidentDiffs`
is computed only for confident ambiguous rows (`import_review_screen.dart:505-513`). The
overwrite banner gives only a count. **Re-import choreography** on the detail screen, by
contrast, replaces only figures, formation and progression (`dance_reimport.dart:33-50`).
Two features with the same name and the same purpose have opposite blast radii.

**Decision:** batch re-import should use the choreography-only update (or offer it as the
default), or at least show a diff and keep tags, rating and links.

### INTAKE-8 — "What came from where" is not recorded durably, and there is nowhere to see it  · **Medium** · Traced

- **One provenance per dance, overwritten by a link.** **Same dance — replace** and
  **Same dance (update existing)** stamp the incoming source onto the existing dance
  (`import_pipeline.dart:733, 826-834`). Link a ContraDB record onto a Caller's Box dance
  and the Caller's Box key is gone. The next Caller's Box import of that dance is no
  longer "already in your collection" (exact key `online_search.dart:328-337`); it falls
  through to fuzzy matching.
- **A received dance loses its real origin and licence.** A dance the sender got from
  Caller's Box #457 is stored as `json` / `callersbox:457`
  (`generic_json_adapter.dart:166-174`). The `RawRecord` carries no permission or licence
  (`:206-220`), so the receiver's detail shows *"via JSON import"* with no Caller's Box
  licence (`dance_detail_screen.dart:1462-1491`). **Re-import choreography** never records
  the source it pulled from (`dance_reimport.dart:33-50`), so a hand-typed dance refreshed
  from Caller's Box still has no provenance. Under INTAKE-5 that makes it a silent
  duplicate target.
- A published-collection dance shows *"via Published collections"* without naming the
  collection or its version, although imports.md:160-161 says the version is recorded "so
  you can see where the dances came from".
- **No collection-level view.** The Collection facets (`collection_facets_scope.dart:12-24`)
  have no import-source facet and no "has figures the app couldn't read" facet. After a
  300-dance `.USR` import, the only aggregate the user ever sees is the result dialog's
  counts. **Re-check custom figures** lists only dances whose gaps can *now* be upgraded.
  imports.md:39-44 tells users to "find the lines worth tidying up", but they can only do
  that by opening dances one at a time.

### INTAKE-9 — "Import and edit" on a Caller's Companion row fails for any dance that has custom-column values  · **Medium** · Traced (not executed)

The `.USR` mapper writes placeholder field ids (`cc-user-field:<key>:<label>`) that only
`CallersCompanionUsrImporter.commit` resolves (`callers_companion_user_fields.dart:7-20`,
`callers_companion_usr_import.dart:268-283`). **Import and edit** sends the row through
the plain `ImportPipeline` instead, "even for the Caller's Companion `.USR` byte source"
(`import_review_screen.dart:1429-1446`). The repository refuses the placeholder ("unknown
custom field", `dance_repository.dart:831`). The pipeline records that as a per-record
error, and the user sees *"Couldn't import that dance to edit."* (`:1452-1460`). The button
is shown on every `.USR` row (`:3535-3539`). Caller's Companion users who defined custom
columns, which imports.md:328-339 highlights, will hit this on most rows. No app test
combines `.USR` user fields with Import and edit.

### INTAKE-10 — `.USR` set locations never match an existing venue, so a second import creates duplicate venues  · **Medium** · Traced

imports.md:345-348: set locations become venues, *"matching one you already have when it is
clearly the same place"*. A `.USR` location is a bare name, and `venueFingerprint` needs a
name plus an address or city, so the cross-import match is structurally unreachable. The
code says so itself (`callers_companion_usr_import.dart:220-226`, `:389-398`). Matching
happens only within one import (`venueIdByLocationKey`, "this-commit-only", `:941-952`).
A later `.USR` import that brings a **new** set at "Grange Hall" mints a second
"Grange Hall". So does any set at a hall the caller already entered by hand. Only programs
that already had a venue are protected (`:368`).

### INTAKE-11 — The first hour does not match getting-started.md  · **Medium** · Traced

- getting-started.md:224-227 says every import lands in a review queue where *"You get a
  side-by-side look at the original and how the app understood it"*. A review row shows
  only title, a structured-count chip, author, formation, source and issue notes
  (`import_review_screen.dart:3467-3603`). No figures are shown and no original text,
  and a row cannot be opened to inspect it without committing it (Import and edit). For
  a 300-dance migration, "look before you keep" is not possible.
- The "Bring in dances you already have" section (`:213-228`) names Caller's Box, ContraDB
  and Compendium files, but **not Caller's Companion**, the main migration path, which has
  its own section in imports.md. "From Collection, choose **Import**" does not match the
  button name used elsewhere (**Import dances**).
- The previously reported "collection starts empty" mismatch has a behavioural side; see
  INTAKE-12.

### INTAKE-12 — The first-run seed dance interferes with a Caller's Companion migration  · **Low** · Inferred

The seed is "The Baby Rose" by David Kaynor, with provenance ContraDB #8, calling notes
*"Imported from ContraDB."*, and created/imported 2020-01-01 (`app/assets/seed/baby_rose.json`;
`seed_service.dart:55-69`). A migrating caller whose library holds Baby Rose by Kaynor gets
a confident ambiguous row, defaulting to **Skip**. Accepting the defaults leaves the
caller's own copy (notes, rating, custom columns) out, and their sets that use it get
placeholder slots (INTAKE-1 mechanism). The seed is not marked as a sample, so the user
cannot tell it apart from their own data. *Not verified:* that a real `.USR` author string
for Kaynor tokenizes to an overlapping author set (the confident gate).

### INTAKE-13 — The two "paste a list of titles" features follow different rules  · **Low** · Traced

Collection → Import → **a list of titles** searches only The Caller's Box, requires
figures, and reviews everything before commit (`title_list_import.dart:586-592`;
imports.md:171-224). Programs → **From title list** searches Caller's Box then ContraDB,
does not require figures, and auto-imports (`program_import_online_resolver.dart:196-298`).
A caller pasting the same list into both gets different dances. See also INTAKE-4.

### INTAKE-14 — Settings → Import… and Collection → Import dances are different screens  · **Low** · Traced

`general_section.dart:519-528` opens the review screen without `publishedCollectionService`,
so the published-collection source is missing there. `collection_shell.dart:200-204`
includes it. imports.md:177-178 treats the two entry points as interchangeable.

### INTAKE-15 — The ECD conversion is a launch-time prompt, undocumented and without undo  · **Low** · Traced

`_maybeShowEcdConvertPrompt` runs only after cold start (`main.dart:2159-2183`, `:2318-2350`),
not after the import that brought in ECD-tagged dances. It rewrites form and removes the
tag in bulk with no Undo, and docs/user does not mention it (only authoring.md:426 lists
the Type).

### INTAKE-16 — The optional post-`.USR` steps have inconsistent undo  · **Low** · Traced

After the result dialog (whose Undo disappears on Done), shorthand seeding reports with a
plain snackbar and **no Undo** (`import_review_screen.dart:1751-1775`). The glossary-terms
step that follows offers Undo (`:1890-1901`), and so does shared-figure adoption.

---

## Cross-cutting patterns

1. **Each intake path has its own commit engine and policy.** There is the review
   pipeline, the archive importer, the `.USR` importer, `commitPreviewedOnlinePlan` and
   two unattended program resolvers. Default tags, failure reporting, undo, and what
   happens to an existing match all differ between them (see the table above;
   INTAKE-3, 4, 5, 6, 13). The docs describe one feature ("It works the same whichever
   source you pick", imports.md:451-452). Code comments describe several deliberate
   per-path rules. Nobody owns the matrix.
2. **The core and the UI disagree about what `reimport` means.** The core acts on it
   automatically, and its tests and program rebuilders assume that. The UI defaults it to
   Skip. Everything downstream that keys off "what this commit wrote" (program slot
   mapping, related-dance links, the variation link-back) silently degrades
   (INTAKE-1, 9).
3. **Undo is four different things.** It can be a dialog button until Done, a transient
   snackbar, a snackbar that removes only part of what was written (program imports), or
   nothing at all (online single import, Re-import choreography, shorthand seeding).
4. **Provenance is single-valued and last-writer-wins**, so the dedupe and "already in
   your collection" features weaken over time as people link, share and refresh dances
   (INTAKE-5, 8).

## Checked and fine

- Title-list import: Cancel stops lookups, nothing is written, and the 100-title cap
  refuses the paste whole (`import_review_screen.dart:887-947`).
- Large `.USR` planning yields to the UI and reports progress; leaving during planning
  writes nothing. Commit blocks back navigation and shows `done/total` (`:2329-2353`, `:1492-1511`).
- Partial failure on the review path: plan-time errors are listed above the rows
  (`_buildBatchErrors`), and commit-time failures are listed in the result dialog. One bad
  record never aborts the batch (`import_pipeline.dart:362-454`, `:845-874`).
- The same external id twice in one batch is dropped with a note (`import_pipeline.dart:424-446`).
- Figureless Caller's Box records are never offered **Same dance**, in review or online
  (`online_search.dart:339-346`, `online_import_dialogs.dart:13-15`).
- Newer-schema files show one batch warning; an incomplete `.USR` shows the "incomplete"
  warning (`generic_json_adapter.dart:127-138`).
- Default tags are added only to dances an import creates, consistently on the review,
  online, `.USR` and published paths; that rule is documented.
- Share intake validates size and format before any UI, and writes nothing on rejection
  (`archive_intake_service.dart:154-238`).
- Shared tags, sources and fields are merged by canonical name (`share_metadata_import.dart:220-260`),
  except for the custom-field strictness in INTAKE-2.

## Out of scope but noticed

- Copy: the provenance label "via JSON import" is developer jargon for a dance received
  from another caller (`danceProvenanceSourceJson`).
- Sync: only the shared-bundle commit is wrapped in `SyncWriterLifecycleScope.runWrite`.
  The review pipeline, `.USR` and published commits are not (`import_review_screen.dart:1942-1953`
  vs `:1559-1640`). Not checked whether that matters.
- Storage: dedupe uses live dances only, so re-importing a dance that sits in the trash
  creates a second dance with the same provenance key. Restoring the trashed one then
  leaves two (Inferred).
- A full **backup** file opened via AirDrop/"Open with" is merged through the share path
  rather than offered as a Restore (`main.dart:1143-1177`); the backup auditor may want
  to confirm that is intended.
