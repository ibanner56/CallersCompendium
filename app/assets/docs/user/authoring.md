# Write & edit dances

Sooner or later you will want to put a dance in yourself — a dance you wrote, one
a friend taught you at a festival, or one that came in from an
[import](./imports.md) with a figure the app could not quite read. This guide
covers the dance editor: how figures go in, where the notes and credits live, and
how the app keeps your work safe while you type.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **New dance**, **Save**, and **Figures**. The first
> time a dance term appears it links to the [Glossary](./glossary.md), so you can
> get a plain-language definition without losing your place.

If you have not entered a dance before, the
[Getting started guide](./getting-started.md#add-your-first-dance) walks through
one end to end. This guide is the fuller reference.

## Open the editor

There are three ways in:

- **New dance**, from your [collection](./glossary.md#collection) — starts a blank
  dance. The screen is titled **New dance**.
- **Edit**, from a dance's detail view — opens that dance. The screen is titled
  **Edit dance**.
- **Edit**, on a row in the [import review](./imports.md) list — brings that one
  dance in straight away and opens it, so you can fix a stubborn figure while the
  rest of the import waits for you.

The editor is a full screen with **Save** in the corner. The **title** is the only
required field; everything else can stay empty until you know it.

## Enter the figures

**Figures** is the heart of the editor. Each figure is one row, in the order the
dance is called, and the app tracks how many [beats](./glossary.md#beats) they add
up to as you go.

### Type and press Enter

Figure entry is keyboard-first. Choose **Add figure** (or **Add first figure** on
an empty dance) and type into **Type a figure**. As the app recognises what you
are typing it offers matching [moves](./glossary.md#move); press Enter to accept
one and it is added with that move's default settings. Typing `sw` and pressing
Enter, for example, gives you a swing.

Anything the app cannot recognise is still kept — it becomes a **custom figure**,
holding your text exactly as you typed it. Nothing you type is ever thrown away
because the app did not understand it.

The box stays open after each figure so you can keep going: type, Enter, type,
Enter. Press Escape when you are done.

### Free-text entry

Turn on **Free-text entry** in [Settings](./settings.md) ▸ **Defaults** ▸
**Dance-authoring defaults** and the same box accepts a whole line at a time
instead of one move at a time. Type `neighbor balance & swing` and you get both
figures; type `16 circle left 3/4` and you get a sixteen-beat circle left
three-quarters. The app tells you how many figures it added and invites you to
type another.

As always, anything it cannot parse is kept as a custom figure rather than
dropped.

### Figure shorthands

If you type the same run of figures over and over, teach it to the app once.
Choose **Figure shorthands** in **Settings** ▸ **Defaults** ▸ **Dance-authoring
defaults**, then **New shorthand**:

- **Shorthand** is the exact line you will type during free-text entry. It is
  matched without regard to capitals, so `NBS` and `nbs` are the same shorthand.
- **Expands to** is the figure or figures it inserts, in order. You build them
  exactly the way you build a normal figure, with the same options and the same
  checks.

Shorthands are your own; each one has to be unique, and the app tells you if you
reuse a token that is already taken. Shorthands only apply while **Free-text
entry** is on.

### Adjust a figure

Select a figure to open it. What you can change depends on the move:

- **Parameters** — most moves have a few (which role, how far, which way round).
  Common ones show straight away; choose **More options** to see the rest, and
  **Fewer options** to fold them back.
- **Beats** — every figure has a beat count you can raise or lower.
- **Progression** — mark the figure the dance progresses on. Moves that can carry
  the progression say so.
- **Add note** — a short note attached to that figure alone.

A figure whose move is not in this version's move list is shown read-only, with a
plain explanation. Its data is preserved untouched, it edits normally again if the
move becomes known, and you can still reorder and delete it in the meantime.

### Custom figure text

A custom figure has two fields: **Custom figure text** and **Beats**.

The **Beats** field sets how many beats the custom figure occupies — use it the
same way you would for any other figure. It defaults to 8.

The **Custom figure text** field also accepts two formatting marks, with buttons
for both:

- `*text*` for **bold**
- `_text_` for underline

As you type, the app quietly styles what it recognises: move names get a dotted
underline, role terms are underlined, and
[discouraged terms](./dialects.md) are struck through. It is a hint, not a
correction — nothing is changed for you.

### Reorder, cut, and duplicate

Each figure row has a drag handle and an actions menu:

| Action | What it does |
|---|---|
| **Move up** / **Move down** | Shifts the figure one place |
| **Cut** | Lifts the figure out, ready to place elsewhere |
| **Duplicate** | Adds an identical figure |
| **Group with next as meanwhile** | Joins it to the next figure as simultaneous action |
| **Mark progression** / **Clear progression** | Sets or clears the progression |
| **Delete** | Removes the figure |

After **Cut**, a banner names the figure that is waiting and **Paste** points
appear between the rows — before the first figure, after any figure, and at the
end of the list — so you can drop it exactly where you want. Every move,
duplication, and deletion is announced for screen readers, and deletions can be
undone.

### Meanwhile figures

Some dances have two things happening at once — the ones on the ends do one
thing while the middles do another. Choose **Group with next as meanwhile** and
the two figures become a **meanwhile** group, labelled with how many **sides** it
has and sharing one set of beats.

Inside the group, each side is labelled **Side 1**, **Side 2**, and so on, and has
its own controls to move up, move down, or **Remove this side**. **Add side** adds
another concurrent figure, up to a maximum the app states when you reach it.

### Keep an eye on the beats

Under the figure list the app shows a running **Total** against what the dance's
[phrase structure](./glossary.md#phrase-structure) expects, and says **Over by**
or **Under by** when the two disagree. It is a nudge, not a rule — you can save a
dance whose beats do not add up, and sometimes that is the honest transcription.

## Details, notes, and credits

### Details

- **Title** — required.
- **Authors** — the [choreographer](./glossary.md#choreographer) or
  choreographers. Type to find an existing author or create a new one.
- **Formation** and **Formation detail** — the shape the dance is danced in, plus
  anything worth adding in words.
- **Phrase structure** — leave it blank for the standard A1 A2 B1 B2, or write
  your own (the field shows `6*8*2` as an example). The app checks that what you
  write is a valid structure, and uses it for the beat count above.

### Notes

- **Calling notes** — how you call it, what to watch for.
- **Hook** — one line on why you would call this dance.
- **Walkthrough** — the step-by-step teach.

### Walkthrough

You can write the walkthrough as free prose, or build it from your figures.

Each figure can carry an **Add walkthrough step** description. What you write
there is *saved as your default for that figure and reused wherever it appears* —
so the way you teach a hey is written once and follows you into every dance with a
hey.

Two things follow from that:

- **Fill from snippets** assembles a walkthrough from the saved snippets of the
  dance's figures. If it would overwrite something, the app asks first. If none of
  the figures has a snippet yet, it says so rather than emptying the field.
- If you edit a step so it no longer matches your saved snippet, the app asks
  **Update your saved snippet?** — choose **Use everywhere** to update the default,
  or **Just this dance** to keep the change local.

Your whole library of snippets lives at **Settings** ▸ **Defaults** ▸
**Walkthrough snippets**, where you can review and edit them. Editing one there
updates the default used everywhere.

### More details

**More details** expands to everything else a dance can carry:

| Field | Notes |
|---|---|
| **Level** and **Status** | How hard it is, and where it is in your workflow |
| **Mixed level** | For dances that span the difficulty scale |
| **Rating** | Your own star rating, with **Clear rating** to unset it |
| **Composed** / **Revised** | A year, optionally with a month and day |
| **Tags** | Your own labels |
| **Tunes** | Tunes you like with this dance |
| **Links** | A URL with an optional label, marked **Source**, **Video**, or **Other** |
| **Published sources** | Citations, with optional page and number |
| **Related dances** | Cross-references to other dances, each with an optional note |
| **Custom fields** | Any fields you have defined — see [Collection & search](./collection.md#make-your-own-fields) |

If the editor spots wording it considers discouraged, it collects it under
**Warnings** with the term named. Nothing is blocked; it is there so you can
decide.

### Author and source details are shared

Choose to edit an author's details and you get **Choreographer details** — name,
website, email, location, notes, and whether they are deceased. The dialog is
explicit about two things, and both matter:

- These details are **shared across every dance credited to that author**, so
  correcting a spelling here corrects it everywhere.
- **Email and location are private.** They are stored only on this device and are
  never shared or exported. See [Share, print & export](./sharing.md#what-stays-private)
  for exactly what leaves the app.

**Source details** works the same way: a source's details are shared across every
dance that cites it, and editing them here updates the source everywhere it is
referenced.

## Undo, drafts, and saving

### Undo and redo

**Undo** and **Redo** sit in the editor's top bar, with keyboard shortcuts:

| Action | Linux / Windows | macOS |
|---|---|---|
| Undo | Ctrl-Z | Cmd-Z |
| Redo | Ctrl-Shift-Z | Cmd-Shift-Z |

### Your work is kept while you type

The editor keeps a draft as you work. If the app closes before you save —
a crash, a flat battery, a phone that decides to reboot — the next time you open
that dance the app offers you the draft back:

> **Unsaved draft** — You have an unsaved draft for this dance. Would you like to
> restore it?

Choose **Restore** to pick up where you left off, or **Discard** to start from the
last saved version. Drafts stay on your device; they are never uploaded, shared,
or included in exports.

### Leaving without saving

If you try to leave with unsaved changes, the app asks **Discard changes?** —
**Keep editing** returns you to the dance, **Discard** leaves it as it was last
saved.

### Save and delete

**Save** writes the dance and returns you to where you came from; the change shows
in your collection straight away. If a save fails, the app says so and leaves your
work in the editor so you can try again.

**Delete dance** (in the top bar, on an existing dance) removes the dance. As
everywhere else in the app, deletion is a soft delete with an **Undo** offered
right away — see
[Keep your collection tidy](./collection.md#keep-your-collection-tidy).

## Start new dances the way you work

If most of your dances share a shape, set that shape once. **Settings** ▸
**Defaults** ▸ **Dance-authoring defaults** decides what a **New dance** starts
as:

- **Form**, **Formation**, and **Progression** — what a new dance begins with.
- **Default phrase structure** — seeded into new dances; blank means the standard
  4×16 (A1 A2 B1 B2).
- **Starting figures** — the figures a new dance starts with. It defaults to a
  single stand still of eight beats; clear it for a completely blank dance.
- **Move defaults** — your preferred parameter values, applied whenever you insert
  that move. These override the move's built-in defaults, and you can still change
  any parameter on the figure afterwards.

Every one of these is only a starting point; you can change any of them on any
dance.

## Fix figures an import could not read

Imported dances sometimes arrive with figures kept as plain custom text simply
because the app could not recognise them at the time. As the app's figure
recognition improves, those can often be upgraded.

Choose **Re-check custom figures** in **Settings** ▸ **General** ▸ **Re-check…**.
The app scans your collection and shows you what it *could* upgrade before
anything changes: how many figures, in how many dances, and which ones. You
confirm, and only then does anything happen.

Your tags, ratings, notes, and everything else on each dance are kept exactly as
they are — only figures that now recognise a known move are replaced. If there is
nothing to upgrade, the app tells you that and leaves your collection alone.

## Where to go next

- **Find and organize what you have entered:**
  [Collection & search](./collection.md)
- **Bring dances in rather than typing them:**
  [Imports & migration](./imports.md)
- **Put figures into your own words:** [Dialect](./dialects.md)
- **Build an evening from your dances:** [Programs & matrix](./programs.md)
- **Hand a dance to someone else:** [Share, print & export](./sharing.md)
- **Using assistive technology or large text?** The
  [Accessibility guide](./accessibility.md) covers screen readers, text size,
  high contrast, and keyboard use.

Not sure what a word means? The [Glossary](./glossary.md) has plain definitions
for every term used across these guides.
