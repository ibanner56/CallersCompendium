#!/usr/bin/env python3
"""Offline tests for ``check_pr_review_gates.py``.

No network: a fake fetcher returns canned GitHub payloads, so each gate is
exercised against the exact shape that made the hand-rolled version read as PASS
-- the author's reply carrying the head SHA (#842), a truncated thread page, a
review body whose only findings are suppressed, a closing reference nobody
intended. A gate that has only ever been seen green is indistinguishable from
one that does nothing.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "check_pr_review_gates", HERE / "check_pr_review_gates.py"
)
assert SPEC and SPEC.loader
gates = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gates)

REVIEWER = gates.REVIEWER_LOGIN
AUTHOR = "ibanner56"
HEAD = "c11f747e2b0f4d9a8c1e5d3b7a6f2e1d0c9b8a77"
STALE = "a76f3e0f1d2c3b4a5968778695a4b3c2d1e0f9a8"


class FakeFetcher:
    repo = "ibanner56/CallersCompendium"

    def __init__(self, rest: dict[str, Any], graphql: Any = None) -> None:
        self._rest = rest
        self._graphql = graphql
        self.rest_calls: list[tuple[str, bool]] = []

    def rest(self, path: str, *, paginate: bool = False) -> Any:
        self.rest_calls.append((path, paginate))
        if path not in self._rest:
            raise AssertionError(f"unexpected REST path: {path}")
        return self._rest[path]

    def graphql(self, query: str) -> Any:
        if self._graphql is None:
            raise AssertionError("unexpected GraphQL call")
        if isinstance(self._graphql, Exception):
            raise self._graphql
        return self._graphql


def review(login: str, commit: str, body: str = "") -> dict[str, Any]:
    return {"user": {"login": login}, "commit_id": commit, "body": body}


def pull(head: str = HEAD) -> dict[str, Any]:
    return {"head": {"sha": head}}


# --------------------------------------------------------------------------- #
# review freshness
# --------------------------------------------------------------------------- #


def test_review_freshness_catches_the_authors_reply_carrying_head() -> None:
    """#842: `.[-1].commit_id` returned the author's reply SHA and read as PASS."""
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            "pulls/1/reviews": [
                [review(REVIEWER, STALE), review(AUTHOR, HEAD)],
            ],
        }
    )
    ok, lines = gates.gate_review(fetcher, 1)
    assert not ok, lines
    assert STALE[:8] in lines[0] and HEAD[:8] in lines[0]


def test_review_freshness_passes_on_current_head() -> None:
    fetcher = FakeFetcher(
        {"pulls/1": pull(), "pulls/1/reviews": [[review(REVIEWER, HEAD)]]}
    )
    ok, lines = gates.gate_review(fetcher, 1)
    assert ok, lines


def test_unreviewed_pr_fails_closed() -> None:
    fetcher = FakeFetcher(
        {"pulls/1": pull(), "pulls/1/reviews": [[review(AUTHOR, HEAD)]]}
    )
    ok, lines = gates.gate_review(fetcher, 1)
    assert not ok, lines
    assert "no review" in lines[0]


def test_reviews_are_read_across_pages() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            "pulls/1/reviews": [
                [review(REVIEWER, STALE)],
                [review(REVIEWER, HEAD)],
            ],
        }
    )
    ok, _ = gates.gate_review(fetcher, 1)
    assert ok
    assert ("pulls/1/reviews", True) in fetcher.rest_calls, "must paginate"


# --------------------------------------------------------------------------- #
# reviewer selection (--reviewer)
# --------------------------------------------------------------------------- #

CLAUDE = gates.CLAUDE


def test_reviewer_logins_are_the_ones_github_reports() -> None:
    """The other tests build fixtures from these constants, so only this one
    can catch a wrong login. Values observed on this repository: Copilot on
    #900, Claude on #1738 (see docs/dev/agents/code-review.md)."""
    assert gates.COPILOT == ("copilot-pull-request-reviewer[bot]", "Copilot")
    assert gates.CLAUDE == ("claude[bot]", "claude[bot]")


