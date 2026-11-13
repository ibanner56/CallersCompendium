# PRES — Does every setting apply everywhere it should?

## Scope & method

User story: a caller sets dialect, capitalized figures, decimal turns, a date format, first day of week, formation and tag colours, and collection card fields, and expects every dance and program surface to follow those choices. They also expect to know which settings follow them to their other devices.

**Read:**
- User guides: `docs/user/settings.md` (all of it), the dialect and Perform sections of `docs/user/dialects.md` and `docs/user/perform.md`, plus the relevant parts of `accessibility.md`, `programs.md`, `sharing.md` and `backup-portability.md`.
- Design: `docs/design/sync.md` §"Device Sync's own configuration never syncs" and §"The settings migration has a one-time ordering effect".
- Code:
  - every `*_scope.dart` consumer for the display settings (by grepping `XScope.of`);
  - every `FigureRenderer.render*` call site in `app/lib`;
  - every date-formatting call site;
  - every delete site;
  - `settings_registry.dart` against `sync_setting_labels.dart`;
  - the `main.dart` preference load/reload path;
  - the program-dialect resolver;
  - the dialect quick-switch;
  - the Collection, Programs and picker sort paths.

**Method:** I built a matrix of setting × surface (below). For each gap, I opened the call path. Nothing was built or run. One renderer behaviour is backed by an existing unit test rather than a run (noted where used).

### Matrix (✓ honours · ✗ bypasses · – n/a / documented exclusion)

| Surface | Active dialect | Discouraged auto-convert | Decimal turns | Capitalize | Verbose | Date format | Formation colour | Sort-ignore-articles |
|---|---|---|---|---|---|---|---|---|
| Dance detail (FigureTable) | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ calling history | ✓ | – |
| Dance editor figure list | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – |
| Perform card (dance + program) | ✓ (program dialect wins) | ✓ | ✓ | ✓ | – (documented) | – | ✓ header | – |
| Perform walkthrough overlay | ✓ | ✓ | – | – | – | – | – | – |
| Glossary | ✓ | ✗ | ✓ | ✓ | ✓ | – | – | – |
| Collection tile | ✓ | ✓ (custom-field quirk, PRES-8) | – | – | – | – | ✓ | ✓ |
| Collection picker (program) | ✓ | ✓ | – | – | – | – | ✓ | ✓ (card fields ✗, PRES-15) |
| Programs list | – | – | – | – | – | ✓ | – | ✗ (PRES-9) |
| Program summary / builder | ✓ (app dialect only) | ✓ | – | – | – | ✓ | ✗ (family tint instead) | – |
| Matrix (screen + PDF) | ✓ | ✓ | – | – | – | ✗ PDF | ✗ (deliberate) | – |
| Dance PDF / text | ✓ | ✓ | ✗ (PRES-10) | – (documented) | – | – | – | – |
| Program PDF / text / email | ✓ (app dialect only) | ✓ | ✗ | – | – | ✗ (PRES-3) | – | – |
| Shorthands list | ✓ | ✗ | ✗ | ✗ | – | – | – | – |
| Import review diff | ✓ (snapshot) | ✗ | ✗ | ✗ | – | – | – | – |
| Sync conflict details | ✓ | ✗ | ✗ | ✗ | – | ✗ (intl yMMMd) | – | – |

---

## Findings

### PRES-1 — Device-specific settings sync silently, and the first connection overwrites them · **Medium · Decision · Traced**

**Scenario:**
1. A caller uses a laptop at a projector with the *High contrast* theme and English UI.
2. Their phone is on a *Dark* palette, German UI, with Reduce motion forced on.
3. They connect the phone to Device Sync.

**What happens:** Every `_preference`-classified key is `shareable`, and every `shareable` settings row syncs (`sync_storage.dart:457`). That includes:
- `theme_mode` and `active_custom_theme`
- `app_locale`
- `reduce_motion`
- `perform_stage_mode` and `auto_size_perform_cards`
- `last_used_*_sort`

The registry lines are `settings_registry.dart:92-96`, `:112`, `:288`, `:301` and `:122-125`.

