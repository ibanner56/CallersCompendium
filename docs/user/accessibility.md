# Accessibility

Caller's Compendium is built to be usable at the dance, on stage, and at your
desk — whatever tools you rely on. This guide gathers the accessibility features
in one place: larger text, high-contrast themes, screen-reader support, full
keyboard control, and small comforts like reduced motion and confirmations before
deleting. The app is built to a **WCAG 2.2 AA** commitment, with extra care given
to [Perform mode](./glossary.md#perform-mode), because that's the screen you read
on a dim stage, at arm's length, often one-handed and under pressure.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Settings**, **Appearance**, and **Reduce motion**.
> The first time a dance term appears it links to
> [App terms](./glossary.md), so you can get a plain-language definition without
> losing your place.

If you're brand new to the app, the [Getting started](./getting-started.md) guide
is a gentle first walkthrough. Everything below can be adjusted at any time, and
most of it lives under **Settings**.

## Bigger, clearer text

Text size matters most when you're reading and moving at the same time. Caller's
Compendium gives you two layers of control.

**System text size, everywhere.** The app respects your device's system text-size
setting throughout. If you've already made text larger in your operating system's
accessibility settings, Caller's Compendium honors that choice automatically — no
separate step needed. This is the simplest way to make every screen more readable
at once.

**Perform mode's own size control.** [Perform mode](./glossary.md#perform-mode)
adds a second layer on top of your system setting, because a stage is a special
case. Perform text starts large — sized to be readable at arm's length — and
there's a very wide range beyond that.

- **Auto-size** fits each card's text to the screen so nothing scrolls off. It's
  on by default. Set how it starts under **Settings › Program › Auto-size Perform
  cards**, and flip it for the night with **Auto-size text to screen** in Perform
  itself.
- The **Decrease text size** and **Increase text size** buttons — **A−** and
  **A+** — set the size yourself. Using either one switches auto-size off, and the
  size you land on is remembered for next time. Choose whatever is comfortable for
  the room you're calling in.

On a tablet or desktop these sit in Perform's toolbar. On a phone they tuck into
its **More actions** menu, where each keeps its full text label and toggles
announce whether they're on.

For the full walkthrough of calling from the app — including these controls in
context — see the [Perform mode guide](./perform.md#set-the-stage).

## Themes, contrast, and the dark stage

Open **Settings › Appearance** to choose how the app looks. You'll find:

- **System** — follows your device's light or dark setting automatically, and
  switches when your device does.
- **Light** — a bright theme for well-lit rooms and daytime prep.
- **Dark** — an easy-on-the-eyes theme that suits calling on a dark stage.
- **High contrast** — a dedicated theme tuned for strong legibility, with bold
  separation between text and background.

There are additional palettes and custom themes to explore as well, but those four
are the ones most people reach for first — see
[Settings › Appearance](./settings.md#appearance).

For calling on a dim stage, **Dark** and **High contrast** are the natural choices
— they keep the screen from glaring at the room while staying readable for you. If
you navigate with a keyboard, you'll notice that focus outlines are clearly
visible as you move between controls, and they're especially strong in **High
contrast**.

**A stage theme just for calling.** Perform mode opens on its own dark,
high-contrast look — built for a contrast ratio of at least 7 to 1 under stage
lighting — without changing the theme you use everywhere else. The **Stage theme**
toggle stays in Perform's toolbar even on a phone, so it's always one reach away,
and its tooltip says which state you're in: *Stage theme on — tap to use app
theme*, or *Stage theme off — tap for dark stage*. Your choice is remembered, so
once you've set it for the hall you call in, it's there next time.

## Using a screen reader

Caller's Compendium works with the screen reader on your platform:

- **VoiceOver** on macOS and iOS/iPadOS
- **TalkBack** on Android
- **Narrator**, **NVDA**, or **JAWS** on Windows
- **Orca** on Linux (best-effort support)

Screens are labelled so a screen reader can describe them meaningfully. As you
work, the app announces changes you'd otherwise have to see:

- Search result counts and selection counts are announced as they change, so you
  know how many matches or selected items you have.
- Moving a [slot](./glossary.md#slot) or a [figure](./glossary.md#figure) is
  announced as it happens.
- A [dance](./glossary.md#dance)'s figure list, the
  [program](./glossary.md#program) [matrix](./glossary.md#matrix) grid, and dance
  details all read as structured, spoken-friendly text. For example, a figure
  reads as its full spoken wording along with its beat count and whether it
  progresses.

**Verbose figure text.** Turn on **Settings › General › Always show verbose figure
text** to display the full spoken-style wording of each figure on screen in the
dance view — not only through a screen reader. This helps screen-reader users
confirm what's shown, and it's just as useful for anyone who prefers plain, spoken
wording over terse notation.

**In Perform, you don't need to turn anything on.** Perform mode always announces
each figure in its expanded, spoken-friendly form, whatever that setting says, so
what you hear on stage is always the fuller wording.

A brief, honest note: screen-reader support is real and actively maintained, but
we don't claim that every corner of every screen is perfectly covered. If you hit
a spot that reads poorly, we'd genuinely like to hear about it — see
[Help us improve](#help-us-improve) below.

## Using the keyboard

You can drive Caller's Compendium from the keyboard without reaching for a
pointer.

**Quick search.** Press **Ctrl-K** (or **Cmd-K** on macOS) from anywhere except while performing (Perform mode) to open a
search box over whatever you're doing. Start typing to filter your dances and
programs, use the **up** and **down arrow keys** to move through results, press
**Enter** to open the highlighted item, and press **Esc** to close.

**Shortcuts on a computer (Windows, macOS and Linux).** Use **Ctrl** on Windows
and Linux and **Cmd** on a Mac:

- **Ctrl-S** (**Cmd-S**) saves the dance or program you're editing, as its
  **Save** button does. In the program builder that's on the **Build** tab,
  where the button is.
- **Ctrl-N** (**Cmd-N**) starts a new dance.
- **Ctrl-F** (**Cmd-F**) puts the cursor in the **Collection**'s search box and
  selects what's already there. Anywhere else it opens Quick search.
- **Ctrl-A** (**Cmd-A**) selects every dance in the **Collection**'s current
  results and starts selecting if you weren't. It works while the keyboard focus
  is in the list of dances; in the search box it selects the text, as usual.
  Dances your filters hide are not selected. Pressing it again leaves everything
  selected.
- **Ctrl-,** (**Cmd-,**) opens **Settings**.
- **Esc**, or **Ctrl-W** (**Cmd-W**), goes back. If a menu, a list of
  suggestions, or a dialog you could close by clicking outside it is open, it
  closes that first. Otherwise it leaves
  the page you're on, as the back button does, so an editor with unsaved
  changes asks you first. A mouse's **Back** button does the same.

Ctrl-N and Ctrl-, take you out of whatever page you're on. If that page is an
editor with unsaved changes, it asks about them first; answer, then press the
keys again. They do nothing while a dialog is open. While performing, Ctrl-N, Ctrl-F
and Ctrl-, do nothing and Esc only leaves full screen (see below); Ctrl-W and a
mouse's Back button ask whether to stop performing, as the back button does.

**Right-click.** On a computer, right-click a dance in the **Collection**, or a
program in **Programs**, to open its **⋮** menu.

**The menu bar on a Mac.** The **Caller's Compendium** menu has **Settings…**.
**File** has **New Dance**, **Import Dances…** and **Close** (which goes back,
like Cmd-W). **View** has the system's full-screen item, **Window** has
Minimize and Zoom, and **Help** has **User Guide**. There is no **Edit** menu.
Cmd-C, Cmd-X, Cmd-V, Cmd-Z and Cmd-A still work in text, and right-clicking
text offers **Copy**. The system's own items (About, Hide, Quit, full screen,
Minimize and the like) are named by macOS, so the app's language setting
doesn't change them.

**Selecting and copying text (Windows, macOS and Linux).** On a dance's page,
drag across any text to select it, then press **Ctrl-C** (**Cmd-C** on macOS) to
copy it. **Ctrl-A** (**Cmd-A**) selects everything on the page, and a right-click
on text offers **Copy** and **Select all**. A figure's beat count and the tags
are left out of a copy. Screen readers announce each figure as a single item, so
they can't select part of a figure; use **Copy dance** for a figure's full text.
Phones and Perform mode don't offer text selection.

**Moving through Perform mode.** In [Perform mode](./glossary.md#perform-mode),
move between [slots](./glossary.md#slot) with the arrow keys, or with **Page Up**
and **Page Down**. When a card is too long to fit, **down** and **Page Down**
scroll it to the end before moving on, and **up** and **Page Up** scroll back to
the top before going back. The **left** and **right** keys always change slot.
When you are performing a single dance there is no slot to move to, so those
keys only scroll a long card.
These work alongside the on-screen next and previous controls and the large edge
zones, so you can use whichever suits you. On a computer, **F11** (**Ctrl-Cmd-F**
on macOS) takes Perform full screen and back, and **Esc** leaves full screen
without leaving Perform. While a dance's walkthrough overlay is open, those keys pause — the
**up** and **down** keys scroll the walkthrough instead — and **Esc** closes it,
so reading ahead never changes your slot.

**Reordering without dragging.** Program slots and figures also offer **move-up**
and **move-down** actions, and figures additionally offer cut and paste, so you
never *need* to drag them. A few settings lists — matrix columns, difficulty
levels and custom-field choices — have no move buttons, so you drag those.

**Figure actions menu.** Tab to a figure's **⋮** button and press **Space** or
**Enter** to open its actions menu. Focus lands on the first action you can use,
the **up** and **down** arrow keys move between actions (skipping any that are
unavailable, such as Move up on the first figure), **Enter** runs the highlighted
one, and **Esc** closes the menu and returns focus to the **⋮** button.

**Add figure menu.** Open it with **Space** or **Enter** and focus lands on its
first choice: **Enter** picks **Add figure**, and the arrow keys reach **Add
meanwhile**, **Add modifier** and **Add sequence**.

**Always know where you are.** Interactive controls show a visible focus outline
as you move through them, so you can always see which control has focus.

## Motion, deleting, and other comforts

A few smaller settings and behaviors round out the experience:

- **Reduce motion** (**Settings › General**) dampens non-essential animation. If
  you've already turned on *Reduce Motion* (or *Remove animations*) in your
  device's system accessibility settings, the app honors that automatically — you
  don't have to find this switch first. Turn the in-app switch on to
  switch off the app's animations and the fade between themes even when your
  device allows motion. Turning it off stops the app removing its own
  animations, but cannot restore animations your device's setting has already
  shortened.
- **Confirm before delete** (**Settings › General**) adds a prompt before you
  delete a dance or a program from its **⋮** menu, from its own screen, or from
  Collection's selection mode. It does not cover the swipe shortcut: swiping a
  row in the Collection or Programs list reveals a **Delete** button, and
  tapping that button deletes straight away. If you want every delete to ask
  first, use the **⋮** menu rather than the swipe. And regardless of this
  setting, deletes are undoable — so a slip is recoverable either way.
- **Meaning is never carried by color alone.** Statuses and special slots — like
  an [alt](./glossary.md#alt) — always include an icon and a text label as well as
  color, so nothing depends on being able to distinguish hues. That holds for the
  colors you choose yourself too: a formation or tag you have colored still shows
  its name, and the app picks a black or white label for it automatically so the
  text stays readable whichever color you pick.
- **Perform mode keeps the screen awake.** The display won't dim or sleep
  mid-dance while you're calling.
- **Comfortable touch targets.** Controls are sized to be easy to hit, and the
  large edge zones in Perform give you generous, forgiving areas for moving
  between slots.

## Help us improve

Accessibility is an ongoing commitment, not a finished checkbox. Everything
above is available today, and real-world use is the best way to find what can
still be better. If a screen reads awkwardly, a control is hard to reach, or
something doesn't work the way it should for you, please
[open an issue](https://github.com/ibanner56/CallersCompendium/issues/new/choose)
or email [compendium@contra.dance](mailto:compendium@contra.dance). Every report
helps make the app better for everyone.

## Where to go next

- [Perform mode](./perform.md) — large-print calling, **A−**/**A+**,
  **Auto-size**, and the stage theme in full context.
- [Settings](./settings.md) — where **Appearance**, **Reduce motion**, verbose
  figure text, and other options live.
- [Dialect](./dialects.md) — how figures are worded and how
  [dialect](./glossary.md#dialect) affects what you read.
- [Programs & matrix](./programs.md) — building and reordering the
  [matrix](./glossary.md#matrix) by keyboard or pointer.
- [Write & edit dances](./authoring.md) — the editor, including keyboard-first
  figure entry and undo.
- [Getting started](./getting-started.md) — a first tour of the app if you're new
  here.