def test_claude_freshness_ignores_a_copilot_review_on_head() -> None:
    """Asking for Claude's review must not be satisfied by Copilot's."""
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            "pulls/1/reviews": [
                [review(CLAUDE.review_login, STALE), review(REVIEWER, HEAD)]
            ],
        }
    )
    ok, lines = gates.gate_review(fetcher, 1, CLAUDE)
    assert not ok, lines
    assert STALE[:8] in lines[0], lines


def test_claude_freshness_passes_on_its_own_review_at_head() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            "pulls/1/reviews": [[review(CLAUDE.review_login, HEAD)]],
        }
    )
    ok, lines = gates.gate_review(fetcher, 1, CLAUDE)
    assert ok, lines


def test_default_reviewer_is_copilot_so_a_claude_review_does_not_count() -> None:
    """Contributors who never pass --reviewer keep the Copilot gate unchanged."""
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            "pulls/1/reviews": [[review(CLAUDE.review_login, HEAD)]],
        }
    )
    ok, lines = gates.gate_review(fetcher, 1)
    assert not ok, lines
    assert REVIEWER in lines[0], lines


def test_claude_findings_read_claudes_inline_comments_only() -> None:
    def inline(login: str, path: str) -> dict[str, Any]:
        return {"user": {"login": login}, "path": path, "line": 3, "body": "x"}

    fetcher = FakeFetcher(
        {
            "pulls/1/reviews": [[review(CLAUDE.review_login, HEAD)]],
            "pulls/1/comments": [
                [
                    inline(CLAUDE.comment_login, "lib/claude.dart"),
                    inline(gates.REVIEWER_COMMENT_LOGIN, "lib/copilot.dart"),
                ]
            ],
        }
    )
    _, lines = gates.gate_findings(fetcher, 1, CLAUDE)
    assert lines[0].startswith(f"1 round(s) by {CLAUDE.review_login}"), lines
    assert "1 inline finding(s)" in lines[0], lines
    assert any("lib/claude.dart" in line for line in lines[1:]), lines
    assert not any("lib/copilot.dart" in line for line in lines[1:]), lines


BLOCK_BODY = """\
## Review verdict: BLOCK

The change falsifies a doc it did not touch.

### Blockers

#### B1. docs/x.md still describes the removed flag
- **Where:** `docs/x.md:3`
"""


def _claude_reviews(*bodies: tuple[str, str]) -> Any:
    """A Claude-only `findings` fixture: (commit, body) per round, no inline
    comments -- the shape of a review whose findings all sit outside the diff."""
    return FakeFetcher(
        {
            "pulls/1/reviews": [[review(CLAUDE.review_login, c, b) for c, b in bodies]],
            "pulls/1/comments": [[]],
        }
    )


def test_claude_block_verdict_with_body_only_findings_fails_the_findings_gate() -> None:
    """A finding on a line outside the diff cannot be an inline comment, so a
    `BLOCK` review can have zero inline findings and zero threads. The gate
    used to read only inline comments and passed it."""
    ok, lines = gates.gate_findings(_claude_reviews((HEAD, BLOCK_BODY)), 1, CLAUDE)
    assert not ok, lines
    assert any("BLOCK" in line for line in lines), lines


def test_claude_block_verdict_fails_through_run_gates_with_exit_one() -> None:
    fetcher = _claude_reviews((HEAD, BLOCK_BODY))
    fetcher._rest["pulls/1"] = pull()
    printed: list[str] = []
    code = gates.run_gates(
        fetcher, 1, ["findings", "review"], [], reviewer=CLAUDE, out=printed.append
    )
    assert code == 1, printed
    assert any(line.startswith("FAIL findings:") for line in printed), printed
    assert any(line.startswith("PASS review:") for line in printed), printed


def test_claude_non_block_verdict_is_surfaced_and_passes() -> None:
    for verdict in ("APPROVE", "APPROVE-WITH-NITS"):
        body = f"## Review verdict: {verdict}\n\nNo blockers."
        ok, lines = gates.gate_findings(_claude_reviews((HEAD, body)), 1, CLAUDE)
        assert ok, lines
        assert any(f"verdict {verdict}" in line for line in lines), lines


