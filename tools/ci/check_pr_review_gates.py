#!/usr/bin/env python3
"""Merge-readiness gates for a pull request, as a script instead of a procedure.

Every check here used to be a paragraph of prose in ``AGENTS.md`` that an agent
had to remember, re-read every turn, and execute by hand -- which is the most
expensive possible way to enforce a rule and the easiest to get subtly wrong.
Each subcommand encodes one of those rules, including the traps that made the
hand-rolled versions read as PASS when they should have failed:

``findings``    Review findings, including the ``Suppressed comments`` blocks
                that ``GET /pulls/<N>/comments``, thread state and the inline
                comment count are all blind to. Reads every page of review
                bodies, every round.
``review``      Review freshness, filtered by *reviewer identity* rather than
                ``.[-1].commit_id`` -- author replies are recorded as review
                entries and carry the new head SHA, so the naive read matches
                head while the actual review sits on a superseded commit.
``threads``     Unresolved review threads, asking for ``totalCount`` so a
                page-size truncation is visible instead of reading as "none
                unresolved".
``ci``          Check runs on the commit being merged, not on a superseded one.
``closes``      ``closingIssuesReferences`` versus the issues you *intend* to
                close -- a branch name or a sentence like "does not close #887"
                can create a link on its own.
``all``         All of the above. Every gate runs even when an earlier one
                fails, so one invocation reports the whole picture rather than
                costing a round trip per gate.

Output is one line per gate: ``PASS <gate>: <evidence>`` or
``FAIL <gate>: <what is wrong>``. A red run should cost a few hundred tokens to
act on, not a few thousand to read.

Requires the ``gh`` CLI, authenticated. Network access is confined to
``GitHubFetcher``; the gate logic is pure and is exercised offline by
``test_check_pr_review_gates.py``.

Exit codes: 0 = all requested gates pass, 1 = a gate failed, 2 = bad input or
the environment could not answer (missing ``gh``, no repository).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from typing import Any, Callable, Iterable, Sequence

REVIEWER_LOGIN = "copilot-pull-request-reviewer[bot]"
# The same reviewer is reported under a different login by the comments
# endpoint. Carrying the /reviews login to /comments yields a silent zero, which
# reads as "no inline findings" rather than "filter matched nothing".
REVIEWER_COMMENT_LOGIN = "Copilot"

SUPPRESSED_BLOCK = re.compile(
    r"<details>\s*<summary>\s*Suppressed comments?\s*\((\d+)\)\s*</summary>(.*?)</details>",
    re.IGNORECASE | re.DOTALL,
)


class GateError(RuntimeError):
    """The environment could not answer the question (exit 2, not a failure)."""


# --------------------------------------------------------------------------- #
# Fetching
# --------------------------------------------------------------------------- #


class GitHubFetcher:
    """The only part of this module that touches the network."""

    def __init__(self, repo: str) -> None:
        self.repo = repo

    def _gh(self, args: Sequence[str]) -> str:
        try:
            result = subprocess.run(
                ["gh", *args],
                check=False,
                capture_output=True,
                encoding="utf-8",
            )
        except FileNotFoundError as exc:  # pragma: no cover - environment
            raise GateError("the `gh` CLI is not installed") from exc
        if result.returncode != 0:
            raise GateError(
                f"gh {' '.join(args)} failed: {result.stderr.strip().splitlines()[-1:] or ['(no output)']}"
            )
        return result.stdout

    def rest(self, path: str, *, paginate: bool = False) -> Any:
        args = ["api"]
        if paginate:
            # --slurp wraps each page in an outer array so nothing is dropped
            # when a PR has more than one page of reviews.
            args += ["--paginate", "--slurp"]
        args.append(f"repos/{self.repo}/{path}")
        return json.loads(self._gh(args))

    def graphql(self, query: str) -> Any:
        owner, _, name = self.repo.partition("/")
        return json.loads(
            self._gh(
                [
                    "api",
                    "graphql",
                    "-f",
                    f"query={query}",
                    "-F",
                    f"owner={owner}",
                    "-F",
                    f"name={name}",
                ]
            )
        )


def detect_repo() -> str:
    try:
        result = subprocess.run(
            ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
            check=False,
            capture_output=True,
            encoding="utf-8",
        )
    except FileNotFoundError as exc:
        raise GateError("the `gh` CLI is not installed; pass --repo owner/name") from exc
    if result.returncode != 0 or not result.stdout.strip():
        raise GateError("could not detect the repository; pass --repo owner/name")
    return result.stdout.strip()


# --------------------------------------------------------------------------- #
# Gate logic (pure; every input arrives through `fetcher`)
# --------------------------------------------------------------------------- #


def _flatten_pages(payload: Any) -> list[Any]:
    """`--slurp` yields a list of pages; a single page yields a bare list."""
    if not isinstance(payload, list):
        return []
    if payload and all(isinstance(page, list) for page in payload):
        return [item for page in payload for item in page]
    return list(payload)


def _reviews(fetcher: Any, pr: int) -> list[dict[str, Any]]:
    return [
        review
        for review in _flatten_pages(fetcher.rest(f"pulls/{pr}/reviews", paginate=True))
        if isinstance(review, dict)
    ]


def gate_findings(fetcher: Any, pr: int) -> tuple[bool, list[str]]:
    """Report review findings, including every suppressed block, every round."""
    reviews = [r for r in _reviews(fetcher, pr) if _login(r) == REVIEWER_LOGIN]
    inline = [
        c
        for c in _flatten_pages(fetcher.rest(f"pulls/{pr}/comments", paginate=True))
        if isinstance(c, dict) and _login(c) == REVIEWER_COMMENT_LOGIN
    ]

    lines: list[str] = []
    suppressed_total = 0
    for index, review in enumerate(reviews, start=1):
        body = review.get("body") or ""
        for match in SUPPRESSED_BLOCK.finditer(body):
            claimed = int(match.group(1))
            suppressed_total += claimed
            for finding in _suppressed_findings(match.group(2)):
                lines.append(f"  round {index} [suppressed] {finding}")

    for comment in inline:
        path = comment.get("path", "?")
        line = comment.get("line") or comment.get("original_line") or "?"
        lines.append(f"  inline {path}:{line} {_first_line(comment.get('body'))}")

    summary = (
        f"{len(reviews)} round(s) by {REVIEWER_LOGIN}; "
        f"{len(inline)} inline finding(s); {suppressed_total} suppressed"
    )
    if reviews and suppressed_total == 0 and not inline:
        summary += " (a zero here is a claim about the query as much as the PR)"
    return True, [summary, *lines]


def _suppressed_findings(block: str) -> list[str]:
    findings: list[str] = []
    for raw in block.splitlines():
        text = raw.strip()
        if not text or text.startswith(("<", "|---", "```")):
            continue
        findings.append(re.sub(r"\s+", " ", text)[:200])
    return findings


def _first_line(body: str | None) -> str:
    return re.sub(r"\s+", " ", (body or "").strip())[:160] or "(empty)"


def _login(entry: dict[str, Any]) -> str:
    user = entry.get("user") or {}
    return user.get("login", "") if isinstance(user, dict) else ""


def gate_review(fetcher: Any, pr: int) -> tuple[bool, list[str]]:
    """The reviewer's latest review must be on the commit being merged."""
    head = _head_sha(fetcher, pr)
    reviewed = [r for r in _reviews(fetcher, pr) if _login(r) == REVIEWER_LOGIN]
    if not reviewed:
        return False, [f"no review by {REVIEWER_LOGIN} (an unreviewed PR fails closed)"]
    latest = reviewed[-1].get("commit_id") or ""
    if latest != head:
        return False, [
            f"reviewed {latest[:8] or '(none)'}, head is {head[:8]} "
            f"-- re-request a review on the current head"
        ]
    return True, [f"reviewed at head {head[:8]} ({len(reviewed)} round(s))"]


