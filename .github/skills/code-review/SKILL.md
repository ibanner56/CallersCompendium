---
name: code-review
description: >-
  Review a diff in the Callers Compendium repository and report bugs, security
  holes, and logic errors — never style — as established findings, plus a
  separate tier of suspected defects whose failure path hinges on one fact the
  reviewer could not read from the code. Use this when reviewing a pull request,
  a staged/unstaged/branch diff, or a proposed change, or when reading and
  answering a Copilot or Claude review. Combines a general reviewing baseline
  (including the Dart/Flutter async, Drift data-layer and sync hazards) with the
  repository-specific hazards that have actually caused churn here
  (documentation drift, missing changelog entries, unclassified persisted
  fields, guard tests that cannot fail, drifted taxonomy fixtures, stale review
  freshness, and unintended issue-closing links).
---

# Code review

This skill reviews a change set. It is **read-only**: it produces findings, it
does not edit code. It is invoked on demand, so — unlike `AGENTS.md` — it may be
detailed; it still points at the reasoning rather than restating it, so the
narrative behind each rule stays in
[`docs/dev/agents/incidents.md`](../../../docs/dev/agents/incidents.md).

## Before you start

Steps and commands below assume the tools a local session has. A CI reviewer
limited to reading files, `gh pr diff` and `gh pr view` uses the equivalents
available to it (the PR description's linked text where an issue cannot be
read), and does not need to run `git` or `tools/preflight.py`. The checks only
an author can perform (a test proven red before green, a measurement re-taken
after the final rebase) are flagged when the diff or PR body shows they were
skipped, not assumed missing.

1. **Get the actual diff.** Review what changed, not the repository at large:
   `git diff <base>...<head>`, the PR's `get_diff`, or the staged/unstaged tree.
   If there is no change set to compare, stop and say so — there is nothing to
   review.
2. **Establish the base is real.** This is often a shallow clone; if you must
   compare against `main` or older history, `git fetch --unshallow origin` and
   fetch the target ref explicitly before diffing.
3. **Read the claim the change is judged against.** The PR description and the
   issues it closes or links (their acceptance criteria, not just their
   titles). "Does the change do what it says?" cannot be answered from the diff
   alone.
4. **Read enough to establish each finding, and no more.** Start from the repo
   map, [`docs/dev/README.md`](../../../docs/dev/README.md). A review is not a
   working session: read every changed function **in full** (not only its
   changed lines), and find its callers, before judging it. A finding about a
   function you saw only as diff hunks is a guess. For everything the change
   does not touch, the budget rule in
   [session-cost.md](../../../docs/dev/agents/session-cost.md) still applies.
5. **Account for earlier rounds, if there were any.** Each push is a new round
   and a reviewer that starts cold repeats itself or forgets what it raised.
   When earlier reviews, replies, or a since-last-round diff are available:
   - do not re-raise a finding the current head fixed;
   - if a finding is still present, raise it again as a finding — do not let it
     lapse because it was raised before;
   - if an author or maintainer disputed a finding, re-judge it on the merits
     and say what the reply missed, or drop it;
   - scrutinise the lines changed since the last reviewed commit hardest. A fix
     is new, unreviewed code, and the usual regressions here are a fix that
     introduces a defect or falsifies a comment. Still review the whole PR.

## What to report, and what to ignore

