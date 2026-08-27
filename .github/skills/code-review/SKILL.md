---
name: code-review
description: >-
  Review a diff in the Callers Compendium repository and report only
  high-confidence bugs, security holes, and logic errors — never style. Use
  this when reviewing a pull request, a staged/unstaged/branch diff, or a
  proposed change, or when reading and answering a Copilot review. Combines a
  general reviewing baseline with the repository-specific hazards that have
  actually caused churn here (documentation drift, missing changelog entries,
  unclassified persisted fields, guard tests that cannot fail, drifted taxonomy
  fixtures, stale review freshness, and unintended issue-closing links).
---

# Code review

This skill reviews a change set. It is **read-only**: it produces findings, it
does not edit code. It is invoked on demand, so — unlike `AGENTS.md` — it may be
detailed; it still points at the reasoning rather than restating it, so the
narrative behind each rule stays in
[`docs/dev/agents/incidents.md`](../../../docs/dev/agents/incidents.md).

## Before you start

1. **Get the actual diff.** Review what changed, not the repository at large:
   `git diff <base>...<head>`, the PR's `get_diff`, or the staged/unstaged tree.
   If there is no change set to compare, stop and say so — there is nothing to
   review.
2. **Establish the base is real.** This is often a shallow clone; if you must
   compare against `main` or older history, `git fetch --unshallow origin` and
   fetch the target ref explicitly before diffing.
3. **Read the smallest thing that answers the question.** Start from the repo
   map, [`docs/dev/README.md`](../../../docs/dev/README.md), and read the changed
   region plus its callers — not whole files. See
   [session-cost.md](../../../docs/dev/agents/session-cost.md).

## What to report, and what to ignore

- **Report only high-confidence findings**: bugs, security vulnerabilities,
  logic errors, data-integrity or privacy regressions, and broken or
  cannot-fail tests. For each, give a severity, a confidence, the file and line,
  and the smallest concrete fix. Emit them in the **output format** below so a
  downstream agent can act on them without re-parsing prose.
- **Do not report style, formatting, naming, or import order.** Those are
  machine-enforced here (`dart format`, `flutter analyze --fatal-infos`) and a
  human finding about them is noise. If the diff would fail a formatter or the
  analyzer, say that in one line and move on.
- **Prefer a gate to an opinion.** If a concern is already covered by a ratchet
  (below), the finding is "this will fail gate X", not a design debate.
- **Say who decided it.** Do not present your inference as a maintainer decision.
  When you assert the code is wrong, state the layer you actually verified, and
  re-derive any figure from source rather than trusting the PR body
  ([`AGENTS.md`](../../../AGENTS.md), "Say who decided it").

## Baseline review pass (applies to any change)

- **Correctness & edge cases.** Off-by-one, null/empty, boundary and error
  paths, concurrency, resource cleanup. Does the change do what its title and
  the linked issue claim?
- **Security.** Untrusted input reaching a sink; injection; SSRF on any
  outbound fetch; secrets committed; auth/permission gaps; unsafe
  deserialization. Online-import fetches must stay behind the `https`-only,
  private-host-blocking guard (`app/lib/src/data/import_io.dart`) — a new fetch
  path that bypasses it is a finding.
- **Tests.** Does the change carry tests, and can they actually fail? See
  "Tests must be shown to fail" below.
- **Blast radius.** Is this one site or a class? A change to a shared widget or a
  duplicated walk is often a defect in three places — grep for siblings.
- **Documentation.** A change to documented behaviour must update the docs in the
  same PR. See "Documentation is part of the change" below.

## Repository-specific hazards (the ones that cause churn here)

Each item below has bitten this repository at least once; the incident is
linked. Treat a diff that trips one as a finding unless the author has visibly
handled it.

### Documentation is part of the change

Documentation drift is this repo's most persistent defect class.

