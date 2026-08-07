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

Open a dance and choose **Export**. Three actions:

| Action | What happens |
|---|---|
| **Share dance (text)** | Hands a plain-text dance card to your system's share sheet — email, messages, notes, whatever you have |
| **Copy dance** | Puts the same text on your clipboard, and confirms with "Dance copied to clipboard." |
| **Export / print PDF** | Builds a PDF and opens your system's print dialog |

**Export / print PDF** is a real print path, not a save-to-PDF shortcut: your
operating system's own dialog opens, and from there you can send it to a printer,
save it as a PDF, or cancel. This works on every platform the app runs on,
including Linux.

### Which words a dance export uses

A dance export is written in your **active [dialect](./glossary.md#dialect)** —
the one selected in the app right now. That is what makes exports genuinely
useful: hand a card to a caller and it reads the way you (and they) speak.

Note that this is the *active* dialect, not the dance detail screen's
canonical-terms view. Switching that view changes what you see on screen; it does
not change what an export contains. To export in different words, switch your
active dialect first — see [Dialect](./dialects.md).

The field labels around the content — *Formation*, *Level*, *Figures*, *Calling
notes*, and so on — follow the app's language setting, not your dialect.

## Share a program

Open a program and choose **Export**. Five actions:

| Action | What happens |
|---|---|
| **Share set list (text)** | Hands a plain-text set list to your system's share sheet |
| **Share (program + dances)** | Packages the program *and* its dances into one file to hand to another caller |
| **Copy set list** | Puts the set list text on your clipboard, and confirms with "Set list copied to clipboard." |
| **Export as JSON file** | The same package, named `.json` instead — for a recipient who doesn't have the app, or when you want to read the file yourself |
| **Export / print PDF** | Builds a PDF set list and opens your system's print dialog |

The set list — text and PDF alike — is titles, event details, and slot notes. It
is deliberately *not* a full figure-by-figure breakdown of each dance; that is
what a dance card or [Perform mode](./perform.md) is for. Because a set list
carries no figures, your dialect does not come into it; the labels follow your
app language, as with dance exports.

If something goes wrong the app says so plainly — "Couldn't share this set list",
"Couldn't export this set list" — and nothing is sent.

### Share a program with its dances

**Share (program + dances)** is the one to reach for when you are handing an
evening to another caller. It builds a single self-contained file — a
`.ccshare` file — containing:

- the program itself;
- every dance the program's slots refer to;
- the choreographers credited on those dances; and
- the program's linked [venue](./glossary.md#venue), if it has one.

The file goes to your system's share sheet, so how it travels is up to you —
AirDrop, email, a messaging app, a USB stick.

On the receiving end, opening the file launches Caller's Compendium straight into
its [import review](./imports.md#open-a-shared-program-someone-sent-you) screen,
loaded with the program, its dances, and its venue. Nothing is added until the
recipient confirms. Bringing the same file in twice does not pile up duplicate
*dances* — the importer matches what is already there. Plain `.json` files are
accepted too, so an older bundle still opens.

One exception worth knowing about: **venues do get duplicated.** The importer
recognises a repeated venue by its name *and* its address, and a shared file
deliberately carries no address (see [What stays private](#what-stays-private)).
So importing two programs held at the same hall, or the same program twice,
leaves a separate venue record each time. They are name-only records, nothing is
lost or overwritten, and you can tidy the extras with
[**Settings ▸ Venues ▸ Manage venues**](./settings.md#venues) — but the app
cannot spot them for you.

### The same thing, as a plain `.json` file

**Export as JSON file** builds *exactly* the same content as **Share (program +
dances)** — same program, same dances with their full figures, same
choreographers, same venue, same privacy rules. The only difference is the name
on the file: `.json` instead of `.ccshare`.

That matters on the receiving end. A `.ccshare` file is registered to Caller's
Compendium, so a device that has the app opens it straight into import review —
but a device that doesn't may not know what to do with it at all. A `.json` file
is a plain document anywhere, so reach for this one when you are:

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
column headings, and prints a legend along the bottom:

| Mark | Meaning |
|---|---|
| `‼` | Same phrase as adjacent dance |
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
  private in the editor and are stripped out of anything you share — see
  [Write & edit dances](./authoring.md#author-and-source-details-are-shared). The
  choreographer's name, website, and notes do travel.

- **A venue's street address.** The address line, city, state or province,
  country, and postcode are left out of everything you share, print, or copy —
  the `.ccshare` file, the JSON file, the PDF, and the text set list alike. There
  is no tick box for these: they are simply not sent. What does travel is the
  venue's **name**, plus its website, schedule, price, sponsor, event name, and
  notes, so a recipient still knows which hall you mean.

  Your own copy is untouched — the address is still there in the venue record,
  and a [backup](./backup-portability.md) still contains it. This is only about
  what leaves the device.

### Included only if you say so

If you export a program as a **PDF** or share it as **program + dances**, and that
program is linked to a venue that has contact people recorded, the app stops and
asks:

> **Include venue contact details in this export?**
> These are personal contact details for the venue. They're left out of this
> export unless you choose to include them.

You get a tick box for each contact detail the venue actually has — up to two
contacts, each with a name, phone, and email. **Every box starts unticked.**

- Tick only what you mean to send, then choose **Continue**.
- Choose **Continue** with nothing ticked and the export goes ahead with all
  contact details removed.
- Choose **Cancel**, or dismiss the dialog, and the whole export is called off —
  nothing is written, printed, or shared.

Whatever you leave unticked is genuinely absent from the file, not hidden inside
it. The venue's other details — its name, website, schedule, price, sponsor,
event name, and notes — are not personal contact details and are always
included. Its street address is always left out; see **Never included** above.

You will not see this dialog when there is nothing to ask about: a program with no
linked venue, or a venue with no contact people recorded, exports straight away.
Text set lists and dance exports never show it either, because neither carries
contact people in the first place.

### A note on diagnostics

Crash reports are a separate system with its own privacy rules, and they are
scrubbed by default. [Settings ▸ Diagnostics](./settings.md#diagnostics) explains
what a report contains and what "include full detail" changes.

## Exports versus backups

They are different tools for different jobs:

| | Share / export | [Backup](./backup-portability.md) |
|---|---|---|
| **Covers** | One dance, or one program | Everything: dances, programs, venues, choreographers, dialects, themes, custom fields, and settings |
| **Meant for** | Handing to another person | Keeping safe, or moving to your own new device |
| **Privacy** | Private contact details stripped or opt-in | Complete — it is your own data, unredacted |
| **Where** | The **Export** menu on a dance or program | **Settings** ▸ **General** ▸ **Export a backup** |

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
