# Design: History filters (venue and recency)

*Design note N1 for audit finding FIND-1 · 2026-10-29 · proposed, not built.
The maintainer chose "Design note now" for `design-history-filters` on
2026-10-29. Every choice below that is not cited as a maintainer decision is a
recommendation from this note, and is listed under
[Decisions needed](#decisions-needed).*

**The gap.** A caller building tonight's program for the Grange wants a dance
they have not called at the Grange, or not called in the last few months. The
app cannot express either today:

- `CalledFilter` has only `called`, `callerFilter`, `performedOnly` and
  `requireEventDate`. It has no venue or date scope
  (`packages/compendium_core/lib/src/search/filter.dart:224-247`, compiled at
  `filter_compiler.dart:356-379`).
- The Filters panel offers only a Called / Not called pair
  (`app/lib/src/widgets/facet_panel.dart:281-305`, built into a `CalledFilter`
  at `app/lib/src/search/collection_query.dart:411-419`).
- The picker rows show "called ×N" and "in program ×N", but not when or where
  (`app/lib/src/widgets/collection_picker.dart:1005`,
  `app/lib/src/widgets/dance_list_tile.dart:116`).
- Venue repeats appear only on the dance detail page, after the caller has
  already picked a candidate (`docs/user/collection.md:284-285`).

**Already covered elsewhere.** B14 (`feat/picker-parity`, FIND-7 = full parity)
gives the picker Collection's sort control, which includes **Last called**. That
is FIND-1's option (d), so this note does not repeat it. Today the picker searches
with no `sort:` argument (`collection_picker.dart:374-379`).

**Out of scope.** Save, New and header placement (D-11 is still open). Duplicate
venue records and venue merging. Saved searches, which the app does not have.

Line numbers are for `origin/main` at `acacb05`.

## Constraints

These come from `decided-work-plan.md` ("Design notes" and N1) on
`claude/app-audit-categories-k2pdon`, and from the code.

1. **One called predicate.** "Called" is decided in one place for SQL and one for
   Dart, and every history surface uses them:
   - the alternate rule, `callingHistoryAlternateClause`
     (`packages/compendium_core/lib/src/storage/calling_history_scope.dart:33-34`),
     with its Dart twin `ProgramSlot.countsTowardCallingHistory`;
   - the caller scope, `callingHistoryCallerClause` (`:15-21`, #583);
   - the event-date rule, `callingHistoryEventDateClause` (`:47-50`);
   - the performed rule, `performed_at IS NOT NULL`
     (`filter_compiler.dart:364-366`);
   - non-deleted programs only, `p.deleted_at IS NULL` (`filter_compiler.dart:376`).

   A venue or recency scope **narrows the set of slots** inside that predicate. It
   never builds a second one.
2. **B1's date rule.** After B1, a call is dated by
   `COALESCE(event_date, performed_at, updated_at)` (GIG-2 = a, maintainer
   decision 2026-10-29). A recency scope must compare that same expression.
   Today the expression is written out by hand in two places, in the old order:
   - history order, `program_repository.dart:1199-1201`;
   - the Last-called sort, `dance_repository.dart:3099-3100`.
3. **The venue key that already exists.** The repeated-venues summary groups a
   dance's history by `id:<venueId>` when the program links a venue record, and
   otherwise by `text:<typed venue>`, folded to lower case with runs of
   whitespace collapsed (`program_repository.dart:1222-1254`). A typed "Grange"
   and a record named "Grange" are therefore two venues today.
4. **GIG-7 = (b).** The maintainer chose "Offer to link old programs" over
   "Merge by the displayed name" (`maintainer-decisions-2026-10-29.md`,
   `venue-history-merge`). History does not treat a typed name and a record as
   one hall by name. B3 does the linking.
5. **Venues have no natural key in sync.** `venues` inserts without
   reconciliation (`docs/design/sync-spec.md:3449-3450`), so two devices can each
   create a "Grange" record. A dangling `programs.venue_id` is kept verbatim
   (`sync-spec.md:3682-3684`); the label then falls back to the typed text
   (`app/lib/src/data/venue_label.dart:21-33`).
6. **Dates.** `programs.event_date` holds UTC midnight of the calendar day the
   caller picked (`app/lib/src/screens/program_editor_screen.dart:4248-4250`).
   `performed_at` and `updated_at` are instants.
7. **`ux.md`.** Undo everywhere, confirm only where Undo is impossible
   (`docs/design/ux.md:192-193`), and single-pane phone layouts (`:26`). The
   Filters panel and the picker share one hidden-sections list (`:51`).
8. **Privacy.** Filter state is session-only unless this note argues otherwise.
   A persisted key or column needs a registry entry on all three axes in the same
   PR (`AGENTS.md`, "Every persisted field must be classified").
9. **Sync.** A new record kind goes through sync-spec §6.6 (aliases) and §6.15
   (the capability gate).

## Q1. How does the venue scope match?

**Recommendation: by the existing venue key (constraint 3).** A program matches
the venue `id:V` when `venue_id = V`. It matches `text:T` when it has no
`venue_id` and its folded typed venue equals `T`. This is "both", but never
across the two: a typed "Grange" does not match the record "Grange".

| Option | For | Against |
| --- | --- | --- |
| **Venue key, as the summary does** (recommended) | The filter and the repeated-venues summary on the detail page always agree. Follows GIG-7 (b). Works with records off. | Before B3 links old programs, a record and a typed name stay split. Two devices' duplicate "Grange" records stay split (constraint 5). |
| Record id only | Simplest SQL. | Useless with venue records off, which is the default (`docs/user/settings.md:122-127`). Typed history is invisible. |
| Typed text only | Works in both modes. | Ignores the record a program links. Renaming a venue record would split its history. |
| Displayed name (record name, else typed text) | Folds the typed/record split and the duplicate-record split. | This is GIG-7's option (a), which the maintainer rejected. The summary would disagree with the filter unless it changed too. |

**How it compiles.** `FilterCompiler` is pure: it turns a filter tree into SQL
with no database access. SQLite cannot reproduce the summary's whitespace fold
(`\s+` → one space), and an approximation such as `LOWER(TRIM(p.venue))` would
split from the summary on a doubled space. So:

- *My recommendation:* `CalledFilter` gains a `venue` field holding a
  `CallingVenueKey` (`id` or `text`). An `id` key compiles to
  `AND p.venue_id = ?`. A `text` key is resolved by `DanceRepository.search` to
  the ids of live programs whose key matches, using the **same Dart function**
  that `_venueCountsFromRecords` uses. It then compiles to
  `AND p.venue_id IS NULL AND p.id IN (…)`. The fold function moves to
  `calling_history_scope.dart` so both callers share it.
- *Rejected:* a stored folded-venue column. It would need a schema bump, a
  migration, a registry entry and a sync review to fix a whitespace rule.

**B3's role.** The scope works without B3. B3 makes it more useful: once old
typed programs are linked to the record, they move from the `text:` key to the
`id:` key, and the filter follows with no change. So H1 below does not wait for
B3.

**The venue chooser** (Collection only; the picker uses the program's own venue,
see Q3) lists the distinct keys over live programs under the current calling
history settings, with their labels from `resolveVenueLabelParts`. When a typed
name and a record share a label, the record row shows the venue icon and the
typed row shows "typed". The chooser leaves out venues with no counted call,
because they cannot change a result.

## Q2. A recency scope

**Recommendation: "within the last …" with presets, plus a chosen date.**

- Presets: 4 weeks, 3 months, 6 months, 1 year.
- **Since a date…** opens the date picker.
- The scope reads with the polarity chip:
  - **Not called** + **within 3 months**: no counted call in the window.
  - **Called** + **within 3 months**: at least one.

| Option | For | Against |
| --- | --- | --- |
| Presets plus a date (recommended) | One tap for the common case; a date for "since the spring dance weekend". | Two controls in one section. |
| Presets only ("in the last N weeks") | Fewest controls on a phone. | No way to say "since that event". |
| A date only ("not called since …") | One control. | Opens a date picker every time. |

**The window** is `[cutoff, ∞)`. It has no upper bound, so a program dated next
month already counts as a call, as it does today for "called ×N" (#583's
documented default). Under "Not called within 3 months" a dance already
programmed for next month's dance is therefore hidden. *My recommendation:* keep
that. A dance already planned for another night is one the caller usually wants
to avoid repeating.

**Cutoff and granularity** (constraint 6). The cutoff is a calendar date: today
in local time, minus the preset, stored as `DateTime.utc(y, m, d)`, like an event
date.

- **Dated programs** compare `event_date >= cutoff` exactly.
- **Undated programs** fall back to `performed_at`, else `updated_at`, which are
  instants. They compare to UTC midnight of the cutoff date, so on the boundary
  day a call can land up to the device's UTC offset on the wrong side. *My call:*
  accept and document this. The question is asked in weeks, and with "Require an
  event date" on there are no undated programs.

**One date expression.** H1 adds `callingHistoryDateExpression(slotTable,
programTable)` to `calling_history_scope.dart`. It returns B1's
`COALESCE(event_date, performed_at, updated_at)`. History order, the Last-called
sort and the recency scope all read it.

> **For B1's scope** (planning, not a maintainer decision): B1's four flip sites
> in `decided-work-plan.md` do not include the Last-called sort's own copy at
> `dance_repository.dart:3099-3100`. If B1 flips history order but not the sort,
> the two disagree. Either B1 adds this helper and uses it at both sites, or H1
> does it and B1 flips the helper.

## Q3. Should the picker exclude or flag dances called at this venue?

The picker knows the program it is adding to only through `addedDanceCounts`
(`collection_picker.dart:89`). It does not know the program's id, venue or date.

**Recommendation: flag, plus a one-tap filter that starts off.** In the picker,
when the program has a venue:

- each row called at this venue shows a **here** marker (Q4);
- a **Not called here** chip sits beside Filters. It sets the same `CalledFilter`
  venue scope with the program's own key, and **starts off** every time the
  picker opens.

| Option | For | Against |
| --- | --- | --- |
| Flag, plus a chip that starts off (recommended) | Nothing is hidden unless the caller asks. A favourite they do want to repeat is one glance away. | The caller must tap once each time. |
| Exclude by default | Matches the headline task with no taps. | Results silently shrink. A caller who wants a repeat must find out why the dance is missing. Remembering an "off" choice would need a settings key. |
| Flag only | No new control. | The caller still scans the whole list by eye. |

**The current program never counts.** A primary slot counts the moment the dance
is in a program (#583; `calling_history_scope.dart:26-29`). Without an exclusion,
a dance added tonight would at once become "called here, today". The chip would
then drop it from the results, and every recency filter would count it. So the
picker's scopes always add `AND p.id <> ?` for the program being edited.
`CalledFilter` gains `excludeProgramId` for this. Collection never sets it.

**No venue, no chip.** A program with no venue and no linked record shows no
chip and no marker.

**How the picker learns the program.** The picker takes a new optional argument,
`programContext`: the program's id, `venueId`, typed venue and event date. It is
additive with a null default, so B14's stable constructor API still holds. The
five mounts that pass nothing compile unchanged:

- `program_editor_screen.dart:3206`, `:3663` and `:3781` pass it;
- `perform_adjust_sheet.dart:273` passes it, since a live swap at the venue is
  the same question;
- `settings/defaults_section.dart:615` has no program and passes nothing.

## Q4. Should picker rows show when and where a dance was last called?

**Recommendation: yes, as a compact "last called" chip, plus the here marker in
the picker.**

- **The chip** shows a relative date ("3 mo ago"). Its semantics label and
  tooltip give the full date. It is a new `CollectionTileField.lastCalled`, so the
  existing card-fields setting can hide it.
- **The here marker** is an icon and the word "here", never colour alone
  (`ux.md` rules). It shows when the dance has a counted call at this program's
  venue. It is a separate field, because it only exists in the picker.
- **No venue name on the row.** A name costs a line on a 360px row and repeats on
  every row. The detail page already lists venues (`collection.md:284-285`).

**Card fields stay forward-compatible.** `collection_tile_visible_fields` stores a
list of names, and an older build ignores a name it does not know
(`app/lib/src/data/collection_tile_fields_scope.dart:3-15`, `:136-144`). A new
field therefore needs **no new key and no registry change**; the key is already
classified (`packages/compendium_core/lib/src/privacy/settings_registry.dart:135`).
New fields default to visible, so Collection rows gain the chip too. This also
shows the value the Last-called sort orders by, which FIND-2 found was never
shown.

**The date must come from the shared predicate.** `DanceListEntry.lastCalled`
exists, but it is the performed stamp only, `MAX(performed_at)`
(`program_repository.dart:1049`, read with no event-date flag at
`app/lib/src/search/collection_data.dart:400-403`, `:547`). With the default
settings it leaves out every slot not marked performed, which "called ×N"
counts, and it ignores "Require an event date". Showing it would put a
third meaning of "last called" on screen (FIND-2's defect class). H3 replaces it
with B1's date expression under the same gates as the count, exposed as
`lastCalledFor(performedOnly, requireEventDate:)`, beside `countFor`.

| Option | For | Against |
| --- | --- | --- |
| Relative chip plus a here marker (recommended) | Answers "recently?" and "here?" at a glance on a phone. Can be hidden. | One more chip on a busy row. |
| A full line ("Last called 12 Mar · Grange") | Says everything. | A taller row on a phone, and the venue repeats on every row. |
| Nothing on the row; sort only (B14) | No row change. | The caller still opens each candidate to check where it was called. |

## Composition rules

These hold on every surface:

- A scope narrows the **slots** before the polarity applies. "Not called at the
  Grange within 3 months" is `NOT EXISTS (a counted slot at the Grange dated on or
  after the cutoff)`. It is never `EXISTS (a slot not at the Grange)`.
- The venue and recency scopes AND with each other and with the caller,
  performed, alternate and event-date clauses. A guest caller's program at the
  Grange does not count when calling history is scoped to the default caller,
  exactly as in the repeated-venues summary.
- The scopes show only when **exactly one** of Called / Not called is chosen.
  With neither or both chosen, `collection_query.dart:411` builds no
  `CalledFilter`, so a scope would do nothing.
- The whole section stays hidden when there is no counted call
  (`collection_picker.dart:844-851`, `docs/design/search.md:164-166`). Every dance
  is then uncalled, and a scope cannot change the result.
- The section's active count counts each scope, so the Filters badge never hides
  an active narrowing.
- Programs in Recently deleted never count (`filter_compiler.dart:376`).
  trash-policy (b) does not change this.

## Privacy and sync

- **Nothing new is persisted.** Every scope and the picker chip live in the
  session's `FacetSelections`, as Called / Not called do now. No settings key, no
  column, no registry entry, no record kind. §6.6 and §6.15 have nothing to gate.
- **One existing key gains a value:** `collection_tile_visible_fields` (Q4). It is
  already `_preference` (non-personal, app user, shareable;
  `settings_registry.dart:20-24`). An older peer ignores the new name, so it needs
  no capability gate.
- **If the maintainer wants the picker to remember the chip** (Decision 3), that
  is one new boolean key. It would be `_preference` and hold no venue. *My
  recommendation:* don't persist a chosen venue. A venue name is classified
  `subject: none` (`field_registry.dart:501-508`, `:550-555`), but a remembered
  venue would be per-device working state with no use on a peer.
- **Duplicate venue records stay split** (constraint 5). Fixing that is a venue
  merge, which belongs with tag and choreographer merging (N2), not here. If a
  future merge writes `id_aliases` for venues, the venue key must follow the
  alias chain like every other alias read (sync-spec §6.6).

## Docs to update

Each implementation branch updates these in the same PR:

- `docs/design/search.md:69` and `:160-161`: the `CalledFilter` rows. They already
  omit `requireEventDate` and the alternate rule; H1 adds those and the two new
  scopes.
- `docs/design/search.md:349`: the Last-called sort reads the shared date
  expression.
- `docs/user/collection.md:157` (Filters: Calling history) and `:52-58` (Last
  called).
- `docs/user/programs.md:158-161` (the picker): the here marker and the Not called
  here chip.
- `docs/user/settings.md:382-386` (card fields): Last called.

## Decisions needed

1. **Venue matching.** Match by the existing venue key, as the repeated-venues
   summary does, with no name merge (recommended, per GIG-7 = b)? Or by displayed
   name, which would reopen GIG-7?
2. **Recency form.** Presets plus a chosen date (recommended), presets only, or a
   date only?
3. **The picker's default.** A Not called here chip that starts off each time
   (recommended), exclude by default, or flag only? If the default is exclude,
   should an "off" choice be remembered? That would add one settings key.
4. **Picker rows.** A relative last-called chip and a here marker (recommended),
   a full line with the venue name, or nothing on the row?
5. **Future-dated programs** count as calls in a recency window (recommended,
   matching "called ×N" today). Or should the window end today?

## Proposed branches

Sizes count changed lines, tests included: S < 150, M 150–400, L 400+.

| # | Branch | Items | Main files | Size | Model | Depends on |
| --- | --- | --- | --- | --- | --- | --- |
| H1 | `feat/called-filter-scopes` | `CalledFilter` gains `venue`, `since` and `excludeProgramId`. The shared venue key and date expression move to `calling_history_scope.dart`. `search()` resolves text keys. A query lists the venue keys with a counted call. Lockstep tests: the venue scope against the repeated-venues summary, and the recency scope against history order. `search.md`. | `filter.dart`, `filter_compiler.dart`, `calling_history_scope.dart`, `dance_repository.dart`, `program_repository.dart` | M (~350) | Opus: it changes the one called predicate. | B1, for the date rule (or H1 adds the helper first; see Q2). Serialize after B12 → B13 and B11 on `filter_compiler.dart` and `dance_repository.dart`. No ARB. |
| H2 | `feat/history-filter-controls` | The Filters panel's Calling history section gains **At venue** and **Within**, in session state. The venue chooser. Active counts. ARB keys in all six files. `collection.md`. Changelog fragment. Both surfaces get it, because the panel is shared. | `facet_panel.dart`, `collection_query.dart`, `collection_data.dart`, ARBs | M (~350) | Sonnet | H1. B14, which extracts Collection's controls into shared widgets. |
| H3 | `feat/picker-history-context` | `programContext`. The Not called here chip. `excludeProgramId` on every picker scope. `lastCalledFor` from the shared date. `CollectionTileField.lastCalled` and the here marker. ARBs. `programs.md` and `settings.md`. Changelog fragment. | `collection_picker.dart`, `dance_list_tile.dart`, `collection_tile_fields_scope.dart`, `dance_list_entry.dart`, `collection_data.dart`, `program_editor_screen.dart` (three mounts), `perform_adjust_sheet.dart` | L (~450) | Opus: `program_editor_screen.dart` and the last-called value are both hot. | H1, H2, B14. F10, F11 and U7 for the editor mounts, so W3. |

H1 can start in W2, once B1 lands. H2 follows B14. H3 lands in W3. If Decision 4
is "nothing on the row", H3 shrinks to M (~250) and drops `dance_list_tile.dart`
and `collection_tile_fields_scope.dart`.
