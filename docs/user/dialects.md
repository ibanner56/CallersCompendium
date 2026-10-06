# Dialect: put the app in your own words

Every caller has their own words. This guide shows you how to make Caller's
Compendium speak yours — choosing the role names and phrasing you use, switching
them in a moment, and doing it all without ever changing the dances you have
saved.

A [dialect](./glossary.md#dialect) is your personal choice of role names and
wording — for example **Larks/Robins** or **Leads/Follows** — applied everywhere
the app shows text. It is *your words, your way*. Dialects are the heart of
Caller's Compendium, so it is worth a few minutes to set yours up the way you
like it.

If you are brand new here, start with the [getting-started guide](./getting-started.md)
first, then come back to make the app sound like you.

## Why callers need dialects

Contra has no single vocabulary. One community calls the roles **Larks** and
**Robins**; another says **Leads** and **Follows**; older cards and some regions
use other words again. The same is true of moves — one caller's "shoulder round"
is another's older term for the very same figure.

That variety is wonderful, but it makes a shared library of dances awkward: if a
[dance](./glossary.md#dance) is written down in one caller's words, everyone
else has to translate it in their head. Dialects solve this. You keep every dance
once, and the app shows it to *you* in *your* words — and to the next caller in
theirs — without anyone rewriting anything.

## The big idea: one library underneath, your words on top

This is the single most important thing to understand, and it makes everything
else safe to experiment with.

Under the hood, every dance in your [collection](./glossary.md#collection) is stored
in one shared, neutral form. Your dialect is a layer of wording laid *on top* of
that stored dance when the app draws it on screen. Choosing or switching a
dialect changes only what you see — it never rewrites the dance itself.

That leads to a distinction worth keeping clear:

- **Changing your dialect changes your *view*.** The role names and wording you
  read on the dance card, in a program, and while calling all update to match. No
  saved dance is touched.
- **Editing a dance changes the *dance*.** That happens only in the dance editor,
  when you deliberately change a [figure](./glossary.md#figure), the notes, or the
  title.

Because the stored form never changes when you switch dialects, three good things
follow on their own:

- **Search always works**, whatever words you prefer. If you search using your
  own role names or an older term, the app matches it against the shared form for
  you, so you find the dance either way.
- **Your data stays portable.** A dance you saved in one dialect opens correctly
  for someone using another, and your [backups](./backup-portability.md) never bake in one set
  of words.
- **Nothing is ever lost in translation.** Switching between dialects — even
  repeatedly, even mid-evening — can't corrupt or reword your saved dances.

![A dance detail view with figures grouped into A1, A2, B1, and B2 sections and the toggle for showing canonical wording visible](images/dance-detail-dialect.png)

*The dance card in the active dialect, with the toggle that switches to shared
canonical wording without changing the saved dance.*

## The dialects that come built in

Caller's Compendium ships with three ready-to-use dialects. You choose one as
your active dialect, and you can add as many of your own as you like.

- **Larks/Robins** — the modern, role-neutral names, and the app's default. If
  you do nothing, this is what you see.
- **Leads/Follows** — another role-neutral choice, ready to pick.
- **Canonical** — the plain, shared wording the app stores underneath (see
  [canonical wording](./glossary.md#canonical-wording)). Handy when you want to
  see a dance in its neutral form (more on this below).

The built-in dialects are deliberately role-neutral. If your community uses other
role names — including traditional gendered ones — you are not stuck: you enter
whatever wording you want yourself, in a custom dialect. The next sections show
how.

## Choose your dialect

1. Open **Settings** and choose the **Dialect** section.
2. In the **Dialects** list, select the one you want to use. The app switches to
   it right away, everywhere.

The built-in dialects carry a **Preset** badge and are read-only, so you can't
change their wording by accident. Your own dialects appear in the same list and
can be edited freely.

![The Settings Dialect section showing the active-dialect picker and controls for managing custom role and move terms](images/settings-dialect.png)

*The Dialect section manages the active dialect and the wording of your own
custom dialects.*

## Make your own dialect

When none of the built-in dialects match your community, make your own. From
**Settings › Dialect**:

- Choose **New dialect** to start from a clean slate. The app asks for a name,
  then opens the dialect's editor.
- Choose **Duplicate from…** to copy an existing dialect (a preset or one of your
  own). The copy is named after the original with "(copy)" added; open its
  **Dialect actions** menu and choose **Edit terms** to change its wording, or
  **Rename** to give it a name of its own.
- To tweak a built-in dialect in one step, choose **Duplicate to customize** from
  its **Dialect actions** menu. This makes an editable copy, opens it in the
  editor, and leaves the original preset untouched.

The editor has a section for each of the following. The **Preview** section shows
sample figures reworded with your dialect and updates as you type, so you can see
the effect immediately. Choose **Save** when you are done.

### Role names

In the **Role terms** section, set the words for the two roles — for example
**Larks** and **Robins**, or your community's own terms. You can enter both the
singular and plural forms; leave the plural blank and the app works it out for
you. This is also where you would enter traditional or gendered role names if
that is what your dancers use.

### Reworded moves

In the **Move substitutions** section, give individual moves the wording you
say out loud. If you always call a move by a particular name, set it here and the
app uses your wording on every dance that contains that move. For moves that come
in left- and right-handed versions, type `%S` where the side belongs — for
example `%S shoulder round` — and the app fills in "left" or "right" for you, so
you don't have to write two versions.

### Move wording templates

To reword the whole sentence around a move, not just its name, add a
**Display template** in the **Move wording templates** section. Type your
sentence and put slots such as `{who}` and `{move}` where the app should fill in
the details; the editor lists the **Available slots** for each move and shows a
preview. A template can be up to 512 characters.

- If a template leaves out one of its available slots, the editor asks you to
  confirm before saving, because that detail won't appear on the dance.
- Some slots hide themselves when they add nothing. For example, a chain's
  `{hand}` is left out when the role already implies it (a robins chain is
  right-hand). Put a `!` in front of the slot, as in `{!hand}`, and it always
  shows. A `!` slot can't show a detail the figure doesn't have, and a few
  move-specific slots (such as `{subject}` or `{balance}`) ignore the `!`.
- If a template can't be read — a slot left unclosed, for example — the editor
  says so, and you need to fix it before you can save the dialect.

A few moves are worded differently depending on how they are danced, so the
editor gives them a separate template for each version:

- **Form a long wave** has one template each for **In only**, **Out only**,
  **In and out**, and **Neither**.
- **Promenade** has one for **Ordinary** and one for **Single file**.

Fill in only the versions you want to reword; any you leave blank keep the
normal wording. A version you do fill in must use every slot the editor lists
for it before you can save, so a dancer's in or out instruction, or a
single-file promenade, never quietly disappears. A **circle** uses one template
for both forms, and the app adds "single file" for you when a circle is danced
that way.

If you made a long-wave or promenade template before the app split them into
versions, it still applies — but only to the ordinary version (**In only** for a
long wave, **Ordinary** for a promenade).

### Dancer wording

In the **Dancer substitutions** section, reword the way the app refers to *who*
is dancing — for example the words for "neighbors" or "the next couple" — to
match how you phrase things from the stage.

### Discouraged terms

Each dialect keeps a list of [discouraged terms](./glossary.md#discouraged-term)
— words you would rather not use. When you type one of these while writing a
dance, the editor flags it (it shows the word struck through) so you can
reconsider, but it never blocks you or changes your text. The list starts with
some common examples and is yours to edit, add to, or clear; **Restore defaults**
brings back the starting list.

Separately, the app updates a fixed set of common older terms whenever it shows
you a dance: "gypsy" and "gyre" read as "shoulder round", and older role words
such as "gents", "ladies", and "ravens" read as your dialect's role names. This
applies to dance details (including formation notes, tunes, and custom-field
values), shorthands, Perform mode, and text and PDF exports. Titles always show
exactly as written. Editing your discouraged-terms list doesn't change which
words are converted.

This conversion is on by default. To see the words exactly as they were saved,
turn off **Auto-convert all discouraged terms** in **Settings › Dialect › Dance
details & shorthands**. Either way, it only changes what you see: your saved
dances, notes, search, shared files, and backups are never altered.

> **The app watches for clashes.** If two different things would end up with the
> exact same wording, the editor warns you right away, because that would make it
> impossible to tell them apart later. Adjust one of the words and the warning
> clears. You can't save a dialect with an unresolved clash.

## Switch dialect on the fly

You don't have to visit Settings every time. On the dance card and in
[Perform mode](./glossary.md#perform-mode) there is a **Switch dialect** control
— a group-of-people icon — that changes your active dialect instantly. On a
narrow screen the dance card lists your dialects in its **More actions** menu
instead.

Choose it, pick a dialect from the list, and the whole app switches to those
words at once. This is built for real evenings: guest-calling for a community that
uses different role names, or switching wording between gigs, takes a moment and
leaves every saved dance exactly as it was.

Remember the distinction: **Switch dialect** changes *how dances read for you*, not
the dances themselves. Switch as often as you like.

## Give a program its own dialect

If you already know tonight's hall uses a particular dialect, you can set it on
the program ahead of time instead of switching on the night. Open the program's
details and choose a dialect under **Perform dialect**; choose **Use app
dialect** to clear it again. The list only offers the dialects you have, so there
is nothing to type.

- The program's dialect applies only in that program's
  [Perform mode](./glossary.md#perform-mode). The program editor, the summary,
  and every export keep reading in your active dialect, and your active dialect
  itself never changes. Other programs are unaffected.
- You can still use **Switch dialect** in Perform. While the program has its own
  dialect, that switch affects the rest of this time in Perform only; the
  program's dialect is back the next time you open it.
- A program remembers the dialect by its **name**. If you rename or delete that
  dialect, the program quietly goes back to using your active dialect in Perform,
  and the editor shows the old name as **unavailable** so you can see what
  happened. Pick a dialect again to reconnect it.

## Peek at the canonical wording

Sometimes you want to see a dance in the plain, shared wording — to compare notes
with another caller, or to double-check what a figure really is underneath your
own phrasing.

On the dance card, the **Canonical** switch (read out by screen readers as
**Show canonical terms**) flips the current view between your dialect and the
shared canonical wording. It appears only after you turn on **Canonical figure
text** in **Settings › Dialect › Dance details & shorthands**; while that setting
is off, dance details stay in your active dialect. The switch changes only what
is on screen right then — it doesn't change your active dialect or touch the
saved dance. When your active dialect is already **Canonical**, the switch isn't
shown, because there would be nothing to switch between.

Perform mode has its own **Show canonical terms** control, which doesn't depend
on the **Canonical figure text** setting. You can call from your own words and,
if a dancer or another caller asks, flip to the canonical wording for a moment
without losing your place. See the [Perform mode guide](./perform.md) for the
full calling view.

## Set your defaults

These settings decide what you see before you touch anything:

- **Your active dialect** (in **Settings › Dialect**) is the wording every screen
  uses by default — except [Perform mode](./glossary.md#perform-mode) for a
  program that has its own dialect (see
  [Give a program its own dialect](#give-a-program-its-own-dialect)).

The rest are in **Settings › Dialect › Dance details & shorthands**:

- **Canonical figure text** controls whether dance details can show canonical
  wording at all. It is off by default.
- **Auto-convert all discouraged terms** controls whether common older terms are
  shown in current wording, as described under
  [Discouraged terms](#discouraged-terms). It is on by default.
- **Open dance details in canonical terms** decides whether a dance opens showing
  your dialect or the canonical wording. It takes effect only while **Canonical
  figure text** is on; while that is off, dances open in your active dialect and
  the app remembers this choice for later.

If an earlier version of the app was set to open dances in canonical terms, that
choice was reset to your active dialect when **Canonical figure text** arrived.
To get it back, turn on **Canonical figure text**, then **Open dance details in
canonical terms**.

For a full tour of everything under Settings, see the
[Settings guide](./settings.md).

## Practical scenarios

**Guest-calling for another community.** You usually call Larks/Robins, but
tonight's crowd says Leads/Follows. Before you start, open **Switch dialect** on the
dance card or in Perform and choose **Leads/Follows**. Every dance now reads in
that community's words. Afterwards, switch back — none of your dances changed.

**Your community's own words.** Your dancers use role names that aren't built in.
Make a custom dialect once (**Settings › Dialect › New dialect**), enter your role
names and any moves you say differently, and set it active. From then on the whole
app speaks your language.

**Bringing in dances written in older words.** When you [import](./imports.md)
dances, they may use terms that have since fallen out of use. The app
understands the common older words and matches them to the shared form, so those
dances still appear in your dialect and still turn up in search — no clean-up
required.

**Comparing a figure with another caller.** Mid-conversation, flip the
**Canonical** switch on the dance card to read the dance in neutral wording you
both recognise, then flip back to your own.

## Good to know

- **Printing and sharing.** Text you copy or share, and a PDF you print, are
  written in your **active** dialect, so what you hand someone matches how you
  speak. The on-screen **Canonical** switch changes only what you are looking at
  — it doesn't change what an export contains. To export in different words,
  switch your active dialect first. A dance file you send to another Caller's
  Compendium user carries the dance itself, so it opens in *their* dialect. See
  [Share, print & export](./sharing.md#which-words-a-dance-export-uses).
- **Screen readers.** The app reads dances aloud in your dialect too — your own
  words are the clearest ones for you — so the spoken view and the visible view
  stay in step. See the [accessibility guide](./accessibility.md) for more.
- **It stays on your device.** Your dialects are stored on your device, and
  there is no account. If you turn on the experimental
  [Device Sync](./settings.md#device-sync), your own dialects and your choice of
  active dialect sync to your other connected devices along with your library.

## Where to go next

- [Getting started](./getting-started.md) — find your way around the app.
- [Perform mode](./perform.md) — call live, with the dialect and canonical
  controls close at hand.
- [Settings](./settings.md) — where the dialect manager and display defaults live.
- [Collection & search](./collection.md) — searching works whatever dialect you
  use.
- [Imports & migration](./imports.md) — bring in dances written in other words.
- [Share, print & export](./sharing.md) — which words leave the app with a dance.
- [Glossary](./glossary.md) — plain definitions of the terms used here.
