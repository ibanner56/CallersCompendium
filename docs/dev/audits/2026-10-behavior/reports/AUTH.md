# AUTH: Getting a dance in accurately

User story: *"I learned a dance at a weekend. I want to get it into my collection quickly and correctly, in my own shorthand, and trust that what I see is what I'll call."*

## Scope & method

**Read:**
- User docs: `docs/user/authoring.md` (all of it), `docs/user/glossary.md`, and the Move-defaults and Meanwhile/Modifier-defaults part of `docs/user/settings.md`.
- Editor and its model: `app/lib/src/screens/dance_editor_screen.dart`, `app/lib/src/screens/dance_editor/dance_editor_controller.dart` (all of it), `dance_editor_form.dart` (shorthand wiring, walkthrough snippets), `app/lib/src/editor/figure_draft.dart`, `editor_snapshot.dart`, `editor_undo_stack.dart`, and the header of `editor_draft_codec.dart`.
- Widgets: `app/lib/src/widgets/move_autocomplete.dart`. In `figure_list_editor.dart` I read the add, free-text, replace and accordion code, the row summary, the move and param mutations, the container editor, the side editor and the beat total.
- Shorthand editors: `shorthand_mapping_editor_screen.dart`, the validation in `compound_shorthand_editor_screen.dart`, and the token sets in `shorthand_mappings_screen.dart`.
- Glossary figure editor: the save and name-collision code. Glossary figure detail: the delete flow.
- Core: `imports/free_text_entry.dart` (all of it), the classifier in `figure_front_end_fan_out.dart`, the upgrade code in `reparse_custom_figures.dart`, `deriveSections` in `phrase_structure.dart`, `param_change_rules.dart`, the hey, swing and mad robin move definitions, and the renderer's summary, meanwhile and modifier paths.
- Display consumers: `widgets/figure_table.dart` (detail view) and the figure rows in `screens/perform_card.dart`.

**Ran:** a throwaway Dart package in `scratchpad/authprobe/` with a path dependency on `compendium_core`. Nothing in the repo was touched. Scripts `bin/probe*.dart` send about 80 realistic caller lines through `parseFreeTextFigureEntry`. They dump params, notes and beats, and render each result the way the editor, the detail view and Perform do. A second probe reproduces `MoveAutocomplete._optionsFor`'s first-match rule against the taxonomy. Every probe output quoted below is real.

**Did not:** build or run the Flutter app, or run any app test.

---

## Findings

### AUTH-1: A typed figure line is silently thrown away unless you press Enter or Add (High, Traced)

**Scenario.** Free-text entry is on. The caller opens **Add figure**, types `neighbors balance and swing`, then does one of these:
- taps **Done** under the box;
- taps the **Save** button;
- uses the back gesture.

**What happens.**
- **Done** calls `_dismissFreeText`, which clears the box: `figure_list_editor.dart:753-758`, wired at `:1185-1187`. The keyboard's own Done/Enter action does the opposite and adds the line (`textInputAction: TextInputAction.done`, `onSubmitted: _submitFreeText` at `:1129,1135`). Two "Done"s on the same field have opposite effects.
- The box's `onChanged` only clears the confirmation text (`:1130-1134`). It never notifies the controller. So the typed line:
  - is not in the autosave snapshot (`captureSnapshot` has no composer state, `dance_editor_controller.dart:722-772`);
  - does not mark the editor dirty, so if nothing else was edited, back leaves without the **Discard changes?** prompt (`dance_editor_screen.dart:807`);
  - is not read by `_save` (`dance_editor_screen.dart:385-450`).

  The dance is saved without the figure the caller just typed, and nothing says so.

**Expected.** The guide says "Nothing you type is ever thrown away" (authoring.md:59-61). Either Done/Save should commit a non-empty line, or leaving should warn.

**Same root, structured mode.** Text typed in a row's **Move** box without pressing Enter is never applied, because `MoveAutocomplete` only acts in `onSubmitted` (`move_autocomplete.dart:252-261`).

### AUTH-2: Rows that look like part of the dance are dropped on save with no warning (High, Traced)

