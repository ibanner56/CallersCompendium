# Settings

**Settings** is where you tune Caller's Compendium to fit the way you work — how your library sorts, how [dances](./glossary.md#dance) look on stage, which [dialect](./glossary.md#dialect) names appear, and how the app protects your data. Most of what you'll find here has a dedicated guide of its own, so think of this page as a tour: it shows you where each control lives and points you to the details.

> **Finding your way around these words.** On-screen buttons and screens are written in **bold** — like **Settings**, **Appearance**, and **Defaults**. The first time a dance term appears it links to the [Glossary](./glossary.md), so you can get a plain-language definition without losing your place.

*Wireframe sketch of the Settings screen: a section list on the left (General, Appearance, Dialect, Language & region, Defaults, Updates, About) beside the settings for the chosen section. This is a low-fidelity layout sketch, not the finished app.*
![Wireframe sketch of the Settings screen showing the section list beside the controls for the selected section](../design/wireframes/7-settings.svg)

## Finding Settings

**Settings** is a top-level destination, marked with a gear icon and labelled **Settings**. On a narrow screen (like a phone) it's a tab in the bottom navigation; on a wide screen (a tablet or desktop) it's in the side navigation rail.

Inside, a list of sections sits beside the controls for the section you've chosen. On a narrow screen you pick a section and it opens as its own page, then you step back to switch sections. There are seven sections, always in this order:

1. **General**
2. **Appearance**
3. **Dialect**
4. **Language & region**
5. **Defaults**
6. **Updates**
7. **About**

## General

The **General** section gathers everyday behavior into small groups.

### Library

- **Ignore leading articles when sorting** (on by default) — alphabetizes titles by their first meaningful word. With this on, "The Nice Combination" files under **N**, not **T**.

### Venues

- **Use reusable venue records** (off by default) — turns a program's [venue](./glossary.md#venue) into a reusable record with address, contacts, and schedule that many programs can share and you edit in one place. When off, a program's venue is a simple free-text field. Switching is **lossless and reversible**: your typed venue text and any linked record are both kept, so flipping the toggle never discards either.
- **Manage venues** — browse, edit, and delete your saved venue records. You can also add a venue on the fly while editing a program (when reusable venue records are on). Deleting a venue is permanent — unlike a deleted dance, it isn't held for later restore. To keep you from stranding a program, a venue can't be deleted while any program is still linked to it; change or remove the venue on those programs first, then delete it.

Whether the toggle is on or off, a program that's linked to a saved venue always shows and exports that venue's full details (the linked record wins over free text). See [Programs](./programs.md) for how the venue field behaves in each mode.

### Performance

