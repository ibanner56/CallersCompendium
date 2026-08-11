# Repository agent guide

Short operational notes for automated agents and contributors working in this
repository. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor
guide and [docs/dev/](docs/dev/) for deeper dev docs.

## Requesting a Copilot code review

Request Copilot as a reviewer by its **bot login**, not the display name:

```sh
gh api --method POST \
  repos/<owner>/<repo>/pulls/<PR_NUMBER>/requested_reviewers \
  -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

Using `reviewers[]=Copilot` (the display name) returns HTTP 201 **but silently
no-ops** — the reviewer is dropped, `requested_reviewers` stays empty, and no
review is ever created. Always verify the request actually attached:

- the POST response's `.requested_reviewers[].login` is `Copilot`, and
- the PR timeline shows a `review_requested` -> Copilot event
  (`gh api repos/<owner>/<repo>/issues/<PR_NUMBER>/timeline`).

Note: the Copilot reviewer is a bot, so it appears under
`requested_reviewers.users` with `"type": "Bot"`; an empty `.users` after a
request means the request did not attach (usually the wrong slug or a
review-concurrency cap — retry once the cap frees).

## Reading a Copilot review

Read the review **body**, not just the inline threads. Copilot can report
"reviewed N of N files and generated no new comments", leave `reviewThreads` at
zero unresolved, and still have findings — collapsed into a block in the body:

```
<details><summary>Suppressed comments (N)</summary>
```

`gh pr view`, the inline comment count, and thread state all read zero while
these exist, so a thread-state-only check will never surface them:

```sh
gh api --paginate repos/<owner>/<repo>/pulls/<N>/reviews -q '.[].body'
```

`--paginate` matters: without it you get only the first page of reviews (30 by
default), so on a PR with several review rounds the older bodies — and any
suppressed sections in them — are silently omitted.

**Re-check the body every round, not once.** Suppressed findings accumulate
independently each round — a review that says "generated no new comments" in
round N can still contain a `Suppressed comments` block. On #842, seven of eight
rounds contained suppressed findings (twelve of nineteen total findings were
suppressed), and only round 1 did not. Checking once after round 1 would have
concluded the pattern did not apply.

**`GET /pulls/<N>/comments` is blind to suppressed findings by construction.**
#842's inline comment count held at 4 (2 findings + 2 author replies) through
all eight rounds while nineteen findings accumulated. Thread state, unresolved
count, and comment count are all blind to suppressed findings — the review
**body** is their only surface.

**The reviewer's login differs by endpoint.** `/pulls/<N>/reviews` records the
author as `copilot-pull-request-reviewer[bot]`; `/pulls/<N>/comments` records it
as `Copilot`. Verified against this repository:

```sh
gh api repos/ibanner56/CallersCompendium/pulls/900/reviews -q '[.[].user.login]|unique'
# -> ["copilot-pull-request-reviewer[bot]","ibanner56"]
gh api repos/ibanner56/CallersCompendium/pulls/900/comments -q '[.[].user.login]|unique'
# -> ["Copilot","ibanner56"]
```

The document
already teaches `select(.user.login=="copilot-pull-request-reviewer[bot]")` for
the `/reviews` endpoint — correct there. If you carry that filter to `/comments`
without adjusting the login, you get a **silent zero**, which reads as "no inline
findings" rather than "filter matched nothing". This happened across four PRs on
this repository in a single day and produced a wrong conclusion — a real inline
security finding had come through the normal thread channel and the mismatched
filter made it invisible. A surprising zero is evidence about your query before
it is evidence about the world.

## Before merging

- **No unresolved review threads.** Ask for `totalCount` too, so a page-size
  truncation is detectable rather than silently reading as "none unresolved":

  ```sh
  gh api graphql -f query='{repository(owner:"<owner>",name:"<repo>"){
    pullRequest(number:<N>){reviewThreads(first:100){
      totalCount pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}'
  ```

  If `hasNextPage` is true (or `totalCount` exceeds the nodes returned), fetch
  the rest with `after: "<endCursor>"` before concluding anything.

- **CI green on the commit being merged.** Re-check after any push; a green run
  on a superseded commit proves nothing about the current head.
- **The review is on the commit being merged.** A completed review is reported
  the same way whether or not the head has moved under it, so check it
  explicitly — on #746 a review landed six seconds before the next push.

  **Do not use `.[-1].commit_id`.** GitHub records author replies to inline
  threads as review entries. When an author reads a review, pushes a fix, and
  replies to the threads — the normal review cycle — their replies are appended
  after the reviewer's entry carrying the new head SHA. `.[-1]` then returns the
  author's reply commit (which matches head) while the actual Copilot review sits
  on the superseded commit. The gate passes; the review does not cover the
  current diff. Reproduced on #842: Copilot reviewed `a76f3e0f`, the author
  replied on `c11f747e`, and `.[-1].commit_id` returned `c11f747e` — matching
  head, reading as PASS.

  Filter by reviewer identity instead, using `--slurp` to collect all pages
  into a single array before filtering:

  ```sh
  gh api --paginate --slurp repos/<owner>/<repo>/pulls/<N>/reviews \
    | jq -er '[.[][] | select(.user.login=="copilot-pull-request-reviewer[bot]")] | last | .commit_id'
  gh pr view <N> --json headRefOid -q .headRefOid
  ```

  `--slurp` wraps all pages into an outer array, so `.[][]` flattens them and
  `last` reliably picks the reviewer's latest entry across pages. (`--slurp` is
  incompatible with `-q`/`--jq`, so the filter is piped to a standalone `jq`.)
  `-r` strips the JSON quotes so the two SHAs are directly comparable; `-e`
  exits non-zero when no matching review exists, so an unreviewed PR fails
  closed rather than printing `null` with exit 0.

- **`requested_reviewers` must not be used to determine review state.** The
  field is cleared on submission, so an empty result is ambiguous between *never
  requested* and *already submitted*. A reading of it is valid only at the
  instant it was taken and goes stale silently. To detect an **in-flight**
  review (requested but not yet submitted), use the timeline's
  `review_requested` event — that event persists after submission. `GET
  /pulls/<N>/reviews` is structurally incapable of showing a pending request;
  neither endpoint answers the question alone.

- **The PR closes only the issues you intend.** See below.
- **State verified from the remote**, not from memory or a stale local checkout.

## A branch name can close an issue on its own

GitHub creates a linked-issue relationship from the **branch name**, not just
from a closing keyword in the body. A branch named `…issue-716-…` closed #716
on merge even though the PR was deliberately titled "Part of #716" with no
`Closes` keyword — mid-way through a four-PR sequence, so the issue had to be
reopened.

The same trap applies to prose that *denies* a link. `Does not close #887`
contains `close #887`, and GitHub parses it — the negation is ignored. On #897
that disclaimer alone produced a closing reference to an issue deliberately
closed as `NOT_PLANNED`. The author did everything else right: no `issue-887`
in the branch name, no closing keyword intended, explicit written denial. The
denial itself created the link, and on merge it would overwrite the
`NOT_PLANNED` decision. Phrase denials so the verb never sits next to the
number — "#887 remains open; that issue is about the format-level question" —
and trust `closingIssuesReferences` rather than the prose either way.

Do not put `issue-<N>` in a branch name, and before merging any partial or
stacked PR, check what it will actually close:

```sh
gh api graphql -f query='{repository(owner:"<owner>",name:"<repo>"){
  pullRequest(number:<N>){closingIssuesReferences(first:10){nodes{number}}}}}'
```

## Documentation is part of the change

Documentation drift is this repository's most persistent defect class, across
design docs, roadmap status, and code comments.

- When a change alters documented behaviour, update the documentation **in the
  same PR**, not a follow-up.
  - `app/CHANGELOG.md` is user-facing release notes, not a commit log. Update it
    for user-visible changes under `## [Unreleased]` and when cutting a release
    (move `[Unreleased]` into a version section).
- When a reviewer flags a claim as wrong, **grep for the claim across the repo**
  before fixing the line they cited. False claims are usually copy-pasted: one
  wrong byte-stability claim took three PRs (#718 -> #721 -> #722) because each
  fix chased the citation instead of the assertion. Grepping finds every instance,
  but each still has to be judged in its own context — the same sentence can be
  true in one file and false in another, and a sweep that makes them uniform will
  make a correct comment wrong. The sentence at
  `packages/compendium_core/lib/src/imports/figure_parser.dart` around `:483`,
  in a partner-token map where absent entries genuinely force custom, reads:
  "and are absent from this map so they decline the whole line to custom."
  The sentence at
  `packages/compendium_core/lib/src/imports/callersbox_figure_dialect.dart`
  around `:1606`, in the shared people-code map, read (before this was fixed):
  "`P6`+ and every `P-n` are absent from this map and decline to custom."
  It is true in the first. In the second it was false (before this PR fixed it)
  for any decoder that only adds params — `_sideRunAnnotation` is one — because
  those decoders fall through to the shared recognizer and the line still
  structures. The surrounding block opening at `:1575` of the same file already
  corrected the general claim ("what 'declines' costs depends on the decoder"),
  making `:1606` a surviving stale instance *within* the corrected block. A sweep
  that fixed the general statement and left the specific one behind is exactly the
  failure mode this rule describes. Fixing the false instance would have made the
  true one wrong if applied uniformly.
- Do not carry a claim forward from adjacent prose just because it was already
  there. Verify it against the code, or delete it. A stale sentence in
  `docs/design/dialect.md` survived a rewrite of the section around it and had
  to be caught in review.
- Grepping for the claim finds the places that *state* it. Also ask **"what did
  I just make untrue?"** and grep for the *property*. PR #751 falsified two
  comments asserting that no live taxonomy param pairs certain kinds with a
  `choices` list; neither comment mentions the PR, the issue, or `ParamKind`, so
  no citation search would reach them, and the tests stayed green because they
  inject a synthetic taxonomy.
- **Re-take any measurement quoted in a PR body after the final rebase.** Corpus
  figures quoted for #729 were taken before a sibling landed, and the sibling
  itself changed them.
- A doc comment that asserts runtime behaviour should be checkable. `star.grip`
  carried a comment claiming it "is surfaced by the verbose/dialect renderer"
  while no renderer referenced it at all.

## Every persisted field must be classified

The app's privacy boundary is a registry, not prose:
`packages/compendium_core/lib/src/privacy/`, rendered to
`docs/dev/data-classification.md`. Any new column, settings key, or data-entry
surface must be classified **in the same PR that introduces it**.

This exists because the boundary used to be prose and prose does not hold. A doc
comment on `Choreographer` said its `email`/`location` "MUST NOT be emitted in
any shareable export"; nothing enforced it, and the same question had no answer
at all for the 22 columns of `venues`. Five ratchets now enforce it, so the
failure mode is a red CI run rather than a silent leak.

Three axes per field, and the third is the one to think about:

- **Category** — a W3C DPV v2.3 term. Freely readable, so you can check your own
  work against the source.
- **Subject** — `none` / `appUser` / `thirdParty`. No published taxonomy
  supplies this. Every one of them assumes the data subject is the person using
  the app, and here it usually is not: venue contacts and choreographers never
  touch this app and cannot consent to a transfer they do not know about.
- **Egress** — `shareable` / `deviceLocal` / `deviceScoped` / `derived`.
  `deviceLocal` and `deviceScoped` are not synonyms. The first is withheld
  because of what it *contains* and may still move by a direct device-to-device
  transfer; the second because of what it *means* on another device, and must
  not travel by any route.

Record **why** in the entry's `note` whenever the call is not self-evident, and
say who decided it if it was contested — see [Attributing
decisions](#attributing-decisions). A classification with no stated reason is
indistinguishable from a guess.

Do not narrow a ratchet's detection pattern to make a false positive go away.
The settings ratchet flags `kUpdateManifestPublicKey`, which is the Ed25519 root
of trust for update authenticity rather than a preference; it is excluded **by
name, with a reason**, so that the next non-settings `…Key` constant still fails
loudly. A cleverer pattern would have dropped both silently.

## Tests

- **Prove a new guard test can fail.** Run it against the unfixed code and watch
  it go red before making it green. A test can be structurally incapable of
  failing and still read as rigorous — one surrogate-pair test was both
  backwards *and* unreachable (its fixture exceeded a regex's length cap, so the
  code under test never ran), and still passed review.
- **Choose the right thing to falsify against.** "Does it fail if I undo my
  work?" is the wrong question; ask **"what mutation would this test catch?"**
  - For a *regression* guard, reverting the fix is the right target — but make
    sure the revert still **builds**. A revert that fails to compile proves
    nothing, and will happen if the fix and the helpers it needs are in one
    commit. Split commits so the revert target is buildable.
  - For a guard on a hazard introduced by *new* behaviour, revert is the wrong
    target: the old code cannot exercise the hazard at all, so the test goes red
    for an incidental reason. Instead **mutate out the guard** — implement the
    naive version a future simplification would produce — and confirm the test
    catches that.
- **Do not use line-window greps to ask whether a declaration contains
  something.** `ParamSpec` and `MoveDef` declarations span lines, so `grep -A3`
  under-reports and a non-greedy regex can run past a short declaration and
  capture a later one's field. The same question answered three ways gave 0, 5,
  and (walking balanced parens) the truth. Walk the delimiters.
- **Figure fixtures are not validated against the taxonomy.** An invalid param
  renders literally and the test still passes, so fixtures drift silently when a
  move changes. Seven `meanwhile` fixtures went stale when `orbit` was split
  into a first-class move (fixed in #745). When changing a move's params, grep
  the suites for fixtures using that move and run
  `contraTaxonomy.validateFigure()` over them.

## Never `git stash` in a worktree

All worktrees of a repository share **one stash stack** — `refs/stash` lives in
the common git directory (`git rev-parse --git-common-dir`), not the per-worktree
one. A `git stash push` in one worktree is visible to, and poppable by, every
other, so a stash/pop pair that looks local is not.

This has caused a real near-miss: a `git stash push -- <path>` on an
already-committed file was a silent no-op, and the paired `pop` therefore popped
an entry belonging to a different worktree.

For red-run verification, restore from a ref instead — it is scoped to the
worktree and cannot touch anyone else's state:

```sh
git checkout HEAD~1 -- <path>     # or any ref
```

## Attributing decisions

Say who decided something, not just what was decided.

Do not label a decision "owner-decided", "maintainer decision", or "as ratified"
in a PR body, issue comment, or source comment unless the maintainer decided it
and you can point to where. These phrases are currently attached to decisions
agents made themselves, which makes the record unauditable — an approved
decision and an assumed one read identically.

When you decide something yourself, say so plainly and give the reason:

```
Chose X. The issue suggested A and B; A is impossible here because <reason>,
and B is disproportionate because <reason>. Not escalated — non-blocking.
```

The same applies to verification. **State which layer you actually checked**, so
a reader can see the edge of the evidence. "The stash is intact" and "no damage
was done" differ in scope, not in confidence — the first was true and verified
while the second was false, and no amount of hedging would have exposed the gap.
Report what you looked at, not just what you concluded.

When correcting a derived figure, **re-derive it from source rather than patching
one term**. A count of "three of five" was corrected to "three of four" by
checking only the denominator; the truth was two of four. The wrong number then
carried the credibility of a correction.