`DanceEditorController._figures` (`:258-268`) builds the save from `draft.toFigures()`. `FigureDraft.toFigure` returns `null`, and the row simply disappears, in these cases (`figure_draft.dart:340-356, 399-400`):

- **A row with no move.** This includes a row whose Move box the caller cleared while retyping. `onCleared: _clearMove` (`figure_list_editor.dart:2381, 1724-1735`) wipes the move and every param as soon as the field is empty, but keeps the note. So a cleared row's note is silently lost too.
- **A meanwhile with fewer than two filled sides.** Example: **Add meanwhile** with cleared defaults gives two blank sides. The caller fills side 1 with "neighbors swing" and saves. The whole group, including the filled side, is gone.
- **A modifier group whose core (first child) is blank.** The filled modifier children go with it (`:346-349`).
- **Any group containing an incomplete nested group.** The whole outer group is dropped, including its complete sides (`:350-351`).

**Why the caller doesn't notice.** In the editor each of these is still a visible row ("Meanwhile, 2 sides", "(empty — choose a move)"). The running **Total** counts every container's beats (`figure_list_editor.dart:852-866`). So the beat total on screen includes groups that will not be saved, and it disagrees with the **Warnings** card, which is computed from the built figures (`controller:713`). `_save` validates only the form.

The guide documents the two-sides rule (authoring.md:394-395) but promises nothing is thrown away. A save-time "N rows are incomplete and won't be saved" prompt, or keeping them as custom figures, would close this.

### AUTH-3: Notes on a meanwhile side or modifier child are never shown outside the expanded editor (High, Traced)

**How the note gets there.**
- The side editor offers **Add note** for every side (`figure_list_editor.dart:3811-3837`), and the note is saved on the child (`figure_draft.dart:343`).
- The free-text parser also puts leftovers on child notes.

**Where it is lost.**
- `renderSummary` for a meanwhile joins the children's summaries without their notes (`renderer.dart:255-269`). The modifier path does the same (`renderer.dart:460-500`).
- The detail view (`figure_table.dart:84-101`) and Perform (`perform_card.dart:1026-1049`) show only `sf.figure.note`, the top-level note.
- The collapsed editor row shows only the group's own note (`figure_list_editor.dart:1898`).
- Nothing in `export/` walks `subFigures`.

**Probe.** `robins allemande right 1 1/2 while larks orbit` parses to `meanwhile{beats:0, [allemande(who:role2s, hand:right) note="1 1/2", custom "role1s orbit"]}` and renders everywhere as **"robins allemande right once while larks orbit"**. The 1½ the caller typed is shown nowhere; the figure says "once".

This directly breaks "what I see is what I'll call".

### AUTH-4: The free-text parser keeps a wrong structured reading when the rest of the line goes into a note (High, Traced via probe)

**The mechanism.** The fan-out accepts a "note-bearing" parse as a structured win (`figure_front_end_fan_out.dart:52-59, 136-138`). The only guard, `_noteIsLeftover` (`:166-179`), demotes a parse only when the note is *exactly* a move name, `and back`, or a bare number. Any extra word slips past it. The typed facts end up in the note, and the structured part shows defaults that contradict them.

**Probe results** (Larks/Robins dialect; rendered text plus note, beats):

| Typed | Saved as | Problem |
|---|---|---|
| `circle left 3/4 and pass through` | **circle left 4 places** · note "3/4 and pass through" (8) | Main line contradicts the note |
| `partners balance and swing, end facing down` | **partner balance** · note "and swing, end facing down" (**4**) | Swing lost from the move; 12 beats short. Without ", end facing down" the same line gives a 16-beat balance & swing |
| `petronella twice` / `petronella turn x2` | petronella · note "twice" (**4**) | Should be 8 beats |
| `Ladies chain over & back!` | robins chain · note "over & back!" (**8**) | `ladies chain over and back` stays custom, as the guide promises (authoring.md:98-103). The `&` spelling slips past `_andBackNote` (`:179`) |
| `down the hall four in line, turn alone` | down the hall · note "four in line, turn alone" | A second move hidden in the note |
| `circle left 3/4 4 bars` | circle left 4 places · note "3/4 4 bars" | Main line contradicts the note |

