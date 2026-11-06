#!/usr/bin/env python3
"""Tests for ``check_claude_workflow_isolation.py``.

The decision is pure (``stowaways``) and tested directly; the git plumbing is
exercised once against a throwaway repository, including the rename case that
``--no-renames`` exists for and the bad-ref case that must not read as OK.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_claude_workflow_isolation.py"
SPEC = importlib.util.spec_from_file_location("check_claude_workflow_isolation", SCRIPT)
assert SPEC and SPEC.loader
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)

REVIEW = ".github/workflows/claude-code-review.yml"
ASSISTANT = ".github/workflows/claude.yml"


def test_no_claude_workflow_passes() -> None:
    assert gate.stowaways(["app/lib/main.dart", ".github/workflows/ci.yml"]) == []


def test_only_the_review_workflow_passes() -> None:
    assert gate.stowaways([REVIEW]) == []


def test_review_workflow_with_another_file_fails() -> None:
    assert gate.stowaways([REVIEW, "docs/x.md"]) == ["docs/x.md"]


def test_the_assistant_workflow_is_not_isolated() -> None:
    """Editing claude.yml leaves the review workflow as on main, so Claude
    still reviews the PR; isolating it would only force needless splits."""
    assert gate.stowaways([ASSISTANT, "docs/x.md"]) == []


def test_every_other_file_is_reported() -> None:
    assert gate.stowaways([REVIEW, "b.py", ASSISTANT, "a.py"]) == [
        ".github/workflows/claude.yml",
        "a.py",
        "b.py",
    ]


def test_other_workflows_are_not_exempt() -> None:
    assert gate.stowaways([REVIEW, ".github/workflows/ci.yml"]) == [
        ".github/workflows/ci.yml"
    ]


OLD = "a" * 40
NEW = "b" * 40


def _pin(sha: str, comment: str = "") -> str:
    return f"        uses: anthropics/claude-code-action@{sha}{comment}"


def _yml(*lines: str) -> bytes:
    return ("\n".join(lines) + "\n").encode("utf-8")


ASSISTANT_BEFORE = _yml("on: issue_comment", "jobs:", _pin(OLD, " # v1.0.266"), "        with: {}")
REVIEW_BEFORE = _yml("jobs:", _pin(OLD, " # v1.0.266"), "      prompt: |", "        Review it.")
REVIEW_AFTER = _yml("jobs:", _pin(NEW, " # v1.0.300"), "      prompt: |", "        Review it.")


def _bump(after: bytes, review: bytes = REVIEW_AFTER) -> bool:
    return gate.is_matching_pin_bump(ASSISTANT_BEFORE, after, REVIEW_BEFORE, review)


def test_a_pin_bump_to_the_review_workflows_pin_rides_along() -> None:
    assert _bump(_yml("on: issue_comment", "jobs:", _pin(NEW, " # v1.0.300"), "        with: {}"))


def test_a_pin_bump_to_another_pin_does_not() -> None:
    assert not _bump(_yml("on: issue_comment", "jobs:", _pin("c" * 40), "        with: {}"))


def test_any_other_changed_line_does_not() -> None:
    assert not _bump(_yml("on: issue_comment", "jobs:", _pin(NEW), "        with: {x: 1}"))
    # A line moved to another action, even one pinned by SHA, is not a pin of
    # this action.
    assert not _bump(
        _yml("on: issue_comment", "jobs:", "        uses: someone/else@" + NEW, "        with: {}")
    )


def test_an_added_or_dropped_line_does_not() -> None:
    assert not _bump(_yml("on: issue_comment", "jobs:", _pin(NEW), _pin(NEW), "        with: {}"))
    assert not _bump(_yml("on: issue_comment", "jobs:", "        with: {}"))
    assert not _bump(ASSISTANT_BEFORE), "a file that does not change is no bump"


def test_a_yaml_line_break_git_does_not_see_hides_nothing() -> None:
    """YAML breaks lines on a lone CR and on NEL, LS and PS; git does not, so
    each could carry a whole step inside what git calls one pin line."""
    for brk in ["\r", "\r\n", "\u0085", "\u2028", "\u2029", "\x0b", "\x0c"]:
        smuggled = _pin(NEW, " # v1.0.300") + brk + "      - uses: evil/exfil@" + NEW
        after = _yml("on: issue_comment", "jobs:", smuggled, "        with: {}")
        assert not _bump(after), repr(brk)
    # Inside the comment, too.
    after = _yml("on: issue_comment", "jobs:", _pin(NEW, " # v1\r  run: x"), "        with: {}")
    assert not _bump(after)


def test_the_review_workflows_own_change_must_be_a_pin_only_bump() -> None:
    """A pin-shaped line it does not run cannot vouch for a SHA: not one added
    in a block scalar, nor one left readable while the real pin is rewritten
    so the pattern cannot read it."""
    after = _yml("on: issue_comment", "jobs:", _pin(NEW), "        with: {}")
    in_scalar = _yml(
        "jobs:", _pin(OLD, " # v1.0.266"), "      prompt: |",
        "            uses: anthropics/claude-code-action@" + NEW,
    )
    assert not _bump(after, in_scalar)
    quoted = _yml(
        "jobs:", '        uses: "anthropics/claude-code-action@' + OLD + '"',
        "      prompt: |", "            uses: anthropics/claude-code-action@" + NEW,
    )
    assert not _bump(after, quoted)
    assert not _bump(after, REVIEW_BEFORE), "a review workflow that moves nothing vouches for nothing"
    other_change = _yml("jobs:", _pin(NEW), "      prompt: |", "        Review it twice.")
    assert not _bump(after, other_change)


def test_pin_moves_reports_the_target() -> None:
    assert gate.pin_moves(REVIEW_BEFORE, REVIEW_AFTER) == {NEW.encode()}
    assert gate.pin_moves(REVIEW_BEFORE, REVIEW_BEFORE) == set()
    assert gate.pin_moves(REVIEW_BEFORE, REVIEW_BEFORE + b"x\n") is None


# --------------------------------------------------------------------------- #
# git plumbing, against a scratch repository
# --------------------------------------------------------------------------- #


def _run(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=repo, capture_output=True, text=True)


def _commit(repo: Path, files: dict[str, str | None], message: str) -> str:
    for rel, content in files.items():
        path = repo / rel
        if content is None:
            _run(repo, "git", "rm", "-q", rel)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        _run(repo, "git", "add", rel)
    _run(repo, "git", "commit", "-q", "-m", message)
    return _run(repo, "git", "rev-parse", "HEAD").stdout.strip()


def _gate(repo: Path, base: str, head: str) -> subprocess.CompletedProcess:
    return _run(repo, sys.executable, str(SCRIPT), base, head)


def test_against_a_real_repository() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        _run(repo, "git", "init", "-q")
        _run(repo, "git", "config", "user.email", "t@example.invalid")
        _run(repo, "git", "config", "user.name", "t")
        _run(repo, "git", "config", "commit.gpgsign", "false")
        base = _commit(repo, {REVIEW: "a\n", "README": "r\n"}, "base")

        only_workflow = _commit(repo, {REVIEW: "b\n"}, "workflow only")
        res = _gate(repo, base, only_workflow)
        assert res.returncode == 0, res.stdout + res.stderr

        mixed = _commit(repo, {"README": "s\n"}, "plus another file")
        res = _gate(repo, base, mixed)
        assert res.returncode == 1, res.stdout + res.stderr
        assert "README" in res.stdout, res.stdout

        # Renaming the workflow away is a change to it; without --no-renames
        # git would report only the new name and the gate would see no
        # Claude workflow at all.
        _run(repo, "git", "checkout", "-q", base)
        _run(repo, "git", "mv", REVIEW, ".github/workflows/renamed.yml")
        _run(repo, "git", "commit", "-q", "-m", "rename")
        renamed = _run(repo, "git", "rev-parse", "HEAD").stdout.strip()
        res = _gate(repo, base, renamed)
        assert res.returncode == 1, res.stdout + res.stderr
        assert "renamed.yml" in res.stdout, res.stdout

        # A bump of the action moves both workflows' pins: the assistant's
        # rides along when it moves to the review workflow's pin and does
        # nothing else.
        _run(repo, "git", "checkout", "-q", base)
        pinned = _commit(
            repo,
            {REVIEW: _pin(OLD) + "\n", ASSISTANT: "on: x\n" + _pin(OLD) + "\n"},
            "pinned",
        )
        bump = _commit(
            repo,
            {REVIEW: _pin(NEW) + "\n", ASSISTANT: "on: x\n" + _pin(NEW) + "\n"},
            "bump both",
        )
        res = _gate(repo, pinned, bump)
        assert res.returncode == 0, res.stdout + res.stderr

        _run(repo, "git", "checkout", "-q", pinned)
        sneaky = _commit(
            repo,
            {REVIEW: _pin(NEW) + "\n", ASSISTANT: "on: y\n" + _pin(NEW) + "\n"},
            "bump both and change the assistant",
        )
        res = _gate(repo, pinned, sneaky)
        assert res.returncode == 1, res.stdout + res.stderr
        assert ASSISTANT in res.stdout, res.stdout

        # A lone CR is one line to git and two to YAML: the hidden step must
        # not ride along as "only a pin".
        _run(repo, "git", "checkout", "-q", pinned)
        (repo / ASSISTANT).write_bytes(
            ("on: x\n" + _pin(NEW) + "\r      - uses: evil/exfil@" + NEW + "\n").encode()
        )
        (repo / REVIEW).write_text(_pin(NEW) + "\n", encoding="utf-8")
        _run(repo, "git", "add", ASSISTANT, REVIEW)
        _run(repo, "git", "commit", "-q", "-m", "smuggle a step behind a CR")
        smuggled = _run(repo, "git", "rev-parse", "HEAD").stdout.strip()
        res = _gate(repo, pinned, smuggled)
        assert res.returncode == 1, res.stdout + res.stderr

        _run(repo, "git", "checkout", "-q", pinned)
        mismatched = _commit(
            repo,
            {REVIEW: _pin(NEW) + "\n", ASSISTANT: "on: x\n" + _pin("c" * 40) + "\n"},
            "bump to different pins",
        )
        res = _gate(repo, pinned, mismatched)
        assert res.returncode == 1, res.stdout + res.stderr

        _run(repo, "git", "checkout", "-q", renamed)
        unrelated = _commit(repo, {"README": "t\n"}, "unrelated")
        res = _gate(repo, renamed, unrelated)
        assert res.returncode == 0, res.stdout + res.stderr

        res = _gate(repo, "no-such-ref", unrelated)
        assert res.returncode == 2, res.stdout + res.stderr


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} Claude-workflow isolation tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
