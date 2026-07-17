# Release Notes Guide — Recurring Beta & Stable Releases

> _Repo integration: keep the running [`app/CHANGELOG.md`](../../app/CHANGELOG.md)
> `## [Unreleased]` section current as PRs merge; at tag time rename it to the
> version + date. The pipeline renders that section as the release body (see
> [releasing.md → CHANGELOG-driven release notes](releasing.md#changelog-driven-release-notes)).
> For beta/rc tags the **Beta / pre-release** banner is added automatically._

From the second tag onward, notes ARE a changelog: "what changed since the last
release," curated for users. This applies to later betas and future stable
releases alike (stable adds a couple of extra sections, noted below).

## Step 1 — Establish the range
- Identify the previous release tag (e.g. v0.1.0-beta.1).
- Get the raw change set:
 git log --no-merges <prev-tag>..<new-commit> --pretty="%s"
 and the squash-merged PRs in that range (PR titles are usually the best
 human-level unit since we ship atomic, reviewed PRs).

## Step 2 — Curate into user-facing categories
Drop pure-internal churn (refactors, test-only, CI, doc-only) from the headline
list — or collect it under a terse "Internal" footer. Group the rest as:
- **Added** — new capabilities.
- **Changed** — behavior changes users will notice.
- **Fixed** — bugs fixed (describe the user-visible symptom, not the code).
- **Deprecated / Removed** — anything taken away.
- **Data / Migrations** — ANY schema change gets called out explicitly, with a
 one-line "what happens to your existing data on upgrade" (it should be
 automatic + lossless; say so). This section is mandatory whenever
 kCompendiumSchemaVersion moved.
- **Known issues** — carried-forward + newly discovered limitations.

Rewrite each kept item from the user's POV. Example transform:
 PR "Dedupe Caller's Companion programs on re-import via Program provenance"
 → "Re-importing a Caller's Companion file now updates the programs you already
 imported instead of creating duplicates."

## Step 3 — Call out upgrade impact (Gate for the notes)
- Schema/migration: state the version move and that upgrade is automatic; note if
 a downgrade is unsupported.
- Import/format changes: if an importer's behavior changed, tell users what to
 expect on re-import.
- Any change to on-disk format, file locations, or settings.

## Step 4 — Compatibility & platforms
- New/changed platform support or signing status changes since last release.
- Minimum OS or dependency changes, if any.

## Step 5 — Header & framing
- Version, date, and a 1–2 line theme ("This beta focuses on import fidelity and
 program planning").
- For betas: keep the "pre-release / expect rough edges + feedback channel" banner.

## EXTRA sections for STABLE (1.0.0+) releases
- **Upgrade guide** — explicit steps if anything is non-automatic; back-up advice.
- **Breaking changes** — a dedicated, prominent section (semver: only in MAJOR).
 For a local-first app, treat "changes that alter or risk user data" as breaking
 even if the code API didn't break.
- **Deprecation timeline** — when removed things were announced / final removal.
- **Full changelog link** — link the compare view (<prev-tag>...<new-tag>).
- Drop the beta/pre-release banner; state stability expectations plainly.

## Consistency rules (all recurring releases)
- Keep a persistent CHANGELOG in "Keep a Changelog" style with an "Unreleased"
 section you append to as PRs merge — then releasing is just renaming
 "Unreleased" to the version + date. This avoids reconstructing everything from
 git at tag time.
- Follow semver: beta = pre-release identifiers on 0.x; first stable = 1.0.0.
- Never claim a fix/feature you didn't verify on the tagged build.
- Schema/data section is never omitted when the schema moved — data trust is the
 whole point of a local-first app.