def test_claude_verdict_is_read_from_the_latest_round_only() -> None:
    """A BLOCK that a later round cleared must not fail the gate, and a BLOCK
    that a later round did not clear must not be hidden by an earlier APPROVE."""
    cleared = _claude_reviews((STALE, BLOCK_BODY), (HEAD, "## Review verdict: APPROVE"))
    ok, lines = gates.gate_findings(cleared, 1, CLAUDE)
    assert ok, lines
    assert not any("verdict BLOCK" in line for line in lines), lines

    reopened = _claude_reviews((STALE, "## Review verdict: APPROVE"), (HEAD, BLOCK_BODY))
    ok, lines = gates.gate_findings(reopened, 1, CLAUDE)
    assert not ok, lines


def test_claude_verdict_survives_markdown_decoration() -> None:
    for body in (
        "## Review verdict: **BLOCK**",
        "### Review verdict: `BLOCK`",
        "intro line\n\n## Review verdict: block\n",
    ):
        ok, lines = gates.gate_findings(_claude_reviews((HEAD, body)), 1, CLAUDE)
        assert not ok, (body, lines)


def test_a_later_verdictless_claude_entry_does_not_mask_an_earlier_block() -> None:
    """Replying to an inline thread records an empty-body review entry, and
    claude.yml posts as claude[bot] too. Neither carries a verdict, so neither
    may stand in for the round that does."""
    for later in ("", "Thanks, looking at it."):
        fetcher = _claude_reviews((HEAD, BLOCK_BODY), (HEAD, later))
        ok, lines = gates.gate_findings(fetcher, 1, CLAUDE)
        assert not ok, (later, lines)
        assert any("verdict BLOCK (round 1" in line for line in lines), lines


def test_a_verdictless_entry_after_a_cleared_block_does_not_resurrect_it() -> None:
    fetcher = _claude_reviews(
        (STALE, BLOCK_BODY), (HEAD, "## Review verdict: APPROVE"), (HEAD, "")
    )
    ok, lines = gates.gate_findings(fetcher, 1, CLAUDE)
    assert ok, lines
    assert any("verdict APPROVE (round 2" in line for line in lines), lines


def test_claude_review_without_a_verdict_line_says_so_and_does_not_fail() -> None:
    """`claude.yml` also posts as claude[bot] with no verdict line. Failing
    on it would block merges on a review that is not a rubric review; hiding it
    would read as a clean verdict."""
    ok, lines = gates.gate_findings(_claude_reviews((HEAD, "Looks fine.")), 1, CLAUDE)
    assert ok, lines
    assert any("no `## Review verdict:` line" in line for line in lines), lines


def test_a_block_mentioned_in_prose_is_not_a_verdict() -> None:
    for body in (
        "Round 1 said ## Review verdict: BLOCK, now fixed.\n\n## Review verdict: APPROVE",
        "## Review verdict: APPROVE\n\nRound 1 said ## Review verdict: BLOCK.",
    ):
        ok, lines = gates.gate_findings(_claude_reviews((HEAD, body)), 1, CLAUDE)
        assert ok, (body, lines)
        assert any("verdict APPROVE" in line for line in lines), lines


def test_a_copilot_review_is_not_read_for_a_verdict() -> None:
    """Copilot's body has no verdict line; the Copilot gate stays as it was."""
    fetcher = FakeFetcher(
        {
            "pulls/1/reviews": [[review(REVIEWER, HEAD, BLOCK_BODY)]],
            "pulls/1/comments": [[]],
        }
    )
    ok, lines = gates.gate_findings(fetcher, 1)
    assert ok, lines
    assert not any("verdict" in line for line in lines), lines


