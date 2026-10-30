# Design: Selectable text on desktop

*Design note N5 · v0.2 (2026-10-30) · **Status: decided, not built.** Answers
audit finding PLAT-17 ("Dance content cannot be selected or copied piecemeal")
from the 2026-10 behavior audit. The maintainer answered its five questions on
2026-10-29/30, each as this note recommended (N5-1 … N5-5 in
`maintainer-decisions-2026-10-30.md`, on `claude/app-audit-categories-k2pdon`);
[Decisions](#decisions) quotes them. Conforms to [ux.md](ux.md) "Cross-cutting
UX rules". Docs-only: this note changes no app code and settles no D-11 question
(Save, New and header placement). The Guide citations under "Problem" are for
`main` at `281fce0`; every other line number dates from the note's first draft
(2026-10-29) and may have moved since.*

## Problem

A desktop caller who wants one figure line, the calling notes or a program's
notes in an email has one option: the whole-card **Copy dance** action
(`app/lib/src/widgets/dance_export_actions.dart:170-176`). The dance detail,
the program summary and Perform draw their text with plain `Text`, which a
pointer cannot select.

The audit report says `SelectionArea` appears in the Guide. It does not. There
is no `SelectionArea` and no `SelectableRegion` anywhere in `app/lib`. The
Guide renders with `Markdown(selectable: true)`
(`app/lib/src/screens/user_guide/user_guide_doc_view.dart:173`) and a
`SelectableText` heading builder (`:244`). That makes each Markdown block its
own selection island: a drag cannot cross from one paragraph to the next. The
Guide is a precedent for *whether* to allow selection, not for *how* to build
it here.

## What the code does today

| Surface | Where | Widget today |
| --- | --- | --- |
| Dance detail body | `dance_detail_screen.dart:1068` (`ListView`) | Plain `Text` throughout |
| Hook and calling notes | `dance_detail_screen.dart:1152-1175`, `:1236-1262` | `_CrossReferenceText` (`:1741-1805`): `Text`, or `Text.rich` with `WidgetSpan` links |
| Figure rows | `widgets/figure_table.dart:150-260` | One `Text` for the figure (`:223-229`), one for the note (`:231`), one for beats (`:246`), all inside `Semantics(excludeSemantics: true)` (`:193-195`) |
| Tag chips | `dance_detail_screen.dart:1189-1209`; `widgets/tag_chip.dart` | `ActionChip` when the Collection scope is present, otherwise `Chip` |
| Program summary | `program_summary_screen.dart:698` (`ListView`) | Title (`:725`), detail rows (`_summaryRow`, `:1475`), notes (`:797-800`), set list (`:1335-1400`) |
| Perform card | `perform_card.dart:130-141`; `perform_program_screen.dart:1225-1243` | `Text`, under two 56 px translucent edge `GestureDetector`s that turn pages |

Which text does a copy contain today? **Copy dance** builds `danceToPlainText`
from the same `dialect` local the screen renders with
(`dance_detail_screen.dart:771` and `:1229`), so it follows the canonical toggle
and the dialect. Its `renderer`, `canonicalizeDiscouragedTerms` and labels also
match the screen (`dance_export_actions.dart:106-118`).

## Questions

### 1. Which surfaces?

- **Dance detail: yes.** Header text (title, authors, hook), figures, calling
  notes, provenance, link rows and custom fields. This is the PLAT-17 case.
- **Program summary: yes, for the header.** Title, detail rows and notes. The
  set list stays out of the selectable region by default. Each row is an
  `InkWell` that opens the dance (`program_summary_screen.dart:1335-1337`), and
  carries a mark-performed toggle (`:925-960`). A drag that starts on a row
  title would compete with that tap for little gain, since the caller wants the
  titles as a block, which the program export menu already copies. Decided:
  N5-2 = (a), header text only.
- **Perform: excluded.** The edge zones turn pages on tap
  (`perform_program_screen.dart:1225-1243`), the screen is entered on a
  deliberate gesture and exits on a deliberate one (`ux.md:167-179`), and a
  stray drag mid-set must never change what is on stage. A caller who wants the
  text copies it from the detail or the summary. Decided: N5-5 = (a).
- **Editors and sheets: out of scope.** Their text fields already select.

### 2. Gesture conflicts

Flutter's `SelectionArea` listens for a drag (and, on touch, a long press) in
the gesture arena. A `Slidable`, `InkWell` or `ActionChip` still wins a tap. A
drag that starts on a child with its own drag recognizer is a conflict. Here is
each gesture the audit named:

| Gesture | Where it lives | Conflict? |
| --- | --- | --- |
| Tap-to-filter tag chip | `dance_detail_screen.dart:1196-1203`, `tag_chip.dart` | **Yes, a small one.** The chip's `Text` label would register as selectable, so a drag that starts on it selects the tag name. Wrap the tag row in `SelectionContainer.disabled`. |
| Long-press preview | `widgets/preview_hold_listener.dart`, used only by `program_slot_list_editor.dart:548` and `collection_picker.dart:1024,1172` | **No.** None of those screens is in the selectable region. |
| Row swipe actions | `Slidable` at `dance_list_screen.dart:3172` and `programs_list_screen.dart:739` | **No.** They live on list rows, outside the detail and summary panes. |
| Long-press to enter batch selection | `dance_list_screen.dart:3131` | **No.** Same reason. |
| Cross-reference links | `_CrossReferenceText`, `dance_detail_screen.dart:1779-1795` | **Probably not, but untested.** The link is an `InkWell` in a `WidgetSpan`, and the `Text` inside it is its own selectable. Selection across a `WidgetSpan` is the least-exercised path in the framework. The implementation PR must test that a drag across a link copies the link text once, and a click still opens the dance. |
| Mark-performed toggle, row open | `program_summary_screen.dart:925-960`, `:1335` | Avoided by keeping the set list outside the region. |
| Perform edge zones | `perform_program_screen.dart:1225-1243` | Avoided by excluding Perform. |

Two smaller points. A figure row's beats column and import-gap badge
(`figure_table.dart:246`, `:241-243`) would otherwise copy as stray digits and
a label between lines. Wrap both in `SelectionContainer.disabled` so a copied
figure is its text and its note. And the app owns no selection colours today,
so the first implementation PR checks contrast of the default selection
highlight on the dance-colour tint (`ColourDanceTheme`) and on the high-contrast
theme, per the "no colour-only meaning" rule (`ux.md:196-199`).

### 3. What does a copy contain?

**Options:**

- **A. The rendered text.** Whatever `SelectionArea` finds on screen: the
  dialect's wording, the capitalisation (`CapitalizeFiguresScope`,
  `figure_table.dart:226`), and the verbose text when "always show verbose
  figure text" is on. *Trade-off:* it matches what the caller sees and costs
  nothing extra. It does not carry canonical text unless the caller flips the
  canonical toggle first, which is the same rule the whole screen follows.
