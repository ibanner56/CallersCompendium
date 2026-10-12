# Requesting and reading a review

Load this chapter when you are requesting a review, reading one, or answering
findings. The mechanical parts are automated by
[`tools/ci/check_pr_review_gates.py`](../../../tools/ci/check_pr_review_gates.py);
read it here when you need the reasoning or are working by hand.

## Choosing a reviewer

Copilot is the default reviewer and needs no setup. Claude is **opt-in, per
PR**: it reviews only PRs carrying the `review: claude` label. Use either one;
neither is required of anyone else.

The merge gate reads one reviewer's reviews, and a review by the other does not
count. It defaults to Copilot, so existing invocations are unchanged. If you
asked Claude instead, say so:

```sh
python3 tools/ci/check_pr_review_gates.py all <PR> --reviewer claude --closes <ISSUE>...
```

## Requesting a Copilot review

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
round N can still contain a `Suppressed comments` block. See
[incidents.md](incidents.md#842-suppressed-findings-accumulate-every-round).

**`GET /pulls/<N>/comments` is blind to suppressed findings by construction.**
Thread state, unresolved count, and comment count are all blind to them — the
review **body** is their only surface.

**The reviewer's login differs by endpoint.** `/pulls/<N>/reviews` records the
author as `copilot-pull-request-reviewer[bot]`; `/pulls/<N>/comments` records it
as `Copilot`. Verified against this repository:

```sh
gh api repos/ibanner56/CallersCompendium/pulls/900/reviews -q '[.[].user.login]|unique'
# -> ["copilot-pull-request-reviewer[bot]","ibanner56"]
gh api repos/ibanner56/CallersCompendium/pulls/900/comments -q '[.[].user.login]|unique'
# -> ["Copilot","ibanner56"]
```

Carrying the `/reviews` filter to `/comments` without adjusting the login yields
a **silent zero**, which reads as "no inline findings" rather than "filter
matched nothing". A surprising zero is evidence about your query before it is
evidence about the world. See
[incidents.md](incidents.md#the-mismatched-reviewer-login-filter).

## Requesting a Claude review

Apply the label. The label is the request, so you need triage access to the
repository:

```sh
gh pr edit <PR_NUMBER> --add-label "review: claude"
```

[`claude-code-review.yml`](../../../.github/workflows/claude-code-review.yml)
then reviews the head. It **reviews again on every push** while the label stays
on, so freshness takes care of itself. To review the same head again, remove
the label and add it back. To stop further rounds, remove it. Each round costs
a model run on the maintainer's Claude subscription, so remove the label once
you no longer need reviews.

Each round submits **one** PR review, using
[`.github/skills/code-review/SKILL.md`](../../../.github/skills/code-review/SKILL.md)
as its checklist and output format. The review's `commit_id` is the head it
reviewed. Findings appear twice: in the body's template and as inline comments
on diff lines. A finding on a line outside the diff appears in the body only.
There is no `Suppressed comments` block. The job cannot run tests or scripts, so
its prompt limits findings to what it established from the code. It never
reports something as merely unverified, and it leaves out the template's
"Verification the author still owes" checklist, which CI and the merge gate
own.

Traps:

- **A green `claude-review` check does not prove a review happened.** The
  action skips itself, and still reports success, when the workflow file
  differs from `main`'s copy. So a PR that edits `claude-code-review.yml` is
  never reviewed by it (observed on #1736). The review entry is the evidence;
  `check_pr_review_gates.py review <N> --reviewer claude` reads that entry, not
  the check.
- **A PR that changes `claude-code-review.yml` or `claude.yml` may change
  nothing else.** Claude refuses to review such a PR, so CI's `Claude workflow
  isolation` job, which `Merge gate` requires, fails if any other file is in
  it. That keeps the unreviewable part of a change to the workflow files
  themselves. Put everything else in a separate PR
  ([`check_claude_workflow_isolation.py`](../../../tools/ci/check_claude_workflow_isolation.py)).
- **Draft PRs and fork PRs are skipped.** Fork runs receive no secrets. For a
  draft, mark it ready (`ready_for_review` starts a round).
- **The login is `claude[bot]` on both `/reviews` and `/comments`.** This comes
  from the action's run identity, not from a review: no Claude review existed in
  this repository when it was written. Confirm it on the first real review,
  then update this line and `CLAUDE` in the gate script:

  ```sh
  gh api repos/<owner>/<repo>/pulls/<N>/reviews -q '[.[].user.login]|unique'
  gh api repos/<owner>/<repo>/pulls/<N>/comments -q '[.[].user.login]|unique'
  ```

- **`@claude` in a comment is not a review request.**
  [`claude.yml`](../../../.github/workflows/claude.yml) answers mentions as a
  general assistant. Its output does not follow the review format, and it does
  not run once per round.

## Answering findings

- **Batch the round.** Fix everything from one review round in a single push
  rather than pushing per comment. Each push can start another round, and each
  round re-reads the diff and re-pays the resident prompt, so per-comment pushes
  multiply the most expensive part of the cycle.
- **Read findings through the script, not raw JSON.** `check_pr_review_gates.py
  findings <N>` (add `--reviewer claude` for a Claude review) prints one line per finding — including the suppressed block —
  instead of pages of paginated review JSON.
- **Reply after the fix is pushed**, so the reply and the corrected code are
  visible together. Note that replies are recorded as review entries, which is
  why review-freshness must be filtered by reviewer identity
  ([merging.md](merging.md)).