On the first sync the most recently stamped value wins each key without asking (`docs/design/sync.md:5286-5290`). After that, last-writer-wins applies, and the change is reloaded live into the running UI (`main.dart:1052-1079`, `_reloadSyncedSettings`). So the laptop's UI language and theme can change mid-session.

**What they'd expect:** Either these stay per-device, or the app tells them they travel. The UI never lists what syncs:
- `settingsSyncIntro` says only "Keep your library in step" (`app_en.arb:643`).
- The only "belongs to this device" statement in the guide covers the Device Sync settings themselves (`settings.md:897-899`).
- The App language text promises only that it "is remembered next time you open the app" (`settings.md:324-328`).

**The split is also internally inconsistent:**
- `perform_text_scale` is kept `deviceLocal` because it is "tuned to the screen it was set on" (`settings_registry.dart:302-310`).
- The sync design keeps `sync_wifi_only` local because "a laptop and a phone want different answers" (`sync.md:622`).
- The same reasoning fits theme, stage theme, auto-size, language and reduce-motion, yet those all sync.

**Options:**
- (a) Reclassify the screen- and device-bound keys as `deviceLocal`. Candidates: theme and active custom theme, `app_locale`, `reduce_motion`, `perform_stage_mode`, `auto_size_perform_cards`, `last_used_*`.
- (b) Keep them synced, but add a "What syncs" list to the Device Sync section and a "synced" marker on affected rows.
- (c) Offer a per-device override.

Right now nobody has been asked to decide this: the `_preference` default decided it.

### PRES-2 — "Custom themes are saved on this device" is false; they sync, and deletes propagate · **Medium · Traced**

**Scenario:** A caller trusts the in-app text "Custom themes are saved on this device" (`app_en.arb:2879`, repeated at `settings.md:213-214`). On their phone they delete a theme they only use on the laptop.

**What happens:**
- `custom_themes` is `_preference`, so it is shareable (`settings_registry.dart:59`).
- It has a sync conflict label (`sync_setting_labels.dart`, `'custom_themes'`).
- The guide's own conflict section lists themes as a synced set (`settings.md:1088-1092, 1119`).

The deletion reaches the laptop on the next sync.

**Fix:** Correct the string and the guide. If the product intent really was device-only, reclassify (see PRES-1). The same audit should check `dialects.md:429-432`, which says "Your dialects are stored on your device" and then correctly adds that they sync. That one is fine.

### PRES-3 — The date format setting is ignored in every export and in calling history · **Medium · Traced**

**Scenario:**
1. A caller in the US sets **Day/month/year**.
2. The Programs list shows `27/10/2026`.
3. They print the set list, email it, export the matrix PDF, and open a dance's calling history.

**What happens:** Each of these formats the event date with `MaterialLocalizations.formatMediumDate`, so it shows "Oct 27, 2026":
- the program PDF (`program_export_menu.dart:541`)
- set-list text, copy and email (`program_export_menu.dart:133-134, 176`)
- the matrix PDF (`program_editor_screen.dart:3330`)
- dance-detail calling history (`calling_history_section.dart:424-427`)

The setting is applied only through `formatEventDate` (`regional_formats.dart:190`). Its callers are the programs list, program summary and editor, the add-to-program sheet, ContraDB import and the retirement banner.

**Why it matters:** The guide says the choice "controls how program event dates appear" (`settings.md:298-300`), and calling history is a list of program event dates.

Sync screens use a third formatter, intl `DateFormat.yMMMd` (`sync_conflict_details.dart:117`, `device_sync_section.dart:758`). Those are timestamps, not event dates, so they are lower priority.

**Fix:** Pass `(d) => formatEventDate(d, DateFormatScope.of(context), …)` into the three exporters and calling history.

### PRES-4 — Changing the Default caller leaves Collection "called ×N" counts stale · **Medium · Traced**

**Scenario:**
1. "Track calling history for all callers" is off (the default).
2. The caller enters themselves as **Default caller** in Defaults › Program defaults.
3. They return to Collection.

**What happens:** The default caller is written with a plain `persistSetting`, with no notifier or scope (`defaults_section.dart:629-637`).

