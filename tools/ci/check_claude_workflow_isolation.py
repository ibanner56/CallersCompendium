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

One companion change may ride along: when the review workflow's whole change
moves its ``anthropics/claude-code-action`` pin to one commit, ``claude.yml``
moving its pin to that same commit and changing nothing else. Both workflows pin the same action, so
every bump of it (Dependabot's included) touches both files, and splitting it
would leave the two on different versions between PRs. That change carries no
content the review workflow's own does not, so it adds nothing that escapes
review. Any other change to ``claude.yml`` makes it a stowaway as before.

The two versions of ``claude.yml`` are compared as bytes, line by line, split
on ``\n`` only -- never as a parsed diff. YAML also breaks lines on a lone CR
and on NEL/LS/PS, which git does not, so a diff line could carry a whole
hidden step; here every line must be byte-identical except pin lines, whose
optional trailing comment may hold printable ASCII only.

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

import re
import subprocess
import sys
from typing import Iterable

REVIEW_WORKFLOW = ".github/workflows/claude-code-review.yml"
CLAUDE_WORKFLOWS = frozenset({REVIEW_WORKFLOW})
ASSISTANT_WORKFLOW = ".github/workflows/claude.yml"

# A whole `uses:` line pinning the action to a full commit SHA, with an
# optional trailing comment (Dependabot writes the version there). Bytes, and
# spaces, tabs and printable ASCII only: anything YAML might read as a line
# break (CR, NEL, LS, PS) fails the match.
_ACTION_PIN = re.compile(
    rb"[ \t]*(?:-[ \t]+)?uses:[ \t]*anthropics/claude-code-action@([0-9a-f]{40})"
    rb"(?:[ \t]+#[ -~]*)?[ \t]*"
)


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


def pin_moves(before: bytes, after: bytes) -> set[bytes] | None:
    """The SHAs the action's pin lines move to from [before] to [after], or
    ``None`` unless that is the only change.

    Every line of [after] must equal the same line of [before], except pin
    lines that were pins before and are pins after (compared as bytes, split on
    ``\\n`` only). An unchanged file moves nothing: the empty set.
    """
    old_lines = before.split(b"\n")
    new_lines = after.split(b"\n")
    if len(old_lines) != len(new_lines):
        return None
    moved: set[bytes] = set()
    for old, new in zip(old_lines, new_lines):
        if old == new:
            continue
        old_pin = _ACTION_PIN.fullmatch(old)
        new_pin = _ACTION_PIN.fullmatch(new)
        if not old_pin or not new_pin:
            return None
        moved.add(new_pin.group(1))
    return moved


def is_matching_pin_bump(
    before: bytes,
    after: bytes,
    review_before: bytes,
    review_after: bytes,
) -> bool:
    """Whether ``claude.yml`` going from [before] to [after] only moves the
    action's pin, to the one SHA the review workflow's own pin-only bump
    ([review_before] to [review_after]) moves to.

    The review workflow's change must be a pin-only bump too. Its pin lines on
    the base branch are real step pins, reviewed when they landed; a change
    that rewrites one so the pattern cannot read it, or adds a pin-shaped line
    in a block scalar, is no pin-only bump, so it cannot vouch for a SHA the
    workflow does not run.
    """
    review_moves = pin_moves(review_before, review_after)
    if not review_moves or len(review_moves) != 1:
        return False
    moves = pin_moves(before, after)
    return bool(moves) and moves == review_moves


def _blob(ref: str, path: str) -> bytes | None:
    res = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True)
    return res.stdout if res.returncode == 0 else None


def _assistant_bumps_with_review(base: str, head: str) -> bool:
    merge_base = _git("merge-base", base, head)
    if merge_base.returncode != 0:
        return False
    fork = merge_base.stdout.strip()
    before = _blob(fork, ASSISTANT_WORKFLOW)
    after = _blob(head, ASSISTANT_WORKFLOW)
    review_before = _blob(fork, REVIEW_WORKFLOW)
    review_after = _blob(head, REVIEW_WORKFLOW)
    if None in (before, after, review_before, review_after):
        return False
    return is_matching_pin_bump(before, after, review_before, review_after)


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        _fail("usage: check_claude_workflow_isolation.py <base_ref> [head_ref]")
    base = argv[1]
    head = argv[2] if len(argv) == 3 else "HEAD"
    _require_commit(base)
    _require_commit(head)

    changed = changed_paths(base, head)
    others = stowaways(changed)
    pin_rides_along = (
        ASSISTANT_WORKFLOW in others and _assistant_bumps_with_review(base, head)
    )
    if pin_rides_along:
        others.remove(ASSISTANT_WORKFLOW)
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

    if pin_rides_along:
        print(
            "OK: only the Claude review workflow changed, and "
            f"{ASSISTANT_WORKFLOW} moves its action pin to the same commit"
        )
    elif set(changed) & CLAUDE_WORKFLOWS:
        print("OK: only the Claude review workflow changed")
    else:
        print("OK: the Claude review workflow is unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
