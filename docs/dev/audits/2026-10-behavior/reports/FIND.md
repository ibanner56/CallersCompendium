# FIND — Finding and organizing dances

Auditor key: `FIND`. Read-only audit, 2026-10-27. Nothing was built, run or edited; no Dart was executed (the core package has no resolved `package_config.json`, and resolving one would have written into the repo). Every finding below comes from reading the code. **Traced** means I followed the call path from the UI to SQL.

## Scope & method

User stories tested:
- **Mid-evening.** "Easy improper dance, no hey, not called at this venue, in under 30 seconds." Tested in the Collection and in the Programs picker.
- **Sunday tidy-up.** Tag, rate, set levels, use custom fields, fix duplicates.

Read:
- **User docs:** `docs/user/collection.md` (all), `programs.md` (picker and calling history), `dialects.md` (search claims).
- **Design docs:** `docs/design/search.md` (all).
- **Core:** `search/{filter_compiler,fts_query,search_enrichment,search_sort,title_sort_key}.dart`; `DanceRepository.search` / `_sortBy*` / `_insertDerivedRows` / `duplicate` / `_updateMany`; `ProgramRepository._programDerivedRows`; `dialect/canonicalize.dart`; `Dialect` presets; `TagRepository.idByName`; FTS tokenizers in `database.dart`.
- **App:** `collection_query.dart`, `collection_data.dart`, `dance_list_screen.dart` (search, sort, selection, batch, grouping, tag filter), `collection_picker.dart`, `command_palette.dart`, `app_shell_search_scope.dart`, `app_shell.dart` (tag-filter navigation), `advanced_query_builder.dart` (`MoveTypeAheadField`), `by_phrase_panel.dart`, `facet_panel.dart` (sections), `dance_list_tile.dart`, `batch_custom_field_dialog.dart`, `add_to_program_sheet.dart`, `tag_colors_screen.dart`, `custom_fields_screen.dart` (searchable flag), `links_editor.dart` and `dance_editor_screen.dart` (related-dance picker), `glossary_screen.dart` (search), `move_autocomplete.dart` (dialect handling), `collection_filter_scope.dart`, `require_performed_for_history_scope.dart`, `sort_ignore_articles_scope.dart`.

## Findings

### FIND-1 — "Not called at this venue" and "not called recently" cannot be expressed anywhere, and the program picker has no calling-history aid at all — **High · Decision · Traced**

**Scenario.** A caller is building tonight's program for the Grange in the picker. They want an easy improper dance with no hey that they have not called at the Grange.
- They can set Formation = Improper, pick a Level, and add a None-of / Has figure "hey" group under Advanced (about 6–8 taps).
- They cannot exclude dances already called at this venue.
- They cannot exclude dances called in the last N weeks.
- The picker cannot sort by **Last called**.
- Picker rows do not show when or where a dance was last called. They show only an all-time "called ×N" count, plus "in program ×N" for the current program.

**Evidence.**
- `CalledFilter` takes only `called`, `callerFilter` and `performedOnly`. It has no venue or date scope (`filter_compiler.dart:280-298`; design table `search.md:160-161`).
- The facet is a two-way Called / Not called toggle (`collection_query.dart:69-71`, `411-419`).
- The picker searches without a `sort:` argument, so results are always in title order (`collection_picker.dart:365-370`). It has no sort control.
- Venue repeats appear only in the dance detail's history ("venues where you have called it more than once", `collection.md:278-281`). That is after the caller has already picked a candidate.

**Why it matters.** This is the headline job the picker exists for. Today the caller opens each candidate's detail to check its history, or leaves the program to use the Collection's Last-called sort, which has its own problems (FIND-2).

**Options (maintainer).**
- (a) Add a venue scope to `CalledFilter`. Programs already carry a venue label or a venue id.
- (b) Add a "not called since <date>" scope.
- (c) In the picker only: default-exclude or flag dances called at this program's venue.
- (d) Give the picker the Collection's sort control, including Last called.

### FIND-2 — The "Last called" sort defines "called" differently from every other calling-history surface, and the guide describes yet another meaning — **High · Traced**

