# Repository agent guide

Operational rules for automated agents and contributors. This file is
**resident context** — injected into every turn of every session — so it holds
only what binds in *every* session. Everything else is one line away.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor guide,
[docs/dev/README.md](docs/dev/README.md) for a map of which document answers
which question, and [docs/dev/agents/](docs/dev/agents/) for the chapters below.

## Load the chapter for the phase you are in

| Read | When |
| --- | --- |
| [docs/dev/agents/code-review.md](docs/dev/agents/code-review.md) | Requesting or reading a Copilot review, or answering findings |
| [docs/dev/agents/merging.md](docs/dev/agents/merging.md) | Merging: review/CI freshness, unresolved threads, what the PR closes |
| [docs/dev/agents/verification.md](docs/dev/agents/verification.md) | Proving a guard test can fail; any red run that mutates the tree |
| [docs/dev/agents/triage.md](docs/dev/agents/triage.md) | Triaging or scoping an issue |
| [docs/dev/agents/releasing.md](docs/dev/agents/releasing.md) | Cutting a release |
| [docs/dev/agents/session-cost.md](docs/dev/agents/session-cost.md) | Scoping work for an agent, or adding to these instructions |
| [docs/dev/agents/incidents.md](docs/dev/agents/incidents.md) | You want the evidence behind a rule — PR numbers, SHAs, reproductions |

Rules that apply to one area of the tree are attached to that area instead, in
[.github/instructions/](.github/instructions/), and load only for sessions that
touch it.

## Run the gates before you push

```sh
python3 tools/preflight.py          # every gate CI runs, terse output
python3 tools/preflight.py --list   # what it will run, and why
```

A clean `dart test` is not the same as a clean gate run: some ratchets — figure
fixtures against the taxonomy, most notably — are not exercised by the test
suites at all. Before merging, run:

```sh
python3 tools/ci/check_pr_review_gates.py all <PR> --closes <ISSUE>...
```

which checks review freshness against the reviewer's own latest entry,
unresolved threads (with `totalCount`, so truncation is visible), CI status on
the current head, and that the PR closes exactly the issues you named. Details
and failure modes: [docs/dev/agents/merging.md](docs/dev/agents/merging.md).

## Documentation is part of the change

Documentation drift is this repository's most persistent defect class, across
design docs, roadmap status, and code comments.

- When a change alters documented behaviour, update the documentation **in the
  same PR**, not a follow-up. `app/CHANGELOG.md` is user-facing release notes,
  not a commit log: update it for user-visible changes under `## [Unreleased]`.
- **Never hand-edit a generated file.** Generated files carry a
  `<!-- generated-by: ... -->` marker on the first line naming the tool that
  writes them and the source they are written from. Read the source, not the
  rendering: `docs/dev/data-classification.md` is 45 KB of registry output whose
  source is `packages/compendium_core/lib/src/privacy/field_registry.dart`.
- When a reviewer flags a claim as wrong, **grep for the claim across the repo**
  before fixing the line they cited — false claims are usually copy-pasted. But
  judge each instance in its own context: the same sentence can be true in one
  file and false in another, and a uniform sweep will make a correct comment
  wrong. Worked example:
  [incidents.md](docs/dev/agents/incidents.md#718---721---722-a-false-claim-chased-by-citation).
- Grepping for the claim finds the places that *state* it. Also ask **"what did
  I just make untrue?"** and grep for the *property* — the comments that will be
  falsified usually cite neither the PR nor the issue
  ([#751](docs/dev/agents/incidents.md#751-the-claim-nobody-would-have-grepped-for)).
- Do not carry a claim forward from adjacent prose just because it was already
  there. Verify it against the code, or delete it.
- A doc comment that asserts runtime behaviour should be checkable.
- **Re-take any measurement quoted in a PR body after the final rebase.**

## Every persisted field must be classified

The app's privacy boundary is a registry, not prose:
`packages/compendium_core/lib/src/privacy/`. Any new database column, settings
key, or data-entry surface must be classified **in the same PR that introduces
it**, or a ratchet fails the build.

Three axes per field, and the third is the one to think about:

- **Category** — a W3C DPV v2.3 term. Freely readable, so you can check your own
  work against the source.
- **Subject** — `none` / `appUser` / `thirdParty`. No published taxonomy supplies
  this. Every one of them assumes the data subject is the person using the app,
  and here it usually is not: venue contacts and choreographers never touch this
  app and cannot consent to a transfer they do not know about.
- **Egress** — `shareable` / `deviceLocal` / `deviceScoped` / `derived`.
  `deviceLocal` and `deviceScoped` are not synonyms. The first is withheld
  because of what it *contains* and may still move by a direct device-to-device
  transfer; the second because of what it *means* on another device, and must
  not travel by any route.

Record **why** in the entry's `note` whenever the call is not self-evident. A
classification with no stated reason is indistinguishable from a guess. Full
rules load automatically when you touch the privacy paths:
[.github/instructions/privacy-registry.instructions.md](.github/instructions/privacy-registry.instructions.md).

## Tests must be shown to fail

- **Prove a new guard test can fail.** Run it against the unfixed code and watch
  it go red before making it green. A test can be structurally incapable of
  failing and still read as rigorous.
- **Ask "what mutation would this test catch?"** — not "does it fail if I undo
  my work?". For a regression guard, revert the fix (and make sure the revert
  still *builds*). For a guard on a hazard introduced by new behaviour, revert is
  the wrong target: mutate out the guard instead and confirm the test catches
  the naive version.
- **Never `git stash`** — worktrees share one stash stack. Commit the change
  first, mutate, then restore with `git checkout <that-commit-sha> -- <path>`;
  restoring from `HEAD` discards uncommitted work silently.
- **Do not use line-window greps** (`grep -A3`) to ask whether a multi-line
  declaration contains something. Walk the delimiters.

Procedure and the incidents behind each:
[docs/dev/agents/verification.md](docs/dev/agents/verification.md).

## Say who decided it

- Do not label a decision "owner-decided", "maintainer decision", or "as
  ratified" unless the maintainer decided it and you can point to where. An
  approved decision and an assumed one must not read identically.
- When you decide something yourself, say so plainly and give the reason,
  including the alternative you rejected and why.
- **State which layer you actually verified.** "The stash is intact" and "no
  damage was done" differ in scope, not in confidence — report what you looked
  at, not just what you concluded.
- When correcting a derived figure, **re-derive it from source** rather than
  patching one term.

## Keep this file small

This file is re-sent every turn of every session; a chapter is read once by the
session that needs it. Adding here must **displace**, not append —
`tools/ci/check_agent_context_budget.py` fails the build when resident
instructions exceed their cap. If a new rule does not fit, it is usually not
universal: put it in a chapter, or in a path-scoped instruction file. Reasoning:
[docs/dev/agents/session-cost.md](docs/dev/agents/session-cost.md).
