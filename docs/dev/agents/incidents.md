# Incidents behind the rules

The rules in [`AGENTS.md`](../../../AGENTS.md) and the chapters beside this file
are one-liners. This file is where their evidence lives: the PR numbers, the
SHAs, the reproductions.

Nothing here is resident context. Read the entry when you want to know *why* a
rule exists, when you are tempted to relax one, or when you are writing a new
rule and want the shape of the failure it should prevent.

## #842: suppressed findings accumulate every round

Seven of eight review rounds contained a `Suppressed comments` block (twelve of
nineteen total findings were suppressed), and only round 1 did not. Checking
once after round 1 would have concluded the pattern did not apply.

The inline comment count held at 4 (2 findings + 2 author replies) through all
eight rounds while nineteen findings accumulated: `GET /pulls/<N>/comments`,
thread state, and unresolved count are all blind to suppressed findings by
construction. The review **body** is their only surface.

Rule: [code-review.md](code-review.md#reading-a-review).

## The mismatched reviewer-login filter

`/pulls/<N>/reviews` records the reviewer as
`copilot-pull-request-reviewer[bot]`; `/pulls/<N>/comments` records it as
`Copilot`. Carrying the `/reviews` filter to `/comments` returns an empty set,
which reads as "no inline findings" rather than "filter matched nothing".

This happened across four PRs on this repository in a single day and produced a
wrong conclusion — a real inline security finding had come through the normal
thread channel and the mismatched filter made it invisible. A surprising zero is
evidence about your query before it is evidence about the world.

Rule: [code-review.md](code-review.md#reading-a-review).

## #842: review freshness read as PASS on a stale review

GitHub records author replies to inline threads as review entries. When an
author reads a review, pushes a fix, and replies to the threads — the normal
review cycle — their replies are appended after the reviewer's entry carrying
the new head SHA. `.[-1].commit_id` then returns the author's reply commit
(which matches head) while the actual Copilot review sits on the superseded
commit. The gate passes; the review does not cover the current diff.

Reproduced on #842: Copilot reviewed `a76f3e0f`, the author replied on
`c11f747e`, and `.[-1].commit_id` returned `c11f747e` — matching head, reading
as PASS. On #746 a review landed six seconds before the next push.

Rule: [merging.md](merging.md#the-gates), automated by
[`tools/ci/check_pr_review_gates.py`](../../../tools/ci/check_pr_review_gates.py).

## #716 and #897: a link created without a closing keyword

A branch named `…issue-716-…` closed #716 on merge even though the PR was
deliberately titled "Part of #716" with no `Closes` keyword — mid-way through a
four-PR sequence, so the issue had to be reopened.

On #897, the prose `Does not close #887` produced a closing reference to an
issue deliberately closed as `NOT_PLANNED`: the string contains `close #887`
and GitHub parses it, ignoring the negation. The author did everything else
right — no `issue-887` in the branch name, no closing keyword intended, an
explicit written denial. The denial itself created the link.

Rule: [merging.md](merging.md#a-branch-name-can-close-an-issue-on-its-own).

## #718 -> #721 -> #722: a false claim chased by citation

One wrong byte-stability claim took three PRs, because each fix chased the
citation the reviewer gave instead of the assertion itself. False claims are
usually copy-pasted; grepping for the claim finds every instance.

But each instance still has to be judged in its own context — the same sentence
can be true in one file and false in another, and a sweep that makes them
uniform will make a correct comment wrong:

- `packages/compendium_core/lib/src/imports/figure_parser.dart` around `:483`,
  in a partner-token map where absent entries genuinely force custom, reads:
  "and are absent from this map so they decline the whole line to custom."
  **True there.**
- `packages/compendium_core/lib/src/imports/callersbox_figure_dialect.dart`
  around `:1606`, in the shared people-code map, used to read: "`P6`+ and every
  `P-n` are absent from this map and decline to custom." **False there**, for
  any decoder that only adds params — `_sideRunAnnotation` is one — because
  those decoders fall through to the shared recognizer and the line still
  structures. The block opening at `:1575` of the same file had already
  corrected the general claim ("what 'declines' costs depends on the decoder"),
  making `:1606` a surviving stale instance *within* the corrected block.

Rule: [`AGENTS.md`](../../../AGENTS.md) — "Documentation is part of the change".

## #751: the claim nobody would have grepped for

PR #751 falsified two comments asserting that no live taxonomy param pairs
certain kinds with a `choices` list. Neither comment mentions the PR, the issue,
or `ParamKind`, so no citation search would reach them, and the tests stayed
green because they inject a synthetic taxonomy.

Grepping for the claim finds the places that *state* it. Also ask "what did I
just make untrue?" and grep for the *property*.

Related: a stale sentence in `docs/design/dialect.md` survived a rewrite of the
section around it and had to be caught in review — do not carry a claim forward
from adjacent prose just because it was already there. And `star.grip` carried a
doc comment claiming it "is surfaced by the verbose/dialect renderer" while no
renderer referenced it at all: a doc comment that asserts runtime behaviour
should be checkable.

## #729: a measurement that went stale before merge

Corpus figures quoted in the PR body were taken before a sibling PR landed, and
the sibling itself changed them. Re-take any measurement quoted in a PR body
after the final rebase.

## #747: drifted figure fixtures were invisible to `dart test`

Rendering SUBSTITUTES rather than validates, so an invalid figure param renders
literally and every test still passes. Seven `meanwhile` fixtures went stale
when #697 split `orbit` into a first-class move, unnoticed for days until #745
fixed them by hand.

`packages/compendium_core/tool/check_fixture_validity.dart` now guards it, run
by `_checks.yml` before the core suite — but `dart test` does not run it over
the real suites (its own unit test drives synthetic input), so a clean local
`dart test` will not catch a fixture you just invalidated. That is why
[`tools/preflight.py`](../../../tools/preflight.py) exists and runs it.

## The privacy boundary that was prose

A doc comment on `Choreographer` said its `email` and `location` "MUST NOT be
emitted in any shareable export"; nothing enforced it, and the same question had
no answer at all for the 22 columns of `venues`. The boundary is now a registry
under `packages/compendium_core/lib/src/privacy/` with a family of ratchets
across `packages/compendium_core/test/privacy/` and `app/test/data/`, so the
failure mode is a red CI run rather than a silent leak.

The settings ratchet flags `kUpdateManifestPublicKey`, which is the Ed25519 root
of trust for update authenticity rather than a preference; it is excluded **by
name, with a reason**, so that the next non-settings `…Key` constant still fails
loudly. A cleverer pattern would have dropped both silently — do not narrow a
ratchet's detection pattern to make a false positive go away.

Rule: [`.github/instructions/privacy-registry.instructions.md`](../../../.github/instructions/privacy-registry.instructions.md).

## A guard test that could not fail

One surrogate-pair test was both backwards *and* unreachable — its fixture
exceeded a regex's length cap, so the code under test never ran — and still
passed review. A test can be structurally incapable of failing and still read as
rigorous.

Rule: [verification.md](verification.md#prove-a-new-guard-test-can-fail).

## The stash that was not local

All worktrees share one stash stack (`refs/stash` lives in the common git
directory). A `git stash push -- <path>` on an already-committed file was a
silent no-op, and the paired `pop` therefore popped an entry belonging to a
different worktree.

Later, mid-red-run and while otherwise complying with the "restore from a ref"
rule, `git checkout HEAD -- <path>` discarded the uncommitted change under test:
`HEAD` was the state *before* it. The command succeeded, printed nothing, and
left a tree that still compiled. What caught it was `git status` showing the
file no longer modified.

Rule: [verification.md](verification.md#never-git-stash-in-a-worktree).

## The line-window grep that gave three answers

`ParamSpec` and `MoveDef` declarations span lines, so `grep -A3` under-reports
and a non-greedy regex can run past a short declaration and capture a later
one's field. The same question answered three ways gave 0, 5, and — walking
balanced parens — the truth.

Rule: [verification.md](verification.md#do-not-use-line-window-greps-to-ask-whether-a-declaration-contains-something).

## The corrected figure that was still wrong

A count of "three of five" was corrected to "three of four" by checking only the
denominator; the truth was two of four. The wrong number then carried the
credibility of a correction. Re-derive from source rather than patching one term.

Rule: [`AGENTS.md`](../../../AGENTS.md) — "Say who decided it".

## The comments are 30% of the code, and cutting them is the wrong fix

Measured across hand-written Dart (generated files excluded): comments are 16.9%
of lines but **30% of bytes** — line counts understate them, because comment
lines are dense prose and code lines are short. Eighty-two files (11.5%) carry
more comment bytes than the entire 8 KiB resident budget;
`callersbox_figure_dialect.dart` carries 93.5 KiB at 72% of the file, so one
`view` of it costs roughly 12× every resident rule combined.

The obvious conclusion — trim the comments — is wrong here, and the same
measurement is what rules it out. Across `lib/`: 1,429 comment lines cite an
issue number, 141 cite a design doc, 274 contain "because", 286 say
"deliberately" or "intentionally"; against 45 `Returns the ...` restatements, 5
`Creates a`, and no `// TODO` markers. The type case is `database.dart` (86% comment, 653
comment lines around 194 of code), which records why the FTS5 table deviates
from `docs/design/storage.md`, why only `(move, section)` is indexed, and why the
v14 index survives in `onCreate` after the migration floor moved to v20. Delete
that and the cost does not go away; it moves to the session that re-derives the
reasoning, gets it wrong, and "fixes" the index.

So the tool built for this
([`report_comment_weight.py`](../../../tools/ci/report_comment_weight.py))
reports and never fails a build, unlike the resident-context ratchet beside it.
The asymmetry is the point: every session pays for `AGENTS.md`, so it earns a
hard cap; only some sessions pay for a given file, and a cap there would create
pressure to delete the `because` clauses. What is actionable is placement and
read granularity, not volume.

Decided by the agent that ran the measurement, not by the maintainer. The
alternative considered and rejected was a byte cap per file with a grandfathered
baseline: it would have produced a green build and a slow erosion of the
rationale ledger, with no signal that the erosion was happening.

Rule: [session-cost.md](session-cost.md#comment-weight).

## The two comment blocks that were ledgers, not reasons

The ranking above says what is actionable is placement, not volume — this is the
first change made under it, and it is recorded because the *selection rule* is
reusable and the obvious reading of the ranking ("start deleting at the top") is
not.

Scanning every hand-written `.dart` file for contiguous comment blocks over
4 KiB found ten. Two dwarfed the rest and shared a property none of the others
had:

| Block | Before | After |
| --- | --- | --- |
| `contra_taxonomy.dart` — `contraTaxonomyVersion` log, v2–v28 | 81.3 KiB comment, 73% of file, 2,118 lines | 41.5 KiB, 59%, 1,530 lines |
| `database.dart` — schema log, v1–v25 | 43.7 KiB comment, 86% of file, 877 lines | 25.9 KiB, 79%, 628 lines |

40.7 KiB of the first sat on the single line `const int contraTaxonomyVersion =
28;`. Both were append-only ledgers of decisions already shipped: they constrain
nothing on the declaration they annotate, and they grow on every bump, so the
cost of reading either file rose monotonically forever. Both moved **verbatim**
to the design doc the code already cited, behind a one-line pointer. Repo-wide
comment bytes fell 2,841.7 KiB → 2,784.1 KiB and both files left the top of the
ranking.

What did *not* move is the load-bearing half of the same comment: the four
things a schema bump must ship, and the rule that a bump never rides a PATCH
release, are still on `CompendiumDatabase`, because those constrain the line.
Nor did the third-heaviest block (11.4 KiB on `repositories.dart`), every bullet
of which names a table that must appear in the `readsFrom` set immediately below
it. No comment anywhere was deleted.

Relocating a ledger creates one new failure mode — a later bump appends its
entry nowhere — so the move shipped with
[`check_version_history.py`](../../../tools/ci/check_version_history.py), which
fails a PR that moves either constant without adding an entry naming that
version. It was proven red before green, and then against the naive
implementation it exists to beat: a gate that asked only "did the doc change?"
passes the realistic mistake (bump to v29 while editing the v28 entry), and five
checks in `test_check_version_history.py` catch that mutant.

Decided by the agent that ran the measurement, not by the maintainer, on the
maintainer's instruction to reduce session cost in one PR. The alternative
considered and rejected was leaving the ledgers inline and narrowing reads
instead: it fixes nothing for the sessions that read the taxonomy whole, and the
blocks would have kept growing.

Rule: [session-cost.md](session-cost.md#worked-example-a-ledger-is-not-a-rationale).
