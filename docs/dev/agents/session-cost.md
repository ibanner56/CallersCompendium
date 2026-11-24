# Session cost: what makes an agent session expensive here

Load this chapter when scoping work for an agent, when starting child sessions
or scheduling check-ins, when a session feels disproportionately expensive, or
before adding anything to the resident instructions.

## The cost model

Every model call re-sends the whole conversation so far: the resident prompt,
everything the session has read, and every earlier turn. (In this chapter a
"turn" is one model call. A response that makes several independent tool calls
at once is still one turn, so batch independent reads.) So a session's input cost is
roughly `context_size × turns`, and `context_size` grows for as long as the
session lives. There are three levers on the number of tokens: **shrink what
is resident**, **take fewer turns**, and **keep long-lived sessions small**. A
fourth lever changes the price per token instead:
**[choose the model for each task](#choose-the-model-for-each-task)**.

In the week of 2026-11-18 to 2026-11-24, the third lever dominated. That week's
74 Opus sessions with reported usage (read from each session's own usage
record) re-read 8.7 billion cached tokens and generated 22.2 million output
tokens: 394 tokens re-read for each token generated. At the Opus list rates of
that week a cached read cost 1% of an output token, yet cache reads were 60% of
Opus spend, cache writes 25% and output 15%. 47 of that week's sessions held
more than 300k tokens of context when their usage was recorded. Because
[the budget](#shrink-what-is-resident) holds `AGENTS.md` at 8 KiB, the resident
prompt is now small next to a context of that size; that is the ratchet working,
not a reason to loosen it. See
[Long-lived and waiting sessions](#long-lived-and-waiting-sessions).

Resident context is `AGENTS.md` plus any
[`.github/instructions/*.instructions.md`](../../../.github/instructions/) whose
`applyTo` glob matches a file in play. It is re-sent every turn of every
session. A chapter under `docs/dev/agents/` is carried only by the sessions that
read it, from that point on.

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
`python3 tools/ci/check_pr_review_gates.py findings <N>` (add `--reviewer
copilot` for a Copilot review) — one line per finding, with Claude's verdict or
Copilot's suppressed block — rather than paginated review JSON. See
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

### Worked example: a ledger is not a rationale

The first pass under that ranking found the distinction worth reusing. Scanning
every hand-written `.dart` file for contiguous comment blocks over 4 KiB turned
up only ten, and the top two were the same species:

```
40.7 KiB  602 ln  taxonomy/contra_taxonomy.dart   -> one line: contraTaxonomyVersion = 28
19.4 KiB  257 ln  storage/database.dart           -> the schema version log, v1..v25
```

Both were **append-only version ledgers**: a log of decisions already taken and
already shipped. That is not a `because` clause protecting the line it sits on —
nothing about either declaration is harder to change without the log — and it is
the only kind of comment that grows without bound, since every future bump
appends another entry that every future reader pays for. Both moved to the
design doc the code already cited (`figure-taxonomy.md`, `storage.md`), verbatim,
behind a one-line pointer. What *did* constrain the declaration stayed: the four
things a schema bump must ship, and the rule that it never rides a PATCH
release, are still on `CompendiumDatabase`.

The third-heaviest block, 11.4 KiB on `repositories.dart`, was deliberately left
alone by the same test — every bullet in it names a table that must appear in
the `readsFrom` set below it, or a subscriber silently stops updating.

Relocating a ledger creates exactly one new failure mode: a later bump appends
its entry nowhere. Prefer a gate to a remembered rule, so the move shipped with
`tools/ci/check_version_history.py`, which fails a PR that moves any constant
it covers without adding the matching entry. **Do not relocate a ledger without
one** — a history that stops recording is worse than a history that is
expensive to read.

So the usable test is: *does this comment constrain the line it sits on, or does
it record something already decided?* The first stays, however long. The second
belongs in a document, with a gate keeping it fed.

## Long-lived and waiting sessions

A session pays for its whole history on every turn, including turns that only
find out nothing has changed. In the week of 2026-11-18 to 2026-11-24, project
channel threads and orchestrator trees (an orchestrator plus every session it
started) came to 81% of all session spend, and child sessions alone were 57% of
all session spend. Two habits drive that: carrying one conversation across many
units of work, and waking a large context to check on something.

### Hand off at a milestone

When a unit of work lands (a PR merges, a plan is approved, a child is
archived) and the session will go on to something else, start a fresh session
with a brief instead of carrying the history forward. The brief is the same one
[Scope before dispatch](#scope-before-dispatch) asks for. Keep state in the
repository, the PR and the issue, which a fresh session can read, rather than
in the conversation, which only that session has.

This holds for project channel threads too. In the week measured, they ran with
a 1M-token window and compacted only at 384k tokens, so a thread that mostly
waited could sit at several hundred thousand tokens for days.

### Make waiting cheap

Every wake-up re-reads the whole context: a PR event, a child reporting back,
a scheduled check-in. A wake-up that finds nothing new costs the same re-read as
one that does work.

- **Let events wake the session.** A Claude Code cloud session subscribed to a
  PR already wakes for its comments, reviews and CI results. A safety-net
  check-in is for what events do not deliver, such as a merge conflict or a
  child that has gone quiet. Space check-ins hours apart rather than hourly,
  and stop re-arming after a couple of empty ones: the next event will wake the
  session anyway, and each empty check-in costs a full re-read.
- **Run a recurring poll in a fresh session.** A cron-style check (new notes,
  new failures, a corpus re-run) should start a new session on each firing,
  with a self-contained prompt, rather than firing into a long-lived thread
  whose context it has to re-read to do a small job. Each firing starts with no
  memory of the one before (as [releasing.md](releasing.md) says of scheduled
  runs), so keep its state in the repository, an issue or PR comment, or
  another durable store, not in local files the next firing will not have.
- **Wait on a condition, not a timer.** Poll a log or a PR state in a
  background command, and wake the large session only when there is something
  to act on. A sub-agent that polls in a loop is still paying for model calls.

## Choose the model for each task

The model sets the price per token, so this is the fourth lever. An
orchestrator chooses the model when it starts each child session or sub-agent,
so it can match the model to the task instead of defaulting either way.

- **Use the strongest model for work that is stateful, cross-cutting, or judged
  on fidelity:** plans, design, UI and user-facing copy, code review, and
  anything ambiguous.
- **Use a lighter model for contained, mechanical work whose result a script or
  check can verify:** fetching raw records for a script to parse, sweeping for
  a string, applying a rename the plan has already specified, running a gate
  whose exit code is the answer.
- **Set effort the same way.** High effort is for tasks that need deliberation,
  not the default for every child.

If a lighter model's result has to be redone, that costs more than using the
stronger model in the first place. So downgrade only where a script or a check
can tell whether the result is right.

## Measure, so this does not silently regress

Track per-session input tokens against three numbers: the resident prompt size,
the turn count, and the size of the context being re-sent. Comparing them says
which lever moved. A rise is prompt growth (fix it by moving rules out of
residency), round-trip growth (fix it by scoping, batching and local gates), or
context growth (fix it by handing off at milestones and making waiting cheap).
Without these numbers a rise is uninterpretable, and the usual response is to
add another rule, which makes it worse.

The budget ratchet prints the resident total on every run, and the
comment-weight report prints the per-read total, so those are available from
any CI log without instrumenting anything. The turn count and context size come
only from the session's own usage record.
