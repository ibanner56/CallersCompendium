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
on diff lines. A finding on a line outside the diff appears in the body only,
so it has no inline comment and no thread, and neither `findings` nor
`threads` lists it. What `findings --reviewer claude` does read from the body is
the `## Review verdict:` line of the latest round: it prints it and fails on
`BLOCK`, so a body-only blocker cannot pass the gate. Read the body itself for
the findings. There is no `Suppressed comments` block.

What a round is given and asked for:

- **The rubric comes from the PR's base commit.** The workflow copies `SKILL.md`,
  `AGENTS.md` and `.github/instructions/*.instructions.md` from the base into the
  job, so a PR cannot loosen the rules it is reviewed under. A PR that edits
  `SKILL.md` is reviewed under the old rubric; the new one applies from the next
  PR.
- **It sees earlier rounds.** The job is handed the previous Claude reviews, the
  inline comments with their replies, and the diff since the last reviewed
  commit. Only Claude's comments and those of repository owners, members and
  collaborators are included, since this text reaches a model that can post the
  review. It should not repeat a fixed finding or drop an unfixed one, and it
  looks hardest at the lines you changed in response.
- **It reads the claim.** The PR description (`gh pr view`) and the issues the PR
  closes. The job fetches those issues itself, through `closingIssuesReferences`,
  into `.claude-review/context/closing-issues.jsonl`; the review cannot run
  `gh issue view`. The same author filter applies as for inline comments: an
  issue's title and body (body capped at 8000 characters) are included only for
  an issue of this repository whose author is an owner, member or collaborator.
  Any other closed issue, whether an outsider's or from another repository, is
  listed without text, and the review lists it in `Coverage` as a closed issue it
  was not given. Issue comments are never included. If the query fails, or the PR
  closes more than 50 issues, the file says the list is incomplete and `Coverage`
  says so. So put the acceptance criteria a reviewer must hold the change to in
  the PR description, not only in an issue whose text would be withheld.
- **Two tiers.** *Findings* carry an input, a path and a wrong result, and decide
  the verdict. *Suspected* items hinge on one fact the job could not read from the
  code (a value set elsewhere, data in an existing database); they are written as
  "Fails if X", never make the verdict `BLOCK` (they can keep it from being a
  clean `APPROVE`), and want a one-line confirm or dismiss.
  They are inline comments like any finding, so `gate threads` counts them:
  reply to confirm or dismiss each, then resolve its thread before merging (the
  gate counts only resolved threads). `findings` prints the first 160 characters
  of each comment with newlines collapsed, so the rubric leads each comment with
  the ID, severity and title. For a Claude review it passes unless the latest
  round's verdict is `BLOCK`; for Copilot it is informational and always passes.
  The job cannot run tests or scripts, so it never reports that something is
  merely unverified, and the workflow (not the rubric) leaves out the template's
  "Verification the author still owes" checklist, which CI and the merge gate
  own.
- **A `Coverage` section** lists every changed file and the disposition of each
  hazard class. `APPROVE` requires it to be complete, so an `APPROVE` over a
  thin `Coverage` is a reason to distrust the review, not to merge. The merge
  gate does not read `Coverage`, and reads the verdict only to fail on `BLOCK`:
  an `APPROVE` or `APPROVE-WITH-NITS` is printed, not trusted, and a missing
  verdict line is printed as missing without failing, since `claude.yml` also
  posts as `claude[bot]`.

Traps:

- **A green `claude-review` check does not prove a review happened.** The
  action skips itself, and still reports success, when the workflow file
  differs from `main`'s copy. So a PR that edits `claude-code-review.yml` is
  never reviewed by it (observed on #1736). The review entry is the evidence;
  `check_pr_review_gates.py review <N> --reviewer claude` reads that entry, not
  the check.
- **A PR that changes `claude-code-review.yml` may change nothing else.**
  Claude refuses to review such a PR, so CI's `Claude workflow isolation` job,
  which `Merge gate` requires, fails if any other file is in it. That keeps the
  unreviewable part of a change to the workflow file itself. Put everything
  else in a separate PR. `claude.yml` is not covered: the action checks only
  the workflow that invoked it, so a PR that edits `claude.yml` is still
  reviewed
  ([`check_claude_workflow_isolation.py`](../../../tools/ci/check_claude_workflow_isolation.py)).
- **Draft PRs and fork PRs are skipped.** Fork runs receive no secrets. For a
  draft, mark it ready (`ready_for_review` starts a round).
- **The login is `claude[bot]` on both `/reviews` and `/comments`**, unlike
  Copilot's two. Verified against this repository on #1738:

  ```sh
  gh api repos/ibanner56/CallersCompendium/pulls/1738/reviews -q '[.[].user.login]|unique'
  # -> ["claude[bot]"]
  gh api repos/ibanner56/CallersCompendium/pulls/1738/comments -q '[.[].user.login]|unique'
  # -> ["claude[bot]"]
  ```

  GraphQL (`reviewThreads`) reports the same author as `claude`,
  without the suffix; the gate script reads only the REST endpoints.

- **`@claude` in a comment is not a review request.**
  [`claude.yml`](../../../.github/workflows/claude.yml) answers mentions as a
  general assistant. Its output does not follow the review format, and it does
  not run once per round.
- **Only a repository insider's `@claude` starts a run.** The job's `if:`
  schedules it only when the author of the comment, review or issue is an
  `OWNER`, `MEMBER` or `COLLABORATOR`; anyone else's mention shows a skipped
  job. The action refuses a non-write actor itself, but only after the runner
  has started and the action has exchanged its OIDC token for a write-scoped
  app token, so the gate keeps outsiders from costing either. It is a
  scheduling gate, not a sandbox: an insider's mention on an outsider's issue
  or PR still gives the model that thread to read.

## Answering findings

- **Batch the round.** Fix everything from one review round in a single push
  rather than pushing per comment. Each push can start another round, and each
  round re-reads the diff and re-pays the resident prompt, so per-comment pushes
  multiply the most expensive part of the cycle.
- **Read findings through the script, not raw JSON.** `check_pr_review_gates.py
  findings <N>` (add `--reviewer claude` for a Claude review) prints one line per finding — including the suppressed block, or for
  Claude the latest round's verdict — instead of pages of paginated review JSON.
- **Reply after the fix is pushed**, so the reply and the corrected code are
  visible together. Note that replies are recorded as review entries, which is
  why review-freshness must be filtered by reviewer identity
  ([merging.md](merging.md)).