**Scenario.** The caller uses the default settings: "Require mark-performed" is off (`require_performed_for_history_scope.dart:7-9`). They build programs but rarely mark slots performed.
- Their cards show "called ×3", and **Called** in Filters includes those dances.
- When they sort by **Last called**, those dances fall into the never-called tail in title order.

A second scenario: in October they back-fill "mark performed" on last spring's programs. Those dances jump to the top as "most recently called".

**Evidence.**
- `_sortByLastCalled` aggregates `MAX(performed_at)` with `performed_at IS NOT NULL`. It applies no caller-scope clause (`dance_repository.dart:2996-3047`, notably 3014-3022).
- The facet and the card both honour the performed setting and the caller scope:
  - `CalledFilter` takes `performedOnly` from the setting (`dance_list_screen.dart:800-801`).
  - The card count uses `countFor(RequirePerformedForHistoryScope.of(context))` (`dance_list_tile.dart:114-116`).
  - Both use the caller-scoped `_programDerivedRows` (`program_repository.dart:980-993`).
- So with "track all callers" off and a default caller set, guest-caller programs still drive the sort but not the count.
- `performed_at` is the moment the slot was marked, not the program's event date. See `program_editor_screen.dart:2299-2301` (`s.copyWith(performedAt: now)`) and `program_summary_screen.dart:863-865`.
- The guide says "**Last called** — the dances you have *programmed* most recently, first" (`collection.md:52`), which matches none of these.
- The value being sorted on is never shown. `DanceListEntry.lastCalled` is loaded (`collection_data.dart:547`), but no widget renders it (grep of `.lastCalled` in `app/lib`). The order cannot be checked from the screen.

**Fix direction.**
- Feed the sort from the same scoped query and setting as the count.
- Decide between the event date and the marking time.
- Show the date on the row while this sort is active.
- Correct `collection.md:52`.

### FIND-3 — Tags cannot be renamed, merged or deleted anywhere — **High · Decision · Traced**

**Scenario.** On a Sunday the caller notices both "Flowy" and "flowing", or a typo such as "Bouncey", in their category tags.
- The only route is: select every dance with the bad tag (no Select all, see FIND-8), batch-add the good tag, then batch-remove the bad one.
- The bad tag then lives on in **Settings → Appearance → Tag colours**, which lists every tag through `watchAll()`, and it cannot be removed.
- The guide sells tags as the caller's "drawers" (`collection.md:74-98`). They are the main organizing tool.

**Evidence.**
- `tag_colors_screen.dart:23-26`: "Tags still have no rename or delete UI anywhere in the app; adding them is a separate piece of work with its own design questions."
- `display_defaults.dart:158`: "Nothing in the app renames a tag today."
- `tag_colors_screen.dart:59` lists every tag, including ones no dance uses.

**Options.**
- Rename with merge-on-collision. The natural key is the name (`TagRepository.idByName`, `tag_repository.dart:260`).
- Delete with a count of affected dances and Undo.
- A manager screen that also hosts the existing colour editing.
- Any rename must also rewrite `default_import_tag_names` (`display_defaults.dart:158-161`).

### FIND-4 — Search ignores the dialect's own move names, unlike the editor and the Glossary — **Medium · Traced**

**Scenario.** The caller's custom dialect renames `swing` to "buzz", the example given in `move_autocomplete.dart:64-68`.
- In the dance editor, typing "buzz" offers the swing, and every dance reads "buzz".
- In the Collection search bar, "buzz" finds nothing.
- In Advanced → Has figure and in By phrase, typing "buzz" offers nothing. The chips and rows show "swing", a word the caller never sees anywhere else in the app.
- The Glossary search does find it by the dialect name.

