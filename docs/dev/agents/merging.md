# Before merging

Load this chapter when a PR is ready to merge. Everything mechanical here is
checked by [`tools/ci/check_pr_review_gates.py`](../../../tools/ci/check_pr_review_gates.py):

```sh
python3 tools/ci/check_pr_review_gates.py all <PR_NUMBER> --closes <ISSUE>...
```

It runs every gate even when one fails, so a single invocation reports the whole
picture, and prints one line per gate. Exit codes: `0` all gates passed, `1` at
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
  pullRequest(number:<N>){closingIssuesReferences(first:100){
    totalCount pageInfo{hasNextPage endCursor} nodes{number}}}}}'
```

Ask for `totalCount` here for the same reason as the thread gate: a truncated
page reads as "closes fewer issues than it does", and the link it dropped is
exactly the unintended one you are looking for. If `hasNextPage` is true (or
`totalCount` exceeds the nodes returned), page with `after: "<endCursor>"`
before concluding anything.

## Never squash a branch-sync PR

This repo squash-merges ([`releasing.md`](../releasing.md)), which is right for
ordinary feature PRs and wrong for a PR whose whole purpose is to carry one
long-lived branch into another — `main` into `athenaeum`, or `athenaeum` back
into `main`.

A squash rewrites the merge into a single-parent commit, so git never records
the source branch as an ancestor and the merge base does not advance. PR #1314
("Merge main into athenaeum") was squash-merged this way. The *content* of
`main` landed correctly, but the merge base stayed pinned at `8f180a9a`, and
every later merge in either direction re-derived twenty-one commits of
already-resolved diff. `app/lib/main.dart`, `app/test/settings_backup_test.dart`
and `app/test/startup_sequence_test.dart` conflicted again, with the same
hunks, against resolutions that were already committed — and would have
conflicted again on every subsequent sync, because nothing about re-resolving
them teaches git where the real base is.

Merge a branch-sync PR with **Create a merge commit**, never *Squash and
merge*. The two-parent commit is the entire point of the PR.

If a sync has already been squashed, do not re-resolve the phantom conflicts —
that buries the problem one merge deeper. Restore the missing parent instead,
with a merge that changes no files:

```sh
git checkout athenaeum
git merge -s ours --no-ff <the-source-commit-the-squash-integrated>
git merge main        # now a normal, minimal merge
```

`-s ours` keeps the current tree and records the second parent, so the merge
base advances to `<the-source-commit>`. It asserts that the squash already
integrated that commit faithfully, which is a claim to verify before you make
it, not after — the assertion is permanent. Replay the merge the squash stood
in for and compare:

```sh
git checkout --detach <pre-squash-tip>
git merge --no-commit --no-ff <the-source-commit-the-squash-integrated>
git diff <squash-commit> -- . ':!<each><conflicted><path>'
```

An empty diff means every path git merged on its own matches the squash. Read
the conflicted paths by hand and confirm both sides survived; a file that is
absent from the squash is only correct if the branch deleted it on purpose
(`BackupControllerScope` was such a case — deleted by `athenaeum` in favour of
`SyncWriterLifecycleScope`, and older than the merge base, so its absence was
intent and not loss).