The **Re-check custom figures** upgrade uses the same classifier (`reparse_custom_figures.dart:176-188`). It can turn an honest imported custom into one of these readings, though the user confirms a preview first.

**Fix direction.** Demote any parse whose note contains a move name or a turn or count token, not just a note that *is* exactly one.

### AUTH-5: Whether a beat count you typed is protected depends on invisible history (Medium, Traced)

`beatsTouched` decides whether a parameter change may recompute beats (`param_change_rules.dart:41-90`). It is set inconsistently:

- **Opening a saved dance:** `true` for every figure, because each stored figure carries `beats` (`FigureDraft.fromFigure`, `figure_draft.dart:51`).
- **After any Undo, Redo or draft Restore:** `false` for every figure. `FigureDraftSnapshot` does not capture the flag, and `toDraft()` takes the default `false` (`editor_snapshot.dart:28-51, 92-110`).

**Scenario.**
1. Open a saved dance.
2. Switch a swing's prefix to *balance*. Beats stay at 8.
3. Undo any unrelated edit, then make the same change. Beats now jump to 16, overwriting a count you typed by hand.

Settings.md:447-450 promises a hand-typed beat count only changes on a balance toggle.

The test `FigureDraftSnapshot round-trips a meanwhile group losslessly` (`app/test/editor_autosave_undo_test.dart:390-413`) sets `beatsTouched = true` but never checks it after the round-trip.

### AUTH-6: Undo within half a second of typing loses what you typed and reverts one extra step (Medium, Traced)

Text edits push their undo snapshot only after a 500 ms pause (`scheduleUndoPush`, `controller:877-886`). `undo()` cancels that pending timer without pushing it (`:888-899`), then steps back from the last snapshot that *was* pushed.

**Scenario.**
1. Change the Type to Square.
2. Type "Petronella Mixer" in the title.
3. Press Ctrl+Z right away.

The title change and the Type change are both undone. Redo brings back the Type change, but the typed title is gone for good.

Ctrl+Z inside a text field reaches this handler: the editor's own `Shortcuts` sits closer to the field than the app-level `DefaultTextEditingShortcuts`, and `EditableText` declares no shortcuts of its own (checked in the Flutter SDK). So this is the common case. No test covers undo during the debounce.

### AUTH-7: "Move defaults" apply to the structured picker only, not to free text, shorthands or Move-box retyping (Medium, Traced)

- `_selectMove` applies `moveParamDefaults` (`figure_list_editor.dart:1585, 1706-1722`).
- Every free-text path builds rows with `FigureDraft.fromFreeTextFigure`, which fills only `taxonomy.effectiveParams` (`figure_draft.dart:74-101`). The controller has no `moveParamDefaults` at all (`controller:1432-1503`).

**Example.** With a Move default of hey `length: full`:
- picking **hey** gives a 16-beat full hey;
- typing `hey` gives an 8-beat half hey.

The guide says Move defaults are "applied whenever you insert that move" (authoring.md:570-572, settings.md:441-443).

### AUTH-8: Pressing Enter in an existing row's Move box picks the first substring match, not the exact name or your shorthand (Medium, Traced)

`MoveAutocomplete.onSubmitted` picks `options.first` whenever *any* option's name, id or keyword *contains* the text (`move_autocomplete.dart:252-257`). Options are in taxonomy order, with the user's own figures first (`:142-146`). Probe results:

- **`star` gives "star through", not star.** It is the only taxonomy name for which this happens. The free-text box reads `star` as a star, so the two entry paths disagree on a common call.
- **Short shorthand tokens never reach the shorthand.** `sw` picks swing, `bal` and `la` pick balance, `cl` picks circle, `rl` picks butterfly whirl, `ra` picks cross trails. So a shorthand like `rl` typed into a row's Move box picks a move, contradicting authoring.md:235-240 ("A shorthand of any kind works in an existing figure's Move box too").
- **One of your own figures wins over the built-in move.** A figure named "Hey with a twist" is picked when you type `hey` and press Enter.

### AUTH-9: Retyping a row as free text drops its progression mark, note and walkthrough step (Medium, Traced)