**Evidence.**
- **Search bar (free text).** `_compileFullText` runs only role canonicalization plus `canonicalizeMoveSearchText` (`filter_compiler.dart:335-344`). `canonicalizeMoveSearchText` maps only the taxonomy's display names and keywords (`canonicalize.dart:173-189`). The dialect's move-substitution reverse map (`_moveReverse`, `filter_compiler.dart:78-86`), including the enrichment's `moveSynonyms`, is used only for `FigureLeaf.move` (`:552-553`).
- **Advanced and By phrase type-ahead.** `MoveTypeAheadField` matches built-in moves on `displayName`, `id` and `searchKeywords` only (`advanced_query_builder.dart:966-977`). It labels them with `MoveDef.displayName` (`:867`, `:809`). By phrase does not even pass a dialect (`by_phrase_panel.dart:175-190`, `140-141`).
- **The dialect-aware siblings.**
  - The editor's `MoveAutocomplete` matches and renders the dialect term (`move_autocomplete.dart:126-137`, `164-169`).
  - The Glossary matches the dialect name, the canonical name and the keywords (`glossary_screen.dart:105-114`).
- **Doc claims.** `search.md:525-526` says the figure-row picker is "dialect-aware, same as the editor". `dialects.md:52-54` says "Search always works, whatever words you prefer." In practice that holds for role words only.

**Note.** For figures of your own, `dialects.md:260-262` deliberately says search uses the figure's own name. That carve-out does not cover built-in moves.

### FIND-5 — Longer multi-word searches only find the exact phrase, so a cross-field search finds nothing; very short searches behave differently — **Medium · Decision · Traced**

**Scenario.** The caller types "Kaynor petronella" (author + figure) or "becket swing". The result is 0 dances. Typing just "Kaynor" works, and so does just "petronella".

**Evidence.**
- Queries of 3 or more characters go to the trigram table as **one** quoted phrase: `toFtsSubstringMatchQuery` (`fts_query.dart:36-40`), selected at `filter_compiler.dart:330-333`.
- A phrase must appear contiguously in a single column, so an author word plus a figure word never match together.
- Queries of 1–2 characters instead use token-prefix AND across columns (`toFtsPrefixMatchQuery`).
- "Best match" is offered only for that 1–2 character path (`collection_query.dart:505-517`, `collection.md:53-56`). The sort that would help most with real words is never available for them.
- `collection.md:102-104` says "Type any words — a title, an author, a phrase from the notes — and the list narrows". A caller reads that as "all of these words".

**Options.** Split the query into words, AND them across columns, and keep each word as a substring. Or keep the phrase meaning and say so plainly in the guide. Either way, consider offering Best match for longer queries.

### FIND-6 — The search bar cannot find several things shown on the dance card — **Medium · Traced**

**Scenario.** The caller types "becket", "flowy" (a tag), "beginner" or "Dmaj" into the search bar. These words are printed on the cards (formation chip, tag chip, level chip, tunes in the detail view), yet the search only finds dances whose title or notes happen to contain them.

**Evidence.** The FTS row holds exactly title, authors, hook, calling notes, figure text, custom values and sources (`dance_repository.dart:1102-1111`). Tags, formation, level, status, tunes and **walkthrough** are not in it.

Each of these has a Filters section, so it is reachable. But the search bar and the card disagree, and "All fields" (`collection.md:114-118`) is a strong name for a list that omits tags. The walkthrough is the caller's longest prose about a dance and has no route at all.

### FIND-7 — The program picker silently drops Collection search features — **Medium · Traced**

**Scenario.** The caller uses **Search in → Author** and the **Sort** menu in Collection, then opens the picker while building a program. The picker:
- has no Search in;
- has no sort;
- restricts online search to **title**. In Collection, online search offers Title, Author and Figure for TCB and ContraDB.
- ignores the caller's **Collection card fields** choice, so rows show every chip.

**Evidence.**
- `collection_picker.dart:356-364`: `buildCollectionFilter` is called without `scope:`, so local search is always All fields.
- `:365-370`: no `sort:`.
- `:557`: `OnlineSearchQuery(title: title, phrases: phrases)`, compared with `dance_list_screen.dart:975-1000` (title, author, figure).
- `:706-707`: no `visibleFields`.

**Doc claim.** `programs.md:135-138` says the picker has "the same search tools you know from Collection & search". A caller who learned Search in will look for it there.

### FIND-8 — Multi-select keeps dances you can no longer see, has no Select all, and covers only part of single-dance editing — **Medium · Traced**

