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

**Suppressed comments are not blocking.** They are suppressed because the
reviewer had low confidence, and many are wrong, stale, or irrelevant — judge
them on their merits rather than treating them as required work.

But read them, because low confidence is not the same as low value. On #746 two
consecutive passes suppressed every substantive finding in the review, and one
was a genuine defect: a comment that would have planted the exact false belief
that PR existed to correct.

Act on the ones that are right, and record why you dismissed the others — so the
next reader can tell "considered" from "missed".

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
- **State verified from the remote**, not from memory or a stale local checkout.

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
- A doc comment that asserts runtime behaviour should be checkable. `star.grip`
  carried a comment claiming it "is surfaced by the verbose/dialect renderer"
  while no renderer referenced it at all.

## Tests

- **Prove a new guard test can fail.** Run it against the unfixed code and watch
  it go red before making it green. A test can be structurally incapable of
  failing and still read as rigorous.
- **Figure fixtures are not validated against the taxonomy.** An invalid param
  renders literally and the test still passes, so fixtures drift silently when a
  move changes. Seven `meanwhile` fixtures went stale when `orbit` was split
  into a first-class move (fixed in #745). When changing a move's params, grep
  the suites for fixtures using that move and run
  `contraTaxonomy.validateFigure()` over them.

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