- **B. Canonical text always.** Needs a custom selection delegate or an
  invisible shadow `Text` per row. *Trade-off:* a caller who has set a dialect
  to speak their own wording gets text they never typed or saw, and Flutter has
  no supported hook for substituting copy text per `Text`.
- **C. A toggle in the copy menu.** Needs a custom toolbar entry that rebuilds
  the selection from the model. *Trade-off:* the most useful and the most
  code. It gets a model-to-selection mapping the framework does not provide.

**Decided: A** (N5-3 = (a), 2026-10-30, as recommended). "What you see is what you copy" is the rule users
expect from selection, it agrees with **Copy dance** on dialect and the
canonical toggle (both use the same `dialect`), and a caller who wants
canonical text flips the toggle. The two differ in two preferences. A selection
copy carries "always show verbose figure text" and figure capitalisation,
because the screen applies both (`figure_table.dart:223-229`); **Copy dance**
applies neither (`packages/compendium_core/lib/src/export/dance_text.dart:121-122`
renders `renderSummary`, terse and uncapitalised). That is what Option A means,
and the maintainer accepted it: the option text says "it differs from Copy
dance on those two settings". The user docs say so in one
sentence.

### 4. Desktop only, or phones too?

**Options:**

- **A. Desktop only** (Windows, macOS, Linux). Gate on
  `defaultTargetPlatform`, the way `search_panel_bar.dart:108,125` already
  branches. *Trade-off:* it keeps phone behaviour byte-for-byte and the change
  small. It leaves phone callers with **Copy dance** alone.
