# Session cost: what makes an agent session expensive here

Load this chapter when scoping work for an agent, when a session feels
disproportionately expensive, or before adding anything to the resident
instructions.

## The cost model

A session's input cost is roughly `resident_prompt × turns`, plus whatever it
reads. So there are exactly two levers: **shrink what is resident** and **take
fewer turns**. Everything below is one or the other.

Resident context is `AGENTS.md` plus any
[`.github/instructions/*.instructions.md`](../../../.github/instructions/) whose
`applyTo` glob matches a file in play. It is re-sent every turn. A chapter under
`docs/dev/agents/` is read at most once, by the session that needs it.

### What was measured

Between 2026-07-22 and 2026-08-14, `AGENTS.md` grew from 1,181 bytes to 25,589 —
21.7×, over thirteen commits, every one of them a net addition and every one
individually justified. Nothing was budgeted against, so the growth was
invisible. Meanwhile roughly 38% of the file applied only to the merge-owner
path or to multi-worktree work, and was inert for a typical coding session — but
still resident in all of them.

The repository's Markdown grew 11.7× over the same period and its Dart grew
15.7×, so *merged prose volume* was not the driver. What drove the floor was the
subset of prose that is resident, and the procedural mandates that multiply
turns.

## Shrink what is resident

- **A rule earns residency by applying to every session.** Path-specific rules
  go in `.github/instructions/` with an `applyTo` glob; phase-specific rules
  (review, merge, release, triage) go in a chapter under `docs/dev/agents/`.
- **Additions must displace, not append.** The resident budget is enforced by
  [`tools/ci/check_agent_context_budget.py`](../../../tools/ci/check_agent_context_budget.py),
  which fails when a resident file exceeds its cap. If a new rule does not fit,
  either it is not universal (move it to a chapter) or something resident has
  stopped earning its place.
- **Keep the rule resident and the reasoning reachable.** The narrative that
  stops a rule being relitigated does not have to be re-sent every turn; it
  lives in [incidents.md](incidents.md).
- **Prefer a gate to a remembered rule.** A rule an agent must remember costs
  tokens every turn forever and fails silently when forgotten; a ratchet costs
  zero prompt tokens and fails loudly. When a rule becomes checkable, write the
  check and reduce the prose to one line pointing at it.

## Take fewer turns

### Scope before dispatch

Most of a session's early turns are rediscovering scope the issue author already
knew. An issue that is ready for an agent names:

- the files to touch (or the entry point to start from),
- the docs that will need updating in the same PR,
- the acceptance criteria, and
- anything already ruled out, and why.

### One concern per PR

Cost is superlinear in review rounds, and multi-concern PRs generate more of
them. Each round re-reads the diff and re-pays the resident prompt.

### Push verbose work into sub-agents

Full test runs, build logs and CI triage produce thousands of lines that are
read once and never referenced again — but stay in context for the rest of the
session, re-sent every turn. Run them in a sub-agent that returns a summary, or
pipe them through a filter. The main context should never hold a full test log.

### Batch review responses

Fix everything from one review round in a single push, and read the round with
`python3 tools/ci/check_pr_review_gates.py findings <N>` — one line per finding,
including the suppressed block — rather than paginated review JSON. See
[code-review.md](code-review.md#answering-findings).

### Fail early, locally

A failure found by CI costs a wait, a log fetch, and a full re-reason at the
current prompt size. `python3 tools/preflight.py` runs the same gates locally.

### Read the smallest thing that answers the question

- Start from the repo map, [`docs/dev/README.md`](../README.md): one 2 KB read
  routinely replaces several broad greps.
- Do not read a **generated** document when you can read its source. Generated
  files carry a `<!-- generated-by: ... -->` marker at the top and are listed in
  the repo map.
- The large design documents carry a section index at the top. Read the section,
  not the file.
- **A source file is read once and then re-sent every remaining turn**, so
  `view`-ing a whole file to reach one method is the same mistake as an
  over-large resident prompt, at smaller scale. Prefer a targeted read.

## Comment weight

Comments cost nothing until a file is read, and then they cost like resident
context: re-sent every remaining turn of the session.

```sh
python3 tools/ci/report_comment_weight.py          # summary + heaviest files
```

Measured at the time of writing: comments are ~30% of the bytes of hand-written
Dart, and **82 files (11.5%) carry more comment bytes than the entire 8 KiB
resident budget** — one of them 12× it, at 72% of the file.

That is *not* an argument for shorter comments. The same measurement found 1,429
comment lines citing an issue number, 141 citing a design doc, 286 saying
"deliberately" or "intentionally", against 45 `Returns the ...` restatements and
no `// TODO` markers. These comments are a rationale ledger; deleting one does not save the
money, it defers it to the session that re-derives the reasoning, gets it wrong,
and "fixes" the thing the comment was protecting.

So the report is a **report**: it never fails a build, deliberately. A cap would
create pressure to delete the `because` clauses, which is the one outcome worse
than the cost. What the ranking is for:

- **Ask whether a reader of this file needs all of it, here.** A decision that is
  stable and cross-cutting can move to `docs/design/` behind a one-line pointer;
  a decision that constrains a specific line stays inline. That cuts
  bytes-per-read without losing a single "why".
- **Treat a file that is mostly prose as a document.** At 77–86% comment, a file
  is a design note wearing a `.dart` extension, and it is read whole every time
  because it is read as code.

Do not quote the tool's number as exact: it classifies lines by their first
characters, so trailing comments are undercounted. Its purpose is to rank files
against each other.

## Measure, so this does not silently regress

Track per-session input tokens against two numbers: the resident prompt size and
the turn count. The ratio says which lever moved — a month's rise is either
prompt growth (fix by moving rules out of residency) or round-trip growth (fix by
scoping, batching, and local gates). Without both numbers, a rise is
uninterpretable and the usual response is to add another rule, which makes it
worse.

The budget ratchet prints the current resident total on every run, and the
comment-weight report prints the per-read total, so both numbers are available
from any CI log without instrumenting anything.