- `replaceWithFreeTextFigures` and `placeShorthandDrafts` swap the row out whole (`controller:1453-1467, 1473-1490`).
- Picking a new move with `_selectMove` keeps the row's `note` and `progression` (`figure_list_editor.dart:1560-1592`).

So the same intent, "change this figure's move", keeps or loses the **progression mark** depending on how you typed it. Nothing announces the loss. Undo recovers it.

### AUTH-10: Restoring a draft can silently overwrite newer changes (Medium, Traced restore path; intermediate-edit sources Inferred)

The draft has no baseline: no `updatedAt` or version in `editor_draft_codec.dart`. `applyRestoredDraft` replaces every field (`controller:677-689, 778-860`), and the prompt says only "You have an unsaved draft for this dance". It gives no age and no "this dance has changed since".

**Scenario.**
1. Edit a dance; the app is killed.
2. Later, add a tag in bulk, change the rating from the detail view, receive a sync, or run Re-check custom figures.
3. Open the editor and choose Restore, then Save.

Those later changes are reverted without warning.

Separately, every new dance shares the one draft key `editor_draft:new` (`controller:454`). An abandoned new dance is offered as "this dance" when you start a different one, including one seeded from a program slot.

### AUTH-11: Groups start at 0 beats and never follow their sides (Medium, Traced)

These paths all create a group with 0 shared beats:
- free-text `circle left || neighbor swing` and `ones swing while twos circle left` (probe: `params: {beats: 0}`); `fromFreeTextFigure` deliberately leaves a container's own count as parsed (`figure_draft.dart:85-95`);
- **Add meanwhile** or **Add modifier** with blank defaults (`controller:1377-1383`);
- every group made in the shorthand editor (`shorthand_mapping_editor_screen.dart:121-139`).

Picking moves for the sides never updates the group's count (`_MeanwhileSideEditor._selectMove`, `figure_list_editor.dart:3492-3515`). A single typed figure "starts with the figure's usual beats" (authoring.md:80-81); a typed group does not.

### AUTH-12: A beat mismatch is flagged only in the editor; elsewhere the section labels silently shift (Medium, Traced)

- `deriveSections(..., issues:)` is called with an `issues` list only by the editor controller (`controller:713`).
- The detail view (`figure_table.dart:44`), Perform (`perform_card.dart:964`) and print/export (`program_figure_widgets.dart:24`) call it without one.
- Import review shows no beat check at all.

A dance saved with a 0-beat group (AUTH-11), a 4-beat "partner balance" (AUTH-4) or an imported short line shows A1/A2/B1/B2 headers computed from the wrong totals in Perform. No indicator says the beats don't add up.

### AUTH-13: A bare "hey" asserts facts the caller never typed (Low, Decision, Traced)

`hey` gives "robins start a half hey - rights in center, lefts on ends", 8 beats. `hey for four` gives a full 16-beat hey (authoring.md:119-121). Bare `swing` shows "partner **(assumed)** swing", but the hey's defaulted `pass1` and `shoulder` are shown with no assumed marker. The cause: `assumedSubject` tracks only `who`, and hey has no `who`.

**Options:**
- **(a)** mark defaulted dancer-set parameters as assumed generally;
- **(b)** let a bare `hey` render without the defaulted pass and shoulder;
- **(c)** accept it as documented behaviour ("A name on its own gives the figure with its usual options").

### AUTH-14: The "Couldn't parse — kept verbatim" badge is sticky and not accurate (Low, Traced)

- A free-text custom gets `CustomOrigin.importGap`. Editing its text keeps that origin: `_applyNonBeatsParamChange('text', ...)` never resets it (`figure_list_editor.dart:2393-2400`). So a line the caller deliberately rewrote keeps the "couldn't parse" badge and can still be "upgraded" by Re-check later.
- The text is not verbatim: role words are rewritten. Probe: `Lady of the Lake figure` is saved as `role2 of the Lake figure` and shown as **"robin of the Lake figure"**; `Men & women swap` is shown as "larks & robins swap". Runs of spaces are collapsed.
- The guide lists only man, men, lady and ladies (authoring.md:287-289); the probe shows "women" is rewritten too.