- A comment or doc that asserts runtime behaviour must be **checkable and true**
  after the change. Ask *"what did I just make untrue?"* and grep for the
  **property**, not only for citations of the file edited — the falsified comment
  usually names neither the PR nor the issue
  ([#751](../../../docs/dev/agents/incidents.md#751-the-claim-nobody-would-have-grepped-for)).
- A false claim is usually copy-pasted: grep the claim across the repo. But judge
  each instance in its own context — the same sentence can be true in one file and
  false in another, so a uniform sweep can make a correct comment wrong
  ([#718→#721→#722](../../../docs/dev/agents/incidents.md#718---721---722-a-false-claim-chased-by-citation)).
- **Never accept a hand-edit to a generated file.** Generated files carry a
  `<!-- generated-by: ... -->` marker on line 1 (e.g.
  `docs/dev/data-classification.md`). The fix is to change the source and
  regenerate.
- **Both CHANGELOGs are load-bearing, and release prep will not catch a missing
  entry.** Release prep drains `## [Unreleased]` *as written* — it does not diff
  the tree — so a bullet omitted at review time is omitted from the record
  permanently. This is not hypothetical: `packages/compendium_core` recorded
  almost nothing across `v0.1.0-beta.1`–`.9`, and 268 core commits had to be
  reconstructed from git history long after the fact. Flag a diff that changes
  behaviour without a matching `## [Unreleased]` bullet:
  - `app/CHANGELOG.md` — anything user-visible.
  - `packages/compendium_core/CHANGELOG.md` — any behavioural change under
    `packages/compendium_core/lib/**`. That section is also the sole trigger for
    bumping the core package version at release time, so a missing entry
    silently suppresses the bump as well as the note.
  - **A core entry does not substitute for an app entry.** If a core change has
    a user-visible outcome in the app, require an entry in **both** CHANGELOGs:
    the core entry records the core package version, while the app entry is what
    `tools/release/gen_release_notes.py` publishes. Flag a PR that has only the
    core entry for that outcome.
  - Neither is owed by a pure refactor, a test-only change, or a docs-only
    change. Say which of those applies rather than staying silent, so the
    omission reads as considered rather than forgotten.
- Within one `##` section, a category (`### Added`, `### Fixed`, …) must appear
  **once**. Appending a second `### Fixed` renders as two lists and hides the
  first. `tools/ci/check_changelog_structure.py` gates this and the ordering of
  version headings.
- Re-take any measurement quoted in the PR body after the final rebase
  ([#729](../../../docs/dev/agents/incidents.md#729-a-measurement-that-went-stale-before-merge)).

### Every persisted field must be classified

Any new **database column, settings key, or data-entry surface** must be
classified on all three privacy axes in the *same* PR, or a ratchet fails the
build. The axis most often wrong is the **subject**: venue contacts and
choreographers are `thirdParty` even though the app user typed them — they cannot
consent to a transfer they do not know about. A classification with no `note` is
indistinguishable from a guess. Do not accept a diff that *narrows a ratchet's
detection pattern* to silence a false positive; exclusions go by name, with a
reason. Detail:
[`.github/instructions/privacy-registry.instructions.md`](../../../.github/instructions/privacy-registry.instructions.md),
background:
[the privacy boundary that was prose](../../../docs/dev/agents/incidents.md#the-privacy-boundary-that-was-prose).

### Tests must be shown to fail

- A new guard test must have been **proven red before green**. A test can be
  structurally incapable of failing and still read as rigorous
  ([a guard test that could not fail](../../../docs/dev/agents/incidents.md#a-guard-test-that-could-not-fail)).
- The right question is *"what mutation would this test catch?"*, not "does it
  fail if I undo the work?" For a regression guard the target is a buildable
  revert of the fix; for a guard on new behaviour, mutate out the guard instead.
- A clean `dart test` is **not** a clean gate run. Rendering substitutes rather
  than validates, so a drifted figure fixture passes every test and only
  `check_fixture_validity.dart` (via `python3 tools/preflight.py`) catches it
  ([#747](../../../docs/dev/agents/incidents.md#747-drifted-figure-fixtures-were-invisible-to-dart-test)).
  See
  [`.github/instructions/imports-dialect.instructions.md`](../../../.github/instructions/imports-dialect.instructions.md)
  and [verification.md](../../../docs/dev/agents/verification.md).

### Display versus canonical

A rendering change is cheap. Putting the same value into **canonical text**
changes FTS, dedupe and the derived projection, and means a taxonomy bump, a
migration and a derived rebuild. If a diff moves a value into canonical text
without those, flag it. Changing a `ParamKind`/`choices` pairing, or splitting a
move, can falsify comments that never mention the taxonomy and leave synthetic
taxonomy tests green — grep for the property.

### Storage, logging, and settings ratchets

The gates below (`python3 tools/preflight.py --list`) encode findings that are
mechanical; a diff that violates one is a hard fail, not an opinion:

- **settings-reads** — raw settings reads must filter `deleted_at IS NULL`.
- **debug-print** — no unguarded `debugPrint` reaches a release build.
- **caught-errors** — every caught user-facing error must reach the diagnostic
  log. (Note the redactor preserves `https` URLs, so logging an exception that
  embeds a URL can leak it into exported diagnostics.)
- **schema-gate / version-history** — a schema or taxonomy bump must ship its
  required entries and never ride a PATCH release; the version ledger must gain
  the matching entry.
- **changelog-gate** — the `## [Unreleased]` section must be promoted at release.
- **l10n / user-docs** — ARB parity/coverage; `docs/user` is the single source of
  the in-app bundle.
- **core-flutter-free** — `compendium_core` must not pull in Flutter.

Run `python3 tools/preflight.py` locally to reproduce any of these rather than
waiting for CI ([session-cost.md](../../../docs/dev/agents/session-cost.md)).

### CI and supply chain

GitHub Actions `uses:` references are pinned to full commit SHAs, not floating
tags. Release/Pages changes that touch signature preservation or manifest
publishing are security-relevant — a manifest without its `.sig` makes the
updater fail closed. See
[`.github/instructions/release-tooling.instructions.md`](../../../.github/instructions/release-tooling.instructions.md).

## Reading and answering a Copilot review

When this skill is used to read a review rather than produce one, the mechanics
have their own traps — do not reinvent them:

- Copilot findings can hide in a `<details><summary>Suppressed comments (N)</summary>`
  block in the review **body** while thread state, inline-comment count, and
  unresolved count all read zero. Read the body every round with
  `python3 tools/ci/check_pr_review_gates.py findings <N>`, and remember the
  reviewer login differs by endpoint (`copilot-pull-request-reviewer[bot]` on
  `/reviews`, `Copilot` on `/comments`). Full procedure:
  [code-review.md](../../../docs/dev/agents/code-review.md).
- Batch fixes for a whole round into one push; each push starts another round and
  re-pays the resident prompt.

## Before signing off on a merge

Merge-readiness is a separate, automated gate — do not approximate it by hand:

```sh
python3 tools/ci/check_pr_review_gates.py all <PR> --closes <ISSUE>...
```

It checks review freshness against the reviewer's own latest entry (not
`.[-1].commit_id`, which a stale review passes), unresolved threads with
`totalCount`, CI on the current head, and that the PR closes exactly the issues
named. Beware that a **branch name** or prose containing `close #N` can close an
issue on its own — even a denial like `Does not close #887`. Reasoning:
[merging.md](../../../docs/dev/agents/merging.md).

## Output format

Most work here is done by AI agents, so a review is an **input to another
session**, not just prose for a human. Emit findings in the structure below: it
is skimmable top-to-bottom, and each finding is self-contained so a fixing agent
can act on one without reading the rest.

Rules for the output:

- **Lead with the verdict line** so a dispatcher can route without reading the
  body.
- **One finding per block.** Never merge two defects into one bullet — they get
  fixed in one push and re-reviewed as a pair.
- **Order by severity**, `blocker` first. Within a severity, order by file.
- **Every finding cites `path:line`** against the diff under review, a
  `Confidence`, and a `Fix` that is a concrete change, not "consider revisiting".
- **Name the gate** when a ratchet already covers the finding (e.g.
  `Gate: settings-reads`) — that turns a debate into a reproduction step.
- **Omit empty sections.** If there are no blockers, drop the heading; do not
  write "None".
- If you inspected an area and found nothing, that belongs in `Checked` (one
  line each), not as a finding.

### Template

```markdown
## Review verdict: <BLOCK | APPROVE-WITH-NITS | APPROVE>

<one sentence: what the change does and the single most important finding, or
"no high-confidence findings">

### Blockers

#### B1. <one-line title>
- **Where:** `path/to/file.dart:123`
- **Severity:** blocker
- **Confidence:** high
- **Category:** correctness | security | privacy | data-integrity | test-gap | docs-drift
- **Gate:** <ratchet name, or "none">
- **What:** <what is wrong and the concrete way it fails — the input, the path,
  the result>
- **Fix:** <the specific change to make>

### Non-blocking findings

#### N1. <one-line title>
- **Where:** `path/to/file.dart:88`
- **Severity:** minor
- **Confidence:** medium
- **Category:** <as above>
- **What:** <...>
- **Fix:** <...>

### Checked (no finding)

- <area inspected> — <why it is fine in one clause>

### Verification the author still owes

- [ ] `python3 tools/preflight.py` clean on the current head
- [ ] <new guard test> proven red before green
- [ ] docs updated in this PR for <the behaviour that changed>
```

For a clean review, the whole output collapses to the verdict line, an empty
finding list, and the `Checked` and `Verification` sections — which is the
signal a dispatcher wants, in the place it looks first.