**Scenario A (hidden selections).** The caller long-presses a dance (selection mode), selects 12 rows, then types a new search to find more. The search field is still active in selection mode (`dance_list_screen.dart:2327-2351`, rendered by `_buildBody` whatever the mode).
- The 12 earlier dances are now off screen but still in `_selectedIds`. The set is never pruned on search (`:1230-1248`; `_runSearch` at `:775-830` does not touch it).
- "Add tags" then edits all of them. The title shows the right total ("14 selected", `:2139-2150`), so this is only a surprise, not a lie.

**Scenario B (bulk work).** "Tag every Roodman dance *Roodman*" means filtering by author and then tapping every row. There is no Select all or Select visible (grep: no `selectAll` anywhere in `app/lib`).

**Batch coverage.**
- Batch offers tags, level, rating, tunes and custom fields (`:2152-2210`).
- It does not offer **delete**, **status** (e.g. mark deprecated), **mixer**, **mixed level**, **add to program** or **source**. Single-dance editing exposes all of those.
- Cleaning up a bad 200-dance import, or the duplicates in FIND-9, means deleting one dance at a time.

**Note.** Entering selection mode also removes the **Group by category** sections (`:2787-2793`). Batch-tagging "within a drawer" makes the list reflow under the caller's finger.

### FIND-9 — No way to find or merge duplicates; "Duplicate as a variation" records no relationship; the related-dance picker cannot tell same-titled dances apart — **Medium · Decision · Traced**

**Scenario.** The caller ends up with two copies of "Butter", one from TCB and one from ContraDB, after choosing "keep both as duplicate" at import (`imports.md:463`, `503`).
- Calling history, ratings and tags are now split between the two copies.
- There is no duplicate finder, and no merge that would move program slots and history onto one copy. Grep finds no merge or duplicate-finding code outside sync's first-connection merge (`settings.md:772`).
- When they link the copies as related dances, the editor's picker lists two identical "Butter" entries with no author shown: title-only substring match (`links_editor.dart:259-263`), options built as `(id, title)` (`dance_editor_screen.dart:108-111`).

**Related.** `collection.md:298` and `:363` say to use **Duplicate** "to spin off a variation". `Dance.duplicate` copies the original's links but does not link the copy back to the original (`dance.dart:352-389`). The variation is unrelated as far as the app knows.

**Options.**
- A "possible duplicates" view, reusing the import-time matcher.
- Merge, which re-points `program_slots` and unions tags.
- Auto-link a duplicate as related.
- Show authors in the related-dance picker.

### FIND-10 — Filters cannot find dances that still need tidying, and rating is filterable but not sortable — **Medium · Traced**

**Scenario.** On a Sunday the caller wants "dances I haven't levelled yet" or "dances I haven't rated". Tags have an **Untagged** chip (`collection_query.dart:81-88`). Level and Rating have no "none" option. Rating is a minimum floor only, and the compiler excludes unrated dances (`filter_compiler.dart:311-315`). Advanced has no level or rating rows (`advanced_query_builder.dart:233-249`).

Related gaps:
- **Rating sort.** Rating is shown on the card and filterable, but there is no Rating sort. The core already implements `SearchSort.rating` (`search_sort.dart:38-42`; `filter_compiler.dart:169`). The UI enum leaves it out (`collection_query.dart:10`).
- **Level ranges.** Level is "is any of" only (`collection_query.dart:404`, `LevelFilter(id)` = `eq`). For the "easy" in the user story the caller must tick each easy level, although core has `LevelOp.lte` (`search.md:93-98`).

### FIND-11 — Batch level, rating, tunes and custom-field changes have no error path, and their Undo is weaker than batch tags' — **Low · Traced**

- **Error handling.** `_applyTags` wraps its write in try/catch and shows `collectionBatchApplyError` (`dance_list_screen.dart:1285-1353`). `_batchSetLevel`, `_batchSetRating`, `_batchAddTunes`, `_batchClearTunes` and `_batchCustomField` have no catch (`:1426-1801`). A failed write gives no message and leaves selection mode open.
- **Undo.** Each of their Undos writes one dance at a time outside a transaction (`:1496-1509`, `1593-1606`, `1729-1738`, `1804-1818`). The tag Undo is transactional (`:1401-1418`).
- **Custom-field Undo** restores each dance's *whole* custom-field list. That overwrites any other field changed in the meantime, for example by sync.
- **Choice fields.** The batch dialog has no "＋ new option" for a choice field, which the single-dance editor offers (`batch_custom_field_dialog.dart:159-173` vs `collection.md:350-352`).

