# User-docs style guide

This guide is the contract for everything under [`docs/user/`](./). It exists so
that every guide reads as if one friendly person wrote it — a person who calls
dances, not one who writes software. If you are contributing or editing a user
guide, follow the conventions here. This document also tries to *model* the voice
and the accessibility practices it describes.

> **Audience reminder:** these docs are for **callers and dancers** using the
> app, not for developers. Developer- and design-facing material lives under
> [`docs/design/`](../design/), [`docs/adr/`](../adr/), and
> [`docs/research/`](../research/); keep the two worlds separate.

## Voice and tone

- **Friendly and plain.** Write the way you would explain something to a caller
  at a dance weekend: warm, direct, and unhurried. Prefer short sentences.
- **Second person, active voice.** Address the reader as "you." Say "Tap **Import**
  to bring in dances," not "Dances may be imported by the user."
- **Non-technical.** Avoid jargon from the codebase (repositories, ASTs, FTS,
  drift, enums, canonical vocabulary as an implementation detail). If a technical
  idea genuinely helps, translate it into everyday terms first.
- **Respectful and inclusive.** This is a community project for a diverse dance
  community. Use role-neutral language by default (see terminology below) and
  never assume a reader's experience level.
- **Encouraging, never condescending.** Assume the reader is capable and busy.
  Skip filler like "simply," "just," and "obviously" — what is obvious to one
  person is a wall to another.

## How these guides are organized

The hub, [`README.md`](./README.md), is the front door — and, because the guides
are bundled into the app, it is also the only navigation surface a reader has
in-app. Keep it working hard:

- **Group guides by what the reader wants to do**, not by app feature. The
  current groups are *Start here*, *Build your collection*, *Plan and call an
  event*, *Share and safeguard your work*, *Make it yours*, and *Look something
  up*.
- **Keep the "I want to…" table current.** Every row is a task in the reader's
  words and a link that lands on the exact heading that answers it. When you add
  a section that answers a common question, add a row.
- **Every guide belongs to exactly one group.** If a new guide does not fit,
  that is a signal the groups need rethinking — raise it rather than bolting on
  a seventh.
- **Don't add status columns or progress markers.** The hub describes what the
  app does today; anything unfinished simply is not documented yet.

## Structure of a guide

Keep guides skimmable — a stressed caller may be reading one the night before a
gig.

- Start with a one- or two-sentence summary of what the guide helps you do.
- Use **task-oriented headings** ("Bring in dances from The Caller's Box"), not
  feature-oriented ones ("The import subsystem").
- Prefer numbered steps for procedures and bullet lists for options.
- Bold the names of on-screen controls and screens: **Collection**, **Programs**,
  **Perform**, **Settings**, the **Import** button.
- Put the most common path first; tuck edge cases and power-user details under a
  later "More options" or "Troubleshooting" heading.
- Cross-link generously to other guides and to the [Glossary](./glossary.md)
  rather than re-explaining the same concept in several places.

## Terminology conventions

Consistent words reduce confusion. Use these, and **link the first use of a term
in each guide to the [Glossary](./glossary.md)** so newcomers can get a
definition without leaving the page. Link to the term's own anchor — for example
`./glossary.md#program` or `./glossary.md#dialect` — so the reader lands directly
on that definition rather than the top of the page.