def test_run_gates_passes_the_reviewer_to_both_review_gates() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            "pulls/1/reviews": [[review(CLAUDE.review_login, HEAD)]],
            "pulls/1/comments": [[]],
        }
    )
    printed: list[str] = []
    code = gates.run_gates(
        fetcher, 1, ["findings", "review"], [], reviewer=CLAUDE, out=printed.append
    )
    assert code == 0, printed
    assert any(CLAUDE.review_login in line for line in printed), printed


def _reviewer_chosen_by_cli(argv: list[str]) -> Any:
    seen: dict[str, Any] = {}

    def fake_run_gates(*_args: Any, reviewer: Any, **_kwargs: Any) -> int:
        seen["reviewer"] = reviewer
        return 0

    real_run, real_fetcher = gates.run_gates, gates.GitHubFetcher
    gates.run_gates, gates.GitHubFetcher = fake_run_gates, lambda repo: None
    try:
        assert gates.main(argv) == 0
    finally:
        gates.run_gates, gates.GitHubFetcher = real_run, real_fetcher
    return seen["reviewer"]


def test_cli_reviewer_defaults_to_copilot_and_accepts_claude() -> None:
    assert _reviewer_chosen_by_cli(["review", "1", "--repo", "o/r"]) == gates.COPILOT
    chosen = _reviewer_chosen_by_cli(
        ["review", "1", "--repo", "o/r", "--reviewer", "claude"]
    )
    assert chosen == CLAUDE


# --------------------------------------------------------------------------- #
# findings
# --------------------------------------------------------------------------- #

SUPPRESSED_BODY = """\
Reviewed 8 of 8 files and generated no new comments.

<details><summary>Suppressed comments (2)</summary>

lib/a.dart:12 — this cast can throw
lib/b.dart:40 — unused parameter

</details>
"""


def test_findings_surface_suppressed_blocks_that_thread_state_cannot_see() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1/reviews": [[review(REVIEWER, HEAD, SUPPRESSED_BODY)]],
            "pulls/1/comments": [[]],
        }
    )
    ok, lines = gates.gate_findings(fetcher, 1)
    assert ok
    assert "2 suppressed" in lines[0]
    assert any("this cast can throw" in line for line in lines[1:])
    assert any("unused parameter" in line for line in lines[1:])


def test_findings_use_the_comments_endpoint_login() -> None:
    """The two endpoints report the reviewer under different logins."""
    inline = {
        "user": {"login": gates.REVIEWER_COMMENT_LOGIN},
        "path": "lib/a.dart",
        "line": 7,
        "body": "possible null dereference",
    }
    wrong_login = dict(inline, user={"login": REVIEWER})
    fetcher = FakeFetcher(
        {
            "pulls/1/reviews": [[review(REVIEWER, HEAD)]],
            "pulls/1/comments": [[inline, wrong_login]],
        }
    )
    _, lines = gates.gate_findings(fetcher, 1)
    assert "1 inline finding(s)" in lines[0], lines
    assert any("lib/a.dart:7" in line for line in lines[1:])


def test_findings_read_every_round_not_just_the_last() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1/reviews": [
                [
                    review(REVIEWER, STALE, SUPPRESSED_BODY),
                    review(REVIEWER, HEAD, "Reviewed 8 of 8 files."),
                ]
            ],
            "pulls/1/comments": [[]],
        }
    )
    _, lines = gates.gate_findings(fetcher, 1)
    assert "2 suppressed" in lines[0], lines


# --------------------------------------------------------------------------- #
# threads
# --------------------------------------------------------------------------- #


def threads_payload(nodes: list[dict[str, Any]], total: int, more: bool) -> Any:
    return {
        "data": {
            "repository": {
                "pullRequest": {
                    "reviewThreads": {
                        "totalCount": total,
                        "pageInfo": {"hasNextPage": more, "endCursor": "Y3Vyc29y"},
                        "nodes": nodes,
                    }
                }
            }
        }
    }


def test_threads_pass_when_all_resolved() -> None:
    fetcher = FakeFetcher({}, threads_payload([{"isResolved": True}], 1, False))
    ok, lines = gates.gate_threads(fetcher, 1)
    assert ok, lines