Collection resolves the caller filter only in `_boot()` (`dance_list_screen.dart:507-515`). `didChangeDependencies` re-boots only when *track-all-callers* changes (`:384-424`). Collection lives in the shell's `IndexedStack`, so it is never rebuilt fresh (`app_shell.dart:37, 304`).

The result: tiles keep counting other callers' programs until restart or an unrelated reload. Opening a dance re-reads the setting and shows the filtered history (`calling_history_section.dart:145-160`). The tile and the detail then disagree, which breaks the explicit claim "so the card and the detail history never disagree" (`dance_list_tile.dart:110-114`).

The same staleness occurs when `default_program_caller` arrives by sync. It is not in `_preferences` (`main.dart:1052-1079`).

**Fix:** Expose the default caller through a scope or notifier, or have the settings write trigger a Collection re-boot.

### PRES-5 — "Confirm before delete" doesn't cover the swipe-to-delete path · **Medium · Traced**

**Scenario:** A caller with a motor tremor turns on **Confirm before delete**, which sits under General › *Accessibility*. They swipe a dance row and hit the revealed **Delete**.

**What happens:** It deletes with no prompt:
- Collection: `dance_list_screen.dart:2961-2981` (`SlidableAction` → `_softDeleteFromList` directly).
- Programs: `programs_list_screen.dart:727-742`.

The code comments say this exception is intentional. The user docs say the setting "adds a prompt before you delete a dance or program" with no exception (`settings.md:67-68`, `accessibility.md:164-166`). The ⋮-menu comment right next to it still says Delete "routes through the identical confirm + soft-delete + undo flow as the Dismissible swipe" (`programs_list_screen.dart:760-762`; the same wording appears in `dance_list_screen.dart:2904-2906`). That comment contradicts the code.

Undo still exists, so nothing is lost permanently.

**Decision:** Either honour the setting on swipe, or document the exception and fix the comments.

### PRES-6 — Perform's "Switch dialect" has two persistence models, and the "quick look at Canonical" leaks into exports and other devices · **Medium · Decision · Traced**

**Scenario:**
1. Mid-gig, a dancer asks what a figure is in canonical terms.
2. In single-dance Perform, or program Perform when the program has no dialect of its own, the caller picks **Canonical** under **Switch dialect**, as the guide suggests (`perform.md:49-50`).
3. They forget to switch back.

**What happens:** Without a program dialect, the switch calls `controller.setActive` (`dialect_quick_switch.dart:47-53`, used at `perform_dance_screen.dart:429` and `perform_program_screen.dart:1042`). That persists `active_dialect_ref` (`dialect_library_controller.dart:226`), which is a synced `_preference`.

Consequences:
- Next week's PDFs and emails are written in Canonical.
- The caller's other devices flip to Canonical.

With a program dialect, the **same control** is session-only (`perform_program_screen.dart:1043-1047`). Dance detail offers a third, view-only Canonical switch.

This is documented (`dialects.md:359-363`), but one control with different side effects depending on a field set elsewhere is a cohesion problem.

**Options:**
- (a) Make Perform's switch always session-scoped, and keep app-wide switching in Settings and dance detail.
- (b) Keep it app-wide, but add a snackbar with Undo: "Active dialect changed to Canonical for the whole app".
- (c) Split "Canonical peek" (session-only) from "Switch dialect".

### PRES-7 — Several surfaces show figures with the terse `render()`, which drops balance, hall-direction enders and hey length · **Medium · Traced (output inferred from tests)**

**Scenario:** A caller has a shorthand `bp` → *balance & petronella*, or re-imports a dance whose only change is a figure's balance flag.

**What happens:** These surfaces call `FigureRenderer.render`:
- Shorthands list preview (`shorthand_mappings_screen.dart:89-93`)
- User-figure shorthand tiles (`:586-587`)
- The import-review figure diff (`figure_diff.dart:300-315`)
- Sync-conflict shorthand values (`sync_conflict_details.dart:678-680`)

`render` deliberately omits the ContraDB secondary modifiers that `renderSummary` adds: the "balance &" prefix, down/up-the-hall enders, hey length and goBack (`renderer.dart:177-199, 295-330`). The existing unit tests show the two diverge, for example `renderSummary(petronella)` → `balance & petronella` (`renderer_test.dart:1720-1741`).

