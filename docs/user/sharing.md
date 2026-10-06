# Share, print & export

A dance or a program is only half useful while it lives on one device. This guide
covers every way to get your work *out* of Caller's Compendium — as text you can
paste into an email, as a PDF you can print, or as a file you can hand to another
caller — and, just as importantly, what the app deliberately leaves behind.

> **Finding your way around these words.** On-screen buttons and screens are
> written in **bold** — like **Export**, **Copy set list**, and **Continue**. The
> first time a dance term appears it links to the [Glossary](./glossary.md), so
> you can get a plain-language definition without losing your place.

Looking for a copy of *everything* — your whole collection, your settings, your
dialects — to move to a new device? That is a different job, and
[Backup & portability](./backup-portability.md) covers it.

## Share a dance

Open a dance and choose **Export**. (On a narrow screen, the same actions are in
the dance's **More actions** menu.) There are five actions:

| Action | What happens |
|---|---|
| **Share dance (text)** | Hands a plain-text dance card to your system's share sheet — email, messages, notes, whatever you have |
| **Share dance file** | Packages the dance, with the details that go with it, into a `.ccshare` file for another Caller's Compendium user |
| **Copy dance** | Puts the same text on your clipboard, and confirms with "Dance copied to clipboard." |
| **Export dance as JSON** | Builds the same file as **Share dance file**, named `.json` instead, then offers **Save**, **Copy raw JSON**, **Share**, or **Cancel** |
| **Export / print PDF** | Builds a PDF and opens your system's print dialog |

**Export / print PDF** is a real print path, not a save-to-PDF shortcut: your
operating system's own dialog opens, and from there you can send it to a printer,
save it as a PDF, or cancel. This works on every platform the app runs on,
including Linux.

A PDF can print Japanese text (hiragana, katakana and the everyday kanji). Rarer
kanji, Chinese-only characters and Korean may still show as empty boxes.

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

The field labels around the content — *Formation*, *Level*, *Figures*, *Calling
notes*, and so on — follow the app's language setting, not your dialect.

A dance *file* (**Share dance file** or **Export dance as JSON**) is different: it
carries the dance itself rather than your wording of it, so it opens in the
recipient's own dialect.

### Share a dance file

**Share dance file** and **Export dance as JSON** build the same file: the dance,
its credited choreographers, its tags and difficulty level, the published
sources it cites, and its [custom fields](./glossary.md#custom-field). The only
difference is the name — `.ccshare` or `.json`. Choreographers' private details
are removed (see [What stays private](#what-stays-private)), and custom fields
with **Include in sharing** turned off are left out.

On Linux the system has no file share sheet, so **Share dance file** is
labelled **Save dance file…** and saves the file through the system dialog
instead; choosing **Share** in the JSON dialog does the same.

Opening either file in Caller's Compendium goes through import review before
anything is added. Tags, sources, and custom fields the recipient already has are
reused, and their own edits are never overwritten. If the file has a custom field
with the same key as one of theirs but set up differently, the import is refused
rather than changing what their field means. After a successful import, the
confirmation message offers **Undo**.

## Share a program

Open a program and choose **Export**. Five actions:

| Action | What happens |
|---|---|
| **Share set list (text)** | Hands a plain-text set list to your system's share sheet |
| **Share (program + dances)** | Packages the program *and* its dances into one file to hand to another caller |
| **Copy set list** | Puts the set list text on your clipboard, and confirms with "Set list copied to clipboard." |
| **Export as JSON file** | Opens a choice to **Save**, **Copy raw JSON**, **Share**, or **Cancel**. The same package is named `.json` for a recipient who doesn't have the app, or when you want to read the file yourself |
| **Export / print PDF** | Builds a PDF set list and opens your system's print dialog |

The set list — text and PDF alike — is titles, event details, and slot notes by
default, with each dance's author shown next to its title if you have authors
turned on (see [Choose which dance fields
appear](#choose-which-dance-fields-appear) below). When you choose **Share set
list (text)**, **Copy set list**, or **Export / print PDF**, the app asks
**Include figures?** with two choices:

- **Set list only** — titles, event details, slot notes, and the author
  (the default). None of your other selected dance fields appear here —
  formation, level, mixer, status, phrase, calling notes, walkthrough, and
  tunes only ever show up on the richer per-dance card described next.
- **Set list and figures** — appends a full card for each dance after the set
  list, showing every dance field you've selected alongside its figures. The
  cards use your app language for field labels; the figure text uses your
  active dialect. Alternate dances are marked "Alternate".

If none of the program's dances have any structured figures, the question is
skipped and the export proceeds as set-list-only automatically.

Cancelling the dialog (or dismissing it) stops the export — nothing is shared or
copied.

If something goes wrong the app says so plainly — "Couldn't share this set list",
"Couldn't export this set list" — and nothing is sent.

### Choose which dance fields appear

Settings › Defaults has a checklist for every non-figures dance field a dance
card can show: author, formation, level, mixer, status, phrase, calling
notes, walkthrough, and suggested tunes. Author is on by default, matching
every export before this setting existed; suggested tunes is off by default,
since no export showed them before.

Turning a field off removes it everywhere it would otherwise appear — but
**author is the only one of these fields the plain numbered set-list line
ever shows.** The rest only appear on the richer per-dance card: the "Set
list and figures" appendix, a single dance's own **Share dance (text)**/
**Copy dance** card, or any PDF. Figures are not part of this list; they stay
controlled by the **Include figures?** choice above.

### Share a program with its dances

**Share (program + dances)** is the one to reach for when you are handing an
evening to another caller. It builds a single self-contained file — a
`.ccshare` file — containing:

- the program itself;
- every dance the program's slots refer to;
- the choreographers credited on those dances;
- the tags, published sources, and [custom fields](./glossary.md#custom-field)
  those dances use, so the recipient can import them completely; and
- the program's linked [venue](./glossary.md#venue), if it has one.

On Linux the system has no file share sheet, so this action is labelled **Save
program file…** and saves the file through the system dialog instead.

Custom fields with **Include in sharing** turned off are left out, values
included, exactly as they are for a single dance. If a definition one of the
dances depends on cannot be found, the share stops with an error instead of
sending the file.

The file goes to your system's share sheet, so how it travels is up to you —
AirDrop, email, a messaging app, a USB stick.

On the receiving end, opening the file takes the recipient to Caller's
Compendium's [import review](./imports.md#open-a-shared-program-someone-sent-you)
screen, loaded with the program, its dances, and its venue. Nothing is added
until the recipient confirms. Bringing the same file in twice does not pile up
duplicate *dances* — the importer matches what is already there.

Venues are matched more narrowly. Importing the same program again, or another
program from the same sender that uses the same venue, reuses the venue the first
import added. But a shared file carries no address (see
[What stays private](#what-stays-private)), so the app can't tell that a shared
venue is a hall you already have in your own records, or that venues from two
different callers are the same place. In those cases you get a separate,
name-only venue record. Nothing is lost or overwritten, and you can tidy the
extras in [**Settings › Program › Venues › Manage venues**](./settings.md#venues).

### The same thing, as a plain `.json` file

**Export as JSON file** builds exactly the same content as **Share (program +
dances)** — same program, same dances with their full figures, same
choreographers, same venue, same privacy rules. You then choose **Save**,
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
straight to import review, and on any device the recipient can bring it in with
**Settings › General › Import…**. A device without the app may not know what to
do with it at all. A `.json` file is a plain document anywhere, so reach for this
one when you are:

- emailing the program to someone who hasn't installed the app yet;
- putting it somewhere that rejects unfamiliar file types; or
- wanting to open and read the file yourself.

Either file imports back into the app the same way, so nothing is lost by
choosing one over the other.

## Print the programming matrix

The [programming matrix](./programs.md#check-your-evening-with-the-matrix) has its
own PDF — it is not in the **Export** menu. Open a program's **Matrix** tab and use
**Export or print matrix as PDF**. The button is unavailable while the matrix is
empty.

The matrix PDF is laid out in landscape, uses your active dialect for the move
column headings, and prints a legend above the grid:

| Mark | Meaning |
|---|---|
| `‼` | Shares beats with an adjacent dance (or same phrase as adjacent dance, if you've turned off **Flag exact beat overlap only** in **Settings › Program › Programs**) |
| `★` | Introduced here |
| `▸` | Dance's first figure |
| `✓` | Present |

The matrix covers dances only, so if your program includes notes or breaks the
PDF says how many were left out. Hiding a column on screen is a viewing
convenience and does not narrow the export — every move column prints.

## What stays private

Exports are a privacy boundary, and the app treats them as one. Some things never
leave, and one thing asks you first.

### Never included

- **A choreographer's email, location, and deceased mark.** These are marked
  private in the editor and are removed from anything you share — see
  [Write & edit dances](./authoring.md#author-and-source-details-are-shared). The
  choreographer's name, website, and notes do travel.

- **A venue's street address.** The address lines, city, state or province,
  country, and postcode of a saved venue record are left out of everything you
  share, print, or copy — the `.ccshare` file, the JSON file, the PDF, and the
  text set list alike. There is no tick box for these: they are never sent. What
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
prints all of them except the notes. Its street address is always left out; see
**Never included** above.

You will not see this dialog when there is nothing to ask about: a program with no
linked venue, or a venue with no contact people recorded, exports straight away.
Text set lists and dance exports never show it either, because neither carries
contact people in the first place.

### A note on diagnostics

The app's diagnostics log is separate from exports. It never leaves your device
unless you export it yourself, and an exported log has your content removed
unless you choose otherwise. [Settings › Diagnostics](./settings.md#diagnostics)
explains what the log contains and what **Include full detail** changes.

## Exports versus backups

They are different tools for different jobs:

| | Share / export | [Backup](./backup-portability.md) |
|---|---|---|
| **Covers** | One dance, or one program | Everything: dances, programs, venues, choreographers, dialects, themes, custom fields, and settings |
| **Meant for** | Handing to another person | Keeping safe, or moving to your own new device |
| **Privacy** | Private contact details stripped or opt-in | Complete — it is your own data, unredacted |
| **Where** | The **Export** menu on a dance or program | **Settings › General › Export a backup** |

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

Not sure what a word means? The [Glossary](./glossary.md) has plain definitions
for every term used across these guides.
