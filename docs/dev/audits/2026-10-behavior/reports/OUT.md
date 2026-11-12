# OUT audit: everything that leaves the app, and whether it comes back intact

Auditor key: `OUT`. Date: 2026-10-27. Read-only; the only thing executed was a
throwaway `dart test` probe against a **scratchpad copy** of `compendium_core`
(nothing in the repo was touched).

## Scope & method

**User guides read:** `docs/user/sharing.md` (all), `backup-portability.md`
(all), `programs.md` §Event details, §Matrix, §Print/export/email, §Track what
you have called; `settings.md` §Library/Accessibility/Formats; `imports.md`
§dedupe; `faq.md` (export/backup answers).

**Code traced:**
- Egress: `app/lib/src/export/` (dance_pdf, program_pdf, program_matrix_pdf,
  dance_share_bundle, program_share_bundle, share_file, share_sanitization),
  `widgets/dance_export_actions.dart`, `dance_export_menu.dart`,
  `program_export_menu.dart`, `export_guard.dart`; call sites in
  `dance_detail_screen.dart`, `program_summary_screen.dart`,
  `program_editor_screen.dart` (`_exportMatrixPdf`).
- Core renderers: `compendium_core/lib/src/export/` (dance_text,
  dance_card_content, dance_card_fields, dance_share_fields, program_text).
- Serialization: `serialization/archive_codec.dart`,
  `archive_entity_codec.dart`, `compendium_archive.dart`
  (`requiredSchemaVersion`), `archive_service.dart` (`ArchiveExporter`).
- Re-entry: `imports/generic_json_adapter.dart`,
  `compendium_archive_import.dart` (`buildArchivePrograms`, `_remapDance`),
  `import_pipeline.dart` (`_rebuildWithIdentity`, `autoResolveAmbiguous`),
  `share_metadata_import.dart`, `dance_repository.dart` (`_upsert` link
  writes), `storage/tables.dart` (`DanceLinks`), `import_review_screen.dart`
  (`_refreshPickedBundle`, `_commitSharedBundle`, `_showSharedBundleUndo`).
- Backup: `data/backup_service.dart`, `backup_document.dart` (versioning).
- Calling history: `program_repository.dart` (`_programDerivedRows`,
  `_callingHistoryRows`), `data/calling_history_caller_filter.dart`.
- Privacy registry entries for every program/dance field that travels.

**Field-coverage matrix** (✓ included, — absent, ✗ deliberately stripped,
⚠ included but see finding):

| Field | Dance text / PDF | Program text | Program PDF | Matrix PDF | `.ccshare` / `.json` | Survives share re-import | Backup → restore |
|---|---|---|---|---|---|---|---|
| Title, figures (dialect-rendered) | ✓ | title only | title; figures in appendix | moves only | ✓ | ✓ | ✓ |
| Authors | ✓ (picker) | ✓ (picker) | ✓ | — | ✓ name/website/notes; ✗ email/location/deceased | ✓ (by name) | ✓ |
| Formation / level / mixer / status / phrase | ✓ (picker) | — | appendix | formation | ✓ | ✓ | ✓ |
| Calling notes / walkthrough / tunes | ✓ (picker; tunes off) | — | appendix (only dances with figures, OUT-10) | — | ✓ | ✓ | ✓ |
| Hook, composed/revised date | — (OUT-6) | — | — | — | ✓ | ✓ | ✓ |
| Source citations | — (OUT-6) | — | — | — | ✓ | ✓ (remapped) | ✓ |
| Links (video / source / related dance) | — (OUT-6) | — | — | — | ✓ | **✗ the whole dance fails (OUT-1)** | ✓ |
| Tags | — | — | — | — | ✓ | ✓ (remapped) | ✓ (+ deleted tags) |
| Custom fields | — (OUT-6) | — | — | — | ✓ shareable only | ✓ (remapped) | ✓ all |
| Rating | — | — | — | — | ⚠ | ⚠ becomes the recipient's (OUT-2) | ✓ |
| Program event details (band, caller, level, notes) | n/a | ✓ | ✓ | date/venue | ✓ | ✓ | ✓ |
| Event date | n/a | ⚠ ignores Date format (OUT-3) | ⚠ same | ⚠ same | ISO | ✓ | ✓ |
| Venue name / descriptive fields | n/a | name | ✓ (not notes) | name | ✓ | ✓ (name-only record) | ✓ |
| Venue address | n/a | ✗ | ✗ | ✗ | ✗ | — | ✓ |
| Venue contacts | n/a | ✗ | opt-in | ✗ | opt-in | ✓ if ticked | ✓ |
| Pay | n/a | — | — | — | ⚠ | ⚠ becomes the recipient's (OUT-2) | ⚠ lost on older build (OUT-5) |
| Perform dialect (`dialectName`) | n/a | — | — | — | ⚠ | ⚠ (OUT-2) | ⚠ lost on older build (OUT-5) |
| Slot performed marks / program status | n/a | `[performed]` | `[performed]` | — | ⚠ | ⚠ feeds the recipient's calling history (OUT-2) | ✓ |
| Slot linked to a dance in the Trash | n/a | "Unknown dance" | same | — | dance dropped | English placeholder with a raw id (OUT-7) | ✓ |
| User figures used | rendered | — | rendered | own column | ✓ (no notes) | offered | ✓ whole glossary |
| Settings, dialects, themes, shorthands, snippets, formation colours | — | — | — | — | — | — | ✓ |
| Published-collection import history | — | — | — | — | — | — | — (not carried; see "Out of scope") |

