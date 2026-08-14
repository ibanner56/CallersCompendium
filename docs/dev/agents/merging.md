# Before merging

Load this chapter when a PR is ready to merge. Everything mechanical here is
checked by [`tools/ci/check_pr_review_gates.py`](../../../tools/ci/check_pr_review_gates.py):

```sh
python3 tools/ci/check_pr_review_gates.py all <PR_NUMBER> --closes <ISSUE>...
```

It prints one line per gate and exits non-zero on the first failure. Read the
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

- **CI green on the commit being merged.** Re-check after any push; a green run
  on a superseded commit proves nothing about the current head.

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
python3 tools/ci/check_pr_review_gates.py closes <N> --closes 716
```

which asks GitHub the same question directly:

```sh
gh api graphql -f query='{repository(owner:"<owner>",name:"<repo>"){
  pullRequest(number:<N>){closingIssuesReferences(first:10){nodes{number}}}}}'
```
