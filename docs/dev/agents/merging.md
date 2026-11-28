# Before merging

Load this chapter when a PR is ready to merge. Everything mechanical here is
checked by [`tools/ci/check_pr_review_gates.py`](../../../tools/ci/check_pr_review_gates.py):

```sh
python3 tools/ci/check_pr_review_gates.py all <PR_NUMBER> --closes <ISSUE>...
```

It runs every gate even when one fails, so a single invocation reports the whole
picture, and prints one line per gate (after a `repo:` line when `--repo` is not
given). Exit codes: `0` all gates passed, `1` at
least one gate failed, `2` at least one gate was unanswerable (a `SKIP` line —
the environment could not answer, which is not the same as a pass). Read the
reasoning below when a gate fails, or when you are checking by hand.

## The gates

- **No unresolved review threads.** Ask for `totalCount` too, so a page-size
  truncation is detectable rather than silently reading as "none unresolved":

  ```sh
  gh api graphql -f query='{repository(owner:"<owner>",name:"<repo>"){
    pullRequest(number:<N>){reviewThreads(first:100){
      totalCount pageInfo{hasNextPage endCursor} nodes{isResolved}}}}}'
  ```

  If `hasNextPage` is true (or `totalCount` exceeds the nodes returned), fetch
  the rest with `after: "<endCursor>"` before concluding anything.

