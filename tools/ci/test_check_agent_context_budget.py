#!/usr/bin/env python3
"""Offline tests for ``check_agent_context_budget.py``.

Each case builds a synthetic tree in a temp dir and asserts the gate's exit
code, so the gate is exercised against a tree that is over budget as well as one
that is within it -- a ratchet that has only ever been seen green is
indistinguishable from one that does nothing.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_agent_context_budget.py"

SCOPED = """\
---
applyTo:
  - "packages/**"
---

# Scoped rules
"""

SCOPED_NO_APPLY_TO = """\
# Scoped rules with no front matter
"""


def run(repo: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(repo)],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )


def build(
    tmp: Path,
    *,
    root_bytes: int,
    scoped: dict[str, str] | None = None,
) -> Path:
    repo = tmp / "repo"
    (repo / ".github" / "instructions").mkdir(parents=True)
    (repo / "AGENTS.md").write_text("x" * root_bytes, encoding="utf-8")
    for name, contents in (scoped or {}).items():
        (repo / ".github" / "instructions" / name).write_text(
            contents, encoding="utf-8"
        )
    return repo


def test_within_budget_passes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(
            Path(tmp),
            root_bytes=4096,
            scoped={"a.instructions.md": SCOPED},
        )
        result = run(repo)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "within budget" in result.stdout


def test_oversized_root_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(Path(tmp), root_bytes=8 * 1024 + 1)
        result = run(repo)
        assert result.returncode == 1, result.stdout + result.stderr
        assert "exceeds the 8192 B resident budget" in result.stdout


def test_oversized_scoped_file_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(
            Path(tmp),
            root_bytes=1024,
            scoped={"big.instructions.md": SCOPED + "y" * (6 * 1024)},
        )
        result = run(repo)
        assert result.returncode == 1, result.stdout + result.stderr
        assert "path-scoped budget" in result.stdout


def test_scoped_file_without_apply_to_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(
            Path(tmp),
            root_bytes=1024,
            scoped={"loose.instructions.md": SCOPED_NO_APPLY_TO},
        )
        result = run(repo)
        assert result.returncode == 1, result.stdout + result.stderr
        assert "applyTo" in result.stdout


def test_missing_root_guide_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        (repo / ".github").mkdir(parents=True)
        result = run(repo)
        assert result.returncode == 1, result.stdout + result.stderr
        assert "missing" in result.stdout


def test_this_repository_is_within_budget() -> None:
    repo = HERE.parent.parent
    result = run(repo)
    assert result.returncode == 0, result.stdout + result.stderr


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} agent-context-budget tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
