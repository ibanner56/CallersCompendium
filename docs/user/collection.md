# Collection & search

Your [collection](./glossary.md#collection) is your whole library of
[dances](./glossary.md#dance) — every transcription you have typed in or
brought in from elsewhere. This guide shows you how to browse and sort it, find
exactly the dance you want (by words, by the [moves](./glossary.md#move) it
contains, or both), add and tidy up dances, and shape the list around how you
work.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Collection**, **Filters**, and **New dance**. The
> first time a dance term appears it links to the
> [Glossary](./glossary.md), so you can get a plain-language definition
> without losing your place.

If you are brand new here, start with the
[Getting started guide](./getting-started.md) for a tour of the whole app, then
come back for the details.

## Browse and sort your dances

**Collection** is where the app opens. It shows your dances in a single scrolling
list that stays fast no matter how large your library grows. Each row gives you
the essentials at a glance:

- the dance **title** and its **author** or authors;
- a [formation](./glossary.md#formation) chip;
- status and tag chips, when a dance carries them;
- a rating indicator, if you have rated the dance; and
- any custom fields you have chosen to show in the list (more on those under
  [Make your own fields](#make-your-own-fields)).

*The Collection screen with a search query, the Filters panel open, and matching
dances visible.*

![The Collection screen showing a search query with the Filters panel open and several matching dances listed](images/collection-search-filters.png)

To change the order, open the **Sort** control at the top of the list. You can
sort by:

- **Title** — alphabetical, ignoring a leading "The," "A," or "An," so *The
  Nice Combination* sorts under **N**, where you would look for it.
- **Author** — grouped by who wrote the dances.
- **Recently added** — newest additions first, handy just after an
  [import](./glossary.md#import).
- **Last called** — the dances you have programmed most recently, first.
- **Best match** — how well each dance matches your words. This one appears only
  while you have a plain-text search active (see below), and it is the order the
  app uses to put the strongest matches at the top.

To open a dance, select it. Its full detail view opens — on a phone as a new
screen, and on a tablet or desktop in the pane beside the list. The
[dance detail view](#read-a-dance-in-detail) is covered further down.

## Group by category (a dance's "vibe")

Many callers think of dances by their **vibe** — bouncy, flowy, glossy,
connected — and organise a card box into those categories so they can jump to a
"drawer" and hot-swap a dance mid-evening. **Tags** are exactly that in the app:
give a dance one or more tags for its vibe or category, and they are ready to
filter and group by.

You can also give a tag its own colour, under **Settings → Appearance → Tag
colours**, so a category stands out on dance cards and in dance detail. Tags
start with no colour and look exactly as they always have until you pick one,
and the tag's name is always shown beside the colour, so nothing depends on
being able to tell the colours apart.

Next to **Sort** is a **Group by category** control. Pick one tag and the list
splits into two labelled sections — the dances that carry that tag, then
**Other** — so a whole category is together in one place. Your chosen **Sort**
still orders the dances *inside* each section, and picking a dance behaves
exactly as it does anywhere else in **Collection** (open it to read or perform;
press and hold to select several). Choose **No grouping** to return to the flat
list.

Grouping is for the current session only: it keeps out of your way next time you
open the app, so you always start from your usual order and pick a category when
you want one.

## Search across your dances

The search bar sits at the top of **Collection**. Type any words — a title, an
author, a phrase from the notes — and the list narrows as you type to the dances
that match.

Search understands your [dialect](./dialects.md) wording. If you saved or
imported a dance in one set of words and search in another, the app still finds
it: searching **robins chain** turns up the dance even if it was stored using
different role names. You do not have to remember how a dance was originally
written down.

Clear the search bar to return to your whole collection.

## Narrow things down with filters

When you want to slice your library by its properties rather than by words, open
the **Filters** panel with one tap. It lets you narrow by:

- **Type** and **Formation**
- **Progression**
- **Author**
- **Tags**
- **Status** and **Level**
- a **minimum star rating** (for example, three stars and up)
- your own custom fields — the choice, yes/no, text, and number fields you have
  defined

Two simple rules govern how filters combine, and knowing them makes the panel
predictable:

- **Within one filter, choices are "any."** Ticking *duple improper* and *becket*
  under Formation finds dances in **either** formation.
- **Across different filters, choices are "all."** Adding an author on top of
  those formations finds dances that match one of the formations **and** are by
  that author.

Filters work alongside the search bar: whatever you type and whatever you tick
apply together.

## Search by the moves a dance contains

Sometimes you are not looking for a title or an author — you are looking for a
shape. *Which of my dances have a petronella? Which put a chain right before a
swing?* Two tools answer questions like these.

### Build a figure query with Advanced

Open the **Advanced** builder to ask about the [figures](./glossary.md#figure) —
the moves — inside your dances. It works by stacking up rows and groups:

1. Add a **"has figure"** row and pick a move with the type-ahead field — start
   typing and choose from the matches.
2. Optionally **pin the move to a section** (for example B2), so it only counts
   when it appears there.
3. Optionally set the move's **parameters** to be more specific.
4. Add a **"then" sequence** to require one move right after another — "a chain
   *then* a swing."

Rows live inside **All**, **Any**, or **None** groups — match every row, any
row, or no row — and groups can nest inside one another, so you can express
questions as detailed as you need.

### Ask per phrase with By-Phrase search

If you think about dances the way The Caller's Box does — phrase by phrase — open
the **By-Phrase** panel. For each phrase (A1, A2, B1, B2) you can require that
certain moves **are present** ("figures match") or that certain moves **are
absent** ("but do not match"). It is a quick way to say, for instance, "a swing
in B1, but no hey anywhere in A."

### Everything combines

You do not have to choose one search tool. The plain-text bar, the **Filters**
panel, the **Advanced** builder, and the **By-Phrase** panel all apply together —
a dance has to satisfy all of them to appear. As you narrow things down, the
number of matching dances is announced to screen readers, so the result count is
never hidden behind a visual-only cue.

## Read a dance in detail

Selecting a dance opens its detail view — the full picture of a single dance.

*The dance detail view with figures grouped into sections and a toggle between
your dialect and neutral wording.*

![A dance detail view with figures grouped into A1, A2, B1, and B2 sections and the dialect-to-canonical wording toggle visible](images/dance-detail-dialect.png)

The detail view brings together:

- **A header** — title, authors, formation, and level, plus a status banner if
  the dance is flagged (for example, deprecated or broken).
- **The figures**, laid out by section (A1, A2, B1, B2), each with a beats column
  and a marker showing where the [progression](./glossary.md#progression) happens.
- **A wording toggle** — flip between your dialect and the neutral, shared
  wording without changing the saved dance. See the [Dialect guide](./dialects.md)
  for how this fits together.
- **Calling notes**, the choreographer's or your own.
- **A Walkthrough** — a dedicated free-text field for the step-by-step teaching
  notes you say while walking a dance through, kept separate from the shorter
  Calling notes. If you keep a [walkthrough snippet library](./settings.md#defaults),
  it pre-fills here from wording you have used for the same figures before, ready
  to tweak for this dance.
- **Links** — to the source, a video, and related dances.
- **Calling history** — which of your [programs](./programs.md) include this
  dance. (A [Settings](./settings.md) toggle decides whether this counts
  only slots you marked performed or any program that contains the dance.)
- **Custom fields** you have filled in.
- **Published-source citation** — the book and page a dance came from, when you
  have recorded it.

One nice touch: when a dance's notes mention another dance by name, that title
becomes a link you can select to jump straight to it.

### What you can do with a dance

From the detail view you can:

- **Edit** the dance.
- **Re-import choreography** from Caller's Box, ContraDB, or a single-dance
  Caller's Compendium JSON file. This is also available from saved dance details
  opened through Programs, search, post-import results, and the Program Editor.
- **Duplicate** it as a starting point for a variation.
- **Add to program** — drop it into a [program](./programs.md) you are building.
- **Print/Share** it as a PDF or as plain text. The export follows your active
  dialect, so what you hand someone matches how they speak — see
  [Share, print & export](./sharing.md#share-a-dance).
- **Perform this dance** — open it in [Perform mode](./perform.md), the
  large-print calling view, to call it on its own.

## Add a dance

To put in a dance by hand, choose **New dance**. This opens the editor, where the
**title** is the only required field. Figure entry is keyboard-first: start
typing a move and accept a match from the type-ahead, with a running beat count
keeping you honest as you go. If a move is unusual and nothing matches, type it in
as free text — it is still recorded as a figure.

When you save, the dance is immediately selected in the detail pane so you can
review it without having to find it in the list — on a tablet or desktop, where
the list and detail pane are side by side. On a phone the editor simply closes
and returns you to the list.

**[Write & edit dances](./authoring.md)** is the full guide to the editor:
figures, meanwhile groups, walkthroughs, credits, drafts, and undo. The
[Getting started guide](./getting-started.md#add-your-first-dance) walks through
your first dance step by step. And if you already keep dances elsewhere, you will
usually want to bring them in rather than retype them — see
[Imports & migration](./imports.md).

## Make your own fields

Beyond the built-in details, you can track whatever matters to you — a tune
suggestion, a "taught it at" note, a difficulty of your own. Choose **Manage
custom fields** to create, edit, and delete your own fields.

A custom field can be a choice list, a yes/no switch, a text note, or a number.
Once you define one, it:

- appears in the dance editor, ready to fill in;
- can show in the dance list, if you turn that on; and
- becomes a filter in the **Filters** panel.

A **choice** field is a handy home for a reusable pick-list you build up over
time — for example the **band adjectives** you like to reach for (driving,
lyrical, punchy). Define it once as a choice field and every dance draws from the
same list, so the wording stays consistent and you can filter by it. You do not
have to prepare the whole list up front: while editing a dance, use the **＋**
beside a choice field to add a new option on the spot, and it joins the shared
list for next time.

A few properties lock once a field is in use on real dances, so the data you have
already entered stays consistent. The app tells you which ones when you edit a
field in use.

## Keep your collection tidy

A growing library needs a little housekeeping. Caller's Compendium makes every
change reversible.

- **Duplicate** a dance to spin off a variation without disturbing the original.
- **Delete** a dance and it is only *soft-deleted* — an **Undo** option appears
  right away, and the dance moves to a **Recently Deleted** area rather than
  vanishing.
- **Restore or remove** from **Recently Deleted** — bring a dance back, or delete
  it permanently when you are sure. Anything left there is purged automatically
  after a retention window, which you can lengthen or switch off in
  [Settings](./settings.md).

### Change many dances at once

To organize in bulk, enter selection mode: choose **Select dances**, or long-press
a row on a touchscreen. Tick as many dances as you like, then apply one change
across all of them. Tags are on the toolbar; the rest are under **More batch
actions**:

- **Add tags** or **remove tags**.
- **Set level**, or clear it with **Unspecified (clear)**.
- **Set rating**, or clear it with **Unrated (clear)**.
- **Add tunes** — build a short list and add it to every selected dance — or
  **clear tunes**, which asks you to confirm first.
- **Set a custom field** to a value, or **Clear this field**.

Every batch change is announced to screen readers and can be undone, and the app
tells you plainly when a change would affect nothing. Selected rows are marked
with a checkmark and a highlight — never colour alone — so the selection is clear
however you are reading the screen.

## Jump straight to a dance or program

Anywhere in the app, the search affordance — the search box in the navigation rail
on a wide screen, the search action in the app bar on a narrow one, or the
keyboard shortcut **Ctrl-K** (**Cmd-K** on macOS) — opens a single search box over
whatever you are doing. Type, and matching **Dances** and **Programs** are listed
in groups; choose one and you go straight there.

It searches titles across your collection and your programs, so it is the fastest
way to reach a dance you can name. For searching *inside* dances — by move, by
level, by tag — use the Collection search and filters above.

## Where to go next

- **Write and edit dances:** [Write & edit dances](./authoring.md)
- **Build an evening from your dances:** [Programs & matrix](./programs.md)
- **Call a dance from the stage:** [Perform mode](./perform.md)
- **Bring in dances you already have:** [Imports & migration](./imports.md)
- **Hand a dance to someone else:** [Share, print & export](./sharing.md)
- **Put the app in your own words:** [Dialect](./dialects.md)
- **Keep your library safe and portable:**
  [Backup & portability](./backup-portability.md) ·
  [Settings](./settings.md)
- **Using assistive technology or large text?** The
  [Accessibility guide](./accessibility.md) covers screen readers, text
  size, high contrast, and keyboard use.

Not sure what a word means? The [Glossary](./glossary.md) has plain
definitions for every term used across these guides.