- **B. All platforms.** *Trade-off:* long-press starts a selection on Android
  and iOS, which is standard but changes what a long press on detail text
  means, adds drag handles over a scrolling `ListView`, and puts a toolbar over
  the Edit FAB clearance zone (`dance_detail_screen.dart:1070-1076`). It needs
  phone-sized golden and gesture tests this note cannot run.

**Decided: A** (N5-1 = (a), 2026-10-30, as recommended), with the gate in one place so B is a one-line change
later. Phone work waits for a phone-selection report; the audit finding is a
desktop one.

### 5. Screen readers

I did not verify this against a screen reader. This is the reasoning and the
test to run.

Figure rows wrap their subtree in `Semantics(excludeSemantics: true)` with the
verbose label (`figure_table.dart:193-195`). The screen reader never sees the
selectable `Text` inside, so a screen-reader user cannot make a text selection
in figures with or without this change. They keep **Copy dance**. Hook, notes,
the summary header and link rows are ordinary semantics, where
`SelectableRegion` exposes the framework's text-selection semantics.

The implementation PR must include a `tester.ensureSemantics()` test that a
figure row's announced label is unchanged, and a manual NVDA/VoiceOver pass
recorded in the PR. The existing label stays authoritative: the change must not
make the row announce twice or read the beats digits an extra time.

### 6. Right-click

B29 (`feat/desktop-shortcuts-and-mac-menu`, the work plan's B29 entry, see "Sources" below) makes
right-click on a dance row and a program row open the ⋮ menu
(`widgets/dance_list_tile.dart:352`, `widgets/program_list_tile.dart:100`; both
are the `PopupMenuButton` construction). Selection's context menu (Copy, Select
all) opens on a secondary tap inside a `SelectionArea`.

The two never meet in the planned layout. B29's handlers sit on list rows in
the Collection and Programs lists. The selectable regions are the detail and
summary panes (and on desktop those are the right-hand pane of the split
view). Neither area contains the other.

**The rule. Decided** (N5-4 = (a), 2026-10-30, as recommended):

1. **Inside a selectable region, the selection menu wins.** Right-click on
   detail or summary text shows Copy and Select all.
2. **On a list row, the ⋮ menu wins.** B29's handler never sits under a
   `SelectionArea`, and a `SelectionArea` never wraps a list.
3. **Any later secondary-tap handler goes outside the region** or on an
   element wrapped in `SelectionContainer.disabled`.

B29 should add a widget test that a secondary tap on detail text shows the
selection toolbar, and one that a secondary tap on a list row shows the ⋮ menu.