- **Caller's Compendium** — the app's full name; "the app" is fine after first use.
- **dance** — a single transcription in your **collection**.
- **collection** — your whole library of dances.
- **figure** / **move** — a single action in a dance (for example, "neighbors
  balance and swing"). Use "figure" for the entry in a dance; "move" for the
  underlying named action.
- **formation**, **progression** — describe how dancers are arranged and how they
  move on to the next couple; keep these as plain contra terms.
- **program** — an ordered set list for an event; the individual entries are
  **slots**, and an alternate dance is an **alt**.
- **matrix** — the figures-by-dances grid inside a program.
- **Perform mode** — the large-print, stage-ready calling view.
- **dialect** — your personal choice of role names and wording (for example,
  **Larks/Robins** or **Leads/Follows**), applied everywhere the app shows text.
  Present it as *your words, your way* — not as a technical mapping.
- **import** — bringing dances in from another source (The Caller's Box, ContraDB,
  Caller's Companion, or a Caller's Compendium file).
- **backup / restore** — saving all your data to a single file and loading it back.

When community usage has moved on from an older term, use the current one (for
example, "shoulder round," not the older gendered term) and let the Glossary note
the history. Never bake gendered role names into examples; use Larks/Robins as the
default and mention that any wording is configurable in your dialect.

## Writing accessibly

These docs are read by people using screen readers, high-contrast displays, and
text zoom — the same audience the app itself is built for. Model good practice:

- **Use real headings in order.** One `#` H1 per page, then `##`, then `###` — do
  not skip levels or fake a heading with bold text. Screen-reader users navigate
  by heading.
- **Write descriptive link text.** Link the words that describe the destination
  ("see the [import guide](./imports.md)"), never "click here"
  or a bare URL.
- **Don't rely on color or symbols alone.** Wherever a guide describes an icon or
  a coloured marker, name it in words too — "a star, labelled *Introduced here*"
  — so the meaning survives for a reader who cannot see it.
- **Spell out abbreviations** on first use.
- **Keep tables simple** with a header row; avoid merged cells and layout tables.
- **Write for zoom and narrow screens** — short paragraphs and lists survive
  reflow better than dense blocks.

## Alt-text policy

Every image in the user docs **must** have alt text. This is not optional.

- **Informative images (screenshots, diagrams):** write alt text that conveys the
  same information the image gives a sighted reader — what screen it is and what
  it shows.

  ```markdown
  ![The Collection screen showing a search for "petronella" with three matching dances listed](images/collection-search-petronella.png)
  ```

- **Decorative images** (a divider, a purely aesthetic flourish that adds no
  information): mark them decorative with **empty** alt text so screen readers skip
  them. Add an HTML comment noting it is decorative if it is not obvious.

  ```markdown
  ![](images/divider.png)
  ```

- **Describe, don't transcribe.** Summarize the meaningful content; you do not
  need to read out every label. Aim for one clear sentence.
- **Don't start with "Image of…"** — the screen reader already announces that it
  is an image.
- **Captions vs. alt text:** a caption (visible text under an image) and alt text
  serve different readers; if a caption already fully describes the image, keep the
  alt text short and complementary rather than duplicating it verbatim.
- **Wireframe illustrations** (see [`images/README.md`](images/README.md)) must say
  they are wireframes in both the caption and the alt text, so no one mistakes a
  sketch for the finished screen.

## Screenshots and images

**The user guide is text-only today.** The guides are bundled into the app and
the in-app reader does not render images — it shows the alt text as a caption
instead. So an illustration only ever reaches readers on GitHub, and a guide that
*needs* a picture to make sense is broken for everyone reading it on stage.

Write every explanation so it stands on its own words. If you do add an image,
treat it as an enhancement, never as a load-bearing part of a procedure, and
follow the rules below.

- **Naming:** lowercase, hyphen-separated, `screen-topic.png` — for example
  `perform-mode-dark.png`, `programs-matrix.png`. Group a series with a shared
  prefix.
- **Format:** PNG for screenshots, SVG for diagrams and wireframes.
- **Size and cropping:** crop to the relevant region; keep each file small (aim
  well under 500 KB). Capture at a standard zoom so text is legible.
- **Themes:** show Perform-mode shots on the dark-stage theme to convey its
  high-contrast intent; show general screens on the default light theme unless the
  guide is specifically about appearance.
- **Store images** in [`images/`](images/) and reference them with relative paths.

## Describing platform behavior neutrally

Caller's Compendium runs on Linux, macOS, Windows, Android, and iOS/iPadOS. Write
so that a reader on any platform feels the docs are for them.

- **Lead with the neutral action, not the gesture.** Say "open **Settings**" or
  "choose **Import**," then add device-specific detail only if it truly differs.
- **Prefer neutral input words:** "select" or "choose" covers tap, click, and
  keyboard activation. Use "tap" only when talking specifically about touch, and
  "click" only when talking specifically about a mouse.
- **Name platforms in a consistent order** when you must list them: Linux, macOS,
  Windows, Android, iOS/iPadOS.
- **Isolate platform differences.** When a step genuinely differs (file pickers,
  where files are saved, share sheets), use a short per-platform list or a small
  table rather than writing separate versions of the whole guide.
- **Don't assume hardware.** Not every reader has a keyboard, a mouse, or a
  touchscreen; describe at least one non-gesture way to do anything important
  (this mirrors the app's own accessibility commitments).
- **Avoid platform-loaded verbs** like "force-quit" or OS-specific menu names
  unless the guide is specifically about that platform.

## Markdown conventions

- One H1 (`#`) per file, matching the guide's title. **The in-app reader uses
  this H1 as the panel title**, so it must read well on its own.
- **Keep headings plain text.** No bold, links, or code spans inside a heading —
  the in-app reader renders headings as plain, selectable text and would drop the
  markup.
- Wrap prose at a reasonable width for readable diffs; don't hard-wrap tables.
- Use relative links between docs so they work on GitHub and in a local checkout.
- **Link to headings, not just to pages.** A cross-reference like
  `./settings.md#diagnostics` lands the reader on the answer. Anchors follow
  GitHub's rules — lowercase, spaces become hyphens, anything that is not a
  letter, number, hyphen, or underscore is dropped — so "Collection & search"
  becomes `#collection--search`. The in-app reader uses the same rules, so a link
  that works on GitHub works on stage.
- End each guide with a **Where to go next** section of onward links.
- Fenced code blocks only for literal input the reader types or file contents —
  not for UI labels (bold those instead).

## Publishing: the docs are inside the app

`docs/user/` is the source of truth, and `tools/ci/sync_user_docs.py` mirrors it
into the app bundle so the guides ship offline. Two things follow from that:

- **After editing any guide, run the sync and commit the result:**

  ```sh
  python3 tools/ci/sync_user_docs.py --write
  ```

  A CI check fails the build if the bundled copies drift from the source.
- **New guides need no registration** — the app discovers whatever is bundled.
  This style guide is deliberately excluded from the bundle, because it is for
  contributors rather than callers.
