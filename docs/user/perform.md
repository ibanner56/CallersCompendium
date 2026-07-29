# Perform mode

[Perform mode](./glossary.md#perform-mode) is the app's stage-ready calling view. This
guide covers calling a single [dance](./glossary.md#dance) or a whole
[program](./glossary.md#program), sizing the text so it is readable from a distance,
moving through your evening, keeping time, and making changes on the fly without
losing your place.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Perform this dance** and **Perform this program**.
> The first time a dance term appears it links to the
> [Glossary](./glossary.md), so you can get a plain-language definition
> without losing your place.

New to the app? Start with the [Getting started guide](./getting-started.md).

## Enter Perform mode

Perform mode is not a navigation tab — you step into it when it is time to call,
and step back out deliberately when you are done. It fills the whole screen.

- To call a **single dance**, open it from your
  [collection](./collection.md#what-you-can-do-with-a-dance) and choose
  **Perform this dance**.
- To call a **whole evening**, open a program and choose **Perform this
  program**. You can also reach it from the program summary.

When you exit, the app takes you back to wherever you came from.

*Wireframe sketch of Perform mode: a full-screen, dark, high-contrast dance card
with very large text, large previous and next arrows at the screen edges, a slot
indicator, and controls to swap an alternate, jump to a slot, adjust, or exit.
This is a low-fidelity layout sketch, not the finished app.*

![Wireframe sketch of Perform mode, showing a full-screen dark card with very large text, edge next and previous arrows, a slot indicator, and adjust and exit controls](../design/wireframes/6-perform.svg)

## Read the card

Perform mode shows one dance at a time in very large type, with the
[figures](./glossary.md#figure) grouped by section (A1, A2, B1, B2) and set in a
typeface built to be read from a distance.

Your [dialect](./dialects.md) is applied, so the card speaks in your words. A
one-tap toggle flips the current card between your dialect and the neutral,
shared wording — handy if a dancer or another caller asks about a figure — and
flips right back without losing your place. Figure detail you recorded shows here
too: when a swing ends facing somewhere other than the usual "in"/across — up or
down the hall, or out of the set — the card notes that ending so you can cue it.

## Size the text to fit

Out of the box, **auto-size** is on: the card scales so the current dance's full
text fits the screen without scrolling. It recomputes whenever you move to a new
dance or slot, rotate the device, or resize the window — so the text is always as
large as it can be while still fitting.

If you would rather set the size yourself, turn auto-size off in
[Settings](./settings.md). Perform mode then uses a manual large-print
control instead: **A−** and **A+** step the size down and up, starting large with
no upper limit. The **A−/A+** controls stay on screen either way, so you can
always nudge the size in the moment.

## Call in high contrast

Perform mode opens on a **high-contrast dark-stage theme** by default, built for
strong legibility (a contrast ratio of at least 7 to 1) under stage lighting. An
in-view toggle lets you fall back to your usual app theme if you prefer it.

## The screen stays awake

While you are in Perform mode, the app keeps the screen awake, so a propped-up
tablet will not dim or sleep partway through a dance. The moment you exit, the
screen is free to sleep as normal again.

## Move through a program

When you are performing a program, step through your slots with whichever
control suits you and your setup:

- the big **next** and **previous** controls;
- the **giant edge hit zones** at the screen edges, easy to hit without looking;
  or
- the **arrow keys** or **page keys** on a keyboard.

A **jump-to-slot overview** lets you jump anywhere in the program at once — useful
if plans change mid-evening. And when a slot has an [alt](./glossary.md#alt),
one tap swaps it in place of the primary.

## Keep time through the evening

For a program, Perform mode shows timing in a status area so you can pace
yourself:

- a **running program clock** for the whole evening;
- a **per-slot elapsed timer** that resets each time you move to a new slot;
- a slot's planned length shown as **"planned N min,"** with a gentle cue when you
  run past it; and
- a **pause/resume** control for interruptions.

Timing is display-only — it helps you keep an eye on the clock but never changes
your program or your dances.

## Adjust on the fly

Plans change mid-gig. The **adjust** sheet lets you make changes without
disturbing the card you are reading. From it you can:

- **reorder the remaining slots** (with a drag handle or move up / move down
  buttons);
- **insert a dance** from a quick search;
- **add an ad-hoc note**; and
- **mark the current slot performed**.

An inserted dance and an ad-hoc note both land right after the current slot, so
"play this next" is one action away. Every change is undoable, and for a saved
program the changes persist. Marking a slot performed is what feeds a dance's
calling history — see [Programs & matrix](./programs.md#track-what-you-have-called).

## Screen readers and verbose figures

For screen-reader users, Perform mode announces each figure in an expanded,
spoken-friendly form — clearer to hear than the terse text shown on the card. If
you would like that fuller wording everywhere, not only through assistive
technology, turn on always-verbose rendering in
[Settings](./settings.md). The
[Accessibility guide](./accessibility.md) covers this and the app's other
accessibility options.

## Print or share a single dance

You do not have to be on stage to hand someone a dance. From a dance's detail
view you can also export or print a single dance card as a PDF or as shareable
text, and the export follows your dialect. See
[what you can do with a dance](./collection.md#what-you-can-do-with-a-dance) in
the Collection guide.

## Where to go next

- **Build the program you will call:** [Programs & matrix](./programs.md)
- **Find and prepare dances:** [Collection & search](./collection.md)
- **Call in your own words:** [Dialect](./dialects.md)
- **Large text, high contrast, screen readers, keyboard:** the
  [Accessibility guide](./accessibility.md) and
  [Settings](./settings.md)

Not sure what a word means? The [Glossary](./glossary.md) has plain
definitions for every term used across these guides.
