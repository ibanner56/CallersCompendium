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


def test_only_claude_workflows_pass() -> None:
    assert gate.stowaways([REVIEW]) == []
    assert gate.stowaways([ASSISTANT]) == []
    assert gate.stowaways([REVIEW, ASSISTANT]) == []


def test_each_claude_workflow_with_another_file_fails() -> None:
    for workflow in (REVIEW, ASSISTANT):
        assert gate.stowaways([workflow, "docs/x.md"]) == ["docs/x.md"], workflow


def test_every_other_file_is_reported() -> None:
    assert gate.stowaways([REVIEW, "b.py", ASSISTANT, "a.py"]) == ["a.py", "b.py"]


def test_other_workflows_are_not_exempt() -> None:
    assert gate.stowaways([REVIEW, ".github/workflows/ci.yml"]) == [
        ".github/workflows/ci.yml"
    ]


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