- **Report two tiers, never a bare hunch.** For each, give the file and line,
  and the smallest concrete fix, in the **output format** below so a downstream
  agent can act on them without re-parsing prose.
  - **Finding** — bugs, security vulnerabilities, logic errors, data-integrity or
    privacy regressions, and broken or cannot-fail tests, where you can state
    the input, the path through the code, and the wrong result. Findings decide
    the verdict.
  - **Suspected** — a concrete failure path that hinges on **one fact you could
    not establish from the code** (a value set somewhere you cannot read, a
    platform behaviour, data in a user's existing database). State it as a
    condition the author can settle in one look: *"Fails if X; X holds when Y
    (`path:line`)"*. Do not write that you could not run, test, or check
    something — name the condition. A Suspected item can keep a round from
    being a clean `APPROVE` but never makes it `BLOCK`, and a failure path you cannot name (an input and a result) is not a
    Suspected item: leave it out.
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
  - For each changed function, try the inputs that usually break it (empty, null,
    one element, a duplicate, the largest realistic value, a value in the old
    format). If one breaks it, name it in the finding; if none does, there is
    nothing to report.
  - Read what the diff **removed**, not only what it added: a deleted guard, a
    deleted early return, a deleted test or assertion, a deleted line of
    documentation. Ask what each one was protecting.
- **Dart/Flutter async and lifecycle.** `BuildContext` use after an `await` is
  already an analyzer error here (`use_build_context_synchronously`), so look
  only for what the lint cannot see: a context stored in a field or captured by
  a callback, `setState` after dispose; a notifier, controller, stream
  subscription, timer or listener created and never disposed or cancelled;
  `notifyListeners` after dispose; an unawaited future whose failure is lost; two
  overlapping calls (double tap, rapid re-query) where a slower, older result
  overwrites a newer one; I/O or a controller created inside `build`.
- **Data layer (Drift/SQLite).** A schema change needs its migration, version
  bump and migration test — gate `schema-gate` covers the bump, not whether the
  migration is right for a database in the old shape. Multi-statement writes
  belong in one transaction. Check what an existing row looks like after the
  change (nullable or newly required columns, rows written by an older app
  version). A query inside a loop is a finding only with a realistic row count or a
  measurable cost; otherwise at most Suspected.
- **Sync and merge.** Anything that changes what is written, tombstoned,
  compared or merged must be judged from the *other* device's side: an older app
  version, a partially synced state, a conflict resolved the opposite way. A
  change that is correct locally and wrong after a merge is a data-integrity
  finding. Gates `sync-invariants` and `join-columns` cover the mechanical part
  (soft-delete joins, sync writes, normalizers, join columns).
- **User-facing surface.** New user-visible strings go through the ARB files, not
  literals; new interactive elements carry semantics and are keyboard operable;
  nothing is conveyed by colour alone (the checklist in
  [`PULL_REQUEST_TEMPLATE.md`](../../PULL_REQUEST_TEMPLATE.md)). Gates cover ARB
  parity, not whether a string was routed through them.
- **Error handling.** A broad `catch` that swallows, a failure reported to the
  user as success, an error path that leaves state half-applied.
- **Security.** Untrusted input reaching a sink; injection; SSRF on any
  outbound fetch; secrets committed; auth/permission gaps; unsafe
  deserialization. Online-import fetches must stay behind the `https`-only,
  private-host-blocking guard (`app/lib/src/data/import_io.dart`) — a new fetch
  path that bypasses it is a finding.
- **Tests.** Does the change carry tests, and can they actually fail? See
  "Tests must be shown to fail" below. A test whose assertion was loosened,
  deleted, or moved to match new behaviour needs the same scrutiny as new code.
- **Blast radius.** Is this one site or a class? A change to a shared widget or a
  duplicated walk is often a defect in three places — grep for siblings.
- **Documentation.** A change to documented behaviour must update the docs in the
  same PR. See "Documentation is part of the change" below.

## Try to refute your own findings

A first pass over a diff produces candidates, not findings. Before anything is
reported:

1. For each candidate, look for the reason it is wrong: a guard in a caller, a
   check upstream, a test that already pins the behaviour, a type that rules the
   input out, a gate that already fails on it. Read the callers; do not reason
   from the hunk alone.
2. If you refute it, drop it. If a single fact decides it and you cannot read
   that fact, move it to **Suspected** with that fact as the condition. If it
   survives, it is a **Finding** — and say in `What` which refutation you tried.
3. Re-read the diff once more for what you did not look at the first time:
   deletions, renames (callers of the old name), changes to a shared helper or
   widget (grep for siblings), and every file you have not yet written a
   Coverage line for.

A finding you could not state as *input, path, result* has not survived.

## Repository-specific hazards (the ones that cause churn here)

Each item below has bitten this repository at least once; the incident is
linked. A diff that trips one is a finding when you can state the input, path
and result, unless the author has visibly handled it; if the hazard is plausible
but that is not established, it is Suspected.

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
- **Changelog fragments are load-bearing, and release prep will not catch a
  missing entry.** Release prep compiles `changelog.d/*.json` — it does not diff
  the tree — so a record omitted at review time is omitted permanently. This is
  not hypothetical: `packages/compendium_core` recorded
  almost nothing across `v0.1.0-beta.1`–`.9`, and 268 core commits had to be
  reconstructed from git history long after the fact. Flag a diff that changes
  behaviour without a matching fragment:
  - `app` — anything user-visible.
  - `core` — any behavioural change under
    `packages/compendium_core/lib/**`. Core fragments are the sole trigger for
    considering a core package bump at release time, so a missing entry
    silently suppresses the bump as well as the note.
  - **A core entry does not substitute for an app entry.** If a core change has
    a user-visible outcome in the app, require an entry in         both audience objects and `user_visible: true`:
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
- **preference-encode** — a live preference's settings handler must persist
  exactly its `PreferenceNotifier` descriptor's `encode` of the value it assigned.
- **debug-print** — no unguarded `debugPrint` reaches a release build.
- **stale-comment-refs** — a comment's `[Type.member]` reference or backticked
  identifier must name a symbol that exists; the unresolved count must equal
  `tools/ci/stale_comment_refs_ceiling.json` (above it fails; below it fails
  until the ceiling is lowered in the same change).
- **caught-errors** — every caught user-facing error must reach the diagnostic
  log. (Note the redactor preserves `https` URLs, so logging an exception that
  embeds a URL can leak it into exported diagnostics.)
- **schema-gate / version-history** — a schema or taxonomy bump must ship its
  required entries and never ride a PATCH release; the version ledger must gain
  the matching entry.
- **changelog-gate** — pending fragments must be compiled and consumed at release.
- **l10n / user-docs** — ARB parity/coverage; `docs/user` is the single source of
  the in-app bundle.
- **sync-invariants / join-columns** — soft-delete joins, sync writes and
  normalizers; repository joins onto `dances` carry their columns or a marker.
- **core-flutter-free** — `compendium_core` must not pull in Flutter.

Run `python3 tools/preflight.py` locally to reproduce any of these rather than
waiting for CI ([session-cost.md](../../../docs/dev/agents/session-cost.md)).

### CI and supply chain

GitHub Actions `uses:` references are pinned to full commit SHAs, not floating
tags. Release/Pages changes that touch signature preservation or manifest
publishing are security-relevant — a manifest without its `.sig` makes the
updater fail closed. See
[`.github/instructions/release-tooling.instructions.md`](../../../.github/instructions/release-tooling.instructions.md).

## Reading and answering a Copilot or Claude review

When this skill is used to read a review rather than produce one, the mechanics
have their own traps — do not reinvent them:

- Copilot findings can hide in a `<details><summary>Suppressed comments (N)</summary>`
  block in the review **body** while thread state, inline-comment count, and
  unresolved count all read zero. Read the body every round with
  `python3 tools/ci/check_pr_review_gates.py findings <N>`, and remember the
  reviewer login differs by endpoint (`copilot-pull-request-reviewer[bot]` on
  `/reviews`, `Copilot` on `/comments`). Full procedure:
  [code-review.md](../../../docs/dev/agents/code-review.md).
- A Claude review (the opt-in `review: claude` label) is this skill's own output
  format, posted as one review per round by `claude-code-review.yml`. Read and
  gate it with `--reviewer claude`; the script defaults to Copilot.
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
session**, not just prose for a human. The opt-in Claude review workflow
(`.github/workflows/claude-code-review.yml`) posts this template as its review
body, so a change here changes what that workflow posts. Emit findings in the structure below: it
is skimmable top-to-bottom, and each finding is self-contained so a fixing agent
can act on one without reading the rest.

Rules for the output:

- **Lead with the verdict line** so a dispatcher can route without reading the
  body. The verdict has a definition, and `APPROVE` has to be earned:
  - `BLOCK` — at least one blocker. A **blocker** is a defect that must not
    merge: data loss or corruption, a security or privacy regression, a
    behaviour regression, a change that fails a gate, or a guard test that
    cannot fail. Everything else established is `minor`.
  - `APPROVE-WITH-NITS` — no blockers, but at least one non-blocking finding or
    Suspected item.
  - `APPROVE` — no findings and no Suspected items, **and** a Coverage section
    that accounts for every changed file. A clean verdict over an incomplete
    Coverage section is not `APPROVE`. The verdict is a text label in the
    review body; the review's GitHub `event` is always `COMMENT`.
- **One finding per block.** Never merge two defects into one bullet — they get
  fixed in one push and re-reviewed as a pair.
- **Order by severity**, `blocker` first. Within a severity, order by file.
- **Every finding cites `path:line`** against the diff under review, a
  `Confidence`, and a `Fix` that is a concrete change, not "consider revisiting".
  A Finding's confidence is `high` or `medium` (`medium`: the path is established
  but its trigger depends on how often a realistic input occurs). A Suspected
  item's is `low` or `medium` (`medium`: the unread fact is probably true). A
  Suspected item has no `Severity` or `Gate` field: it has not been established
  enough to rank.