def test_threads_fail_on_unresolved() -> None:
    fetcher = FakeFetcher(
        {},
        threads_payload(
            [{"isResolved": False, "path": "lib/a.dart"}, {"isResolved": True}], 2, False
        ),
    )
    ok, lines = gates.gate_threads(fetcher, 1)
    assert not ok
    assert "lib/a.dart" in lines[0]


def test_truncated_thread_page_fails_rather_than_reading_as_none_unresolved() -> None:
    fetcher = FakeFetcher({}, threads_payload([{"isResolved": True}], 140, True))
    ok, lines = gates.gate_threads(fetcher, 1)
    assert not ok, lines
    assert "140" in lines[0] and "Y3Vyc29y" in lines[0]


def test_total_count_beyond_nodes_is_truncation_even_without_the_flag() -> None:
    fetcher = FakeFetcher({}, threads_payload([{"isResolved": True}], 9, False))
    ok, _ = gates.gate_threads(fetcher, 1)
    assert not ok


# --------------------------------------------------------------------------- #
# ci
# --------------------------------------------------------------------------- #


CHECK_RUNS_PATH = f"commits/{HEAD}/check-runs?per_page=100"


def check_runs_page(runs: list[dict[str, Any]], total: int | None = None) -> dict[str, Any]:
    return {"total_count": len(runs) if total is None else total, "check_runs": runs}


def test_ci_reports_failures_on_head() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            CHECK_RUNS_PATH: [
                check_runs_page(
                    [
                        {"name": "checks", "status": "completed", "conclusion": "failure"},
                        {"name": "build", "status": "completed", "conclusion": "success"},
                    ]
                )
            ],
        }
    )
    ok, lines = gates.gate_ci(fetcher, 1)
    assert not ok
    assert "checks" in lines[0]


def test_ci_fails_while_a_check_is_still_running() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            CHECK_RUNS_PATH: [
                check_runs_page([{"name": "build", "status": "in_progress"}])
            ],
        }
    )
    ok, _ = gates.gate_ci(fetcher, 1)
    assert not ok


def test_ci_passes_when_green_and_skipped_counts_as_green() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            CHECK_RUNS_PATH: [
                check_runs_page(
                    [
                        {"name": "checks", "status": "completed", "conclusion": "success"},
                        {"name": "docs", "status": "completed", "conclusion": "skipped"},
                    ]
                )
            ],
        }
    )
    ok, lines = gates.gate_ci(fetcher, 1)
    assert ok, lines


def test_ci_reads_check_runs_across_pages() -> None:
    """A commit with more check runs than fit on one page must have every
    page evaluated, not just the first."""
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            CHECK_RUNS_PATH: [
                check_runs_page(
                    [{"name": "checks", "status": "completed", "conclusion": "success"}],
                    total=2,
                ),
                check_runs_page(
                    [{"name": "build", "status": "completed", "conclusion": "success"}],
                    total=2,
                ),
            ],
        }
    )
    ok, lines = gates.gate_ci(fetcher, 1)
    assert ok, lines
    assert "2 check(s)" in lines[0], lines


def test_ci_fails_when_total_count_exceeds_fetched_runs() -> None:
    """A truncated fetch must fail closed rather than read as green -- the
    bug this gate exists for: a later, unfetched check run can be failing."""
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            CHECK_RUNS_PATH: [
                check_runs_page(
                    [{"name": "checks", "status": "completed", "conclusion": "success"}],
                    total=4,
                )
            ],
        }
    )
    ok, lines = gates.gate_ci(fetcher, 1)
    assert not ok, lines
    assert "4" in lines[0] and "1" in lines[0], lines


def test_ci_requests_max_page_size_and_paginates() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            CHECK_RUNS_PATH: [
                check_runs_page(
                    [{"name": "checks", "status": "completed", "conclusion": "success"}]
                )
            ],
        }
    )
    gates.gate_ci(fetcher, 1)
    assert (CHECK_RUNS_PATH, True) in fetcher.rest_calls, fetcher.rest_calls


# --------------------------------------------------------------------------- #
# closes
# --------------------------------------------------------------------------- #


