# Accessibility

Caller's Compendium is built to be usable at the dance, on stage, and at your desk — whatever tools you rely on. This guide gathers the accessibility features in one place: larger text, high-contrast themes, screen-reader support, full keyboard control, and small comforts like reduced motion and confirmations before deleting. The app is built to a **WCAG 2.2 AA** commitment, with extra care given to [Perform mode](./README.md#glossary), because that's the screen you read on a dim stage, at arm's length, often one-handed and under pressure.

> **Finding your way around these words.** On-screen buttons and screens are written in **bold** — like **Settings**, **Appearance**, and **Reduce motion**. The first time a dance term appears it links to the [Glossary](./README.md#glossary), so you can get a plain-language definition without losing your place.

If you're brand new to the app, the [Getting started](./getting-started.md) guide is a gentle first walkthrough. Everything below can be adjusted at any time, and most of it lives under **Settings**.

## Bigger, clearer text

Text size matters most when you're reading and moving at the same time. Caller's Compendium gives you two layers of control.

**System text size, everywhere.** The app respects your device's system text-size setting throughout. If you've already made text larger in your operating system's accessibility settings, Caller's Compendium honors that choice automatically — no separate step needed. This is the simplest way to make every screen more readable at once.

**Perform mode's own size control.** [Perform mode](./README.md#glossary) adds a second layer on top of your system setting, because a stage is a special case. Perform text starts large — sized to be readable at arm's length — and there's a very wide range beyond that.

- **Auto-size** fits each card's text to the screen so nothing scrolls off. It's on by default. You can turn it on or off under **Settings › General › Auto-size Perform cards**.
- When you turn **Auto-size** off, you set the size yourself with the **A−** and **A+** buttons right there in Perform. Choose whatever is comfortable for the room you're calling in.

For the full walkthrough of calling from the app — including these controls in context — see the [Perform mode guide](./perform.md).

## Themes, contrast, and the dark stage

Open **Settings › Appearance** to choose how the app looks. You'll find:

- **System** — follows your device's light or dark setting automatically, and switches when your device does.
- **Light** — a bright theme for well-lit rooms and daytime prep.
- **Dark** — an easy-on-the-eyes theme that suits calling on a dark stage.
- **High Contrast** — a dedicated theme tuned for strong legibility, with bold separation between text and background.

There are additional palettes and custom themes to explore as well, but those four are the ones most people reach for first.

For calling on a dim stage, **Dark** and **High Contrast** are the natural choices — they keep the screen from glaring at the room while staying readable for you. If you navigate with a keyboard, you'll notice that focus outlines are clearly visible as you move between controls, and they're especially strong in **High Contrast**.

## Using a screen reader

Caller's Compendium works with the screen reader on your platform:

- **VoiceOver** on macOS and iOS/iPadOS
- **TalkBack** on Android
- **Narrator**, **NVDA**, or **JAWS** on Windows
- **Orca** on Linux (best-effort support)

Screens are labelled so a screen reader can describe them meaningfully. As you work, the app announces changes you'd otherwise have to see:

- Search result counts and selection counts are announced as they change, so you know how many matches or selected items you have.
- Moving a [slot](./README.md#glossary) or a [figure](./README.md#glossary) is announced as it happens.
- A [dance](./README.md#glossary)'s figure list, the [program](./README.md#glossary) [matrix](./README.md#glossary) grid, and dance details all read as structured, spoken-friendly text. For example, a figure reads as its full spoken wording along with its beat count and whether it progresses.

**Verbose figure text.** Turn on **Settings › General › Always show verbose figure text** to display the full spoken-style wording of each figure directly on screen — not only through a screen reader. This helps screen-reader users confirm what's shown, and it's just as useful for anyone who prefers plain, spoken wording over terse notation.

A brief, honest note: screen-reader support is real and actively maintained, but we don't claim that every corner of every screen is perfectly covered. If you hit a spot that reads poorly, we'd genuinely like to hear about it — see [Help us improve](#help-us-improve) below.

## Using the keyboard

You can drive Caller's Compendium from the keyboard without reaching for a pointer.

**Quick search and command palette.** Press **Ctrl-K** (or **Cmd-K** on macOS) from anywhere to open a command palette and quick search. Start typing to filter, use the **up** and **down arrow keys** to move through results, press **Enter** to open the highlighted item, and press **Esc** to close.

**Moving through Perform mode.** In [Perform mode](./README.md#glossary), move between [slots](./README.md#glossary) with the **left** and **right arrow keys**, or with **Page Up** and **Page Down**. These work alongside the on-screen next and previous controls and the large edge zones, so you can use whichever suits you.

**Reordering without dragging.** Anything that supports dragging — program slots, figures — also offers **move-up** and **move-down** actions, plus cut and paste. You never *need* to drag to reorder something.

**Always know where you are.** Interactive controls show a visible focus outline as you move through them, so you can always see which control has focus.

## Motion, deleting, and other comforts

A few smaller settings and behaviors round out the experience:

- **Reduce motion** (**Settings › General**) dampens non-essential animation. If movement on screen is distracting or uncomfortable, turn this on.
- **Confirm before delete** (**Settings › General**) adds a prompt before you delete a dance or a program. And regardless of this setting, deletes are undoable — so a slip is recoverable either way.
- **Meaning is never carried by color alone.** Statuses and special slots — like an [alt](./README.md#glossary) — always include an icon and a text label as well as color, so nothing depends on being able to distinguish hues.
- **Perform mode keeps the screen awake.** The display won't dim or sleep mid-dance while you're calling.
- **Comfortable touch targets.** Controls are sized to be easy to hit, and the large edge zones in Perform give you generous, forgiving areas for moving between slots.

## Help us improve

Accessibility is an ongoing commitment, not a finished checkbox. Everything above is available today, but we know real-world use turns up rough edges we haven't found yet. If a screen reads awkwardly, a control is hard to reach, or something just doesn't work the way it should for you, please tell us through the project's issue tracker — you'll find the link in the [project README](../../README.md). Your reports genuinely make the app better for everyone.

## Where to go next

- [Perform mode](./perform.md) — large-print calling, **A−**/**A+**, and **Auto-size** in full context.
- [Settings](./settings.md) — where **Appearance**, **Reduce motion**, verbose figure text, and other options live.
- [Dialect](./dialects.md) — how figures are worded and how [dialect](./README.md#glossary) affects what you read.
- [Programs & matrix](./programs.md) — building and reordering the [matrix](./README.md#glossary) by keyboard or pointer.
- [Getting started](./getting-started.md) — a first tour of the app if you're new here.