- **Name the gate** when a ratchet already covers the finding (e.g.
  `Gate: settings-reads`) — that turns a debate into a reproduction step.
- **Omit empty sections, except Coverage.** If there are no blockers, drop the
  heading; do not write "None". Coverage is always present: it is how a reader
  tells "looked and found nothing" from "did not look".
- **Coverage is the evidence behind a clean result.** List every changed file
  with one disposition. A run of mechanical files (a regenerated ARB set, a
  fixture batch) may share one line that names the pattern and why they are
  mechanical. For each of the six classes under "Repository-specific hazards"
  (documentation and changelog, persisted fields, tests, display versus
  canonical, storage/logging/settings ratchets, CI and supply chain), say
  `finding <id>`, `checked — <why it is fine in one clause>`, or
  `n/a — <why it does not apply>`. The baseline checks (async, Drift, sync,
  user-facing, error handling, security) need a line only when one produced a
  finding. A file reviewed from the file because the diff was too large reads
  `read in full`.
- **Post every finding and Suspected item as an inline comment** on its diff line
  when it has one. The body carries the structure; the inline comment is what
  `check_pr_review_gates.py findings` prints and what the thread-resolution gate
  counts, so a Suspected item's thread must be resolved before the merge gate
  passes (the gate counts only resolved threads, so a reply that dismisses it
  is not enough on its own). `findings` prints only the first 160 characters of each
  comment, newlines collapsed, so start each inline comment with the ID,
  severity and title: `B1 blocker: <title>`, `N2 minor: <title>`,
  `S1 suspected: <title>`; the rest of the comment is that finding's block.