- **The latest Claude review reads `APPROVE`.** Only when Claude is the
  reviewer (the default). `findings` prints the latest `## Review verdict:`
  line and fails on anything else. On `BLOCK` because a blocker on a line
  outside the diff exists in the review body only, so no inline comment or
  thread records it and the other gates pass. On `APPROVE-WITH-NITS` because a
  resolved thread is not a cleared item: fix each item, or dispute it and
  re-request the review so the next round re-judges it. A dispute the reviewer
  upholds goes to the maintainer. Details:
  [code-review.md](code-review.md#requesting-a-claude-review).

- **CI green on the commit being merged.** Re-check after any push; a green run
  on a superseded commit proves nothing about the current head. "Every check on
  the head is green" is not enough on its own: a `pull_request_target` workflow
  such as "Claude review status" reports on a head that CI has not reached, so
  bookkeeping checks alone read as green: on a conflicted PR (#2421's body
  records three such heads) and on a fresh head before CI starts. The `ci` gate
  therefore also requires the check the `official` ruleset requires, `Merge
  gate` (below), to have run on the head and finished `success`; any other
  check may also be `neutral` or `skipped`.

- **No merge conflict.** GitHub builds no merge ref for a PR that conflicts with
  its base, so it starts no `pull_request` workflow on it: no CI and no Claude
  review. The `ci` gate fails when the PR's `mergeable_state` is `dirty`, saying
  CI cannot run until the conflict is resolved. `unknown` (GitHub has not
  computed mergeability yet) is not a failure on its own; `Merge gate` is still
  required. GitHub computes mergeability lazily, so a first read after the base
  moves can say `unknown` for a PR that conflicts: re-run the gate.

- **The review is on the commit being merged.** A completed review is reported
  the same way whether or not the head has moved under it, so check it
  explicitly — on #746 a review landed six seconds before the next push.

  **Do not use `.[-1].commit_id`.** GitHub records author replies to inline
  threads as review entries, so the author's reply — carrying the new head SHA —
  is appended after the reviewer's entry on the superseded commit. `.[-1]` then
  matches head and reads as PASS while the review does not cover the current
  diff. Reproduced on #842; see
  [incidents.md](incidents.md#842-review-freshness-read-as-pass-on-a-stale-review).

  Filter by reviewer identity instead, using `--slurp` to collect all pages
  into a single array before filtering:

  ```sh
  gh api --paginate --slurp repos/<owner>/<repo>/pulls/<N>/reviews \
    | jq -er '[.[][] | select(.user.login=="copilot-pull-request-reviewer[bot]")] | last | .commit_id'
  gh pr view <N> --json headRefOid -q .headRefOid
  ```

  The login above is Copilot's. For a Claude review it is `claude[bot]`; the
  script reads Claude's by default and takes `--reviewer copilot` rather than a
  login
  ([code-review.md](code-review.md#choosing-a-reviewer)). Filtering by login is
  not enough for Claude: a reply to an inline thread and a `claude.yml` answer
  also record `claude[bot]` review entries, carrying the head, so the script
  takes Claude's latest entry that carries a `## Review verdict:` line, the
  same rule `findings` reads the verdict by. By hand, add
  `select(.body // "" | test("(^|\n)#{1,6}[ \t]*Review verdict:"))` to the
  filter (jq's `^` matches only at the start of the body, so the `\n` stands in
  for Python's multiline mode).

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

- **The PR closes only the issues you intend** (below).
- **`main`'s changes since your base do not touch your change**, or you have
  synced and re-verified (below). No script checks this one.
- **State verified from the remote**, not from memory or a stale local checkout.

## Sync with `main` when its changes touch yours

GitHub does not require a PR's branch to contain the latest `main`. The
maintainer turned that requirement off because it caused too much churn, and
does not want it back (their answers to questions 36 and 42 of the pre-release
audit's decision sheet, 2026-11-27). So a branch is not synced just because
`main` moved. It is synced when what `main` gained since the branch's base
touches the branch's change. Local preflight and the Claude review saw the
branch without those changes, and CI saw `main` only as it stood when CI last
ran, so a touching change on `main` may never have been tested or reviewed
together with yours.

Right before merging (or enabling auto-merge), list what `main` gained and what
the PR changes. Run it on the PR's head as pushed, not on a local checkout that
may differ (`git rev-parse HEAD` must equal the PR's `headRefOid`), and in a
clone deep enough to hold the branch point: in a shallow clone, run
`git fetch --unshallow origin` first. The `||` stops the check rather than
letting an empty base turn both lists into something else.

```sh
git fetch origin main
base=$(git merge-base origin/main HEAD) || { echo "no merge base: fetch --unshallow"; exit 1; }
git diff --name-only --no-renames "$base" origin/main   # main's side
git diff --name-only --no-renames "$base" HEAD          # your side
```

`--no-renames` lists both paths of a renamed file, so a file `main` renamed
still shows up next to your edit of its old path.

"Touches" means either of these:

- **The same files** appear in both lists.
- **Code your change depends on or affects** changed on `main`, in a different
  file. Examples: a function, model, string or schema your change calls or
  extends; a caller or test of something your change alters; a document or
  generated file that describes what you changed. A shared file is easy to see
  in the two lists. A dependency has to be judged by reading `main`'s side.

If anything touches: disable auto-merge if it is on, sync with `main`, run
`python3 tools/preflight.py` on the synced tree, and clear the merge gates again
on the new head (`check_pr_review_gates.py all`), including a Claude review of
that head ([code-review.md](code-review.md#requesting-a-claude-review) says
what to do when the push was not by a human). If nothing touches, merge without
syncing.

Either way, record what you checked in the PR (a comment, or the body when you
write it last): the two lists, or a summary of them, and why nothing on
`main`'s side touches your change. Repeat it in your report if you write one. A
reviewer that sees a branch behind `main` can then check the record rather than
ask for a sync.

Auto-merge leaves a window: the check covers `main` as it stood when you enabled
auto-merge. If a PR that touches yours lands on `main` before yours merges,
disable auto-merge and sync. When `main` is busy in the same area, prefer to
merge directly once CI is green.

## Merging as an agent

GitHub merges when the `official` ruleset is satisfied. That ruleset requires
only `Merge gate`, allows squash only, and lets nobody bypass it. `Merge gate`
reads CI job results only (its `needs` in
[`ci.yml`](../../../.github/workflows/ci.yml)), so nothing on GitHub waits for a
review of the current head, for open threads, or for an `APPROVE` verdict:
clear those gates yourself, before either path below.
[`.claude/settings.json`](../../../.claude/settings.json) lets Claude Code
sessions take both without a prompt.

- **CI still running: enable auto-merge.** Enable it only once the Claude
  review of the current head has posted, every gate except `ci` passes, and
  [the sync check](#sync-with-main-when-its-changes-touch-yours) finds nothing
  on `main` touching your change (or you have synced):

  ```sh
  python3 tools/ci/check_pr_review_gates.py findings <PR> &&
  python3 tools/ci/check_pr_review_gates.py review <PR> &&
  python3 tools/ci/check_pr_review_gates.py threads <PR> &&
  python3 tools/ci/check_pr_review_gates.py closes <PR> --closes <ISSUE>...
  ```

  The chain stops at the first `FAIL` or `SKIP`, so its exit status is `0`
  only when all four pass. `ci` is the gate auto-merge waits on. **After any
  push, disable auto-merge first**, then clear the gates again on the new head.
  Otherwise the PR can merge as soon as CI on the new head goes green, before
  that head has been reviewed.
- **CI already green: merge directly.** GitHub refuses to enable auto-merge on
  a PR whose checks have all passed, which is common when CI finishes before
  the review posts (#2208). Squash-merge once
  `check_pr_review_gates.py all <PR> --closes <ISSUE>...` exits `0` and
  [the sync check](#sync-with-main-when-its-changes-touch-yours) finds nothing
  touching (or you have synced), and pass
  the head SHA the gates checked as the expected head (`sha` in the REST merge
  call, `expectedHeadSha` in the GitHub MCP tool), so a push in between fails
  the merge instead of landing an unchecked commit.

A PR whose `findings` gate fails is merged by neither path. When the reviewer
upholds an item the author disputes, the maintainer decides, and merges by hand
([code-review.md](code-review.md#requesting-a-claude-review)).

## When GraphQL is refused (Claude Code cloud sessions)

Claude Code cloud sessions answer `gh api graphql` with HTTP 403 ("GitHub
GraphQL is not available from Claude Code sessions"). On that one error the
script answers `threads` and `closes` from REST instead of reporting SKIP, and
labels the evidence line "via REST":

- **`threads`** reads the CCR route `GET /repos/{owner}/{repo}/pulls/{n}/ccr/review_threads`.
  That route reports no total, so a list of 30 or more threads FAILs ("cannot
  prove the list is not truncated") rather than passing; check those from an
  environment with GraphQL.
- **`closes`** cannot read `closingIssuesReferences` over REST, so it parses the
  closing keywords from the PR title, body and commit messages, plus the branch
  name, the same things GitHub links from. **It cannot see a link added by hand
  in the PR sidebar**, so its PASS is weaker than GraphQL's; the evidence line
  says so. A denial such as `Does not close #887` still counts, as it does on
  GitHub.

Repository detection needs no GraphQL either: it reads `--repo`, then
`GITHUB_REPOSITORY`, then the git remote (`upstream`, else the branch's tracking
remote, else `origin`), and only then asks `gh repo view`. It prints the repo and
its source on the first line; check that it is the repo the PR is on, and pass
`--repo` if not.

Any other GraphQL failure (timeout, auth, rate limit) is still a SKIP, and exit
2 still means a gate went unanswered.

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
python3 tools/ci/check_pr_review_gates.py closes <N> --closes 716
```

which asks GitHub the same question directly:

```sh
gh api graphql -f query='{repository(owner:"<owner>",name:"<repo>"){
  pullRequest(number:<N>){closingIssuesReferences(first:100){
    totalCount pageInfo{hasNextPage endCursor} nodes{number}}}}}'
```

Ask for `totalCount` here for the same reason as the thread gate: a truncated
page reads as "closes fewer issues than it does", and the link it dropped is
exactly the unintended one you are looking for. If `hasNextPage` is true (or
`totalCount` exceeds the nodes returned), page with `after: "<endCursor>"`
before concluding anything.

## Branch-sync PRs

`main` is the only long-lived branch; `athenaeum`, the last other one, is gone.
A PR that brings another branch into `main` is squash-merged like any other
(the `official` ruleset allows nothing else), and the gates above, auto-merge
included, apply to it unchanged.

A squash records no second parent, so it never advances the merge base between
the two branches. That costs nothing for a branch that ends at the merge (merged
branches are deleted), and a lot for one that keeps living: every later sync
re-derives conflicts that were already resolved. If a long-lived branch comes
back, read
[#1314](incidents.md#1314-a-squashed-sync-pinned-the-merge-base) before its
first sync. It records what that cost and how to restore the missing parent.
