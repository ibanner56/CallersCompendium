# Settings

**Settings** is where you tune Caller's Compendium to fit the way you work — how
your library sorts, how [dances](./glossary.md#dance) look on stage, which
[dialect](./glossary.md#dialect) names appear, and how the app protects your data.
Most of what you'll find here has a dedicated guide of its own, so think of this
page as a tour: it shows you where each control lives and points you to the
details.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Settings**, **Appearance**, and **Defaults**. The
> first time a dance term appears it links to the [Glossary](./glossary.md), so
> you can get a plain-language definition without losing your place.

*The Settings Dialect section with the section list beside controls for the
active dialect and custom wording.*
![The Settings Dialect section showing the section list, active-dialect picker, and custom wording controls](images/settings-dialect.png)

## Finding Settings

**Settings** is a top-level destination, marked with a gear icon and labelled
**Settings**. On a narrow screen (like a phone) it's a tab in the bottom
navigation; on a wide screen (a tablet or desktop) it's in the side navigation
rail.

Inside, a list of sections sits beside the controls for the section you've
chosen. On a narrow screen you pick a section and it opens as its own page, then
you step back to switch sections. There are ten sections, always in this order:

1. **General**
2. **Program**
3. **Appearance**
4. **Dialect**
5. **Language & region**
6. **Defaults**
7. **Updates**
8. **Diagnostics**
9. **Experimental**
10. **About**

## General

The **General** section gathers everyday behavior into small groups.

### Library

- **Ignore leading articles when sorting** (on by default) — alphabetizes titles
  by their first meaningful word. With this on, "The Nice Combination" files under
  **N**, not **T**.

### Accessibility

- **Reduce motion** — trims animations and movement. Follows your device's system
  *Reduce Motion* setting by default; flip this switch to override it either way.
- **Always show verbose figure text** — shows the full spoken-style
  [figure](./glossary.md#figure) wording on screen in the dance view, not only to
  screen readers. Turn it off for the terse notation. This affects the dance view;
  [Perform mode](./perform.md) has its own text-size controls.
- **Show turns as decimals** — shows turn and rotation amounts as decimals (0.75)
  instead of fractions (¾). Screen-reader wording is unaffected.
- **Confirm before delete** — adds a prompt before you delete a dance or program.
  Deletes are still undoable either way.

These are the highlights; the [Accessibility guide](./accessibility.md) gives you
the full picture.

### Deleted items

- **Keep deleted dances for** — choose **30 days**, **60 days**, **90 days**, or
  **Never** (default is **30 days**). Deleted dances are held for this long and
  then purged. For how soft-delete and restore work, see
  [Collection & search](./collection.md).

### Sync decisions

- **Sync decisions** — review conflicts that [Device Sync](#device-sync)
  couldn't settle on its own, and choose how each one is resolved. Three kinds of
  conflict currently offer a decision:
  - **A device deleted something another device still has.** One of your
    devices deleted a choreographer, tag, custom field, or difficulty level
    that this device had already created on its own under the same name,
    before either device had seen the other's copy. **Merge** accepts the
    deletion, so this device's copy goes too. **Keep both** gives this
    device's record a new, distinct name so it survives alongside the
    deletion. Dances never enter this decision; they use the dance one below.
  - **Another device renamed a record onto a name this device already uses.**
    Both records already exist here — they may well be two different people or
    two different tags — so nothing is merged behind your back. **Merge** keeps
    one record and points everything that referred to the other at it.
    **Keep both** asks you for a new name for the record that currently holds
    the name, and then applies the other device's rename. Until you choose, the
    other device's change is not applied.

    Merging two choreographers is the one case that loses something: an email
    address, location, and deceased marker are kept only on your own device and
    are never sent to your other devices, so the ones on the record that is not
    kept cannot be recovered. The app asks you to confirm before this happens.
  - **Two devices independently created dances with the same title but
    different choreography.** This turns up when a device first connects to a
    store that already has dances in it. **Merge** combines the two dances into
    one. **Keep both** renames one of the dances so both are kept separately.
  Any other conflict is shown as retained, with no action available yet, until
  a future version knows how to resolve it.

### Import

- **Import dances** — the entry point for bringing dances in from other sources.
  See [Imports & migration](./imports.md).
- **Published collections** — browse signed collections from the trusted catalog
  and send one through the review flow. See
  [Imports & migration](./imports.md#import-a-published-collection).
- **Re-check custom figures** — re-reads imported dances whose figures were kept
  as plain custom text only because the app couldn't recognise them at the time.
  You preview and confirm before anything changes, and your tags, ratings, and
  notes are preserved. See
  [Write & edit dances](./authoring.md#fix-figures-an-import-could-not-read).

### Backup & restore

- **Export a backup** and **Restore from a backup** — save a copy of everything or
  bring a copy back.
- **Backup reminder** — set to **Off**, **Weekly**, or **Monthly**, with a "last
  backup" date so you know where you stand.

For the whole workflow, see [Backup & portability](./backup-portability.md).

## Program

The **Program** section gathers the settings that shape how you build, check, and
perform your [programs](./glossary.md#program) — venues, the programming matrix,
Perform mode, and calling history.

### Venues

- **Use reusable venue records** (off by default) — turns a program's
  [venue](./glossary.md#venue) into a reusable record with address, contacts, and
  schedule that many programs can share and you edit in one place. When off, a
  program's venue is a simple free-text field. Switching is **lossless and
  reversible**: your typed venue text and any linked record are both kept, so
  flipping the toggle never discards either.
- **Manage venues** — browse, edit, and delete your saved venue records. You can
  also add a venue on the fly while editing a program (when reusable venue records
  are on). Deleting a venue is permanent — unlike a deleted dance, it isn't held
  for later restore. To keep you from stranding a program, a venue can't be
  deleted while any program is still linked to it; change or remove the venue on
  those programs first, then delete it.

Whether the toggle is on or off, a program that's linked to a saved venue always
shows and exports that venue's full details (the linked record wins over free
text). See [Programs](./programs.md) for how the venue field behaves in each mode,
and [Share, print & export](./sharing.md#what-stays-private) for how venue contact
details are handled when you export.

### Programs

- **Flag exact beat overlap only** (on by default) — controls how the
  [programming matrix](./programs.md#check-your-evening-with-the-matrix)'s alert
  marker decides that a move repeating in two back-to-back dances is worth a
  second look. On (the default), only a move whose beats actually **overlap**
  between the two dances is flagged. Off, any move that merely lands in the same
  **named phrase** (A1, A2, B1, B2…) is flagged, even if its beats don't overlap
  at all — this was the matrix's original behavior. The screen legend and the
  printed PDF legend always agree with whichever mode is on.

- **Matrix columns** — opens a dedicated editor for the columns of the
  [programming matrix](./programs.md#check-your-evening-with-the-matrix). These
  changes are saved and apply to **every** program, both on screen and in the
  printed PDF — distinct from the per-session eye icon in a matrix's own header,
  which only hides a column until you reopen that program. In the editor you can:
  - **Reorder** columns by dragging the handle on the left of each row.
  - **Rename** a column with a name that suits your callers; leave the field
    empty to fall back to the built-in name (shown as a hint).
  - **Remove** a column you never use, or **restore** one you removed earlier —
    removed columns stay listed here (struck through) so you can always bring
    them back.
  - **Restore removed columns** brings back everything you removed and returns the
    built-in columns to their original order, while keeping your renames and any
    custom columns.
  - **Restore all defaults** clears every customisation and returns the matrix to
    how it ships. Because it discards your renames and custom columns, it asks
    you to confirm first.

### Performance

- **Auto-size Perform cards** (on) — scales each card so it fits the screen in
  [Perform mode](./glossary.md#perform-mode). Turn it off when you'd rather size
  the text yourself using the **A−** and **A+** buttons while performing. See
  [Perform mode](./perform.md) for more.
- **Show timer for individual Perform** (on) — shows an elapsed timer and
  pause/resume control while performing a single dance. Turn it off when you
  want individual Perform to stay timer-free.
- **Show caller notes in program Perform** (on) — shows each non-empty
  per-slot caller note above the dance title while performing a program. Turn it
  off when you want the program card to show only the dance's own details.

### Calling history

- **Require "mark performed" for calling history** (off) — when on, a dance's
  calling history lists only the [programs](./glossary.md#program) whose
  [slot](./glossary.md#slot) was actually marked performed, rather than every
  program the dance appears in.
- **Track calling history for all callers** (off) — when off *and* you've set a
  [default caller for new programs](#program-defaults), a dance's calling history
  and "called ×N" counts include only programs led by that caller (plus any
  programs with no caller recorded, which are treated as your own). Turn it on —
  or leave the default caller blank — to track every program that contains the
  dance. Matching ignores surrounding spaces and letter case, and applies on top
  of the *Require "mark performed"* setting (both must pass).
- **Repeated venues in calling history** (3) — shows the top venues where a
  dance was called more than once. Set this to 0 to hide the summary, or choose
  up to 10 venues.

## Appearance

The **Appearance** section controls how the app looks.

### Theme

A gallery of built-in themes: **System** (follows your device), **Light**,
**Dark**, and a set of named color palettes, including high-contrast and
editor-inspired schemes. Selecting a theme previews and applies it right away.
There's a **High Contrast** theme for maximum legibility — see the
[Accessibility guide](./accessibility.md) for when it helps.

### Custom themes

- **New custom theme** — opens an editor seeded from your current theme, so you
  start from something familiar. You can tune any colour in it.
- Saved custom themes can be selected, edited, duplicated, or deleted at any time.
  They are saved on this device.

### Easter eggs

- **Colour-named dances tint the theme** (off by default) — a playful surprise:
  open a dance whose title names a colour, like *Baby Rose* or *Blue Boy*, and its
  view is tinted that colour. It steps aside when a high-contrast theme is active,
  so readability always wins.

### Set lists

- **Colour-code set-list rows** — tints each dance row in a program's set list
  (both the read-only summary and the builder) by its
  [formation](./glossary.md#formation) family — contras, triplets, mixers,
  circles, and squares each get their own accent, so you can read the *shape* of a program at a
  glance. Dances marked as [mixers](./glossary.md#mixer) always get the mixer
  accent regardless of their formation, so a mixer-flagged Improper reads as
  a mixer rather than a contra. The formation (and "Mixer" when applicable) is
  always shown as text on the row too, so rows stay fully readable without relying
  on colour, and the accents adapt to the High Contrast theme. On by default; turn
  it off to hide the tints.

### Formation colours

- **Formation label colours** — highlight individual formations in your own
  colours (for example Becket clockwise in yellow and Becket counter-clockwise in
  pink). Your choices show on dance cards, in dance detail, and in the Perform
  header.

### Tag colours

- **Tag colours** — give a tag its own colour so it stands out wherever it
  appears, on dance cards and in dance detail. Only the tags you colour change;
  every other tag looks exactly as it does now. The tag's name is always shown
  beside the colour, so tags stay readable without relying on colour, and the
  app picks a black or white label automatically so your colour stays legible in
  every theme.

## Dialect

The **Dialect** section is your library of [dialects](./glossary.md#dialect) — the
role names and wording the app uses when it describes dances.

- Preset dialects are read-only, but you can **Duplicate to customize** to make
  your own version.
- Custom dialects can be edited, renamed, or deleted.
- One dialect is active at a time.

### Dance details & shorthands

- **Canonical figure text** (off by default) — allow dance details to show
  canonical role and move names. When it is off, dance details open in your
  active dialect and do not show the in-detail **Canonical** switch.
- **Auto-convert all discouraged terms** (on by default) — show supported
  discouraged terms in canonical wording across read-only dance details,
  shorthands, notes, Perform mode, and exports. Saved text and entry fields are
  unchanged.
- **Open dance details in canonical terms** — when enabled, and canonical figure
  text is enabled, dance details open in canonical wording. When canonical
  figure text is disabled, this preference is retained but ignored until the
  gate is enabled again. On an existing installation, the first detail open
  initializes the new gate off and converts an older canonical default to the
  active-dialect default; later changes to the gate never overwrite this
  preference.
- **Free-text entry** — when on, adding a figure lets you type a whole line
  (for example "neighbor balance & swing") instead of building it field by field.
- **Figure shorthands** — map short tokens to one or more figures you can insert
  during free-text entry. See
  [Figure shorthands](./authoring.md#figure-shorthands).
- **Walkthrough snippets** — manage your personal, per-figure walkthrough
  wording. These settings are independent of canonical figure text.

This is just the entry point — see [Dialect](./dialects.md) for the full story on
choosing and customizing wording.

## Language & region

The **Language & region** section handles formats and localization.

### Formats

- **Date format** — choose **System default**, **Year-month-day**,
  **Day/month/year**, **Month/day/year**, or **Custom…**. A live example shows the
  result, and your choice controls how program event dates appear.

  A custom pattern is built from these tokens:

  | Token | Meaning |
  |---|---|
  | `yyyy` or `yy` | Year |
  | `MM` | Month as digits |
  | `MMM` | Month as a short name |
  | `MMMM` | Month as a full name |
  | `d` or `dd` | Day |

  Separate them with a hyphen, slash, dot, comma, or space. If a pattern isn't
  recognised the app says so and falls back to the system default until you
  correct it.

- **First day of week** — choose **System default**, **Sunday**, **Monday**, or
  **Saturday**. This sets which day starts the week in the date views the app
  draws for itself — today that is the "this week" strip at the top of the
  Programs list, which reorders the moment you change the setting. Date *entry*
  still uses the system picker, which follows the app's active language.

### Language

- **App language** — choose **System default** or one of the bundled languages
  (currently English, German, French, Japanese, Danish, and Dutch). Changing it
  re-renders the app immediately and is remembered next time you open the app.
  Your dance content — figure and call wording — is governed by your chosen
  [dialect](./dialects.md), independent of the interface language.

## Defaults

The **Defaults** section sets the starting points for new items. Every default
here can still be changed on each item later — they just save you repetitive
setup.

### Program defaults

- **Default caller** and **Default band** — prefilled into each new program, and
  editable per program.
- **Starting program** — configure an ordered template of dances, caller notes,
  breaks, and free-text entries for manually created programs. Dance references
  that are no longer in your collection are skipped. This applies only to the
  normal manual editor flow; imports, duplicates, and “create with this dance”
  keep their own source slots.

### Display defaults

- **Collection sort order** — the default order for your library when you open it.
  You can still change the sort while browsing.

### Dance-authoring defaults

These help if you write your own dances. Keep in mind you can override any of them
per dance. [Write & edit dances](./authoring.md) covers them in context.

- **Form**, **Formation**, and **Progression** — the starting choices for a new
  dance.
- **Default phrase structure** — leave blank for the standard 4×16 A1 A2 B1 B2, or
  set your own.
- **Starting figures** — the figures a new dance begins with; defaults to a single
  stand still of eight beats. Clear it for a blank new dance.
### Difficulty levels

- **Manage difficulty levels** — define the ordered vocabulary used by dance
  editors, collection filters, and batch actions. Add a level, rename it, or
  drag it into a different position; renaming keeps existing dance assignments
  attached to that level.
- A level cannot be removed while any dance uses it. Once its assignments are
  cleared or changed, you can remove it, including one of the levels that ships
  with the app.

- **Meanwhile defaults** — the ordinary side figures used when you choose **Add
  meanwhile** while authoring a dance. Leave this list empty to start with two
  blank sides, or configure up to six ordinary sides. If only one side is
  configured, the app adds a blank second side so the container can be completed.
  Invalid or unavailable saved defaults use two stand-still sides.
- **Modifier defaults** — the core and modifier figures used when you choose
  **Add modifier** while authoring a dance. Leave this list empty to start with
  two blank figures, or configure up to six figures. Invalid or unavailable
  saved defaults use two stand-still figures.
- **Move defaults** — preferred parameter values applied automatically when you
  insert a [move](./glossary.md#move) while writing. These override that move's
  built-in defaults, and you can still change any parameter afterwards.
- **Aggressively recompute figure beats** (off by default) — when on, changing a
  figure's move or a parameter that affects timing recalculates its beat count
  immediately, even overwriting a beat count you typed in by hand. When off, a
  beat count you've edited is never changed automatically.

## Updates

The **Updates** section lets the app tell you when a newer version is out — and,
on desktop, help you install it. Nothing here happens behind your back: the app
never updates itself automatically, and no update is ever downloaded or installed
without you choosing to.

- **Check for updates** — check right now, any time. It shows the version you're
  on and whether a newer one is available. If it can't reach the update service it
  simply reports that no update was found, so a checkup never interrupts you with
  an error.
- **Beta channel** (off by default) — turn this on to be offered pre-release beta
  versions. Left off, you're only offered stable releases.
- **Check automatically** (off by default) — when on, the app quietly checks for a
  newer version as it starts up. Left off, checking only happens when you ask.

When an update is available, a dismissible banner points you to the release so you
can read what's new before deciding.

On **desktop**, once an update is found you can **Download & install update**: the
app downloads it, verifies it hasn't been tampered with, then hands it to your
system's installer to finish — it never replaces itself in place. On **macOS**,
you first choose where to save the disk image. After it is verified, choose
**Update now** to open the image and close the app; you can then replace the app
in **Applications**. Choose **Not now** to keep working and use **Update and
restart** from the banner or Updates section later. On **Windows**, clicking
**Download & install update** authorizes the verified installer to run; it handles
closing and replacing the existing installation. On phones and tablets, the
banner's link takes you to the release to download it the usual way for your
platform.

Your privacy is built in: an update check downloads a small version file over a
secure connection and nothing else. No information about you, your device, or how
you use the app is ever sent.

## Diagnostics

When something goes wrong, the app writes a short technical note to a log on your
own device — not just outright crashes, but also errors you see reported on
screen (like a failed import). **It is never sent anywhere — there is no
telemetry.** The **Diagnostics** section is where you read that log, hand a
copy to a bug report, or wipe it.

### Recent entries

A list of the most recent entries, newest first, so you can see whether anything
was captured around the time the trouble happened. If nothing has ever gone wrong
you'll see **No errors recorded**. If the log can't be read, the app says so and
still lets you try to export or clear it.

### Export

- **Include full detail (may contain your content)** — **off by default**. Left
  off, the export removes your content, file paths, email addresses, and phone
  numbers. Turn it on only when you mean to share the full, unredacted log.
- **Export / share log** — hands the log to your system's share or save dialog.
  The row tells you which kind you're about to send: a scrubbed copy safe to
  attach to a bug report, or the full unredacted log. If the app can't prepare a
  safe scrubbed copy it saves nothing and tells you, rather than sending more than
  you asked for.

If there is nothing in the log, the app says **No diagnostics to export** instead
of producing an empty file.

### Clear log

- **Clear log** — deletes the local crash log from this device. The app asks first
  and is blunt about it: this cannot be undone.

Filing a bug? A scrubbed log attached to a
[GitHub issue](https://github.com/ibanner56/CallersCompendium/issues) is the most
useful thing you can send.

## Experimental

The **Experimental** section is a home for features that are still in
development. It may be empty, and anything that appears there can change before
it becomes a regular setting. Each feature sits in its own section: tap its
heading to open or close it.

### Device Sync

**Device Sync** keeps your library in step across your own devices. It is **off
until you turn it on**, and while it is off the app sends nothing anywhere.
Turning it on does not send anything by itself; nothing is exchanged until you
connect a store. The section starts closed while Device Sync is off and open
while it is on. You can tap its heading to open or close it.

- **Sync only on WiFi** is on by default. On a mobile-data connection automatic
  sync waits, and pressing **Sync now** tells you why and points at this setting.
  A pass that was skipped runs the next time sync is triggered; you do not need
  to do anything.
- **Skip unused imported dances** is off by default. If you have a large
  imported collection, turning it on cuts what this device uploads — but a
  dance that's actually used in one of your programs, or linked from another
  dance, is always included, so nothing that's still in use loses anything.
  Turning it on removes nothing already on your other devices; this device
  just stops advertising the rest. Turning it back off republishes them.
- **Status** opens with **Your sync phrase** — the phrase this device is
  connected with — so you can add another device later even if you didn't write
  it down when you first connected. It stays hidden behind bullets until you
  tap the eye button, and **Copy** puts it on the clipboard without showing it,
  which is all you need to type or paste it into the other device. Keep it to
  yourself: anyone who has the phrase can read and change everything you sync,
  and the only way to change it is to move every device to a new one.
- **Status** also shows when this device last synced. **Sync is not a backup:**
  a store that goes unused for 30 days is removed, so keep making file backups.
  From three weeks of disuse the status also warns that the store is close to
  expiring.
- **Notices** appear under that last-synced line when a sync had something to
  report. A sync can finish successfully and still leave one of these standing,
  which is the point of them: the conditions they name are ones the app will
  not guess its way out of. You'll see a notice when the same record was
  changed on two devices in the same moment and neither copy could be chosen
  (edit either one to settle it); when something created here was kept rather
  than removed by a device that had never seen it; when something on *this*
  device has a date the app can't trust, so it isn't being sent anywhere
  (check this device's clock); when records from another device couldn't be
  used and were skipped; when another device's clock looks far off; when an
  update arrived while you were editing the same record, so it waits for the
  next sync; and when changes from this device still haven't reached your
  other devices after several syncs. A notice is only ever a message — it
  never blocks an edit, never holds up a sync, and there is nothing to dismiss.
  It stays until a sync no longer finds the condition, then goes away on its
  own. One kind is deliberately stickier: a record refused from another device
  is only mentioned once per run of the app, so its notice stays for the rest
  of that run rather than disappearing at the next sync and leaving you with
  nothing. Notices are not kept when you close the app; anything still true is
  reported again by the next sync.
- These settings belong to this device. They are not synced to your other
  devices, and they are not included in a backup, so restoring a backup never
  turns sync on.

**Connecting.** Once enabled, tap **Connect** to either **create a new store**
(you get a phrase — read it aloud or share it with your other device, or
replace it with one of your own: four words separated by hyphens. If the phrase
you choose looks easy to guess, the screen says so but still lets you use it) or
**connect to an existing one** (enter the phrase shown on the device you
already set up). The screen tells you which you're doing; it never guesses.
The **Server** field is pre-filled with the Caller's Compendium sync server,
`https://athenaeum.callerscompendium.com/`; leave it alone unless you run your
own. If you change it, the screen warns you that whoever runs that server can
read, change, and delete everything you sync, and once you're connected the
status keeps showing which server you're using. The address must start with
`https://` (plain `http://` is accepted only for `localhost` or `127.0.0.1`,
for testing a server on the same machine).
Along the way it explains two things worth knowing before you commit to
sharing a phrase: a second device using the same phrase can edit the same
records, and if both of you touch the same dance or program at once, one
edit silently wins — there is no merge and no warning. It also explains that
the phrase itself has no password reset: losing it locks you out of that
store, and a phrase that has leaked can't be taken back, so carrying on
syncing means moving every device to a new phrase. That does not remove what
the old phrase still opens — see **Deleting the store** below. Before
connecting, you're offered an optional one-time backup of your library —
accepting or skipping it doesn't change what connecting does.

**Disconnecting.** To stop syncing on this device without turning Device Sync
off, tap **Disconnect this device** and confirm. The device forgets its phrase
and the server it was using, and stops syncing, but nothing else changes: your
library here stays as it is, the store keeps everything, and your other devices
carry on syncing. Nothing is sent when you disconnect. To reconnect — to the
same store or a different one — tap **Connect** again; you'll need the phrase,
so keep it somewhere safe, along with the server address if you changed it.
Disconnecting really does forget it, so copy it from **Your sync phrase**
first if it isn't written down anywhere else.
Turning **Device Sync** off and on again, by contrast, keeps this device
connected.

**Your other devices.** **Other devices** lists everything else connected to
this store, and lets you remove one you no longer use — a phone you've replaced,
or one that's been lost. Removing a device frees the place it was taking up
straight away; a store holds 32 devices, so a run of replaced phones can
eventually leave no room for a new one. The store also drops that device's list
of what it shared, though the shared items themselves are cleared up later, in
the server's own time, so the space they use doesn't come back immediately.
Nothing is deleted from the removed device, and nothing is deleted from yours.

Removing is for a device that's genuinely gone. It doesn't disconnect anything
and it isn't a ban: a device that's still running will publish its list again
the next time it syncs and reappear in this list, and any device can connect to
this store again with the phrase. To stop a device syncing you have to
disconnect it on that device.

The list shows the identifiers the server made up for each device, because
that's all the server knows — there are no device names, and this device isn't
in the list. If you can't tell which is which, it's safe to leave them: the
only cost of an extra entry is one of the 32 places.

**Deleting the store.** **Disconnect all devices and delete the store** removes
everything the store holds from the server, for every device at once, and it
can't be undone. Your library stays on this device and on each of your other
devices, but anything that had only ever reached another device through syncing
won't arrive here. This device disconnects and forgets its phrase; your other
devices find the store gone the next time they sync and are asked whether to
start a new one, the same question as any store that's no longer there.

This is what to use if someone else has seen your sync phrase. A leaked phrase
can't be revoked, and moving your devices to a new phrase doesn't help on its
own — whoever has the old one can still read and change everything in the old
store. Deleting the store is the only thing that takes that away immediately.
It is not the answer to running out of room, though: remove a device you don't
use instead.

If a store this device used to sync with is no longer there, the app asks
before creating a replacement: it may have gone unused past its 30-day limit,
or it may have been removed — the app can't tell which. Reconnecting re-sends
your whole library, so it follows **Sync only on WiFi** like everything else:
on mobile data with that setting on, nothing is sent and the app points you at
the setting, with the question still waiting once you're back on WiFi. If a
reconnection doesn't go through, the question comes back and says so, and you
can try again or leave it. Declining makes no
network request and leaves the choice for later. Sync then **pauses**: the
status says so and keeps saying so, and automatic syncs stop running rather
than asking again every time. Nothing is lost while it is paused. When you
want to decide, tap **Sync now** — that reopens the same question, and the
paused line goes once a sync completes.

**Venues sync partially.** A venue's name, website, schedule, and notes sync
like everything else, but its address and both contact blocks stay on each
device — there's no channel for them to travel through. While Device Sync is
on, the [venue](./glossary.md#venue) editor shows a note on a venue whose
address and contact fields are blank, naming exactly those fields. (Notes
does sync — if you've put contact information there, it travels with the
note.)

## About

The **About** section tells you what you're running and where it comes from.

- App name, **Version**, and the app's tagline.
- A **User guide** link that opens the built-in offline guides — the same pages
  you're reading now.
- License info: the app is free software under **AGPL-3.0**, with **View source on
  GitHub**.
- Bundled-font credits — Fraunces, Atkinson Hyperlegible, and Roboto, under the
  SIL Open Font License.
- Theme-palette and dance-data attributions, including The Caller's Box
  (CC BY-NC).
- **View licenses** — the full license texts.

## Where to go next

- [Dialect](./dialects.md) — customize the role names and wording your dances use.
- [Backup & portability](./backup-portability.md) — export, restore, and set
  backup reminders.
- [Imports & migration](./imports.md) — bring dances in from other sources.
- [Accessibility](./accessibility.md) — reduce motion, verbose figure text,
  high-contrast themes, and more.
- [Write & edit dances](./authoring.md) — authoring defaults, shorthands, and
  walkthrough snippets in context.
- [Collection & search](./collection.md) — custom fields and restoring deleted
  dances.
