# Design: History filters (venue and recency)

*Design note N1 for audit finding FIND-1 · 2026-10-29, decisions recorded
2026-10-30 · **decided, not built.** The maintainer chose "Design note now" for
`design-history-filters` on 2026-10-29, and answered all nine of this note's
questions on 2026-10-29/30 (N1-1 … N1-9 in
`maintainer-decisions-2026-10-30.md`, on `claude/app-audit-categories-k2pdon`).
[Decisions](#decisions) quotes each answer. Two answers differ from this
note's recommendation (N1-4 and N1-6), and the maintainer's note on N1-2 changes
its presets. The text below now follows the answers. A choice still marked **Recommendation** is this note's,
not the maintainer's, and a reviewer can overturn it.*

**The gap.** A caller building tonight's program for the Grange wants a dance
they have not called at the Grange, or not called in the last few months. The
app cannot express either today:

- `CalledFilter` has only `called`, `callerFilter`, `performedOnly` and
  `requireEventDate`. It has no venue or date scope
  (`packages/compendium_core/lib/src/search/filter.dart:224-247`, compiled at
  `filter_compiler.dart:356-379`).
- The Filters panel offers only a Called / Not called pair
  (`app/lib/src/widgets/facet_panel.dart:282-307`). It becomes a `CalledFilter`
  at `app/lib/src/search/collection_query.dart:412-421`.
- The picker rows show "called ×N" and "in program ×N", but not when or where
  (`app/lib/src/widgets/collection_picker.dart:1005`,
  `app/lib/src/widgets/dance_list_tile.dart:116`).
- Venue repeats appear only on the dance detail page, after the caller has
  already picked a candidate (`docs/user/collection.md:284-285`).

**Already covered elsewhere.** B14 (`feat/picker-parity`, FIND-7 = full parity)
gives the picker Collection's sort control, which includes **Last called**. That
is FIND-1's option (d), so this note does not repeat it. Today the picker searches
with no `sort:` argument (`collection_picker.dart:374-379`).

**Out of scope:**

- Save, New and header placement (D-11 is still open).
- Duplicate venue records and venue merging.
- Saved searches, which the app does not have.

Line numbers are for `origin/main` at `296b594`, except where a line says
`90fe5e8` (the tree the 2026-10-30 decisions were recorded against; B1 moved
much of `calling_history_scope.dart` and `program_repository.dart`).

## Constraints

These come from `decided-work-plan.md` ("Design notes" and N1) on
`claude/app-audit-categories-k2pdon`, and from the code.

1. **One meaning of "called".** Every history surface applies the same five rules:
   - **the alternate rule:** `callingHistoryAlternateClause`
     (`packages/compendium_core/lib/src/storage/calling_history_scope.dart:33-34`),
     with its Dart twin `ProgramSlot.countsTowardCallingHistory`;
   - **the caller scope:** `callingHistoryCallerClause` (`:15-21`, #583);
   - **the event-date rule:** `callingHistoryEventDateClause` (`:47-50`);
   - **the performed rule:** `performed_at IS NOT NULL`. It has no shared helper
     and is written inline at `filter_compiler.dart:364-366`,
     `program_repository.dart:1194` and `dance_repository.dart:3104`;
   - **non-deleted programs only:** `p.deleted_at IS NULL`
     (`filter_compiler.dart:376`).

   A venue or recency scope **narrows the set of slots** these rules select. It
   never builds a second definition of "called".
2. **The call date.** GIG-2 = (a) is a maintainer decision (2026-10-29): use the
   event date when there is one, and the tap time only for undated programs. B1
   carried it out in #2032 as `COALESCE(event_date, performed_at, updated_at)`.
   The last fallback, `updated_at`, is B1's own choice, not part of the decision.
   *Update, 2026-10-30 (all line numbers in this paragraph and the next are at
   `90fe5e8`):* B1 put the expression in one helper, `callingHistoryDateSql`
   (`packages/compendium_core/lib/src/storage/calling_history_scope.dart:47-52`;
   the event-date clause in constraint 1 is now at `:65-68`).
   History order (`program_repository.dart:1263`) and the Last-called sort
   (`dance_repository.dart:3126`) read it. It has two Dart copies, each with
   its own `eventDate ?? performedAt ?? programUpdatedAt` chain:
   `DanceCallingRecord.effectiveDate` (`program_repository.dart:82`), which
   orders the detail page's rows, and the detail page's display date,
   `callingHistoryDisplayDate`
   (`app/lib/src/screens/dance_detail/calling_history_section.dart:399-403`).

   A further date, `last_called` in the bulk counts
   (`program_repository.dart:1110-1114`), is not this order. After B1 it is still
   the newest **performed** slot only, now dated
   `COALESCE(event_date, performed_at)`, with a `last_called_dated` variant for
   "Require an event date". So with the default settings, Collection's
   `lastCalled` still leaves out every unperformed slot that "called ×N" counts
   (see Q4).
3. **The venue key that already exists.** The repeated-venues summary groups a
   dance's history by `id:<venueId>` when the program links a venue record, and
   otherwise by `text:<typed venue>`. The typed text is trimmed, its whitespace
   runs are collapsed and it is lower-cased in Dart
   (`program_repository.dart:1222-1254`). A typed "Grange" and a record named
   "Grange" are therefore two venues today.
4. **GIG-7 = (b).** The maintainer chose "Offer to link old programs" over
   "Merge by the displayed name" (`maintainer-decisions-2026-10-29.md`,
   `venue-history-merge`). History does not treat a typed name and a record as
   one hall just because the names match. B3 does the linking. B3's
   `linkTypedVenues` bumps `updatedAt` on every program it links.
5. **Venues have no natural key in sync.** `venues` inserts without
   reconciliation (`docs/design/sync-spec.md:3449-3450`), so two devices can each
   create a "Grange" record. A dangling `programs.venue_id` is kept verbatim
   (`sync-spec.md:3682-3684`). The label then falls back to the typed text
   (`app/lib/src/data/venue_label.dart:21-33`).
6. **Dates.** `programs.event_date` holds UTC midnight of the calendar day the
   caller picked (`app/lib/src/screens/program_editor_screen.dart:4342`).
   `updated_at` and most `performed_at` values are instants. Status → Performed
   is the exception: it copies the event date into `performed_at`
   (`calling_history_section.dart:398-414`).
7. **`ux.md`'s rules:**
   - undo everywhere, and confirm only where Undo is impossible
     (`docs/design/ux.md:201-202`);
   - no meaning carried by colour alone (`:209`);
   - single-pane phone layouts (`:26`).

   The Filters panel and the picker share one panel, `FacetPanel`, and one list
   of hidden sections (`:51`).
8. **Privacy.** Filter state is session-only unless this note argues otherwise.
   A persisted key or column needs a registry entry on all three axes in the same
   PR (`AGENTS.md`, "Every persisted field must be classified").
9. **Sync.** A new record kind goes through sync-spec §6.6 (aliases) and §6.15
   (the capability gate).

## Q1. How does the venue scope match?

**Decided: by the existing venue key (constraint 3).** N1-1 = (a), 2026-10-30,
as this note recommended.

- A program matches `id:V` when `venue_id = V`.
- It matches `text:T` when it has no `venue_id` and its folded typed venue equals
  `T`.

So the scope matches by both record and typed text, but never across them. A
typed "Grange" does not match the record "Grange".

| Option | For | Against |
| --- | --- | --- |
| **Venue key, as the summary does** (recommended; decided, N1-1) | The filter and the repeated-venues summary always agree. Follows GIG-7 (b). Works with venue records off. | Until B3 links old programs, a record and a typed name stay split. Duplicate "Grange" records from two devices stay split too (constraint 5). |
| Record id only | Simplest SQL. | Useless with venue records off, which is the default (`docs/user/settings.md:122-127`). Typed history is invisible. |
| Typed text only | Works in both modes. | Ignores the record a program links. A renamed record would split from its programs' typed text. |
| Displayed name (record name, else typed text) | Joins a typed name to its record, and joins duplicate records. | This is GIG-7's option (a), which the maintainer rejected. The summary would disagree unless it changed too. |

**How a `text:` key reaches SQL.** SQLite cannot reproduce the summary's fold:
- it has no regular expressions, so it cannot collapse a whitespace run;
- its `LOWER` is ASCII-only, while Dart's `toLowerCase` folds every script.

So `LOWER(TRIM(p.venue))` would split from the summary on "Salle  Église" (two
spaces, non-ASCII capitals). An `id:` key compiles to `AND p.venue_id = ?` in
every option below.

| Route | For | Against |
| --- | --- | --- |
| **A Dart SQL function** (recommended) | `applyCompendiumSqliteSetup` registers a function, `cc_venue_key(text)`, on every connection (`packages/compendium_core/lib/src/storage/database_setup.dart:37-40`). Both connections the app opens use that setup: the app's (`app/lib/src/data/app_database.dart:152`) and the sync isolate's (`app/lib/src/sync/sync_isolate.dart:466`). The compiler emits `AND p.venue_id IS NULL AND cc_venue_key(p.venue) = ?`. The summary calls the same Dart function. One rule, exact, no extra query. | Every connection must register it, and today only the two production ones run the setup. The test databases (`packages/compendium_core/test/storage/test_database.dart:8`, `:155`; `app/test/support/test_repositories.dart:29`) and the core tools and benchmarks (`packages/compendium_core/tool/write_head_database.dart:55`, `packages/compendium_core/benchmark/search_benchmark.dart:59` and `scalability_benchmark.dart:482`) open without it, and would fail with "no such function". Only a search with a `text:` venue scope would fail there with "no such function", and many more test files open their own connection. So H1 passes the setup in the two shared test helpers and the tools above (WAL is a no-op in memory, `database_setup.dart:33-35`). Venue-scope tests use those helpers, and one test per production path asserts the function exists. An open-time check was rejected: it would break every other connection site, whether or not it searches by venue. |
| Resolve to program ids first | `DanceRepository.search` lists live programs and folds their venues in Dart before compiling, so the compiler stays pure. | An extra query on every search. An `IN (…)` list that grows with the venue's history and needs chunking past the bind limit (`_chunkIds`, `dance_repository.dart:3094`). |
| A stored folded column | Plain indexed SQL. | A schema bump, a migration, a registry entry and a sync review, all to fix a whitespace rule. |

**B3's role.** The scope works without B3. B3 makes it more useful: once old
typed programs are linked to the record, they move from the `text:` key to the
`id:` key, and the filter follows with no change. So H1 does not wait for B3.

**The venue chooser.** This is Collection only; the picker uses the program's
own venue (Q3).
- It lists the distinct keys over live programs, under the current calling
  history settings. Each label comes from `resolveVenueLabelParts`.
- Venues with no counted call are left out, because choosing one cannot change a
  result.
- Every row shows how many programs it covers. A typed key also says "typed".
  So a typed "Grange", a record "Grange" and a second device's record "Grange"
  read as three different rows.
- An `id:` key whose record is missing (constraint 5) is labelled with the typed
  text of its most recent program.

## Q2. A recency scope

**Decided: "within the last …" with presets, plus a chosen date, plus a way to
ask for dances never called.** N1-2 = (a), 2026-10-30, with the maintainer's
note: "Also an option for dances which haven't been called. I think you can just
say 1mo, 3mo, 6mo, or since a date on top of that, 1 year is a long while."

- Presets: 1 month, 3 months, 6 months. There is no 1-year preset, and no
  4-week one: the maintainer's note replaces the option text's "4 weeks … or
  1 year". "1mo" is a calendar month, counted like the other two
  (*planner's reading, accepted by the maintainer 2026-10-30*;
  `design-work-plan.md` ambiguity 2).
- **Since a date…** opens the date picker.
- **Never called.** The maintainer's note asks for this as a choice in the same
  control. *Planner's reading, accepted by the maintainer 2026-10-30*
  (`design-work-plan.md` ambiguity 1, on the audit branch): it is the
  control's "no window" state, labelled so that it reads as "dances that have
  never been called" when **Not called** is chosen. Today's **Not called** with
  no scope already selects exactly those dances, so this adds a label and a
  choice, not a new predicate. H2 shows the wording in its PR.
- The scope reads together with the polarity chip:
  - **Not called** + **within 3 months**: no counted call in the window.
  - **Called** + **within 3 months**: at least one counted call in it.

| Option | For | Against |
| --- | --- | --- |
| Presets plus a date (recommended; decided, N1-2) | One tap for the common case, and a date for "since the spring dance weekend". | Two controls in one section. |
| Presets only ("in the last N weeks") | Fewest controls on a phone. | No way to say "since that event". |
| A date only ("not called since …") | One control. | Opens a date picker every time. |

**Which date a call has.** Under B1, a slot in an undated program with no
performed stamp is dated by `updated_at`, the program's last edit. That date is
not a call. Fixing a typo in an old undated program would mark all its dances
"called this week", and so would a new undated draft. B3 would do the same to
every undated program it links, because linking bumps `updatedAt`
(constraint 4).

- **Decided (N1-3 = (a), 2026-10-30, as recommended):** the recency scope dates
  a call by `COALESCE(event_date, performed_at)`. A slot with neither still counts as
  "called" for Called / Not called and for "called ×N". But no recency window
  contains it, so it is neither "recent" nor "within 3 months".
- **Alternatives:**
  - use B1's full expression and accept the `updated_at` drift;
  - turn on "Require an event date" for the recency scope only. That drops
    undated programs, performed or not.

**The window** starts at a cutoff and has no end. So a program dated next month
already counts as a call, as it does today for "called ×N" (#583's documented
default). Under "Not called within 3 months", a dance already programmed for
next month is hidden. **Decided (N1-9 = (a), 2026-10-30, as recommended):**
keep this. A dance already planned for another night is one the caller usually
wants to avoid repeating.

**Where the window starts. Decided: at today, everywhere** (N1-4 = (b),
2026-10-30). *This differs from this note's recommendation, which was to count
back from the program's event date in the picker.*
- **In Collection and in the picker,** the cutoff is today minus the preset. The
  picker does not read the program's date for this.
- The option text names the cost: "Simpler, but wrong for a program planned
  weeks ahead." A program built two months ahead asks "not called within 3
  months" of today, not of its own night.
- The window still has no end, so it holds every later program (N1-9).
- **Not chosen:** count back from the program's event date (this note's
  recommendation), and close the window at the program's date.

**Cutoff and granularity** (constraint 6). The cutoff is a calendar date, stored
as `DateTime.utc(y, m, d)` like an event date.
- **Dated programs** compare `event_date >= cutoff` exactly.
- **Undated, performed programs** compare an instant with UTC midnight. So on the
  boundary day a call can land on the wrong side by up to the device's UTC
  offset.
- **Recommendation:** accept and document this. The question is asked in weeks,
  and with "Require an event date" on, no undated program is counted.

**One date expression.** B1 (#2032) added `callingHistoryDateSql` to
`calling_history_scope.dart` (constraint 2). History order and the Last-called
sort read it. H1 adds the recency variant beside it: the same expression
without `updated_at`. The recency scope and the H3 chip read that variant.
- The two Dart copies (`effectiveDate` and `callingHistoryDisplayDate`,
  constraint 2) cannot share a SQL string. Today no test compares
  `callingHistoryDisplayDate` with either of the others. H1 adds a lockstep
  test that the SQL, `effectiveDate` and the display date pick the same date
  for the same rows (the display date in local time), and the same lockstep for
  the recency variant.

## Q3. Should the picker exclude or flag dances called at this venue?

The picker knows the program it is adding to only through `addedDanceCounts`
(`collection_picker.dart:84-89`). It does not know the program's id, venue or
date. Perform's sheet passes no program at all.

**Decided: flag, plus a one-tap filter that starts off** (N1-5 = (a),
2026-10-30, as recommended). In the picker, when the program has a venue:

- each row called at this venue shows a **here** marker (Q4);
- a **Not called here** chip sits beside Filters. It **starts off** for each
  program. On the two-pane editor the picker stays mounted, so the chip resets
  when the editor opens a different program, not every time the pane is shown.

| Option | For | Against |
| --- | --- | --- |
| Flag, plus a chip that starts off (recommended; decided, N1-5) | Nothing is hidden unless the caller asks. A favourite they do want to repeat is one glance away. | One tap per program. |
| Exclude by default | Matches the headline task with no taps. | Results silently shrink. A caller who wants a repeat must work out why the dance is missing. Remembering an "off" choice needs a settings key. |
| Flag only | No new control. | The caller still scans the whole list by eye. |

**The chip is its own filter.** It adds
`CalledFilter(called: false, venue: <this program's key>, …)`, ANDed with
whatever the Filters panel holds. It does not edit the panel's Called / Not
called choice, so with **Called** chosen in the panel, the chip still means "not
called here". The "exactly one polarity" rule in
[Composition rules](#composition-rules) applies to the panel's scopes, not to
this chip.

**The program being edited.** A primary slot counts the moment the dance is in a
program (#583; `calling_history_scope.dart:26-29`). Without an exception, a dance
added to tonight's program would at once read as "called here, tonight".
- **Decided: leave out the whole program** (N1-6 = (c), 2026-10-30). *This
  differs from this note's recommendation, which left out only the program's
  unperformed slots.* Every picker scope and every picker row value ignores
  every slot of the program being edited, performed or not. `CalledFilter`
  gains `currentProgramId`, which compiles to `AND p.id <> ?`. Collection never
  sets it.
- **The cost, as the option stated it:** this "also hides a dance performed an
  hour ago, and Perform has no in-program marker to make up for it." In
  Perform's live-swap sheet, a dance already called tonight reads as neither
  called here nor recently called. The picker's existing "in program ×N"
  still counts it, because that count comes from the program's own slots, not
  from history.

**No venue, no chip.** A program with no venue and no linked record shows no
chip and no marker.

**How the picker learns the program.** The picker takes a new optional argument,
`programContext`: the program's id, `venueId` and typed venue. *My call:* it
carries no event date, because N1-4 = (b) counts every window back from today,
so nothing in the picker reads the program's date. Rejected: passing it anyway
"in case", which is an unused parameter.
- It defaults to null, so B14's stable constructor API still holds, and all five
  mounts compile unchanged.
- Four of the mounts are edited to pass it:
  - `program_editor_screen.dart:3287`, `:3756` and `:3874`;
  - `perform_adjust_sheet.dart:273`, because a live swap at the venue asks the
    same question.
- `settings/defaults_section.dart:616` has no program and passes nothing.
- Because the editor mounts are edited, H3 waits for F10, F11 and U7. F10
  (#2022) and U7 (#2033) have merged; F11 (#2040) is open.

## Q4. Should picker rows show when and where a dance was last called?

**Decided: yes. Show a compact "last called" chip, and in the picker a here
marker** (N1-7 = (a), 2026-10-30, as recommended).

- **The chip** shows a relative date: "3 mo ago", or "in 3 wk" for a program
  that is still ahead. Its semantics label and tooltip give the full date. It
  uses the recency scope's date (Q2). A dance whose only counted calls have
  neither an event date nor a performed stamp shows **undated** instead of a
  date. So a called dance always has a chip, and the chip never shows an edit
  time as a call. It is a new `CollectionTileField.lastCalled`, so the card-fields
  setting can hide it.
- **The here marker** is an icon and the word "here", never colour alone
  (`ux.md:209`). It is picker-only. Its data comes from one search,
  `CalledFilter(called: true, venue: <this program's key>, currentProgramId:
  …)`, which returns a set of dance ids. The search reruns when the program's
  venue or slots change.
- **No venue name on the row.** A name costs a line on a 360px row, and it would
  repeat on every row. The detail page already lists venues
  (`collection.md:284-285`).

**"Called ×N" in the picker.** Today the picker's count includes the program
being edited, and "in program ×N" shows that program separately.
- Under N1-6 (Q3), the new chip and the marker leave out the whole edited
  program.
- *My reading:* the question this note put (Decision 6) covered "called ×N",
  so the picker's "called ×N" follows the same rule, and one row never says "called ×1" beside no last-called date.
  This changes what the picker's count shows: a dance in this program and
  nowhere else reads as uncalled, with "in program ×N" beside it. Collection's
  count is unchanged.

**The card-fields setting is an allow-list.** `collection_tile_visible_fields`
stores the names of the **visible** fields. A user who has changed it has a list
without `lastCalled`, so the chip stays hidden for them until they turn it on
(`app/lib/src/data/collection_tile_fields_scope.dart:136-144`). Contrast the
hidden-facets key, a deny-list "so a filter added later is visible by default"
(`app/lib/src/data/settings_keys.dart:140-146`).
- The key is a shareable `_preference`
  (`packages/compendium_core/lib/src/privacy/settings_registry.dart:135`). An
  older build ignores the unknown name, but if that build saves the setting, it
  writes back only the names it knows. One toggle there removes `lastCalled` on
  every synced device.
- Both effects already apply to any card field added later. They are listed here
  because this note adds one.

N1-8 = (a), 2026-10-30, as recommended: keep the allow-list.

| Option | For | Against |
| --- | --- | --- |
| Keep the allow-list (decided) | No new key, no registry change, no migration. The changelog says where to turn the chip on. | Users who have customised the setting don't see the chip unless they look. An older peer can drop it. |
| Add a deny-list key, as the hidden-facets key does | New fields appear for everyone. | A new key, a registry entry, a one-time migration from the old key, and a §6.15 capability gate, because older peers don't know the key. |

**Where the date comes from.** `DanceListEntry.lastCalled` reads the bulk
counts' `last_called` (constraint 2). After B1 it is still the newest
**performed** slot only, dated `COALESCE(event_date, performed_at)`, with a
`last_called_dated` variant. With the default settings it leaves out every slot
not marked performed, which "called ×N" counts. *(This note first said B1 would
move `last_called` to the full call date. B1 kept the performed-only meaning
instead, so the paragraph is corrected here.)*
- H3 adds the variant B1 did not: the newest **counted** slot, dated by the
  recency variant, so with "Require mark performed" off the chip counts what
  "called ×N" counts. It honours both settings the way `countFor` does
  (`lastCalledFor(performedOnly, requireEventDate:)`), and adds a
  `currentProgramId` variant of the bulk counts for the picker. These are new columns in `_programDerivedRows` and fields on
  `DanceCallCounts` (`program_repository.dart:1042-1061`).
- FIND-2's evidence also notes that no screen shows the value the Last-called
  sort orders by. The chip shows it, with one exception. The sort keeps B1's
  `updated_at` fallback, because it needs a date for every called dance. So
  whenever a dance's newest counted call has neither an event date nor a
  performed stamp, the sort places it by that program's last edit. Its chip
  shows an older date, or "undated". This is
  a cost of N1-3 = (a), and the option text says so. The alternative, giving the sort the
  recency date too, would drop those dances into the never-called tail, which is
  FIND-2's original complaint.

| Option | For | Against |
| --- | --- | --- |
| Relative chip, plus a here marker in the picker (decided, N1-7) | Answers "recently?" and "here?" at a glance on a phone. Can be hidden. | One more chip on a busy row. |
| A full line ("Last called 12 Mar · Grange") | Says everything. | A taller row on a phone, and the venue name repeats on every row. |
| Nothing on the row; sort only (B14) | No row change. | The caller still opens each candidate to see where it was called. |

## Composition rules

These hold on every surface.

**How a scope combines:**
- A scope narrows the **slots** before the polarity applies. "Not called at the
  Grange within 3 months" is `NOT EXISTS (a counted slot at the Grange in the
  window)`. It is never `EXISTS (a slot not at the Grange)`.
- The venue and recency scopes AND with each other and with the caller,
  performed, alternate and event-date rules. A guest caller's program at the
  Grange does not count when calling history is scoped to the default caller,
  exactly as in the repeated-venues summary.

**When the panel's scopes apply:**
- They apply only when **exactly one** of Called / Not called is chosen. With
  neither or both chosen, `collection_query.dart:412` builds no `CalledFilter`,
  so a scope would do nothing.
- A scope stays set when its polarity is cleared, but it goes inert. It shows the
  hint "Applies with Called or Not called", and the active count leaves it out.
  Choosing a polarity again brings it back.
- The picker's Not called here chip is its own filter (Q3) and needs no polarity.

**When the section shows:**
- The whole section stays hidden when nothing has been called
  (`collection_picker.dart:844-851`, `docs/design/search.md:164-166`). Every
  dance is then uncalled, so a scope cannot change the result.
- The section's active count includes each active scope, so the Filters badge
  never hides an active narrowing.

**Deleted programs:**
- Programs in Recently deleted never count (`filter_compiler.dart:376`).
  trash-policy (b) does not change this.

## Privacy and sync

- **Nothing new is persisted.** Every scope and the picker chip live in session
  state, as Called / Not called do now (`FacetSelections`,
  `collection_query.dart:50`). No settings key, column, registry entry or record
  kind, so §6.6 and §6.15 have nothing to gate.
- **`collection_tile_visible_fields` gains a value** (Q4). It is already
  `_preference`: non-personal, about the app user, shareable
  (`settings_registry.dart:20-24`). An older peer ignores the new name, so the
  value needs no capability gate. The deny-list alternative in Q4 would need one.
- **The picker does not remember the chip.** N1-5 = (a) starts it off for each
  program, so no key is needed. (Remembering an "off" choice was a sub-question
  of the exclude-by-default option, which was not chosen.)
- **Recommendation: don't persist a chosen venue.** A venue name is classified
  `subject: none` (`field_registry.dart:501-508`, `:550-555`), so privacy does not
  forbid it. But a remembered venue would be per-device working state with no use
  on a peer.
- **The SQL function** (Q1) is code, not data. It changes no schema and no
  registry.
- **Duplicate venue records stay split** (constraint 5). Fixing that is a venue
  merge, which belongs with tag and choreographer merging (N2), not here. If a
  future merge writes `id_aliases` for venues, the venue key must follow the
  alias chain, like every other alias read (sync-spec §6.6).

## Docs to update

Each implementation branch updates these in the same PR:

- `docs/design/search.md:69` and `:160-161`, the `CalledFilter` rows. They already
  omit `requireEventDate` and the alternate rule. H1 adds those and the new
  scopes.
- *(Done by B1, #2032: `docs/design/search.md:355-358` already says the
  Last-called sort orders by the history date.)*
- `docs/user/collection.md:157` (Filters: Calling history) and `:52-58` (Last
  called).
- `docs/user/programs.md:160-163` (the picker): the here marker, the Not called
  here chip, and what the picker's "called ×N" counts.
- `docs/user/settings.md:382-386` (card fields): Last called.

## Decisions

*Planner's readings.* Where an answer left a detail open, the planning session
proposed a reading in `design-work-plan.md` ("Ambiguities the answers leave
open", on the audit branch). The maintainer accepted all eight on 2026-10-30
("Accept all 8 (Recommended)"), as recorded in `maintainer-decisions-2026-10-30.md`
under "Design plan / N1–N5". This note labels each one "planner's reading,
accepted by the maintainer 2026-10-30".

The maintainer answered every question on 2026-10-29/30. Each entry quotes the
decision as `maintainer-decisions-2026-10-30.md` (on
`claude/app-audit-categories-k2pdon`) records it, and the maintainer's own note
verbatim where there is one.

1. **N1-1, venue matching.** "(a) Venue key, like the repeated-venues list. The
   filter always agrees with the dance page's repeated venues, but a typed
   "Grange" and a saved "Grange" stay separate until old programs are linked."
   As recommended. See Q1.
2. **N1-2, recency form.** "(a) Presets plus a chosen date. One tap for 4 weeks,
   3 months, 6 months or 1 year, plus "Since a date"; it costs two controls in
   one section." Maintainer's note: "Also an option for dances which haven't
   been called. I think you can just say 1mo, 3mo, 6mo, or since a date on top
   of that, 1 year is a long while." The note changes the presets to 1, 3 and 6
   months and adds a never-called choice. See Q2.
3. **N1-3, calls dated only by an edit.** "(a) Leave them out of recency
   windows. They still count as called and in "called ×N" but never as recent;
   the Last-called sort can then place a dance differently from its chip." As
   recommended. See Q2 and Q4.
4. **N1-4, where the picker's window starts.** "(b) Always from today. Simpler,
   but wrong for a program planned weeks ahead." *Differs from the
   recommendation, (a).* See Q2.
5. **N1-5, the picker's default.** "(a) Flag them, with an off-by-default chip.
   Rows called here show a "here" marker, and a Not called here chip hides them
   in one tap per program." As recommended. See Q3.
6. **N1-6, the program being edited.** "(c) Leave out the whole program. Also
   hides a dance performed an hour ago, and Perform has no in-program marker to
   make up for it." *Differs from the recommendation, (a).* See Q3 and Q4.
7. **N1-7, picker rows.** "(a) Short "last called" chip plus "here". Rows show
   "3 mo ago", and picker rows add a "here" marker; one more chip on a busy row,
   which card fields can hide." As recommended. See Q4.
8. **N1-8, card-field visibility.** "(a) No, they turn it on themselves. No new
   setting or migration; the changelog says where to turn it on, and an older
   synced device can drop it again." As recommended. See Q4.
9. **N1-9, future-dated programs.** "(a) Yes, count future programs. "Not called
   within 3 months" hides a dance already planned for next month, matching
   "called ×N"." As recommended. See Q2.

## Branches

Sizes count changed lines, tests included: S < 150, M 150–400, L 400+. Updated
2026-10-30 for the decisions above and for what has merged since the note was
written (`main` at `90fe5e8`: B1 #2032, B6 #2042, B11 #2039, B12 #2037, F10
#2022, U7 #2033 and U9 #2027 have merged; F11 #2040 is open). The audit
branch's `design-work-plan.md` gives each branch's guard tests, docs and wave;
there these branches are N1-H1, N1-H2 and N1-H3.

| # | Branch | Items | Main files | Size | Model | Depends on |
| --- | --- | --- | --- | --- | --- | --- |
| H1 | `feat/called-filter-scopes` | `CalledFilter` gains `venue`, `since` and `currentProgramId` (the whole program, N1-6). The `cc_venue_key` function, registered per connection and used by the summary too. The recency date variant of B1's `callingHistoryDateSql`, without `updated_at` (N1-3). A query that lists the venue keys with a counted call. Lockstep tests: the venue scope against the repeated-venues summary, the recency scope against the call date, and SQL against the Dart `effectiveDate`. `search.md`. | `filter.dart`, `filter_compiler.dart`, `calling_history_scope.dart`, `database_setup.dart`, `dance_repository.dart`, `program_repository.dart`, the test-database helpers and core tools listed in Q1 | L (~450) | Opus: it changes the one definition of "called". | B1 (merged, #2032). Hot files: after B7 → B13 on `dance_repository.dart` (B11 and B12 have merged), and in the `program_repository.dart` chain after B9 and B3, before B4 (B9 → B3 → **H1** → B4 → B5). No ARB, no changelog. |
| H2 | `feat/history-filter-controls` | The Filters panel's Calling history section gains **At venue** and **Within** (1 month, 3 months, 6 months, Since a date…, and the never-called choice, N1-2), with the inert state and hint. The venue chooser. Active counts. ARB keys in all six files. `collection.md`. Changelog fragment. Both surfaces get it, because `FacetPanel` is shared (`dance_list_screen.dart:2738`, `collection_picker.dart:834`). | `facet_panel.dart`, `collection_query.dart`, `collection_data.dart`, and both `FacetPanel` hosts: `dance_list_screen.dart` (venue keys) and `collection_picker.dart` (wiring). ARBs. | M (~400) | Sonnet | H1. After B14 → B15, which own both host files. |
| H3 | `feat/picker-history-context` | `programContext` (id and venue, no date: N1-4). The Not called here chip. `currentProgramId` on the picker's scopes, row values and "called ×N" (N1-6). `lastCalledFor` and the bulk-count variants. `CollectionTileField.lastCalled` (allow-list unchanged, N1-8) and the here marker. ARBs. `programs.md` and `settings.md`. Changelog fragment saying where to turn the chip on. | `collection_picker.dart`, `dance_list_tile.dart`, `collection_tile_fields_scope.dart`, `dance_list_entry.dart`, `collection_data.dart`, `program_repository.dart`, `program_editor_screen.dart` (three mounts), `perform_adjust_sheet.dart` | L (~500) | Sonnet: read-only aggregates and widgets, with no transaction, sync or schema change (the work plan's model rule; the note first said Opus). | H1, H2, B14. F11 (#2040) for the editor mounts, so W3. Hot files: one open PR in the `program_editor_screen.dart` group (B4 → B5, B24, B29), and after B5 in the `program_repository.dart` chain. |

H1 can start now: B1 has landed. It merges after B3. H2 follows H1 and B15. H3
lands in W3.

H1 shrinks from the note's ~500 to ~450 because B1 already added the shared
date helper and moved the sort onto it. N1-7 = (a) keeps H3 at L; the M
(~300) variant applied only to "nothing on the row".