### AUTH-15: The shorthand list preview hides parameters that distinguish shorthands (Low, Traced)

`_summarize` uses `render()`, not `renderSummary()` (`shorthand_mappings_screen.dart:93`). Probe: "balance & petronella" previews as "petronella", and "long lines forward" (no go-back) previews as "long lines". Two different shorthands can look identical. `import_shorthand_seed_screen.dart:82` and `compound_editor_screen.dart:1609` do the same.

### AUTH-16: Counts in bars don't behave as the guide says (Low, Traced via probe)

Authoring.md:126-127 says a count in bars "is kept as a note on the figure":
- `circle left 4 bars` does become circle + note "4 bars";
- `neighbor swing 2 bars` and `star right 6 bars` become whole-line custom figures.

### AUTH-17: A dialect change while editing, or a restore under another dialect, mis-saves figure-note text (Low, Inferred)

- `updateDialect` restyles only the prose controllers (`controller:466-471`).
- Figure notes and custom text were rendered into the *old* dialect at load (`:106-126`), or captured in it in an autosave draft, but are canonicalized against the *new* dialect at save (`:97-98`).

Built-in role words survive through the legacy synonym set. A custom dialect's role words would be stored literally and stop following dialects. I did not find an in-editor dialect switch; the realistic path is crash, change dialect, Restore.

---

## Cross-cutting patterns

1. **Editor state that doesn't feed the save, the draft or the dirty flag.** The composer text (AUTH-1), un-entered Move-box text (AUTH-1), incomplete rows (AUTH-2), and `beatsTouched` missing from snapshots (AUTH-5). The editor shows things the saved dance will not contain, and nothing reconciles the two at Save. One "what Save will write" pass would cover AUTH-1 and AUTH-2: flush or warn about pending text, and list rows that won't be saved.
2. **Container children are second-class.** Their notes don't render (AUTH-3). The parser parks leftovers there (AUTH-3, AUTH-4). Group beats don't derive (AUTH-11). Free text and shorthands aren't available in sides (documented). Most container gaps trace to "the renderer and the beat model treat a group as one leaf".
3. **The same intent goes through different code depending on the entry path.** The structured picker, the free-text box, the Move box with free text on, and the Move box with free text off each:
   - pick differently (AUTH-8);
   - apply Move defaults differently (AUTH-7);
   - keep or drop progression and note differently (AUTH-9);
   - seed beats differently (AUTH-5, AUTH-11).

   A single "make a row from (text | move | shorthand)" function in the controller would remove most of these.
4. **Validation lives only in the editor.** The beat total and warnings exist only there (AUTH-12). The read-only surfaces trust the data.

## Checked and fine

- `neighbor balance & swing` (free text) and picking swing → neighbors → prefix balance (structured) give the same 16-beat figure.
- Shorthand token uniqueness: covers all three kinds, including tokens hidden while Custom Figures is off (`shorthand_mappings_screen.dart:150-157`). Both shorthand editors show the shadow warning, and the glossary-name check includes shorthand tokens.
- An unreadable stored transcription is preserved on save, and the "Add figure" placeholder does not defeat that (`_preserveStoredFigures`).
- The autosave write/clear race (#616) is handled with a generation counter and a chained queue.
- Deleting one of your own figures states how many dances use it and what happens to them.
- Compound placeholders: expanded at save with the live definition; the fallback is documented and shown on the row.
- Free text `sw` becoming a custom figure (not a swing) is documented and as described.
- An invalid phrase structure blocks Save through the field validator; warnings keep the last good state.
- Ctrl+Z inside a field reaches the editor's undo consistently: no competing text-field undo.

## Out of scope but noticed

- The program editor likely shares the debounce-then-undo pattern of AUTH-6; not checked.
- The walkthrough snippet "learn on first entry" writes to the global snippet library immediately, even if the dance edit is then discarded (`dance_editor_form.dart:813-818`). Documented, but it can't be undone.
- "Fill from snippets" silently truncates the walkthrough at `kMaxWalkthroughLength` (`dance_editor_form.dart:899-901`).
