# Release Notes Guide — First Beta

> _Repo integration: our release pipeline builds the draft GitHub Release body
> from the `## [x.y.z]` section of [`app/CHANGELOG.md`](../../app/CHANGELOG.md)
> (see [releasing.md → Cutting a release](releasing.md#cutting-a-release)). For
> the **first** beta, put these introduction-style notes into the shared
> `## [X.Y.Z]` section **before** tagging. The release gate rejects a missing
> section before it creates a draft; correct the CHANGELOG and retag instead of
> hand-editing a draft. A **Beta / pre-release** banner is prepended
> automatically by `gen_release_notes.py` — don't add your own._

The first beta has no prior tag to diff against, so notes are written as an
"introduction," not a changelog. Goal: tell a first-time tester what this is,
what works, what to try, and what's rough — honestly.

## Structure
1. **Header** — Product name, version, date, and a one-sentence "what it is":
 "Caller's Compendium is a local-first, cross-platform organizer for contra
 dance callers." State clearly: THIS IS A BETA / PRE-RELEASE.

2. **Highlights / What you can do today** — 4–8 bullets of real, working
 capability framed as user value (not internal phases):
 - Build and manage your dance Collection (create, edit, tag, soft-delete/restore).
 - Plan Programs (event date, venue, slots, alternates, status).
 - Import your existing library from JSON, The Caller's Box, ContraDB, and
 Caller's Companion (.USR) — with one-tap undo.
 - Search/filter with dialect-aware terminology.

3. **Platforms & install** — Which OS artifacts are provided; how to install.
 Explicitly warn about unsigned desktop builds and the OS prompts to expect.

4. **Known limitations** — Be candid. Anything unsigned, any source not yet
 supported, any feature intentionally out of beta scope, any data caveat.
 Testers forgive known issues; they don't forgive surprises.

5. **Your data & safety** — One short paragraph: data is stored locally; imports
 are undoable; back up your file before large imports if you want belt-and-suspenders.

6. **How to give feedback** — Exact channel (issue tracker link + what to include:
 platform, version, steps, and — since imports are central — a sanitized sample
 file if the bug is import-related).

7. **License** — AGPL-3.0, with the source link.

## Tone rules
- Written for a caller, not a developer. Avoid phase numbers, PR numbers, internal
 module names.
- Every claim must be something you actually verified in the smoke test.
- Prefer "what it does for you" over "what we built."

## Sourcing the content
- Highlights: pull from the smoke-test list you just ran (only ship claims you
 verified on the tagged build).
- Known limitations: pull from the Roadmap's still-open items + the checklist's
 "unsigned / N/A" boxes.
- Don't derive first-beta notes from the git log — it's too granular and full of
 internal churn. The git log is for RECURRING releases (next guide).