def closes_payload(
    numbers: list[int],
    branch: str = "docs/agents-split",
    total: int | None = None,
    has_next: bool = False,
) -> Any:
    return {
        "data": {
            "repository": {
                "pullRequest": {
                    "headRefName": branch,
                    "closingIssuesReferences": {
                        "totalCount": len(numbers) if total is None else total,
                        "pageInfo": {
                            "hasNextPage": has_next,
                            "endCursor": "Y3Vyc29yOnYyOpHOAA",
                        },
                        "nodes": [{"number": n} for n in numbers],
                    },
                }
            }
        }
    }


def test_closes_flags_an_unintended_link() -> None:
    """#897: `Does not close #887` created the link the sentence denied."""
    fetcher = FakeFetcher({}, closes_payload([887]))
    ok, lines = gates.gate_closes(fetcher, 1, [])
    assert not ok
    assert "#887" in lines[0]


def test_closes_flags_an_issue_branch_name() -> None:
    """#716: the branch name closed the issue mid-sequence."""
    fetcher = FakeFetcher({}, closes_payload([716], branch="feat/issue-716-part-2"))
    ok, lines = gates.gate_closes(fetcher, 1, [716])
    assert not ok
    assert any("issue-716" in line for line in lines)


def test_closes_flags_a_missing_intended_link() -> None:
    fetcher = FakeFetcher({}, closes_payload([]))
    ok, lines = gates.gate_closes(fetcher, 1, [990])
    assert not ok
    assert "#990" in lines[0]


def test_closes_passes_on_an_exact_match() -> None:
    fetcher = FakeFetcher({}, closes_payload([990]))
    ok, lines = gates.gate_closes(fetcher, 1, [990])
    assert ok, lines


def test_closes_passes_when_nothing_is_closed_and_nothing_intended() -> None:
    fetcher = FakeFetcher({}, closes_payload([]))
    ok, lines = gates.gate_closes(fetcher, 1, [])
    assert ok, lines


def test_truncated_closing_references_fail_rather_than_comparing_a_subset() -> None:
    """A dropped node would read as "closes fewer than intended", or hide an
    unintended link entirely -- neither may pass as an answer."""
    fetcher = FakeFetcher({}, closes_payload([990], total=140, has_next=True))
    ok, lines = gates.gate_closes(fetcher, 1, [990])
    assert not ok, lines
    assert "140" in lines[0] and "Y3Vyc29y" in lines[0]


def test_closes_total_count_beyond_nodes_is_truncation_even_without_the_flag() -> None:
    fetcher = FakeFetcher({}, closes_payload([990], total=9))
    ok, _ = gates.gate_closes(fetcher, 1, [990])
    assert not ok


# --------------------------------------------------------------------------- #
# REST fallback when GraphQL is refused (Claude Code cloud sessions)
# --------------------------------------------------------------------------- #

REFUSED = gates.GraphQLUnavailable(
    "gh api graphql failed: gh: GitHub GraphQL is not available from Claude "
    "Code sessions; use the REST API (HTTP 403)"
)
THREADS_PATH = "pulls/1/ccr/review_threads"


def rest_thread(resolved: bool, path: str = "lib/a.dart") -> dict[str, Any]:
    return {"resolved": resolved, "outdated": False, "path": path, "line": 1}


def test_fetcher_classifies_only_the_graphql_refusal_as_unavailable() -> None:
    fetcher = gates.GitHubFetcher("o/r")

    def refused(args: Any) -> str:
        raise gates.GateError(
            "gh api graphql failed: gh: GitHub GraphQL is not available from "
            "Claude Code sessions; use the REST API (HTTP 403)"
        )

    def rate_limited(args: Any) -> str:
        raise gates.GateError("gh api graphql failed: API rate limit exceeded (HTTP 403)")

    fetcher._gh = refused  # type: ignore[method-assign]
    try:
        fetcher.graphql("q")
    except gates.GraphQLUnavailable:
        pass
    else:
        raise AssertionError("the refusal must be GraphQLUnavailable")

    fetcher._gh = rate_limited  # type: ignore[method-assign]
    try:
        fetcher.graphql("q")
    except gates.GraphQLUnavailable:
        raise AssertionError("a rate limit is not a refusal; it must not fall back")
    except gates.GateError:
        pass