### FIND-12 — The Ctrl/Cmd-K palette matches titles differently from every other surface and can hide the obvious hit — **Low · Traced**

- **Matching.** Plain Dart `toLowerCase().contains` over titles (`command_palette.dart:144-161`). No diacritic folding: Collection's 1–2 character path folds diacritics (`database.dart:28`), the palette does not.
- **Order.** The source list is ordered by `dances.title` with SQLite's default BINARY collation (`dance_repository.dart:1826-1832`). Uppercase titles therefore sort before lowercase ones, and articles are not ignored.
- **Cap.** Only the first 8 per group are shown, in that alphabetical order rather than exact-or-prefix first.
- **Effect.** Typing "hey" in a large library can bury the dance titled "Hey" behind "Cheyenne…". The capped count ("8 of 23") is at least honest.

### FIND-13 — Turning a custom field's "Searchable" off does not stop the search bar from matching it; yes/no values are matched as "true" and "false" — **Low · Traced**

- **Toggle.** Its subtitle is "Expose this field as a filter in the search panel" (`app_en.arb:11769`). It only hides the facet (`collection_data.dart:472`).
- **Indexing.** Every live field's value still goes into the FTS `custom_values` column (`dance_repository.dart:1552-1555`). A private "problems at this venue" note stays findable by All fields.
- **Booleans.** Values are indexed with `toString()`, so searching "true" or "false" matches every dance with any yes/no field set.

### FIND-14 — Tapping a tag chip throws away the whole search with no Undo, and from Programs it moves you to Collection — **Low · Decision · Traced**

- **In Collection.** Tapping a tag chip on any row replaces the query. Text, all facets, By phrase, the Advanced tree and online mode are cleared (`dance_list_screen.dart:476-496`). A carefully built Advanced query is lost to a tap on a small chip in a dense row.
- **From Programs.** In a dance detail opened from the Program summary, the chips are live (`program_summary_screen.dart:1126-1132`, not read-only). Tapping one switches the shell to Collection and pops every route (`app_shell.dart:123-134`).
- **Options.** Add the tag to the current filters instead, or offer Undo.

### FIND-15 — Sorting is English- and ASCII-centric although the app ships in da, de, fr and ja — **Low · Decision · Traced**

- **Articles.** Only "the", "a" and "an" are ignored (`title_sort_key.dart:6`).
- **Comparison.** Lowercased strings are compared by UTF-16 code unit (`dance_repository.dart:2944`). The SQL base order is `COLLATE NOCASE`, which folds ASCII case only (`filter_compiler.dart:170`). "École", "Über …" and "Ångström" all land after Z. Danish Æ, Ø, Å come out in code-point order, Å < Æ < Ø, instead of Æ < Ø < Å.
- **Authors.** Author sort uses the first author's *full name* (`dance_repository.dart:2979-2991`), so Gary Roodman files under G.
- **Options.** Locale-aware collation (ICU or `intl`); per-locale article lists; sort authors by surname.

### FIND-16 — Internal role tokens leak into partial searches — **Low · Traced (not executed)**

Figure text is stored with literal tokens such as `role1s` and `role2s`, because the canonical dialect has no role words (`dialect.dart:197-200`, `search.md:22`). The search bar's canonical branch searches every column, including figure text. So while typing:
- "ro" prefix-matches `role…` in almost every dance;
- "rol", "role" and "ole" substring-match it;
- "rob" or "robi" match no figures;
- "robin" matches again.

Typing "Rolling Off a Log" or "Roodman" therefore shows nearly the whole library for a keystroke or two, and the result count jumps around.

### FIND-17 — The add-to-program sheet for a single dance is weaker than the program picker — **Low · Traced**

