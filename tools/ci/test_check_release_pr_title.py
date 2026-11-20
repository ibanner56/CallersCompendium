#!/usr/bin/env python3
"""Offline tests for ``check_release_pr_title.py``.

Run directly: ``python3 tools/ci/test_check_release_pr_title.py``.

``judge`` is pure and holds the policy table. The rest drive the real script in
a throwaway repository, because reading the pubspec at two refs and taking the
title from the environment only exist in that integration.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_release_pr_title.py"
sys.path.insert(0, str(HERE))

import check_release_pr_title as gate  # noqa: E402

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(name)
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


GOOD = "docs(release): prepare v0.10.0-beta"

# (title, base, head, passes, why)
TABLE = [
    (GOOD, "0.9.0", "0.10.0", True, "beta title matching the pubspec"),
    ("docs(release): prepare v0.10.0", "0.9.0", "0.10.0", True, "stable title"),
    ("docs(release): prepare v1.0.0", "0.10.0", "1.0.0", True, "stable 1.0.0"),
    ("chore(release): prepare v0.10.0-beta", "0.9.0", "0.10.0", False, "chore prefix"),
    ("docs(release): prepare v0.1.0-beta", "0.1.0", "0.1.1", False, "title version differs from pubspec"),
    ("docs(release): prepare v0.10.0-beta.7", "0.9.0", "0.10.0", False, "counter-suffixed form is rejected"),
    ("docs(release): prepare 0.10.0-beta", "0.9.0", "0.10.0", False, "missing v"),
    ("docs(release): prepare v0.10.0-beta ", "0.9.0", "0.10.0", False, "trailing space (judge is strict; main strips)"),
    ("docs(release): prepare v0.10.0-beta\n", "0.9.0", "0.10.0", False, "trailing newline is not accepted by fullmatch"),
    ("docs(release): prepare v0.10.0-rc", "0.9.0", "0.10.0", False, "only -beta is a release suffix"),
    ("Add a feature", "0.9.0", "0.10.0", False, "ordinary title on a version change"),
    ("docs(release): prepare v0.10.00-beta", "0.9.0", "0.10.0", False, "leading zero"),
    ("Add a feature", "0.10.0", "0.10.0", True, "unchanged version: not a release PR"),
    ("chore(release): oops", "0.10.0", "0.10.0", True, "unchanged version: title not read"),
    ("Add a feature", None, "0.10.0", False, "unreadable base counts as a change"),
]


def git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, check=False)


def commit(root: Path, version: str | None, message: str) -> str:
    pubspec = root / "app" / "pubspec.yaml"
    pubspec.parent.mkdir(parents=True, exist_ok=True)
    if version is not None:
        pubspec.write_text(f"name: app\nversion: {version}\n", encoding="utf-8")
    git(root, "add", "-A")
    git(root, "commit", "-q", "--allow-empty", "-m", message)
    return git(root, "rev-parse", "HEAD").stdout.strip()


def run(root: Path, title: str | None, *refs: str) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if k != "PR_TITLE"}
    if title is not None:
        env["PR_TITLE"] = title
    return subprocess.run([sys.executable, str(SCRIPT), *refs], cwd=root, capture_output=True, text=True, env=env)


def main() -> int:
    for title, base, head, passes, why in TABLE:
        error = gate.judge(title, base, head)
        check(f"judge: {why}", (error is None) == passes, repr(error))
    check("judge: names the example form", "docs(release): prepare v0.10.0-beta" in (gate.judge("x", "0.9.0", "0.10.0") or ""))

    check("pubspec_version reads a core version", gate.pubspec_version("name: a\nversion: 0.10.0\n") == "0.10.0")
    check("pubspec_version rejects a suffixed version", gate.pubspec_version("version: 0.10.0+3\n") is None)

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        git(root, "init", "-q", ".")
        git(root, "config", "user.email", "t@example.invalid")
        git(root, "config", "user.name", "test")
        base = commit(root, "0.9.0", "base")

        # Version bump with the right title / wrong prefix / wrong version.
        git(root, "checkout", "-q", "-b", "release")
        bump = commit(root, "0.10.0", "docs(release): name something else")
        res = run(root, GOOD, base, bump)
        check("e2e: correct title passes", res.returncode == 0, res.stdout + res.stderr)
        res = run(root, "chore(release): prepare v0.10.0-beta", base, bump)
        check("e2e: chore(release) fails", res.returncode == 1, res.stdout + res.stderr)
        res = run(root, "docs(release): prepare v0.1.0-beta", base, bump)
        check("e2e: title version != pubspec fails", res.returncode == 1, res.stdout + res.stderr)
        res = run(root, f"  {GOOD}  ", base, bump)
        check("e2e: surrounding whitespace from the event is stripped", res.returncode == 0, res.stdout + res.stderr)
        res = run(root, "Anything", base, bump)
        check("e2e: commit subjects are not what is judged", res.returncode == 1)

        # No version change: any title passes.
        other = commit(root, None, "unrelated")
        res = run(root, "Add a feature", bump, other)
        check("e2e: no version change passes any title", res.returncode == 0, res.stdout + res.stderr)

        # Cannot decide.
        res = run(root, None, base, bump)
        check("e2e: missing PR_TITLE is exit 2", res.returncode == 2, res.stdout + res.stderr)
        res = run(root, GOOD, "no-such-ref", bump)
        check("e2e: unresolvable base is exit 2", res.returncode == 2, res.stdout + res.stderr)
        res = run(root, GOOD)
        check("e2e: missing base argument is exit 2", res.returncode == 2)
        res = run(root, GOOD, base, "no-such-ref")
        check("e2e: unresolvable head is exit 2", res.returncode == 2, res.stdout + res.stderr)

    if FAILURES:
        print(f"\n{len(FAILURES)} check(s) failed")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