### Template

```markdown
## Review verdict: <BLOCK | APPROVE-WITH-NITS | APPROVE>

<one sentence: what the change does and the single most important finding, or
"no findings or suspected items">

### Blockers

#### B1. <one-line title>
- **Where:** `path/to/file.dart:123`
- **Severity:** blocker
- **Confidence:** high
- **Category:** correctness | security | privacy | data-integrity | test-gap | docs-drift
- **Gate:** <ratchet name, or "none">
- **What:** <what is wrong and the concrete way it fails — the input, the path,
  the result — and the refutation you tried>
- **Fix:** <the specific change to make>

### Non-blocking findings

#### N1. <one-line title>
- **Where:** `path/to/file.dart:88`
- **Severity:** minor
- **Confidence:** medium
- **Category:** <as above>
- **What:** <...>
- **Fix:** <...>

### Suspected (never makes the verdict BLOCK; confirm or dismiss in one line)

#### S1. <one-line title>
- **Where:** `path/to/file.dart:57`
- **Confidence:** low | medium
- **Category:** <as above>
- **Fails if:** <the one condition, stated as a fact about the code or data, and
  where to look to settle it>
- **What:** <the input and path that fail when the condition holds>
- **Fix:** <the change to make if it does>

### Coverage

- **Files:** `path/a.dart` — reviewed · `lib/l10n/*.arb` (12) — regenerated
  from `app_en.arb`, parity checked · `path/b.dart` — read in full (diff
  too large)
- **Hazards:** documentation — finding N1 · changelog — checked, app fragment
  present · privacy registry — n/a, no persisted field · tests — checked, the
  new guard asserts the removed branch · display vs canonical — n/a · …

### Verification the author still owes

- [ ] `python3 tools/preflight.py` clean on the current head
- [ ] <new guard test> proven red before green
- [ ] docs updated in this PR for <the behaviour that changed>
```

For a clean review, the whole output collapses to the verdict line and the
`Coverage` section (plus `Verification` where it is not stripped, as the CI
workflow does) — which is the signal a dispatcher wants, in the place it looks
first.