Effects:
- The shorthand list can read "petronella" for a balance shorthand.
- The import diff can show a "removed / added" pair with identical text, because the canonical keys differ while the displayed text does not.

None of these surfaces apply decimals, capitalize or discouraged conversion either.

**Fix:** Use `renderSummary` (plus the scopes) on any surface that shows a dance's figure to a caller.

### PRES-8 — Turning off auto-convert also turns off role-word substitution for custom-field values · **Low · Traced**

**Scenario:** In a Leads/Follows dialect, a custom field reads "larks start". The caller turns **Auto-convert all discouraged terms** off.

**What happens:**
- Calling notes, hook and tunes still go through `renderFreeText` and show "leads".
- Custom-field values fall back to the raw `field.value` and show "larks" (`dance_detail_screen.dart:1359`, `dance_list_tile.dart:309-320`).
- The ON branch, `renderFreeTextWithCanonicalDiscouragedTerms`, uses the merged role + discouraged substitutor (`renderer.dart:2016-2019`), so with the switch ON the value is "leads".

The guide groups custom-field values with notes (`dialects.md:285-287`).

**Fix:** Use `renderFreeText(field.value, dialect)` in the OFF branch.

### PRES-9 — The Programs list's title sort ignores "Ignore leading articles when sorting" · **Low · Traced**

**What happens:** `programs_list_screen.dart:330-334` compares `title.toLowerCase()` directly. Collection and the program dance picker use `titleSortKey`. So "The Spring Fling" files under **T** in Programs and the equivalent dance under **S**.

The setting's wording ("when sorting", `settings.md:47-49`) does not limit it to dances.

Related: `kIgnoredLeadingArticles` holds English articles only (`title_sort_key.dart:6`), while the UI ships in de, fr, nl and da. That is out of this scope and possibly intended.

### PRES-10 — "Show turns as decimals" never reaches PDFs or text exports, and the guide doesn't say so · **Low · Decision · Traced**

**What happens:** No exporter passes `decimals`. `program_figure_widgets.dart:47-51` calls `renderSummary(sf.figure, dialect)`, and the export directories contain no `decimals` references at all. Capitalize states its export exclusion explicitly (`settings.md:53-55`); decimals, which sits under *Accessibility*, says nothing.

**Decision:** Document the exclusion, or honour the setting on the caller's own printed cards.

### PRES-11 — A per-program dialect applies only in Perform, and a renamed dialect silently unpins programs at showtime · **Low · Decision · Traced**

**What happens:**
- Precedence is consistent and documented: session pick > program dialect > app dialect (`perform_program_screen.dart:963-977`, `programs.md:215-218`).
- The program's dialect is stored by name, so renaming it makes Perform fall back to the app dialect without a word (`program_dialect.dart:28`).
- Only the editor shows "(unavailable)" (`program_editor_screen.dart:4031-4075`). This is documented at `dialects.md:339-342`.
- A caller who sets "Gents/Ladies" on a program also gets an app-dialect PDF for that same program.

**Options:**
- Cascade dialect renames to programs, or warn when Perform opens with an unresolved dialect.
- Consider letting the program's own exports follow its dialect.

### PRES-12 — Formation label colours are absent where formation sequencing matters most · **Low · Decision · Traced**

**What happens:** User formation colours are read only by the dance tile, dance detail and the Perform header (`FormationColorsScope.of` consumers). That matches `settings.md:236-241`.

Program summary and builder rows use a separate fixed formation-*family* palette (`set_list_color_coding`). The matrix formation cell is deliberately plain (`program_matrix_table.dart:720-726`). A caller who colours *Becket CCW* pink to avoid back-to-back Beckets won't see pink in the set list.

**Decision:** Decide whether user overrides should take precedence over family tints in set lists.

### PRES-13 — Settings placement doesn't match what the settings change · **Low · Traced**

- **Collection card fields**, **Collection filters** and **Shared dance fields** sit under *Defaults*, whose intro says "every default here can still be changed on each item later" (`settings.md:334-336`). None of the three are per-item defaults.
- **Default caller** (*Defaults › Program defaults*) silently controls calling-history filtering. Its effect is explained under *Program › Calling history* (`settings.md:186-192`), and its own row says nothing about it.
- Figure-display settings are split three ways:
  - Capitalize: *General › Library*
  - Decimals and verbose: *General › Accessibility*
  - Canonical and discouraged: *Dialect*