- **What it lists.** Every program, including long-past Performed ones, with no search or status. Programs are sorted by last edit (`add_to_program_sheet.dart:28-30`, `71-84`).
- **Duplicates.** It does not mark programs that already contain the dance. The editor picker shows "in program ×N" (`collection_picker.dart:991-1047`).
- **New program.** It offers "Create a new program with this dance" only when no programs exist (`:61-70`).
- **Undo.** Undo restores the program's whole earlier slot list (`:233-241`), which would overwrite any edit made in between.

## Cross-cutting patterns

1. **No shared "dance matcher".** At least six surfaces match dance or move text in their own way:
   - Collection FTS: phrase for 3+ characters, token-prefix for 1–2, diacritics folded only for 1–2.
   - Command palette: Dart `contains` over titles.
   - Related-dance picker: Dart `contains` over titles.
   - Search's move type-ahead: canonical names and keywords.
   - Editor's move autocomplete: dialect-aware.
   - Glossary: dialect, canonical and keywords.

   The same query gives different answers depending on where it is typed (FIND-4, 5, 12, 16).
2. **"Called" has three definitions.** Card count and facet: setting-aware and caller-scoped. Last-called sort: performed-only, unscoped, marking time. Guide: "programmed". Venue appears only in the detail view (FIND-1, 2).
3. **Dialect support reaches roles, not moves, outside the editor and Glossary.** Role words are handled thoroughly (active dialect, legacy synonyms, union enrichment). Move substitutions are reversed only for structured `FigureLeaf`s, which the type-ahead never produces from dialect wording (FIND-4).
4. **The picker gets Collection features piecemeal.** It shares Filters, By phrase and Advanced, but not Search in, sort, online scopes or card fields (FIND-7). New Collection features do not automatically reach it.
5. **Organizing tools stop at "add".** You can add tags, levels, ratings and fields in bulk. You cannot rename or delete tags (FIND-3), delete in bulk, find what is missing (FIND-10) or merge duplicates (FIND-9).

## Checked and fine

- **Soft-deleted dances** are excluded from the compiled search, relevance search, palette, picker, tag lists and facet vocabularies (`filter_compiler.dart:117`, `140`; `dance_repository.dart:1833-1835`).
- **Tombstoned tags, authors, sources, levels and custom-field definitions** match nothing. Joins: `filter_compiler.dart:196-259`, `400-403`, `450-466`.
- **Role-word dialect search** works across the active dialect, legacy synonyms ("gents") and every saved dialect (`SearchEnrichment`). This holds in both Collection and the picker (`collection_picker.dart:367-368`), and a raw branch keeps names such as "Robin Hayden" verbatim (`filter_compiler.dart:359-372`).
- **Hidden filter sections** clear their selection in both Collection and the picker. The hidden set is shared, as documented (`dance_list_screen.dart:407-411`, `collection_picker.dart:224-228`).
- **Facets and searches do not leak between surfaces.** Each surface owns its own `FacetSelections`. The only cross-surface push is the tag-chip request (FIND-14).
- **Batch writes are single-transaction and idempotent,** and report "no changes" honestly (`dance_repository.dart:2369-2405`). Undecodable tune lists are skipped by batch tunes and by its Undo (`dance_list_screen.dart:1623-1633`).
- **Best match** degrades to Title when the query stops qualifying, and is never saved as the default sort (`dance_list_screen.dart:738-744`, `779-784`).
- **The Called facet and the "called ×N" card** use the same performed setting and caller scope (`dance_list_tile.dart:114-116`, `collection_picker.dart:835-837`).
- **Ignore-articles** is honoured identically by Collection and picker, and updates live.
- **Tunes facet** semantics match the guide, including the undecodable-JSON guard (`filter_compiler.dart:221-242`).

## Out of scope but noticed

- **Programs / navigation (Inferred).** The tag-filter navigation does `popUntil(isFirst)` (`app_shell.dart:131`). `Navigator.pop` does not consult `PopScope.canPop`, so a route with unsaved state below a non-read-only dance detail would be dropped. I found no current path from the program editor; the editor's preview is read-only.
- **Copy/presentation.** Yes/no custom fields render on cards as "Label: true" or "Label: false" (`collection_data.dart:545`).
- **Delete UX.** Swipe-to-delete skips the "Confirm before delete" setting by design (`dance_list_screen.dart:2965-2970`); the ⋮ Delete honours it.