def test_threads_fall_back_to_rest_and_pass_when_all_resolved() -> None:
    fetcher = FakeFetcher({THREADS_PATH: [[rest_thread(True)]]}, REFUSED)
    ok, lines = gates.gate_threads(fetcher, 1)
    assert ok, lines
    assert "via REST" in lines[0]


def test_threads_fall_back_to_rest_and_fail_on_unresolved() -> None:
    fetcher = FakeFetcher(
        {THREADS_PATH: [rest_thread(False, "lib/b.dart"), rest_thread(True)]}, REFUSED
    )
    ok, lines = gates.gate_threads(fetcher, 1)
    assert not ok
    assert "lib/b.dart" in lines[0] and "via REST" in lines[0]


def test_rest_threads_at_the_page_size_cannot_prove_completeness() -> None:
    full = [rest_thread(True)] * gates.REST_THREADS_MAX
    fetcher = FakeFetcher({THREADS_PATH: full}, REFUSED)
    ok, lines = gates.gate_threads(fetcher, 1)
    assert not ok, lines
    assert "truncated" in lines[0]


def test_threads_report_both_failures_when_rest_fails_too() -> None:
    class RestBroken(FakeFetcher):
        def rest(self, path: str, *, paginate: bool = False) -> Any:
            raise gates.GateError("HTTP 404")

    try:
        gates.gate_threads(RestBroken({}, REFUSED), 1)
    except gates.GateError as exc:
        assert "REST fallback also failed" in str(exc) and "HTTP 404" in str(exc)
    else:
        raise AssertionError("an unanswerable gate must raise, not pass")


def test_a_graphql_failure_that_is_not_the_refusal_still_skips() -> None:
    """No weaker REST answer for a transient failure: it stays unanswered."""
    fetcher = FakeFetcher({}, gates.GateError("gh api graphql failed: timeout"))
    try:
        gates.gate_threads(fetcher, 1)
    except gates.GraphQLUnavailable:
        raise AssertionError("a timeout must not trigger the fallback")
    except gates.GateError:
        pass
    assert fetcher.rest_calls == []


def closes_rest(
    body: str = "",
    commits: list[str] | None = None,
    title: str = "A change",
    branch: str = "claude/a-change",
) -> dict[str, Any]:
    return {
        "pulls/1": {"title": title, "body": body, "head": {"ref": branch}},
        "pulls/1/commits": [[{"commit": {"message": m}} for m in (commits or [])]],
    }


def test_closes_fall_back_to_rest_and_pass_on_an_exact_match() -> None:
    fetcher = FakeFetcher(closes_rest(body="Closes #1841.\n\nSupersedes #895."), REFUSED)
    ok, lines = gates.gate_closes(fetcher, 1, [1841])
    assert ok, lines
    assert "closes exactly #1841" in lines[0]
    assert "sidebar" in lines[0], "the weaker evidence must be labelled"


def test_closes_via_rest_flags_a_denial_that_still_links() -> None:
    """#897 again, through the fallback: `Does not close #887` links it."""
    fetcher = FakeFetcher(closes_rest(body="Closes #990. Does not close #887."), REFUSED)
    ok, lines = gates.gate_closes(fetcher, 1, [990])
    assert not ok
    assert "#887" in lines[0]


def test_closes_via_rest_reads_commit_messages_and_the_title() -> None:
    fetcher = FakeFetcher(
        closes_rest(title="Fixes #12", commits=["Resolve: #13", "tidy"]), REFUSED
    )
    ok, lines = gates.gate_closes(fetcher, 1, [12])
    assert not ok
    assert "#13" in lines[0] and "#12" not in lines[0].split("also close")[1]


