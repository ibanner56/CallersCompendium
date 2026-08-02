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

**Suppressed comments are not blocking**, but suppression reflects the
reviewer's *confidence*, not the finding's *importance*. On this repository the
suppressed block has held both the most substantive findings and the most
misguided ones — on #746 every substantive finding in the review arrived
suppressed, and all of them were correct. Read and judge them; neither trust nor
dismiss them wholesale.

Act on the ones that are right, and record why you dismissed the others — so the
next reader can tell "considered" from "missed".

A useful pattern when judging: this reviewer's *observations* are reliable — a
file really does mix literals and constants, a changelog really does say "two"
while listing three. Where it errs is the *remedy*, because consistency and DRY
are its only objectives and it cannot tell a redundant duplicated literal from a
load-bearing one. **When a suggestion would make two sides of an assertion move
together, treat it as a claim about test strength and measure it** rather than
accepting it as a style preference: on #751 a suggested refactor would have made
a pinning assertion vacuous (spelled out, the vocabulary mutation produced 2
failures; in the suggested form, 47/47 passed and the mutation went
undetected).

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

- **Suppressed comments read and considered** (above).
- **CI green on the commit being merged.** Re-check after any push; a green run
  on a superseded commit proves nothing about the current head.
- **The review is on the commit being merged.** A submitted review is pinned to
  the commit it ran against, so a push after it lands leaves a review that has
  not seen the change — exactly like a CI run on a superseded commit, and just
  as invisible. On #746 a review landed six seconds before the next push.

  **Filter by the reviewer's login, and do it before `tail`:**

  ```sh
  gh api --paginate repos/<owner>/<repo>/pulls/<N>/reviews \
    -q '.[]|select(.user.login=="copilot-pull-request-reviewer[bot]")|.commit_id' \
    | tail -n 1
  gh pr view <N> --json headRefOid -q .headRefOid
  ```

  Taking the last element without filtering does not work, because **this
  endpoint returns a review object for every inline thread reply**, not just for
  submitted reviews. Those replies carry the *PR author's* login and an empty
  body, and they are appended after the reviewer's review — so the last element
  is usually the author's own last activity, whose `commit_id` matches head by
  construction. The check then reports a stale review as fresh. Measured on
  #764, where the only real review was two commits behind head:

  ```
  copilot-pull-request-reviewer[bot]   bodylen=4075   83934433   <- the review
  ibanner56                            bodylen=0      1b5b51be   <- thread reply
  ibanner56                            bodylen=0      1b5b51be   <- thread reply
  ```

  **Use the bot login, not the display name.** The reviews endpoint spells it
  `copilot-pull-request-reviewer[bot]`; `Copilot` — the spelling that appears in
  `requested_reviewers` above — matches nothing here and returns empty. Verified
  back to back on #764: filtering on `Copilot` gives ``, filtering on the bot
  login gives `1b5b51be`. That failure is silent and mis-directed: an empty
  result reads as "no review yet", which looks like a reason to wait rather than
  a reason to look again.

  Assert the result is non-empty, so a future login change fails loudly instead
  of reading as "not reviewed yet".

  `--paginate` for the same reason as above; `tail -n 1` because `-q` is applied
  to each page separately, so the un-tailed form emits one match per page.

- **The PR closes only the issues you intend.** See below.
- **State verified from the remote**, not from memory or a stale local checkout.

## A branch name can close an issue on its own

GitHub creates a linked-issue relationship from the **branch name**, not just
from a closing keyword in the body. A branch named `…issue-716-…` closed #716
on merge even though the PR was deliberately titled "Part of #716" with no
`Closes` keyword — mid-way through a four-PR sequence, so the issue had to be
reopened.

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
- When a reviewer flags a claim as wrong, **grep for the claim across the repo**
  before fixing the line they cited. False claims are usually copy-pasted: one
  wrong byte-stability claim took three PRs (#718 -> #721 -> #722) because each
  fix chased the citation instead of the assertion.
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
  - **Report the red-run result in the PR body.** Squash-merging collapses the
    commit split, so a branch structured to keep the revert target buildable
    survives only as concatenated prose, not as revertable commits. If the
    result is not written down it is not recoverable afterwards.
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

## Tracking follow-up work

When you accept a known limitation, **file the follow-up issue at that moment**
and reference it from the code or design doc. Do not defer to a sibling issue:
sibling issues close.

A limitation recorded in `docs/design/search.md` was deferred to a sibling that
shipped and closed without addressing it. Nothing caught the dangling pointer,
and the limitation went untracked until an audit found it (now #748).

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