def _head_sha(fetcher: Any, pr: int) -> str:
    payload = fetcher.rest(f"pulls/{pr}")
    head = payload.get("head") if isinstance(payload, dict) else None
    sha = head.get("sha") if isinstance(head, dict) else None
    if not sha:
        raise GateError(f"could not read the head SHA of PR #{pr}")
    return sha


THREADS_QUERY = """
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: %d) {
      reviewThreads(first: 100) {
        totalCount
        pageInfo { hasNextPage endCursor }
        nodes { isResolved isOutdated path }
      }
    }
  }
}
"""


def gate_threads(fetcher: Any, pr: int) -> tuple[bool, list[str]]:
    """No unresolved review threads -- and prove the page was not truncated."""
    payload = fetcher.graphql(THREADS_QUERY % pr)
    threads = _dig(payload, "data", "repository", "pullRequest", "reviewThreads")
    if threads is None:
        raise GateError(f"could not read review threads for PR #{pr}")
    nodes = threads.get("nodes") or []
    total = threads.get("totalCount", len(nodes))
    truncated = bool(_dig(threads, "pageInfo", "hasNextPage")) or total > len(nodes)
    unresolved = [n for n in nodes if not n.get("isResolved")]
    if truncated:
        return False, [
            f"{total} thread(s) but only {len(nodes)} fetched -- page with "
            f"after: \"{_dig(threads, 'pageInfo', 'endCursor')}\" before concluding"
        ]
    if unresolved:
        paths = ", ".join(sorted({n.get("path") or "?" for n in unresolved})[:5])
        return False, [f"{len(unresolved)} of {total} thread(s) unresolved: {paths}"]
    return True, [f"0 of {total} thread(s) unresolved"]