## Findings

### OUT-1 — High — A shared dance that has a link fails to import, and the recipient is told the import succeeded
**Confidence: Traced, and reproduced** by running the importer against an
in-memory database.

**Scenario A (related dance).** A caller imported "Petronella (variant)" and
chose **Import as a variation**. That choice adds a related-dance link by
default (`import_pipeline.dart:737-760`). They then use **Share dance file**,
or share a program that contains the dance. The friend opens the file. That
dance never arrives. In a program file, its slot becomes the placeholder
`Dance not imported (<sender's uuid>)`. The success message still reads
"Imported N items." with **Undo**. When nothing else imported, N is 0 and the
message reads "Import complete.".

**Scenario B (any link, round trip).** A dance that has a video or source link
is shared to a friend. The friend edits or retitles it and sends it back, or
the recipient chooses **Import a second copy** of a dance they received
earlier. The import fails, because the dance-link id already exists in that
library.

**Why.**
- The share codec writes each link's own `id` and the sender's `targetDanceId`
  verbatim (`archive_entity_codec.dart:134-137, 180-191`).
- On import, `_remapDance` gives tags, sources and custom fields receiver ids,
  but not links (`compendium_archive_import.dart:924-942`).
- `_rebuildWithIdentity` copies `links: src.links` (`import_pipeline.dart:1333`).
- `DanceRepository._upsert` inserts `link.id` and `link.targetDanceId` as given
  (`dance_repository.dart:755-774`).
- `dance_links.target_dance_id` is a foreign key to `dances`
  (`tables.dart` `DanceLinks`), and `PRAGMA foreign_keys = ON`
  (`database.dart:857`).

**The failure is then swallowed.** It is recorded in `CommittedRecord.error`,
not thrown. `_showSharedBundleUndo` counts only `r.succeeded` records and never
reports the failed ones (`import_review_screen.dart:2081-2095`).

**Probe output** (scratchpad copy, `test/out_probe_test.dart`):
- Single dance with a related link: `CommitAction.create err=… FOREIGN KEY constraint failed (code 787)`, and 0 dances in the database.
- Program carrying **both** linked dances: `dances: [Beta]`; slots: `[Dance not imported (sender-a), <beta id>]`. The link fails even when its target is in the same file, because the target gets a new id.
- Round trip of a dance with a video link: `UNIQUE constraint failed: dance_links.id (code 1555)`.

Backup restore is not affected: it keeps the original ids and defers foreign
keys (`archive_service.dart:133`).

**This breaks a documented promise.** `sharing.md:210-211` says "Either file
imports back into the app the same way, so nothing is lost".

**Fix direction.**
1. Mint fresh link ids on import.
2. Remap `targetDanceId` through the original→committed id map when the target
   is in the file. Otherwise drop the related link, or turn it into a label.
3. Show failed records in the shared-import result.

---

### OUT-2 — High (**Decision**) — A received program goes into the recipient's calling history, with the sender's pay and the sender's star ratings
**Confidence: Traced, and reproduced.**

**Scenario.** A caller shares last Saturday's performed program with a friend
("here's what I called"). The friend imports it, and on their device:
- Every dance in it now shows **called ×1** and a **last called** date of last
  Saturday. Collection's last-called sort and the dance's Calling history list
  it as if the friend had called it.
- The program shows **Performed**, with the sender's **Pay** (for example
  250 USD) and the sender's **Perform dialect** name.
- Each newly created dance carries the sender's personal **star rating**
  (authoring.md:479 calls it "Your own star rating"). It now matches the
  friend's **Minimum rating** filter.