def test_closes_via_rest_flags_another_repository() -> None:
    fetcher = FakeFetcher(closes_rest(body="Closes other/repo#5"), REFUSED)
    ok, lines = gates.gate_closes(fetcher, 1, [])
    assert not ok
    assert "other/repo#5" in lines[0]


def test_closes_via_rest_counts_a_same_repo_qualified_reference() -> None:
    fetcher = FakeFetcher(
        closes_rest(body="Closes ibanner56/CallersCompendium#7"), REFUSED
    )
    ok, lines = gates.gate_closes(fetcher, 1, [7])
    assert ok, lines


def test_closes_via_rest_flags_a_missing_link_and_an_issue_branch() -> None:
    fetcher = FakeFetcher(closes_rest(body="Mentions #3", branch="feat/issue-716-x"), REFUSED)
    ok, lines = gates.gate_closes(fetcher, 1, [990])
    assert not ok
    assert any("#990" in line for line in lines)
    assert any("issue-716" in line for line in lines)


def test_closes_via_rest_ignores_words_that_merely_contain_a_keyword() -> None:
    fetcher = FakeFetcher(closes_rest(body="A prefixed #4 and disclosed #5"), REFUSED)
    ok, lines = gates.gate_closes(fetcher, 1, [])
    assert ok, lines


def test_run_gates_exits_zero_through_the_fallback() -> None:
    rest = {
        "pulls/1": {
            "head": {"sha": HEAD, "ref": "claude/x"},
            "title": "t",
            "body": "Closes #9",
        },
        "pulls/1/reviews": [[review(REVIEWER, HEAD)]],
        "pulls/1/comments": [[]],
        THREADS_PATH: [rest_thread(True)],
        "pulls/1/commits": [[]],
    }
    printed: list[str] = []
    code = gates.run_gates(
        FakeFetcher(rest, REFUSED), 1, ["closes", "threads", "review"], [9], out=printed.append
    )
    assert code == 0, printed
    assert not any(line.startswith("SKIP") for line in printed), printed


# --------------------------------------------------------------------------- #
# runner
# --------------------------------------------------------------------------- #


def test_run_gates_reports_every_gate_and_exits_non_zero() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            "pulls/1/reviews": [[review(REVIEWER, STALE)]],
            "pulls/1/comments": [[]],
        },
        threads_payload([{"isResolved": True}], 1, False),
    )
    printed: list[str] = []
    code = gates.run_gates(
        fetcher, 1, ["findings", "threads", "review"], [], out=printed.append
    )
    assert code == 1
    assert any(line.startswith("FAIL review:") for line in printed)
    assert any(line.startswith("PASS threads:") for line in printed)


def test_environment_failure_exits_two_rather_than_reporting_a_gate_failure() -> None:
    class Broken:
        def rest(self, path: str, *, paginate: bool = False) -> Any:
            raise gates.GateError("the `gh` CLI is not installed")

    printed: list[str] = []
    code = gates.run_gates(Broken(), 1, ["review"], [], out=printed.append)
    assert code == 2
    assert printed and printed[0].startswith("SKIP review:")


def test_an_unanswerable_gate_does_not_hide_the_answerable_ones() -> None:
    # Reproduces the failure mode where `gh` is missing for one gate's endpoint:
    # returning early left the remaining gates silent, so a run that could have
    # reported a real thread failure printed nothing about it.
    class PartlyBroken:
        def rest(self, path: str, *, paginate: bool = False) -> Any:
            raise gates.GateError("the `gh` CLI is not installed")

        def graphql(self, query: str) -> Any:
            return threads_payload([{"isResolved": False}], 1, False)

    printed: list[str] = []
    code = gates.run_gates(
        PartlyBroken(), 1, ["review", "threads"], [], out=printed.append
    )
    assert code == 2, printed
    assert any(line.startswith("SKIP review:") for line in printed), printed
    assert any(line.startswith("FAIL threads:") for line in printed), printed


def test_cli_requires_explicit_closes_intent() -> None:
    code = gates.main(["closes", "1", "--repo", "o/r"])
    assert code == 2


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} PR-review-gate tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