def gate_ci(fetcher: Any, pr: int) -> tuple[bool, list[str]]:
    """Checks must be green on the head commit, not on a superseded one."""
    head = _head_sha(fetcher, pr)
    payload = fetcher.rest(f"commits/{head}/check-runs")
    runs = payload.get("check_runs", []) if isinstance(payload, dict) else []
    if not runs:
        return False, [f"no check runs on head {head[:8]} (has CI started?)"]
    pending = [r for r in runs if r.get("status") != "completed"]
    failed = [
        r
        for r in runs
        if r.get("status") == "completed"
        and r.get("conclusion") not in ("success", "neutral", "skipped")
    ]
    if pending:
        names = ", ".join(sorted(r.get("name", "?") for r in pending)[:5])
        return False, [f"{len(pending)} check(s) still running on {head[:8]}: {names}"]
    if failed:
        names = ", ".join(sorted(r.get("name", "?") for r in failed)[:5])
        return False, [f"{len(failed)} check(s) failing on {head[:8]}: {names}"]
    return True, [f"{len(runs)} check(s) green on head {head[:8]}"]


CLOSES_QUERY = """
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: %d) {
      headRefName
      closingIssuesReferences(first: 100) {
        totalCount
        nodes { number }
      }
    }
  }
}
"""


def gate_closes(fetcher: Any, pr: int, intended: Iterable[int]) -> tuple[bool, list[str]]:
    """The PR must close exactly the issues you named -- no more, no fewer."""
    payload = fetcher.graphql(CLOSES_QUERY % pr)
    pull = _dig(payload, "data", "repository", "pullRequest")
    if pull is None:
        raise GateError(f"could not read closing references for PR #{pr}")
    refs = pull.get("closingIssuesReferences") or {}
    actual = {n["number"] for n in (refs.get("nodes") or []) if "number" in n}
    expected = set(intended)

    problems: list[str] = []
    unexpected = sorted(actual - expected)
    missing = sorted(expected - actual)
    if unexpected:
        problems.append(
            "will also close "
            + ", ".join(f"#{n}" for n in unexpected)
            + " -- check the branch name and any sentence containing a closing "
            "verb next to the number (a denial still links)"
        )
    if missing:
        problems.append("will NOT close " + ", ".join(f"#{n}" for n in missing))

    branch = pull.get("headRefName") or ""
    if re.search(r"issue-\d+", branch):
        problems.append(
            f"branch name {branch!r} contains issue-<N>, which creates a closing "
            "link on its own"
        )

    if problems:
        return False, problems
    listed = ", ".join(f"#{n}" for n in sorted(actual)) or "nothing"
    return True, [f"closes exactly {listed}"]


def _dig(payload: Any, *keys: str) -> Any:
    for key in keys:
        if not isinstance(payload, dict):
            return None
        payload = payload.get(key)
    return payload


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

GATES: dict[str, Callable[..., tuple[bool, list[str]]]] = {
    "findings": gate_findings,
    "review": gate_review,
    "threads": gate_threads,
    "ci": gate_ci,
    "closes": gate_closes,
}

# `closes` runs first: it is the cheapest and the only one whose failure is
# unrecoverable after a merge.
ALL_ORDER = ("closes", "findings", "threads", "review", "ci")


def run_gates(
    fetcher: Any,
    pr: int,
    names: Sequence[str],
    intended: Sequence[int],
    *,
    out: Callable[[str], None] = print,
) -> int:
    failed = 0
    for name in names:
        gate = GATES[name]
        try:
            ok, lines = (
                gate(fetcher, pr, intended) if name == "closes" else gate(fetcher, pr)
            )
        except GateError as exc:
            out(f"SKIP {name}: {exc}")
            return 2
        head, *rest = lines or ["(no detail)"]
        out(f"{'PASS' if ok else 'FAIL'} {name}: {head}")
        for line in rest:
            out(line)
        if not ok:
            failed += 1
    return 1 if failed else 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("gate", choices=[*GATES, "all"])
    parser.add_argument("pr", type=int, help="pull request number")
    parser.add_argument(
        "--closes",
        type=int,
        nargs="*",
        default=None,
        metavar="ISSUE",
        help=(
            "issue numbers this PR is INTENDED to close; pass it with no "
            "numbers to assert the PR closes nothing"
        ),
    )
    parser.add_argument("--repo", help="owner/name (default: detected via gh)")
    args = parser.parse_args(argv)

    names = list(ALL_ORDER) if args.gate == "all" else [args.gate]
    if "closes" in names and args.closes is None:
        # Defaulting to "closes nothing" would silently pass a PR that closes
        # an issue by branch name, which is the failure this gate exists for.
        print(
            "SKIP closes: pass --closes with the intended issue numbers "
            "(--closes with no numbers asserts the PR closes nothing)"
        )
        return 2

    try:
        repo = args.repo or detect_repo()
    except GateError as exc:
        print(f"SKIP: {exc}")
        return 2

    return run_gates(GitHubFetcher(repo), args.pr, names, args.closes or [])


if __name__ == "__main__":
    sys.exit(main())
