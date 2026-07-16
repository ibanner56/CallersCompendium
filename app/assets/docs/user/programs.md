# Programs & matrix

A [program](./glossary.md#program) is an ordered set list for one event —
Saturday's dance, a weekend, a one-off gig. This guide shows you how to build a
program from your [dances](./glossary.md#dance), check the variety of your
evening at a glance with the
[matrix](./glossary.md#matrix), print or share it, and keep track of what you
have called.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Programs**, **New program**, and **Matrix**. The
> first time a dance term appears it links to the
> [Glossary](./glossary.md), so you can get a plain-language definition
> without losing your place.

New to the app? The [Getting started guide](./getting-started.md) gives you the
lay of the land first. To fill your library before you build a program, see
[Collection & search](./collection.md).

## Create and manage programs

Open **Programs** to see the programs you have built. It starts with a short
prompt and a **New program** button until you make your first one.

- **Start one** with **New program**.
- **Duplicate** a program to reuse last month's shape as a starting point.
- **Delete** a program and it is only soft-deleted — an **Undo** option appears,
  and it moves to a **Recently Deleted** area you can restore from later, exactly
  as with [dances](./collection.md#keep-your-collection-tidy).

## Build a program

On a wide screen — a desktop or a tablet in landscape — the builder shows two
panes side by side that work together. On a narrower screen, such as a phone,
the same pieces are still there: your program fills the screen and the
collection picker opens as a panel when you go to add a dance.

*Wireframe sketch of the Programs builder: a two-pane layout with the ordered
program slots on the left and a searchable collection picker on the right. This
is a low-fidelity layout sketch, not the finished app.*

![Wireframe sketch of the Programs builder, showing ordered program slots on the left and a collection picker with filters on the right](../design/wireframes/4-programs-builder.svg)

- **Your program** — the ordered list of
  [slots](./glossary.md#slot) that make up the evening.
- **The collection picker** — the same search tools you know from
  [Collection & search](./collection.md): the **Filters** panel, the
  **Advanced** figure builder, and the **By-Phrase** panel. Find a dance and add
  it to the program.

### Kinds of slots

A program is made of three kinds of slots:

- **Dance slots** — dances pulled from your [collection](./glossary.md#collection).
- **Free-text slots** — for the things between dances: a break, a waltz,
  announcements.
- **[Alts](./glossary.md#alt)** — an alternate dance you might call instead
  of the one above it. An alt appears indented under its primary and is marked
  with an icon and text (never color alone), so it is always clear which dance is
  the backup.

Each slot can also carry a **note**, a **guest caller**, and a **planned length**
in minutes — useful both for pacing the evening and for the timing display in
[Perform mode](./perform.md#keep-time-through-the-evening).

To reorder slots, use the **drag handle** or the **move up / move down** buttons.
Both do the same job, so you are never forced to drag.

### Event details

A program carries the details of its event:

- **date**, **venue**, and **notes**; and
- program-level **band**, **caller**, and dancer **level**.

If you often play the same role, set a default caller or band in **Settings →
Defaults** and new programs will prefill them — see
[Settings](./settings.md). You can always change these per program.

## Check your evening with the matrix

The **Matrix** tab turns your program into a grid worked out from the
choreography, so you can see the shape of the evening at a glance.

*Wireframe sketch of the program matrix: a grid with moves as columns and dances
as rows, a star marking each dance's first figure and a check mark where a move
appears, with the row and column headers pinned. This is a low-fidelity layout
sketch, not the finished app.*

![Wireframe sketch of the program matrix, showing moves as columns and dances as rows, with a star marking each dance's first figure, check marks where a move appears, and pinned row and column headers](../design/wireframes/5-program-matrix.svg)

Here is how to read it:

- **Dances are rows; moves are columns.**
- **A ★ (star)** marks each dance's first figure.
- **A ✓ (check mark)** shows where a move appears in a dance.
- **Headers stay pinned** as you scroll, so you never lose track of which row or
  column you are looking at.

The matrix shows **presence, not counts** — whether a move is in a dance, not how
many times, and not the order the moves come in. That is exactly what you want
for spotting patterns across the evening: scan a move's column and you can see at
a glance that, say, several dances in a row all have a swing, or that one move
turns up in nearly every dance. To make the grid meaningful, swings are split out
by role and heys by their length, so similar-looking moves are not lumped
together.

A few practical notes:

- **On a narrow phone screen**, the matrix falls back to a compact layout that
  still conveys the same information.
- **For screen-reader users**, the matrix reads as a proper table, so you can
  navigate it row by row and column by column.
- **To take it with you**, print or export the matrix as its own landscape PDF,
  complete with a legend explaining the ★ and ✓ markers.

## Print, export, and email a program

When it is time to hand out or file your set list, you can export or print a
program as:

- a **PDF**,
- **plain text**, or
- an **emailable text set list** you can drop straight into a message.

As with a single dance, the export follows your [dialect](./dialects.md), so the
wording matches how you — or whoever you are handing it to — speak.

## Track what you have called

Every program feeds a dance's **calling history**. Open any dance from your
[collection](./collection.md#read-a-dance-in-detail) and its detail view lists
the programs that include it, most recent first.

There are two ways to think about "called," and a setting lets you choose:

- **Any program that contains the dance** counts (the default), or
- **only slots you marked performed** count.

You mark a slot performed from within [Perform mode](./perform.md), during the
event. The [Settings](./settings.md) toggle decides which of the two
rules a dance's calling history follows.

## Where to go next

- **Fill your library first:** [Collection & search](./collection.md)
- **Call your program from the stage:** [Perform mode](./perform.md)
- **Put your programs in your own words:** [Dialect](./dialects.md)
- **Save and move your data:**
  [Settings](./settings.md) ·
  [Backup & portability](./backup-portability.md)

Not sure what a word means? The [Glossary](./glossary.md) has plain
definitions for every term used across these guides.
