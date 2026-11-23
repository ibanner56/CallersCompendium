# Share, print & export

A dance or a program is only half useful while it lives on one device. This guide
covers every way to get your work *out* of Caller's Compendium — as text you can
paste into an email, as a PDF you can print, or as a file you can hand to another
caller — and, just as importantly, what the app deliberately leaves behind.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Export**, **Copy set list**, and **Continue**. The
> first time a dance term appears it links to [App terms](./glossary.md), so
> you can get a plain-language definition without losing your place.

Looking for a copy of *everything* — your whole collection, your settings, your
dialects — to move to a new device? That is a different job, and
[Backup & portability](./backup-portability.md) covers it.

## Share a dance

Open a dance and choose **Export**. (On a narrow screen, the same actions are in
the dance's **More actions** menu.) There are six actions:

| Action | What happens |
|---|---|
| **Share dance (text)** | Hands a plain-text dance card to your system's share sheet — email, messages, notes, whatever you have |
| **Share dance file** | Packages the dance, with the details that go with it, into a `.ccshare` file for another Caller's Compendium user |
| **Show code** | Shows the same dance file as a full-screen QR code, and keeps the screen awake while it shows — see [Show a dance as a code](#show-a-dance-as-a-code) |
| **Copy dance** | Puts the same text on your clipboard, and confirms with "Dance copied to clipboard." |
| **Export dance as JSON** | Builds the same file as **Share dance file**, named `.json` instead, then offers **Save**, **Copy raw JSON**, **Share**, or **Cancel** |
| **Export / print PDF** | Builds a PDF and opens your system's print dialog |

With **Print calling cards** turned on in Settings ▸ Experimental ▸ Calling
cards, there is a seventh: **Print calling card**, which prints the dance on a small card — see
[Print calling cards](#print-calling-cards).

**Copying a selection instead.** On Windows, macOS and Linux you can also drag
across part of a dance's page and press **Ctrl-C** (**Cmd-C** on macOS). That copy
is what the page shows: it follows the canonical-text toggle and your dialect,
like **Copy dance**, but it also carries **Always show verbose figure text**,
figure capitalization and **Show turns as decimals** when those are on, which
**Copy dance** never applies. (Decimal turns show only while verbose text is off.)

**Export / print PDF** is a real print path, not a save-to-PDF shortcut: your
operating system's own dialog opens, and from there you can send it to a printer,
save it as a PDF, or cancel. This works on every platform the app runs on,
including Linux.

A PDF can print Japanese text (hiragana, katakana and the everyday kanji). Rarer
kanji, Chinese-only characters and Korean may still show as empty boxes.

A PDF is laid out on the paper size you pick in the print dialog — Letter, A4,
or another size — and every page carries "Page 1 of 3" at the bottom. From the
second page on, the dance's or program's title also runs along the top.

**File names.** A dance or program you share as a file (`.ccshare` or `.json`)
is named after its title, keeping its letters in any script ("Contredanse à la
française" stays that way) and replacing characters that can't go in a file name
with `_`, and shortening a very long title. A program's file name and its PDF's suggested name end with the event
date — `Saturday_Contra_2026-10-31` — so a weekly program doesn't export under
the same name every time. Backups are named for the day you took them on your
device's clock.

### Which words a dance export uses

Text you share or copy, and a PDF you print, are written in your **active
[dialect](./glossary.md#dialect)** — the one selected in the app right now. Hand
a card to a caller and it reads the way you speak.

This is the *active* dialect, not the dance detail screen's **Canonical**
switch. Flipping that switch changes what you see on screen; it does not change
what an export contains. To export in different words, switch your active
dialect first — see [Dialect](./dialects.md#switch-dialect-on-the-fly). If
**Auto-convert all discouraged terms** is on (the default), common older terms
are also shown in current wording — see
[Discouraged terms](./dialects.md#discouraged-terms).

One exception: a dance whose author has asked that it only be called with
**larks** and **robins** exports with those role terms whatever your dialect,
and switching dialect does not change them. The rest of your dialect still
applies — see [Good to know](./dialects.md#good-to-know).

The field labels around the content — *Formation*, *Level*, *Figures*, *Calling
notes*, and so on — follow the app's language setting, not your dialect, and so
does the punctuation after them (in Japanese, a full-width colon:
`フレーズ：AAB`).

A dance *file* (**Share dance file** or **Export dance as JSON**) is different: it
carries the dance itself rather than your wording of it, so it opens in the
recipient's own dialect.

### Share a dance file

**Share dance file** and **Export dance as JSON** build the same file: the dance,
its credited authors, its tags and difficulty level, the published
sources it cites, its [custom fields](./glossary.md#custom-field), and any of
[your own new figures](./authoring.md#your-own-figures) it uses, without your
notes on them. The only
difference is the name — `.ccshare` or `.json`. Authors' private details
are removed (see [What stays private](#what-stays-private)), and custom fields
with **Include in sharing** turned off are left out. Your star rating of the
dance is left out too; it stays on your devices and in your backup.

On Linux the system has no file share sheet, so **Share dance file** is
labeled **Save dance file…** and saves the file through the system dialog
instead; choosing **Share** in the JSON dialog does the same.

Opening either file in Caller's Compendium goes through import review before
anything is added. Tags, sources, and custom fields the recipient already has are
reused, and their own edits are never overwritten. A custom field in the file
with the same key as one of theirs is the same field when it has the same type
(and, for a choice field, the same choices): its values go into their field,
which keeps their name, choice order, **Show in list**, **Searchable** and
**Include in sharing** settings. If the type or the choices differ, the values
go into the field with their key plus `_2` instead, so their own field never
changes meaning. That field is added the first time; when the same file comes
again, its values go into the same `_2` field. If `_2` is already taken by a
field that differs, or by another field in the same file, the next number is
used. Import review says so before anything is
added. A link to a video or web page
comes along as it is. A link to a related dance comes along when that dance is
imported from the same file. It also comes along when the recipient already has
the related dance from an earlier file, as long as that dance is in this file
too or the sender added it by hand rather than importing it. Otherwise that one
link is left out, and the rest of the dance still imports. After the import, a
summary says what happened to each dance, lists any dance that could not be
imported and any link that was left out, and offers **Undo** until you choose
**Done**.

### Show a dance as a code

**Show code** opens a full-screen QR code that holds the same dance file
**Share dance file** sends, with the dance's title underneath. The screen stays
awake while the code is up, so you can hold it out for someone to read. It needs
no network, and the app asks for no new permission.

The code carries exactly what [a dance file](#share-a-dance-file) carries, under
the same privacy rules: authors' private details are removed (see
[What stays private](#what-stays-private)), custom fields with **Include in
sharing** turned off are left out, and your star rating and your notes on your
own figures stay on your devices.

Opening a code inside Caller's Compendium itself is not available yet. For now,
another phone's camera app reads the code and shows the link as text; to hand a
dance to another Caller's Compendium user, use **Share dance file**.

A short dance is drawn with the Caller's Compendium logo in the middle. A longer
one is drawn without it, because the logo would cover too much of a code that
full. A dance too long for any code (a long walkthrough is the usual reason)
says so, and offers **Share dance file** on the same screen. On Linux that
button is labeled **Save dance file…**.

## Share a program

Open a program and choose **Export**. Five actions, and a sixth for a program
with a date:

| Action | What happens |
|---|---|
| **Share set list (text)** | Hands a plain-text set list to your system's share sheet |
| **Share program and dances** | Packages the program *and* its dances into one file to hand to another caller |
| **Copy set list** | Puts the set list text on your clipboard, and confirms with "Set list copied to clipboard." |
| **Export as JSON file** | Opens a choice to **Save**, **Copy raw JSON**, **Share**, or **Cancel**. The same package is named `.json` for a recipient who doesn't have the app, or when you want to read the file yourself |
| **Export / print PDF** | Builds a PDF set list and opens your system's print dialog |
| **Add to calendar (.ics)** | Only when the program has an event date and, in the builder, once it is saved. Writes a calendar file for your calendar app — see [Put programs in your calendar](#put-programs-in-your-calendar) |

With **Print calling cards** turned on in Settings ▸ Experimental ▸ Calling
cards, there is one more: **Print calling cards**, one small card for each of the program's dances — see
[Print calling cards](#print-calling-cards).

The set list — text and PDF alike — is titles, event details, and slot notes by
default, with each dance's author shown next to its title if you have authors
turned on, and its meter and key if you have meter, key and Barnes turned on
(see [Choose which dance fields appear](#choose-which-dance-fields-appear)
below). When you choose **Share set
list (text)**, **Copy set list**, or **Export / print PDF**, the app asks
**Include figures?** with two choices:

- **Set list only** — titles, event details, slot notes, the author, and the
  meter and key (the default). None of your other selected dance fields appear
  here — formation, level, mixer, status, phrase, calling notes, walkthrough,
  tunes, hook, sources, the composed and interpreted years, the interpreters
  and the Barnes reference only ever show up on the richer per-dance card
  described next.
- **Set list and figures** — appends a full card for each dance after the set
  list, showing every dance field you've selected alongside its figures. The
  cards use your app language for field labels; the figure text uses your
  active dialect. Alternate dances are marked "Alternate". A dance with no
  structured figures still gets its card when it has calling notes, a
  walkthrough, a hook or a published source and you've selected that field; a dance with nothing to show
  beneath its title gets no card.

A program's [times](./programs.md#times) appear in the set list too: the
dance's start and end beside the date, such as "7:30 PM–10:30 PM", with
"(next day)" when it ends after midnight, and the **Beginner lesson** on its
own line. **Arrive by** never appears in the set list or the PDF: it is your
own logistics. When the program has a start or end time, the PDF's venue
details leave out the venue's usual **Time**. A program file you share (**Share program and dances**, or
**Export as JSON file**) keeps all four times, so a guest caller you send it
to knows when to arrive.

If none of the program's dances have anything to put on a card — no structured
figures, and no selected calling notes, walkthrough, hook or published source —
the question is skipped and the export proceeds as set-list-only automatically.

Canceling the dialog (or dismissing it) stops the export — nothing is shared or
copied.

If something goes wrong the app says so plainly — "Couldn't share this set list",
"Couldn't export this set list" — and nothing is sent.

### Choose which dance fields appear

Settings ▸ Defaults has a checklist for every non-figures dance field a dance
card can show: author, formation, level, mixer, status, phrase, calling
notes, walkthrough, suggested tunes, hook, published sources, and meter, key
and Barnes. Everything except suggested tunes, the hook and published sources
is on by default; those three are off by default, since no export showed them
before.

**Authors** also prints the year the dance was composed beside its authors,
such as *Pat Shaw (1951)*, and who interpreted it and when on a line of its
own, such as *Interpreted by Cecil Sharp (1916)*. **Meter, key and Barnes**
prints the tune's meter and key on one line, such as *Meter: 6/8 · Key: G
minor*, and the Barnes reference on the next, such as *Barnes: BIII p. 92*.
It is on for a new install. If you had already changed this checklist before
it was added, it starts off: tick it to print them.

A published source prints as one line per citation, such as *Give-and-Take —
A. Author, 1990 (p. 12, no. 3)*: its title, author and year, then the page and
number you recorded. The source's web address is not printed. A citation whose
source has since been removed from your library still prints its page and number
under "(unknown source)". A dance's custom fields and its links (video, source,
related dance) never appear on a card. Only a
[shared dance file](#share-a-dance-file) carries them (a custom field only if
you marked it **Include in sharing**).

Turning a field off removes it everywhere it would otherwise appear — but
**the plain numbered set-list line shows only the authors' names and the
meter and key**, such as *1. Lilac Lane — by A. Author (English; Meter: 6/8 ·
Key: G minor; 5 min)*, where the form is named only when the program mixes
forms. The rest only appear on the richer per-dance card: the "Set list and
figures" appendix, a single dance's own **Share dance (text)**/**Copy dance**
card, a single dance's PDF, or a printed calling card. Figures are not part of
this list; they stay controlled by the **Include figures?** choice above.

### Share a program with its dances

**Share program and dances** is the one to reach for when you are handing an
evening to another caller. It builds a single self-contained file — a
`.ccshare` file — containing:

- the program itself;
- every dance the program's slots refer to, except one deleted for good on
  another device, which travels as the words "Deleted dance" (see
  [Programs](./programs.md#when-a-dance-in-a-program-is-deleted));
- the authors credited on those dances;
- the tags, published sources, and [custom fields](./glossary.md#custom-field)
  those dances use, so the recipient can import them completely;
- any of [your own new figures](./authoring.md#your-own-figures) those dances
  use: each one's name, description, parameters and wording, but not your
  notes on it; and
- the program's linked [venue](./glossary.md#venue), if it has one.

The file leaves out what is private to you: the program's **Pay**, its
**Perform dialect**, whether you [archived](./programs.md#create-and-manage-programs)
it, and the star **rating** on each dance. Those stay on your own devices and in
your [backup](./backup-portability.md), and still move with Device Sync. A
program you archived arrives unarchived, so it shows in the other caller's list. Pay is never part of the shared set-list text or PDF either; apart from your backup, the only export that carries it is the [programs spreadsheet](#export-programs-as-a-spreadsheet-csv).

On Linux the system has no file share sheet, so this action is labeled **Save
program file…** and saves the file through the system dialog instead.

Custom fields with **Include in sharing** turned off are left out, values
included, exactly as they are for a single dance. If a definition one of the
dances depends on cannot be found, the share stops with an error instead of
sending the file.

The file goes to your system's share sheet, so how it travels is up to you —
AirDrop, email, a messaging app, a USB stick.

The recipient gets your program as a plan, not as your calling history. It
arrives as a **Draft**, with your performed marks and its event date cleared,
just as a [duplicated program](./programs.md#create-and-manage-programs) would. With their
default settings it counts toward their calling history like any other program;
their **Require an event date for calling history** setting keeps it out until
they date it.

On the receiving end, opening the file takes the recipient to Caller's
Compendium's [import review](./imports.md#open-a-shared-program-someone-sent-you)
screen, loaded with the program, its dances, and its venue. Nothing is added
until the recipient confirms. Any of your own figures the file carries are
offered to them afterwards, to add to their Glossary or not — see
[Figures in a shared file](./imports.md#figures-in-a-shared-file). Bringing the same file in twice does not pile up
duplicate *dances* — the importer matches what is already there. A dance it
recognizes as one you already have defaults to **Skip**, and the program still
points at your copy of it. Programs are different: each import adds the program
as a new one. If a caller sends you an updated version of a program you already
have, it arrives beside your copy and never overwrites it, so your own date,
marks and edits stay as they were.

Venues are matched more narrowly. Importing the same program again, or another
program from the same sender that uses the same venue, reuses the venue the first
import added. But a shared file carries no address (see
[What stays private](#what-stays-private)), so the app can't tell that a shared
venue is a hall you already have in your own records, or that venues from two
different callers are the same place. In those cases you get a separate,
name-only venue record. Nothing is lost or overwritten, and you can tidy the
extras in [**Settings ▸ Program ▸ Venues ▸ Manage venues**](./settings.md#venues).

### The same thing, as a plain `.json` file

**Export as JSON file** builds exactly the same content as **Share (program +
dances)** — same program, same dances with their full figures, same
authors, same venue, same privacy rules. You then choose **Save**,
**Copy raw JSON**, **Share**, or **Cancel**. The only difference in the file
itself is the name: `.json` instead of `.ccshare`. A
[JSON file](./glossary.md#json-file) is a plain-text format that almost any
device can open.

On Linux, the third button reads **Save as…** instead of **Share** and saves the
file through the system dialog, because there is no file share sheet to open. On desktop, **Save** opens a native
file-save dialog. On Android and iOS it
opens the platform's document-save flow so you can choose a user-accessible
location. If the platform reports the destination, the confirmation names it.
The native save flow handles an existing filename rather than silently
overwriting an earlier export. Dismissing the choice dialog or the save dialog
produces no file, clipboard change, or share.

That matters on the receiving end. A `.ccshare` file is Caller's Compendium's
own file type: on a Mac, iPhone, or iPad with the app installed, opening one goes
straight to import review, on Android it is offered under **Open with** (the app
checks the file and tells you if it isn't a share file), and on Windows the
installer registers it, so double-clicking one opens import review. On Linux it
opens the same way once the file type is set up, which the downloads don't do
for you (see [Installing on Linux](./installation.md#install-on-linux)). On any
device the recipient can bring it in with **Settings ▸ General ▸ Import…**. A device without the app may not know what to
do with it at all. A `.json` file is a plain document anywhere, so reach for this
one when you are:

- emailing the program to someone who hasn't installed the app yet;
- putting it somewhere that rejects unfamiliar file types; or
- wanting to open and read the file yourself.

Either file imports back into the app the same way, so nothing is lost by
choosing one over the other.

## Export dances as a spreadsheet (CSV)

To get your dances into Excel, Numbers, LibreOffice or Google Sheets, export
them as a [CSV file](./glossary.md#csv-file): a plain table with one row per
dance.

- **Some dances:** in the Collection, select them (see
  [Change many dances at once](./collection.md#change-many-dances-at-once)),
  then choose **More batch actions** ▸ **Export as CSV**. It exports exactly
  the dances you selected, including any the current search hides.
- **Every dance:** **Settings ▸ General ▸ Backup & restore ▸ Export dances as
  a spreadsheet**.

Then choose **Save** or **Share**, or **Cancel** to export nothing. On Linux
the second button reads **Save as…** instead of **Share** and saves the file
through the system dialog, because there is no file share sheet to open.

Each row holds the dance's title, authors and when it was composed, who
interpreted it and when, type, formation, progression, level, whether it is a
mixed-level dance and a mixer, status, your star **rating** (empty when
unrated), tags, tunes, meter, key, its Barnes reference (English dances),
published sources, hook, calling notes, walkthrough and figures, then one
column for each custom field with **Include in sharing** on. Dates are written
as a year, year-month or year-month-day, as precisely as you know them (for
example `1951`, `1951-03` or `1951-03-14`). The figures are in one cell, one
per line with their phrase labels, worded in your active
[dialect](./dialects.md) exactly as the dance's text export words them.

The file is the same wherever you are: the columns are always separated by
commas, and the text is UTF-8, so accented and Japanese text shows correctly.
The column headings are in the app's language. A title or note that starts
like a spreadsheet formula (with `=`, `+`, `-` or `@`) gets an apostrophe in
front, so the spreadsheet shows it as text instead of running it.

A CSV is a file you might send to anyone, so it follows the same privacy rules
as a shared dance, with one exception: **it includes your star ratings**. See
[What stays private](#what-stays-private). It is not a backup, and the app
cannot restore from it, but you can bring it back in as new or matching dances
with [Bring in your own spreadsheet](./imports.md#bring-in-your-own-spreadsheet).

## Export programs as a spreadsheet (CSV)

To keep a list of your gigs in a spreadsheet, open the **Programs** list's
**More actions** menu (⋮) and choose **Export programs as CSV**. It exports the
programs the list is showing, in its order: archived programs are included only
while **Show archived** is on. Choose **Save** or **Share** (**Save as…** on
Linux), or **Cancel**.

Each row is one program: its title, event date, status, the venue's name,
caller, band, dancer level, **pay** (the amount and its currency), notes, the
number of dances, and the dances in order, one per line, with alternates marked
**Alternate**. Event dates are written as year-month-day (for example
`2026-03-01`), so any spreadsheet reads them as dates, and the pay amount uses
a decimal point. Alternates a program hides are left out, as in its set list.
Like the dances spreadsheet, the file always uses commas and UTF-8 whatever
your region, and a title or note that starts like a formula gets an apostrophe
in front so the spreadsheet shows it as text.

The programs spreadsheet follows the same privacy rules as a shared program,
with one exception: **it includes your pay**, because it is your own record of
your gigs. It leaves out the venue's street address and contact people, the
program's **Perform dialect** and whether you archived it.

If you have turned off **Show pay** in
[Settings ▸ Program ▸ Programs](./settings.md#programs), the spreadsheet has no
pay columns at all, and the export dialog says that pay is hidden in Settings
and so left out. Turn **Show pay** back on to include it.

## Put programs in your calendar

A calendar file (`.ics`) puts your gigs in the calendar app you already use, so
you don't type them in twice. There are two ways to make one:

- **One program:** open it and choose **Export ▸ Add to calendar (.ics)**. It is
  offered for any saved program with an event date, past or upcoming. In the
  builder it appears once the program is saved, and not while it has unsaved
  changes: the file names the program as it is stored.
- **Several programs:** on the Programs list, choose **More actions** (⋮) ▸
  **Export calendar (.ics)**. A checklist shows your upcoming programs — dated
  today or later, not archived — all ticked. Turn on **Show past programs** to
  add earlier ones to the list, unticked, and tick the ones you want. Choose
  **Export** to write them all into one file. A program with no date is not
  listed.

You then choose **Save**, **Share** (**Save as…** on Linux), or **Cancel**, as
for a JSON file. Open the file with your calendar app, or import it there.

Each program becomes one calendar event:

- **Title:** the program's title.
- **When:** the program's date, from its [start time](./programs.md#times) to
  its end time when you've set them, or as an all-day event when it has no
  start time. The times are local to the hall, so your calendar shows them at
  that clock time wherever you are. An end earlier than the start ends the next
  day; with a start and no end, the event has no end time. An end with no
  start makes an all-day event, and its notes give the end time.
- **Where:** the venue's name — a linked venue's name, or the venue you typed.
- **Notes:** the program's status (Draft, Finalized or Performed); the
  beginner lesson and **Arrive by** times, if you've set them; and a linked
  venue's time, if it has one and the program has no start time.

**The venue's street address is yours to include.** If a chosen program is
linked to a venue with an address, the app asks first:

> **Include the venue's address?**

with one tick box, **Include the venue's address**, unticked. Leave it unticked
and the event names the venue only. Tick it and the address follows the name in
the event's location. Dismissing the dialog cancels the export, and nothing is
written. The app does not remember your answer: it asks again next time.
Calendars are often synced to an online account or shared with family or
bandmates, so think about who sees yours.

A calendar file never carries the venue's contact people, your pay, program
notes, the band, the caller, or the set list.

**Exporting again.** A program keeps the same event identity in every calendar
file, from any of your devices, and an edited program is marked as the newer
version. Calendar apps differ in what they do with a file they have imported
before. A program you delete in the app is not removed from a calendar you exported it
to; delete it there yourself.

## Print calling cards

A calling card is one dance on a small card, such as a 3 × 5 index card, to hold
while you call. Turn on **Print calling cards** in Settings ▸ Experimental ▸
Calling cards first; that is also where you choose the card size and lay out what goes on it (see
[Calling cards](./settings.md#calling-cards)).

- **One dance:** open it and choose **Export** ▸ **Print calling card**.
- **A whole program:** open it and choose **Export** ▸ **Print calling cards**.
  You get one card per dance, in program order, each alternate after the dance
  it stands in for. For a layout that prints the `number`, each card carries
  the number the dance has in the set list, and an alternate is marked
  **Alternate**. A dance that appears twice prints once, under its first
  number, and a slot that is only a note (a waltz, the break) prints no card.
  A program that hides its alternates prints no cards for them. The action is unavailable until the
  program has a dance in it.

Your system's print dialog opens on the card's own paper size, and each page
of what it prints is one card — the cards don't change if you pick other paper
in the dialog, so load your printer with cards of that size, or save the PDF.
With **Several cards to a page** on, it's the other way round: pick the paper
you have in the dialog, and the cards are laid out on it as many to a page as
fit, with marks to cut along (see [Calling cards](./settings.md#calling-cards)).
A card that doesn't fit even at half size is cut off at the bottom and marked
with a small grey triangle at the bottom-right corner of its printed area, and
after printing the app says how many were cut off.

Calling cards follow your **active dialect**, like every other export, and the
same [shared dance fields](#choose-which-dance-fields-appear): a field you
turned off there never appears on a card. They never include anything listed
under [What stays private](#what-stays-private), and the program's venue isn't
on them at all, so printing never asks about venue contacts.

## Print the programming matrix

The [programming matrix](./programs.md#check-your-evening-with-the-matrix) has its
own PDF — it is not in the **Export** menu. Open a program's **Matrix** tab and use
**Export or print matrix as PDF**. The button is unavailable while the matrix is
empty.

The matrix PDF is laid out in landscape on the paper you choose in the print
dialog, uses your active dialect for the move column headings, and prints a
legend above the grid. When the grid runs onto more than one page, its heading
row repeats at the top of each page. It is saved under its own name — your
program's title followed by "Programming matrix" — so it never overwrites the
set-list PDF:

| Mark | Meaning |
|---|---|
| `‼` | Shares beats with an adjacent dance (or same phrase as adjacent dance, if you've turned off **Flag exact beat overlap only** in **Settings ▸ Program ▸ Programs**) |
| `★` | Introduced here |
| `▸` | Dance's first figure |
| `✓` | Present |

The matrix covers dances only, so if your program includes notes or breaks the
PDF says how many were left out. Hiding a column on screen is a viewing
convenience and does not narrow the export — every move column prints.

## What stays private

Exports are a privacy boundary, and the app treats them as one. Some things are
left out of everything you share, with the exceptions noted below, and one
thing asks you first.

### Never included

- **An author's email, location, and deceased mark.** These are marked
  private in the editor and are removed from anything you share — see
  [Write & edit dances](./authoring.md#author-and-source-details-are-shared). The
  author's name, website, and notes do travel.

- **Your pay, Perform dialect, archived state and star ratings.** A program
  file leaves out the program's **Pay**, its **Perform dialect** and whether you
  archived it, and every share file or code leaves out your star rating of a
  dance. They stay on your devices, still move with Device Sync, and are kept
  in a [backup](./backup-portability.md). The spreadsheets are the exceptions:
  the [dances spreadsheet (CSV)](#export-dances-as-a-spreadsheet-csv) includes
  your star ratings, and the
  [programs spreadsheet](#export-programs-as-a-spreadsheet-csv) includes your pay,
  unless you have turned off **Show pay**.

- **Your notes on your own figures.** A shared file or code carries each of
  [your own new figures](./authoring.md#your-own-figures) its dances use, but
  not the notes you keep on it. They stay in your Glossary and in a
  [backup](./backup-portability.md).

- **A venue's street address, except in a calendar file you ask for.** The
  address lines, city, state or province, country, and postcode of a saved
  venue record are left out of everything you share, print, or copy — the
  `.ccshare` file, the JSON file, the PDF, the text set list and the programs
  spreadsheet alike. There is
  no tick box for these. The one exception is a
  [calendar file](#put-programs-in-your-calendar), which asks whether to include
  the venue's address and leaves it out unless you tick it. What
  does travel is the venue's **name**, so a recipient still knows which hall you
  mean; the `.ccshare` and JSON files also carry its website, time, schedule,
  price, sponsor, event name, and notes, and the PDF prints all of those except
  the notes.

  Your own copy is untouched — the address is still there in the venue record,
  and a [backup](./backup-portability.md) still contains it. This is only about
  what leaves the device. A program's free-text venue label is different: it is
  shared exactly as you typed it, so leave an address out of it if you don't
  want that sent.

### Included only if you say so

If you export a program as a **PDF**, JSON, or share it as **program + dances**,
and that program is linked to a venue that has contact people recorded, the app
stops and asks before any delivery choice:

> **Include venue contact details in this export?**
> These are personal contact details for the venue. They're left out of this
> export unless you choose to include them.

You get a tick box for each contact detail the venue actually has — up to two
contacts, each with a name, phone, and email. **Every box starts unticked.**

- Tick only what you mean to send, then choose **Continue**.
- Choose **Continue** with nothing ticked and the export goes ahead with all
  contact details removed.
- Choose **Cancel**, or dismiss the dialog, and the whole export is called off —
  nothing is written, copied, printed, or shared.

Whatever you leave unticked is genuinely absent from the file, not hidden inside
it. The venue's other details — its name, website, time, schedule, price, sponsor,
event name, and notes — are not personal contact details, so they are not part
of this choice: the `.ccshare` and JSON files carry all of them, and the PDF
prints all of them except the notes. Its street address is left out; see
**Never included** above.

You will not see this dialog when there is nothing to ask about: a program with no
linked venue, or a venue with no contact people recorded, exports straight away.
Text set lists, calendar files and dance exports never show it either, because
none of them carries contact people in the first place.

### A note on diagnostics

The app's diagnostics log is separate from exports. It never leaves your device
unless you export it yourself, and an exported log has your content removed
unless you choose otherwise. [Settings ▸ Diagnostics](./settings.md#diagnostics)
explains what the log contains and what **Include full detail** changes.

## Exports versus backups

They are different tools for different jobs:

| | Share / export | [Backup](./backup-portability.md) |
|---|---|---|
| **Covers** | One dance or one program; as a spreadsheet, the dances you select or the programs the list shows | Everything: dances, programs, venues, authors, dialects, themes, custom fields, and settings |
| **Meant for** | Handing to another person | Keeping safe, or moving to your own new device |
| **Privacy** | Private contact details stripped or opt-in; your pay, dialect and star ratings left out (the dances spreadsheet keeps the ratings, the programs spreadsheet the pay) | Complete — it is your own data, unredacted |
| **Where** | The **Export** menu on a dance or program; **Export as CSV** for selected dances; **Export programs as CSV** in the Programs list | **Settings ▸ General ▸ Export a backup** |

The **Include in sharing** setting on a custom field applies to share/export
files sent to other people. Your own backup remains complete, including fields
whose sharing setting is turned off.

Because a backup is complete and unredacted, treat a backup file as you would
your own address book — it is for you, not for sharing.

## Where to go next

- **Build the program you are about to share:** [Programs & matrix](./programs.md)
- **Bring someone else's file in:** [Imports & migration](./imports.md)
- **Move everything to a new device:**
  [Backup & portability](./backup-portability.md)
- **Change the words an export uses:** [Dialect](./dialects.md)
- **Record the details that travel with a dance:**
  [Write & edit dances](./authoring.md)

Not sure what a word means? [App terms](./glossary.md) has plain definitions
for every term used across these guides.
