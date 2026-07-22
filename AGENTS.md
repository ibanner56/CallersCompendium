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