- **Auto-size Perform cards** (on) — scales each card so it fits the screen in [Perform mode](./glossary.md#perform-mode). Turn it off when you'd rather size the text yourself using the **A−** and **A+** buttons while performing. See [Perform mode](./perform.md) for more.

### Calling history

- **Require “mark performed” for calling history** (off) — when on, a dance's calling history lists only the [programs](./glossary.md#program) whose [slot](./glossary.md#slot) was actually marked performed, rather than every program the dance appears in.

### Accessibility

- **Reduce motion** — trims animations and movement. Follows your device's system *Reduce Motion* setting by default; flip this switch to override it either way.
- **Always show verbose figure text** — shows the full spoken-style [figure](./glossary.md#figure) wording on screen, not only to screen readers.
- **Confirm before delete** — adds a prompt before you delete a dance or program. Deletes are still undoable either way.

These are the highlights; the [Accessibility guide](./accessibility.md) gives you the full picture.

### Deleted items

- **Keep deleted dances for** — choose **30 days**, **60 days**, **90 days**, or **Never** (default is **30 days**). Deleted dances are held for this long and then purged. For how soft-delete and restore work, see [Collection & search](./collection.md).

### Import

- **Import dances** — the entry point for bringing dances in from other sources. See [Imports & migration](./imports.md).

### Backup & restore

- **Export a backup** and **Restore from a backup** — save a copy of everything or bring a copy back.
- **Backup reminder** — set to **Off**, **Weekly**, or **Monthly**, with a "last backup" date so you know where you stand.

For the whole workflow, see [Backup & portability](./backup-portability.md).

## Appearance

The **Appearance** section controls how the app looks.

### Theme

A gallery of built-in themes: **System** (follows your device), **Light**, **Dark**, and a set of named color palettes, including high-contrast and editor-inspired schemes. Selecting a theme previews and applies it right away. There's a **High Contrast** theme for maximum legibility — see the [Accessibility guide](./accessibility.md) for when it helps.

### Custom themes

- **New custom theme** — opens an editor seeded from your current theme, so you start from something familiar.
- Saved custom themes can be selected, edited, duplicated, or deleted at any time.

### Set lists

- **Colour-code set-list rows** — tints each dance row in a program's set list (both the read-only summary and the builder) by its [formation](./glossary.md#formation) family — contras, triplets, mixers, circles, and squares each get their own accent, so you can read the *shape* of a program at a glance. The formation is always shown as text on the row too, so rows stay fully readable without relying on colour, and the accents adapt to the High Contrast theme. On by default; turn it off to hide the tints.

## Dialect

The **Dialect** section is your library of [dialects](./glossary.md#dialect) — the role names and wording the app uses when it describes dances.

- Preset dialects are read-only, but you can **Duplicate to customize** to make your own version.
- Custom dialects can be edited, renamed, or deleted.
- One dialect is active at a time.

This is just the entry point — see [Dialect](./dialects.md) for the full story on choosing and customizing wording.

## Language & region

The **Language & region** section handles formats and localization.

- **Date format** — choose **System default**, **Year-month-day**, **Day/month/year**, or **Month/day/year**. A live example shows the result, and your choice controls how program event dates appear.
- **First day of week** — shown as **Coming soon** and disabled for now. A future update will let you choose which day the week starts on in the app's own date views; today, date entry uses the system picker, which follows the app's active language.
- **App language** — choose **System default** or one of the bundled languages (currently English, German, French, Japanese, Danish, and Dutch). Changing it re-renders the app immediately and is remembered next time you open the app. Your dance content — figure and call wording — is governed by your chosen [dialect](./dialects.md), independent of the interface language.

## Defaults

The **Defaults** section sets the starting points for new items. Every default here can still be changed on each item later — they just save you repetitive setup.

### Program defaults

- **Default caller** and **Default band** — prefilled into each new program.

### Display defaults

- **Collection sort order** — the default order for your library: **Title**, **Author**, **Recently added**, or **Last called**.
- **Open dance details in canonical terms** — when on, dances open showing their canonical names instead of your active dialect. You can still switch to your dialect while viewing.

### Dance-authoring defaults

These help if you write your own dances. Keep in mind you can override any of them per dance.

- **Form**, **Formation**, and **Progression** dropdowns — the starting choices for a new dance.
- **Default phrase structure** — leave blank for the standard 4×16 A1 A2 B1 B2, or set your own.
- **Starting figures** — an editor for the figures a new dance begins with; defaults to a single stand-still.
- **Move defaults** — preferred parameter values applied automatically when you insert a [move](./glossary.md#move) while writing.
- **Walkthrough snippets** — a personal, per-figure library of your own walkthrough wording. The first time you walk a figure the app learns the text you write, then pre-fills the [Walkthrough](./collection.md#read-a-dance-in-detail) for any dance that uses that figure. Editing a snippet asks whether to change it **everywhere** or **just for this dance**. Manage the whole library from here — review, edit, or delete any snippet.

For writing and editing dances, see [Collection & search](./collection.md).

## Updates

The **Updates** section lets the app tell you when a newer version is out — and, on desktop, help you install it. Nothing here happens behind your back: the app never updates itself automatically, and no update is ever downloaded or installed without you choosing to.

- **Check for updates** — check right now, any time. It shows the version you're on and whether a newer one is available. If it can't reach the update service it simply reports that no update was found, so a checkup never interrupts you with an error.
- **Beta channel** (off by default) — turn this on to be offered pre-release beta versions. Left off, you're only offered stable releases.
- **Check automatically** (off by default) — when on, the app quietly checks for a newer version as it starts up. Left off, checking only happens when you ask.

When an update is available, a dismissible banner points you to the release so you can read what's new before deciding.

On **desktop**, once an update is found you can **Download & install update**: the app downloads it, verifies it hasn't been tampered with, then hands it to your system's installer to finish — it never replaces itself in place. On phones and tablets, the banner's link takes you to the release to download it the usual way for your platform.

Your privacy is built in: an update check downloads a small version file over a secure connection and nothing else. No information about you, your device, or how you use the app is ever sent.

## About

The **About** section tells you what you're running and where it comes from.

- App name, **Version**, and the app's tagline.
- A **User guide** link that opens the built-in offline guides.
- License info: the app is free software under **AGPL-3.0**, with **View source on GitHub**.
- Bundled-font credits — Fraunces, Atkinson Hyperlegible, and Roboto, under the SIL Open Font License.
- Theme-palette and dance-data attributions, including The Caller's Box (CC BY-NC).
- **View licenses** — the full license texts.

## Where to go next

- [Dialect](./dialects.md) — customize the role names and wording your dances use.
- [Backup & portability](./backup-portability.md) — export, restore, and set backup reminders.
- [Imports & migration](./imports.md) — bring dances in from other sources.
- [Accessibility](./accessibility.md) — reduce motion, verbose figure text, high-contrast themes, and more.
- [Collection & search](./collection.md) — writing dances, custom fields, and restoring deleted dances.