**Why.**
- `buildArchivePrograms` copies `performedAt`, `status`, `payMinorUnits`,
  `payCurrency` and `dialectName` verbatim (`compendium_archive_import.dart:71-74, 140-171`).
- `_rebuildWithIdentity` keeps `rating` and `status` (`import_pipeline.dart:1313-1317`).
- `lastCalledByDance` is `MAX(program_slots.performed_at)` over every
  non-deleted program, and counts include all slots
  (`program_repository.dart:980-993`).
- With the default settings, the caller filter is `null`, so every program
  counts (`calling_history_caller_filter.dart:23-38`; `programs.md:428-441`).

**Probe:** after the import, `lastCalled = {<dance>: 2026-10-24 20:00Z}`,
`pay=25000`, `status=performed`.

**What the docs say.** `sharing.md:149` says Pay travels. Nothing says that
performed marks, status, ratings or the Perform dialect travel, or that they
feed calling history.

**Why the classification allows it.** The registry note for `programs.pay_*`
justifies `shareable` only as "follows the caller to their other devices and
into their own archive export" (`field_registry.dart:575-585`). That reasoning
does not cover sending it to another person. Venue contacts get a consent
dialog; the caller's own income gets none.

**Options:**
- **(a)** Strip these fields in `ArchiveSerializationMode.share`: rating,
  `performedAt`, program status, pay, `dialectName`. They would keep
  travelling by backup and sync.
