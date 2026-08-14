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


def test_ci_reports_failures_on_head() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            f"commits/{HEAD}/check-runs": {
                "check_runs": [
                    {"name": "checks", "status": "completed", "conclusion": "failure"},
                    {"name": "build", "status": "completed", "conclusion": "success"},
                ]
            },
        }
    )
    ok, lines = gates.gate_ci(fetcher, 1)
    assert not ok
    assert "checks" in lines[0]


def test_ci_fails_while_a_check_is_still_running() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            f"commits/{HEAD}/check-runs": {
                "check_runs": [{"name": "build", "status": "in_progress"}]
            },
        }
    )
    ok, _ = gates.gate_ci(fetcher, 1)
    assert not ok


def test_ci_passes_when_green_and_skipped_counts_as_green() -> None:
    fetcher = FakeFetcher(
        {
            "pulls/1": pull(),
            f"commits/{HEAD}/check-runs": {
                "check_runs": [
                    {"name": "checks", "status": "completed", "conclusion": "success"},
                    {"name": "docs", "status": "completed", "conclusion": "skipped"},
                ]
            },
        }
    )
    ok, lines = gates.gate_ci(fetcher, 1)
    assert ok, lines


# --------------------------------------------------------------------------- #
# closes
# --------------------------------------------------------------------------- #


def closes_payload(numbers: list[int], branch: str = "docs/agents-split") -> Any:
    return {
        "data": {
            "repository": {
                "pullRequest": {
                    "headRefName": branch,
                    "closingIssuesReferences": {
                        "totalCount": len(numbers),
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
