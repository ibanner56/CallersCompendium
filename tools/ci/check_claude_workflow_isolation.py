#!/usr/bin/env python3
"""Claude-workflow isolation gate: a PR that edits the review workflow edits nothing else.

``anthropics/claude-code-action`` refuses to run when the workflow file invoking
it differs from the default branch's copy -- and the job still reports success.
So a PR that touches ``claude-code-review.yml`` is the one kind of PR Claude
explicitly refuses to review, and any other file riding along in it escapes
review without anything turning red.

This gate keeps that blind spot to the workflow file itself: if a PR changes
it, that must be its only change. Everything else lands in a PR Claude can
review.

``claude.yml`` (the ``@claude`` assistant) is deliberately not covered. The
action's validation is a token exchange that presents only the running job's
OIDC token, so it checks the workflow that invoked it: a PR editing
``claude.yml`` is reviewed by an unchanged ``claude-code-review.yml``.

The diff is the whole PR (``<base>...<head>``, i.e. against the merge base), not
an incremental range, and uses ``--no-renames`` so that renaming a workflow
counts as removing it -- which is a change to it.

Usage:
    check_claude_workflow_isolation.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD``. Exit codes: 0 = OK (the review workflow
unchanged, or the only change), 1 = the review workflow changed alongside other files, 2 = usage / git error, including a ref that does not
resolve to a commit -- which must never be mistaken for "nothing to check".
"""

from __future__ import annotations

import subprocess
import sys
from typing import Iterable

CLAUDE_WORKFLOWS = frozenset({".github/workflows/claude-code-review.yml"})


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}")
    sys.exit(code)


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], capture_output=True, text=True)


def _require_commit(ref: str) -> None:
    res = _git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if res.returncode != 0 or not res.stdout.strip():
        _fail(
            f"ref {ref!r} does not resolve to a commit. Ensure full history is "
            "fetched (checkout fetch-depth: 0) and that the ref is correct; "
            "refusing to run the Claude-workflow isolation gate against an "
            "unknown ref."
        )


def changed_paths(base: str, head: str) -> list[str]:
    res = _git("diff", "--name-only", "--no-renames", f"{base}...{head}")
    if res.returncode != 0:
        _fail(f"git diff {base}...{head} failed: {res.stderr.strip()}")
    return [line for line in res.stdout.splitlines() if line]


def stowaways(changed: Iterable[str]) -> list[str]:
    """Files that would escape Claude's review, or [] if none would.

    Non-empty only when the change touches the review workflow *and* something
    else; the something-else is what is returned.
    """
    changed = set(changed)
    if not changed & CLAUDE_WORKFLOWS:
        return []
    return sorted(changed - CLAUDE_WORKFLOWS)


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        _fail("usage: check_claude_workflow_isolation.py <base_ref> [head_ref]")
    base = argv[1]
    head = argv[2] if len(argv) == 3 else "HEAD"
    _require_commit(base)
    _require_commit(head)

    changed = changed_paths(base, head)
    others = stowaways(changed)
    if others:
        touched = ", ".join(sorted(set(changed) & CLAUDE_WORKFLOWS))
        print(
            f"::error::This PR changes {touched} together with {len(others)} "
            "other file(s). Claude refuses to review a PR whose review workflow "
            "differs from main's, so those files would merge unreviewed. Move "
            "the workflow change into a PR of its own. "
            "See docs/dev/agents/code-review.md#requesting-a-claude-review."
        )
        for path in others:
            print(f"  {path}")
        return 1

    if set(changed) & CLAUDE_WORKFLOWS:
        print("OK: only the Claude review workflow changed")
    else:
        print("OK: the Claude review workflow is unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