**A coordination point with PLAT-8.** B29 replaces the macOS menu with a
`PlatformMenuBar` that has no Edit menu (the work plan's B29 entry).
Cmd-C and Cmd-A still work, because `SelectableRegion` binds them itself. But a
Mac caller loses the menu item for them, so the right-click toolbar is the only
visible Copy. That is one more reason rule 1 should hold.

## Constraints

- **Privacy registry.** The decided design persists nothing: no setting, no
  column. N5-1 = (a) keeps phones unchanged, so no "allow selection" setting
  arises. Had one been added, it would be a settings key classified on
  category, subject and egress in the same PR (`AGENTS.md` "Every persisted
  field must be classified";
  `.github/instructions/privacy-registry.instructions.md`), and the
  `perform_text_scale` precedent would make it `deviceLocal`. The subject axis is the app user, but copied text can carry a
  choreographer's name and a venue's contact details out of the app. That is
  the user's own act, the same one **Copy dance** performs, and it is not
  automatic egress.
- **Sync.** No new record kind and no merge, so sync-spec §6.6 and §6.15 do not
  apply.
- **Undo.** Selection mutates nothing. `ux.md:192-193` (Undo everywhere,
  confirm only where Undo is impossible) is satisfied by having no destructive
  step.
- **Phone-first layouts.** Option A in question 4 leaves phone layouts
  untouched.
- **D-11.** Nothing here touches Save, New or header placement. The summary
  header row (`program_summary_screen.dart:722-756`) stays as it is; selection
  wraps its *text*, not its action buttons.

## Proposed design

One small widget, `SelectableContent`, in `app/lib/src/widgets/`. It wraps its
child in `SelectionArea` on desktop and returns the child unchanged elsewhere.
It carries the single platform gate (Question 4). Callers mark non-selectable
islands with `SelectionContainer.disabled`.

- **Dance detail.** Wrap the `ListView` in `_buildBody`
  (`dance_detail_screen.dart:1068`). Disable the tag chip row, the figure beats
  column and the import-gap badge, and any action buttons in rows.
- **Program summary.** Wrap the header block: title, detail rows and notes
  (`program_summary_screen.dart:722-800`). The action buttons stay out, and so
  does the set list.
- **Tests.** Widget tests for: a drag over a figure row copies its text and
  note without the beats; a drag across a `WidgetSpan` link copies the link
  text once and a click still opens the dance; a chip click still filters; a
  secondary tap on text shows the selection toolbar; the phone path returns
  the child unchanged. Each guard must be shown to fail against a build that
  omits its `SelectionContainer.disabled` (`AGENTS.md` "Tests must be shown to
  fail").
- **Docs.** `ux.md:62-72` (Dance detail) gets one sentence; `accessibility.md`
  "Using the keyboard" (`:119`) gets Cmd/Ctrl-C and Cmd/Ctrl-A for selected
  text, and the screen-reader limit on figures; the user docs name the canonical
  toggle's effect on a copy. The implementation PR adds its own
  `changelog.d/<id>.json` fragment, since it is user-visible. This note adds
  none.

## Decisions

The maintainer answered all five on 2026-10-29/30, each as recommended. Each
entry quotes the decision as `maintainer-decisions-2026-10-30.md` records it.
The maintainer left no notes on these five.

1. **N5-1, platforms.** "(a) Desktop only. Phones stay exactly as now and keep
   only Copy dance; turning it on everywhere later is a one-line change."
2. **N5-2, the summary set list.** "(a) No, header text only. Title, details
   and notes select; set-list rows keep their taps, and the export menu copies
   the titles."
3. **N5-3, copy contents.** "(a) What you see. Copies the wording as shown,
   including verbose text and capitals; it differs from Copy dance on those two
   settings."
4. **N5-4, right-click.** "(a) Copy menu in text, ⋮ on rows. Right-click on
   dance or summary text shows Copy and Select all; on a list row it opens the
   ⋮ menu." This binds B29 too.
5. **N5-5, Perform.** "(a) No, leave Perform out. Nothing on stage changes from
   a stray drag; callers copy from the dance page or the summary."

## Branches

Sized like the work plan (see "Sources"). Each touches only the files named.
Updated 2026-10-30 for the decisions and for what has merged (`main` at
`90fe5e8`: F10 #2022 and U7 #2033 have merged; F11 #2040 is open). In the audit
branch's `design-work-plan.md` these are N5-S1 … N5-S3.

| # | Branch | Main files | Size | Model | Depends on |
| --- | --- | --- | --- | --- | --- |
| S1 | `feat/selectable-detail-text` | new `widgets/selectable_content.dart`; `dance_detail_screen.dart`; `widgets/figure_table.dart`; tests; the `ux.md`, `accessibility.md` and user-doc lines; a changelog fragment | M (~250) | Sonnet | None. N5-1, N5-3 and N5-5 are decided. |
| S2 | `feat/selectable-summary-text` | `program_summary_screen.dart`; tests | S (~100) | Sonnet | S1 (the widget). N5-2 is decided. After F11 (#2040), and after B4 → B5 and B22, which edit the same file (the work plan's hot-files table). |
| S3 | `test/selectable-right-click-rule` | one test file in B29's branch | S (~50) | Sonnet | B29 and S1. Folded into B29 if B29 lands later. N5-4 is decided. |

S1 and S2 share no file, but S2 reuses S1's widget, so S2 follows S1. Neither
edits a privacy or storage path, so neither joins the registry serialisation
queue: N5-1 added no setting.

## Sources

The B29 facts and the branch sizing come from the 2026-10 behavior audit's
`decided-work-plan.md` (the "B29" entry, the "Design notes" section and the
hot-files table), which lives at
`docs/dev/audits/2026-10-behavior/decided-work-plan.md` on branch
`claude/app-audit-categories-k2pdon` and is not on `main` yet. Until it
lands, treat B29's right-click handlers and its menu-bar replacement as
planned work, not shipped behaviour. The audit finding is PLAT-17 in
`reports/PLAT.md` on the same branch.