- The **Perform stage theme** has no Settings row at all, yet it syncs (`perform_stage_mode`, `_preference`).

### PRES-14 — Reduce-motion override doesn't reach framework animations · **Low · Inferred**

**What happens:** The in-app tri-state is read only through `ReduceMotionScope` by 8 widgets. `MaterialApp` gets no `MediaQuery(disableAnimations:)` override and no `themeAnimationStyle` (`main.dart:2527-2556`). So framework transitions, including the 200 ms theme cross-fade, follow the OS rather than the switch that claims to "override the system setting in either direction" (`accessibility.md:159-163`).

I did not check which Flutter widgets actually consult `disableAnimations`.

One explicit ungated animation exists: `program_matrix_table.dart:626` (`AnimatedOpacity`, 120 ms).

### PRES-15 — Card-field choice applies to Collection only, while its sibling filter setting also covers the picker · **Low · Decision · Traced**

**What happens:**
- *Collection filters* explicitly applies to Collection **and** the program dance picker (`settings.md:367-368`).
- *Collection card fields* applies to Collection only. The picker passes no `visibleFields` (`collection_picker.dart:706-707`).

A caller who hides noisy custom fields still sees them in the picker. The guide's wording is accurate, but the two siblings in the same section behave differently.

---

## Cross-cutting patterns

1. **Settings that are read ad hoc, not through a scope, go stale.** Default caller (PRES-4), dance-detail canonical and free-text entry are read once from `SettingsRepository`. They are absent from `_preferences`, so neither a local edit elsewhere nor a sync reload reaches screens that are already alive. Any setting consumed by an `IndexedStack` tab needs a notifier.
2. **There are two renderer APIs and no rule for which one a surface uses.** `render` vs `renderSummary`, and the plain vs `…WithCanonicalDiscouragedTerms` variants, are chosen per call site. Decimals, capitalize and discouraged conversion are then threaded by hand. Every newer surface (shorthands, import diff, sync conflict, glossary) misses one or more (PRES-7, PRES-8, glossary discouraged). A single "display render" helper that reads all the scopes would close this class.
3. **The "shareable" classification is used as a stand-in for "syncs".** Choosing `_preference` decides sync behaviour, but the classification's question is about privacy, not whether the value makes sense on another device. PRES-1 and PRES-2 follow from that.
4. **Exports bypass the display preferences inconsistently.** Some exclusions are documented (capitalize, active-dialect-only); some aren't (date format, decimals). Users can't predict which.

## Checked and fine

- Collection picker honours sort-ignore-articles, hidden filters and live require-performed (`collection_picker.dart:211-240`).
- Perform card and walkthrough overlay honour dialect, discouraged, decimals and capitalize; verbose is excluded from Perform as documented.
- Program-dialect precedence and fallback are consistent and documented; the editor shows unavailable names.
- Synced settings that *are* in `_preferences` reload live after a sync pass and after a restore (`main.dart:1714-1795`).
- Program editor and matrix pick up a live dialect change, matrix column config and collision mode (`program_editor_screen.dart:604-626`).
- Colour-dance theme defers to High contrast and to the Perform stage theme (`colour_dance_theme.dart:45-49`, `perform_card.dart:573-575`).
- First day of week drives only the Programs strip; the date-picker exception is documented.
- Dance detail, editor and summary deletes all go through `confirmDeleteIfEnabled`.
- The share-fields setting is honoured by dance and program text/PDF exports.
- `perform_text_scale` is `deviceLocal` with a stated reason.
- The add-to-program sheet's recently-updated ordering is a reasonable fixed choice.
- The command palette is title-only and needs no display settings.

## Out of scope but noticed

- `titleSortKey` ignores only English articles despite five other UI languages (search/i18n).
- On first sync, settings resolve by migration-stamp recency, which the design notes as a known "one-time ordering effect" (sync auditor).
- The stale ⋮-menu comment in `programs_list_screen.dart:760` and `dance_list_screen.dart:2904` contradicts the swipe code (docs drift).
