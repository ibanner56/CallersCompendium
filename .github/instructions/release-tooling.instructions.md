---
applyTo:
  - "packaging/**"
  - "tools/release/**"
  - ".github/workflows/release.yml"
  - ".github/workflows/pages-site.yml"
  - ".github/workflows/pages-sig-gate.yml"
  - ".github/ISSUE_TEMPLATE/**"
  - "app/CHANGELOG.md"
  - "packages/compendium_core/pubspec.yaml"
  - "packages/compendium_core/CHANGELOG.md"
  - "tools/ci/check_changelog_structure.py"
  - "docs/dev/releasing.md"
  - "docs/dev/release-checklist.md"
---

# Release tooling and packaging

These rules load for sessions touching the release path. The step-by-step is
[`docs/dev/releasing.md`](../../docs/dev/releasing.md); the hazards it does not
prevent on its own are in
[`docs/dev/agents/releasing.md`](../../docs/dev/agents/releasing.md).

## Non-negotiables

- **Changelog promotion is manual and is the highest-risk moment.** Contributors
  write under `## [Unreleased]`; nothing promotes it. The notes generator
  resolves the section by SemVer *core*, so a section left over from the previous
  release is found, is valid, and renders happily under the new version's banner.
  `tools/ci/check_changelog_promoted.py` gates the common case; reading the
  rendered draft is the backstop.
- **A passing gate is not evidence the notes are current.** The gate tests that a
  section *exists*, not that it is *fresh*, and no exit code distinguishes those.
- **Re-derive schema and taxonomy versions from source at tag time.** They move
  while a release is being prepared. The Data/Migrations section is where users
  learn what is about to happen to their data.
- **Derive the next tag from the existing tags.** Do not assume the increment.
- **`packages/compendium_core` has its own version, and it is not the tag's.**
  Bump it if and only if `packages/compendium_core/CHANGELOG.md` has entries
  under `## [Unreleased]` — that section as written is the trigger, not a diff
  and not a judgement call — and get the new number by **asking the maintainer**,
  showing them the current one. Nothing resolves that `version:` at build time
  (the app takes the core by workspace `path:`), so no gate and no build failure
  will tell you it is wrong; it is a record, and a bump invented to look tidy is
  a false one. Unlike the app's shared `## [X.Y.Z]` section, each core bump gets
  its own new heading.
- **A core CHANGELOG entry never replaces an app one.** The release-notes
  generator reads `app/CHANGELOG.md` only. If a `packages/compendium_core`
  change has a user-visible effect in the app, record that outcome under the
  app's `## [Unreleased]` as well as recording the core change under the core's.
  The two entries have different audiences: the core entry is the package
  version record; the app entry is the published user-facing release note.
- **Issue-form build hints are static.** GitHub cannot substitute the latest
  release tag when a reporter opens a form. On every app version bump, update
  every explicit build-version literal in `.github/ISSUE_TEMPLATE/*.yml` and
  `*.yaml` to the new bare app `X.Y.Z`; `tools/ci/check_app_version.py` rejects
  a stale, suffixed, or tag-prefixed literal. The release workflow makes that
  pubspec version the tag core, so the hints match the latest release after the
  tag lands.
- **Publish only after the provenance gate is green**, then confirm the channel
  manifest *and* its detached `.sig` are both live and that the signature
  verifies. A manifest without its signature makes the in-app updater fail closed
  and stop offering updates silently.

## Changing the tooling

The supply-chain suites under `tools/release/` (SBOM, release metadata, notes,
Pages publish, signature-file checks) run in `_checks.yml` as a PR gate, because
the release path itself only exercises them after a tag. If you add a tool here,
add its test to that step in the same PR — otherwise it is covered by nothing
until the next release, which is the worst place to find out.

Signature preservation in the Pages publish steps is security-relevant and is
asserted by `tools/release/test_publish_pages_site.py`. Do not weaken it to make
a publish step simpler.

## Concurrency

Guard it mechanically, not by agreement: compare the candidate commit against
the newest release tag, check for an in-progress release run, and let the remote
reject a duplicate tag. Deference between two agents fails silently the moment
one stops existing.