- **(b)** Keep them in the file, but reset them on import ("received programs
  arrive as Draft, unperformed").
- **(c)** Ask on import ("Import as my calling history / as a plan").
- **(d)** Document the current behaviour.

(a) or (b) matches what a caller expects. Either needs a maintainer ruling,
because `buildArchivePrograms` states verbatim fidelity as intended.

---

### OUT-3 — Medium — Printed and emailed set lists ignore the Date format setting
**Confidence: Traced.**

**Scenario.** A UK caller sets **Date format → Day/month/year**. The program
list and the program summary show "15/07/2026". The emailed set list, the
program PDF and the matrix PDF print "Jul 15, 2026" (or whatever the platform
locale's medium date is).

**Evidence.**
- Exports call `MaterialLocalizations.formatMediumDate` directly:
  `program_export_menu.dart:133-134` (text) and `:541` (PDF), and
  `program_editor_screen.dart:3330` (matrix).
- The screens call `formatEventDate(date, DateFormatScope.of(context), …)`:
  `program_summary_screen.dart:694-699`, `program_list_tile.dart:48-50`,
  `regional_formats.dart:190-201`.
- `settings.md:298-300` says the choice "controls how program event dates
  appear".

**Fix.** Pass `formatEventDate` with the scope's setting into all three
`formatDate:` parameters.

---

### OUT-4 — Medium — Every PDF is A4, whatever paper the user picks
**Confidence:** Traced that the paper format is ignored. Inferred what the
printer then does (not rendered).

**Scenario.** A US caller prints a set list to a Letter printer, or chooses
"Save as PDF". The app always lays out A4: the PDF is taller than Letter and
gets shrunk to about 94% or clipped at the bottom.

**Evidence.**
- All three `Printing.layoutPdf` call sites drop the dialog's page format:
  `onLayout: (format) => build…Pdf(…)` with no `pageFormat:` argument
  (`dance_export_actions.dart:229`, `program_export_menu.dart:536`,
  `program_editor_screen.dart:3322`).
- The builders default to `PdfPageFormat.a4` (`dance_pdf.dart:52`,
  `program_pdf.dart:178`). The matrix hard-codes `PdfPageFormat.a4.landscape`
  (`program_matrix_pdf.dart:94`).
- Most contra callers are in North America.

**Fix.** Thread `format` through, using `format.landscape` for the matrix.

---

### OUT-5 — Medium — A backup restored on an older app version silently drops Pay and Perform dialect
**Confidence:** Traced how the version is stamped. Inferred the older reader's
behaviour from the codec's "unknown keys ignored" contract
(`archive_codec.dart:38-40`).

**Scenario.** A caller on 0.6.0 or later backs up and gets a new laptop. They
install a 0.5.2–0.5.4 build (an old installer, or a store that lags) and
restore. The restore reports success. Every program's Pay and Perform dialect
are gone.

**Why.**
- These keys are written "only when set" with no schema bump
  (`archive_entity_codec.dart:234-241`). `requiredSchemaVersion` never accounts
  for them (`compendium_archive.dart:147-177`).
- A backup therefore stamps core v3 (v7 only when deleted tags exist) and
  `backupVersion` 1 when there is no glossary data. 0.5.2 already reads v7
  (CHANGELOG:434). Pay and Perform dialect arrived in 0.6.0 (CHANGELOG:265-266).

**What this contradicts.**
- `backup-portability.md:124-128` promises that a file from "a newer version of
  the app that this one can't read" is refused before anything is touched.
- `backup_document.dart:20-22` states the design rule: "an older build refuses
  to replace-restore one that has them rather than silently dropping them".

**Fix.** Stamp a new archive version when any program has pay or a dialect,
following the existing conditional-bump pattern. Then audit the other
"only when set" keys.

---

### OUT-6 — Low (**Decision**) — The printed or emailed dance card cannot show where the dance came from
**Confidence: Traced.**

**Scenario.** A caller prints a dance card for a workshop handout. They have
recorded "Give-and-Take, p. 12", a video link, the composed date, the hook,
and a custom field marked **Include in sharing** ("Teaching level: 2").

**What happens.** None of these can appear on the PDF or the text card.
`DanceShareField` offers only authors, formation, level, mixer, status, phrase,
calling notes, walkthrough and tunes (`dance_share_fields.dart:21-48`), and
`DanceCardContent` builds nothing else (`dance_card_content.dart:51-77`).

**Inconsistent with the file path.** The `.ccshare` file carries all of these.
"Include in sharing" on a custom field governs only files, which a user is
unlikely to guess.

**Options.** Add source citation, hook and links (and possibly shareable custom
fields) to the picker, or document that the card is choreography-only.

---

### OUT-7 — Low — A program slot whose dance is in the Trash exports badly
**Confidence:** Traced on the export side. Inferred for the on-screen rendering.

**Scenario.** A caller trashes a dance that is still in a program, then exports
the program.
- **Set list text and PDF** print "Unknown dance". The summary loads dances
  with `getById` and its default `includeDeleted: false`
  (`program_summary_screen.dart:474`).
- **`.ccshare`** silently omits the dance (`program_share_bundle.dart:118-123`).
- **On the recipient's device**, the slot becomes the stored, English-only
  text `Dance not imported (3f2a…uuid)` (`compendium_archive_import.dart:111`,
  `program_slot_note.dart:9`).

**Expected.** Either the export warns, or it includes the dance (it is still
restorable).

---

### OUT-8 — Low — File names follow no single convention, and some are lossy
**Confidence: Traced.**
- **Backup:** `callers-compendium-backup-YYYY-MM-DD.json`, dated in **UTC**
  (`backup_service.dart:805-808`). A backup taken at 8 pm Pacific on 15 July
  is named the 16th.
- **Share and JSON files:** `replaceUnsafeNameChars(title)`
  (`dance_share_bundle.dart:98-105`, `program_share_bundle.dart:269-280`).
  - The safe set is ASCII only, so "Contredanse à la française" becomes
    `Contredanse___la_fran_aise.ccshare`.
  - An all-Japanese title becomes `dance.ccshare` or `program.ccshare`. The PDFs
    print that same Japanese text correctly (sharing.md:35).
  - Trailing `_` is not stripped ("Ain't She Sweet?" becomes
    `Ain_t_She_Sweet_.ccshare`). The PDF job name, via `sanitizeExportName`,
    does strip it.
- **No date in program file names**, so weekly "Saturday Contra" exports all
  get the same name.
- **The matrix PDF's job name is the program title**
  (`program_editor_screen.dart:3321`), identical to the set-list PDF's
  (`program_export_menu.dart:535`). Saving both into one folder collides.

---

### OUT-9 — Low — PDFs have no page numbers or running header, and the matrix header row does not repeat
**Confidence:** Traced. Readability is Inferred (not rendered).

- The three PDFs do share one visual system: the same theme loader, a 24 pt
  bold `pw.Header` title and 12 pt meta lines.
- None has a footer, page "x of y", or a running title on later pages
  (`dance_pdf.dart:71-83`, `program_pdf.dart:231-290`,
  `program_matrix_pdf.dart:93-130`). A set list with its figures appendix
  easily runs to 3–6 loose, unnumbered pages.
- The matrix is a single `pw.Table` with no header repetition
  (`program_matrix_pdf.dart:215-219`). Every move column is forced into one
  landscape A4 width (sharing.md:231-232 says hidden columns still print), so a
  wide evening's 9 pt headers will be very narrow.

---

### OUT-10 — Low — "Set list and figures" silently skips dances that have no structured figures
**Confidence: Traced.**

**Scenario.** A dance was imported from The Caller's Box without figures, or
has only a walkthrough and calling notes. It gets no card in the text or the
PDF appendix (`program_export_menu.dart:295`, `program_pdf.dart:322`). When no
dance has figures, the prompt is skipped, so walkthroughs and notes cannot be
exported at all (`program_export_menu.dart:231-233`).

**What the docs say.** `sharing.md:104-107` says "appends a full card for each
dance, showing every dance field you've selected".

## Cross-cutting patterns

1. **"Shareable" mixes up two different egresses.** The registry has no class
   for "travels to my own devices and backups, but not to another person".
   Personal usage data (rating, performed marks, program status, pay, Perform
   dialect) is therefore `shareable`. Share mode reuses the full entity
   serializer, minus a short list of redactions, and the importer re-applies
   it as the recipient's own data (OUT-2). Each new personal field will repeat
   this unless share mode becomes an allow-list.
2. **Importing sender ids is inconsistent.** Authors, tags, sources, custom
   fields, difficulty levels, venues, programs and slots all get receiver ids
   or remaps. Dance links do not (OUT-1). Of the ids a dance carries, links
   are the only ones the importer passes through unmapped.
3. **Exports read user settings at each call site, with nothing shared.**
   Dialect, discouraged terms and share fields are threaded in correctly. Date
   format (OUT-3) and paper size (OUT-4) were missed because each of the three
   PDF call sites assembles its own inputs. One `ExportContext` resolved once
   from the widget tree would stop this drift.
4. **Schema bumps are opt-in, and recent fields did not opt in** (OUT-5). The
   rule "bump only when the content needs it" is sound, but nothing enforces
   it. A ratchet that fails when `archiveDanceToJson` or
   `archiveProgramToJson` gains a key without a matching
   `requiredSchemaVersion` case would catch this.

## Checked and fine

- **Dialect:** the dance text, dance PDF, program appendix (text and PDF) and
  matrix headers all use the active dialect plus the discouraged-term setting,
  as `sharing.md` says. The program's Perform dialect is correctly ignored by
  exports, as `programs.md:215-218` says.
- **Share-field picker:** honoured identically by the dance text and dance PDF
  through `DanceCardContent`. In program set-list lines only the author
  appears, as documented. Both dance-export surfaces pass
  `DanceShareFieldsScope` (`dance_detail_screen.dart:666, 767`).
- **Venue address:** stripped from text, PDF and file. Contacts are gated by
  one consent dialog for PDF, JSON and `.ccshare`; the text path never carries
  them (`program_export_menu.dart:351-361`).
- **Choreographer email, location and deceased:** stripped in both bundle
  builders.
- **Non-shareable custom fields:** definitions and values are dropped in share
  mode; strict resolvers fail closed. Backup keeps them, with the flag.
- **`.ccshare` vs `.json`:** byte-identical payload with one encoder.
- **Hide alternates:** honoured by text and PDF; the file still carries the
  alternates, as documented.
- **Backup completeness:** includes soft-deleted dances and programs, deleted
  tags, the glossary, figure notes, dialects, themes and settings (including
  shorthands, snippets and formation colours). It excludes sync, window and
  draft keys, as documented.
- **Rendering settings:** Capitalize figures does not affect exports (and the
  docs say so). Verbose rendering is "dance view" only (as documented).
  Decimal turns are not applied to exports either; nothing promises they are.
- **Export failures:** every PDF, share and JSON action runs inside
  `guardExport`. Cancelling a sheet is not reported as an error.
- **Published collections:** there is **no user-side "publish" feature**. The
  client only verifies and imports a signed, maintainer-run catalog
  (`published_collection_service.dart`). The "publish part of my collection"
  step of the user story has no path in the app. Whether that is a gap is a
  product question, not a defect.

## Out of scope but noticed

- **Matrix PDF failure message:** reads "Couldn't export this set list"
  (`program_editor_screen.dart:3319`). Copy issue.
- **Published-collection import history:** `collection_import_events` is not
  in the backup, although the registry allows it in a local backup. After a
  restore, the history of which collection versions were imported is gone.
- **Untranslated stored text:** `kUnresolvedDanceMarkerPrefix`
  ("Dance not imported (") is English text persisted into user data and synced.
- **"Copy set list" error handling:** it is not wrapped in `guardExport`
  (`program_export_menu.dart:584-585`), unlike its siblings.
- **Strictness differs between the two bundle builders:** a dance share throws
  on a missing choreographer (`dance_share_bundle.dart:24-26`), while a
  program share skips it silently (`program_share_bundle.dart:131`).
