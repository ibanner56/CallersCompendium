# Requesting and reading a Copilot review

Load this chapter when you are requesting a review, reading one, or answering
findings. The mechanical parts are automated by
[`tools/ci/check_pr_review_gates.py`](../../../tools/ci/check_pr_review_gates.py);
read it here when you need the reasoning or are working by hand.

## Requesting a review

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

## Reading a review

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

## Answering findings

- **Batch the round.** Fix everything from one review round in a single push
  rather than pushing per comment. Each push can start another round, and each
  round re-reads the diff and re-pays the resident prompt, so per-comment pushes
  multiply the most expensive part of the cycle.
- **Read findings through the script, not raw JSON.** `check_pr_review_gates.py
  findings <N>` prints one line per finding — including the suppressed block —
  instead of pages of paginated review JSON.
- **Reply after the fix is pushed**, so the reply and the corrected code are
  visible together. Note that replies are recorded as review entries, which is
  why review-freshness must be filtered by reviewer identity
  ([merging.md](merging.md)).
