#!/usr/bin/env python3
"""Guard: the Linux build legs run on the runner that sets the glibc floor.

The Linux tar.gz and AppImage are not self-contained: glibc, GTK 3 and the
rest of the desktop stack come from the user's system, and every binary
compiled in CI (the runner executable and the plugin ``.so`` files) may require
any glibc up to the one on the machine that built it. Which one it needs moves
with the code and the toolchain headers: a trivial ``strtol`` call compiled on
``ubuntu-24.04`` (glibc 2.39) already needs ``GLIBC_2.38``. Only the build
image bounds it (post-audit finding platform-3).

So the release workflow's Linux leg is pinned to ``ubuntu-22.04`` (glibc
2.35), and that is the minimum the user guide states
(``docs/user/installation.md``). ``ubuntu-latest`` would silently move the
floor up the next time GitHub repoints it (to 26.04, from November 2026). ``ci.yml``'s Linux build leg is
pinned to the same image so main's push build proves the release toolchain
still builds before a tag does.

GitHub has begun deprecating the ``ubuntu-22.04`` image (fully unsupported
from 2027-04-17, actions/runner-images#14254). Keeping the same floor after
that means running the leg in an ``ubuntu:22.04`` container on a newer runner;
this guard then needs to read the job's ``container`` instead.

This walks each workflow's build matrix: it finds the ``include`` entry for
the Linux leg and reads that entry's own ``os`` key, stopping at the next
entry, so an ``os`` belonging to a neighbouring leg is never read as Linux's.
It then checks that the job holding that matrix has ``runs-on: ${{ matrix.os
}}``; a fixed label there would make the pinned ``os`` decorative.

Usage: ``check_linux_build_runner.py`` (no arguments). Exit 0 when every leg
matches, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# The runner image whose glibc is the documented Linux floor. Changing this is
# a support decision: update docs/user/installation.md in the same PR.
LINUX_BUILD_RUNNER = "ubuntu-22.04"

# (workflow path, matrix key naming the leg)
LEGS = (
    (Path(".github/workflows/release.yml"), "platform"),
    (Path(".github/workflows/ci.yml"), "target"),
)

_ENTRY_RE = re.compile(r"^(?P<indent>\s*)-\s+(?P<key>[\w-]+):\s*(?P<value>\S+)\s*$")
_OS_RE = re.compile(r"^(?P<indent>\s*)os:\s*(?P<value>\S+)\s*$")


def linux_leg_runners(text: str, key: str) -> list[str]:
    """Returns the ``os`` of every matrix entry whose first key is
    ``key: linux``, in file order. An entry with no ``os`` yields ``""``."""
    lines = text.splitlines()
    runners: list[str] = []
    for i, line in enumerate(lines):
        entry = _ENTRY_RE.match(line)
        if not entry or entry.group("key") != key:
            continue
        if entry.group("value").strip("'\"") != "linux":
            continue
        # The entry's own keys sit deeper than its "- "; it ends at the first
        # non-blank, non-comment line at or above the dash's indentation.
        dash_indent = len(entry.group("indent"))
        found = ""
        for follow in lines[i + 1 :]:
            stripped = follow.strip()
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(follow) - len(follow.lstrip())
            if indent <= dash_indent:
                break
            os_match = _OS_RE.match(follow)
            if os_match:
                found = os_match.group("value").strip("'\"")
                break
        runners.append(found)
    return runners


_JOB_RE = re.compile(r"^  (?P<job>[\w-]+):\s*(?:#.*)?$")
_RUNS_ON_RE = re.compile(r"^    runs-on:\s*(?P<value>.+?)\s*$")

# The only `runs-on` that puts a job on its matrix entry's `os`.
MATRIX_RUNS_ON = "${{ matrix.os }}"


def linux_leg_job_runs_on(text: str, key: str) -> list[str]:
    """Returns, for every ``key: linux`` matrix entry, the job-level
    ``runs-on`` of the job that holds it (``""`` when the job has none).

    The job is the nearest line above the entry at the two-space indentation
    of a key under ``jobs:``; its body runs until the next line at that
    indentation or shallower. Only a ``runs-on`` at the job's own level (four
    spaces) counts, so one inside a step or a nested map is never read."""
    lines = text.splitlines()
    result: list[str] = []
    for i, line in enumerate(lines):
        entry = _ENTRY_RE.match(line)
        if not entry or entry.group("key") != key:
            continue
        if entry.group("value").strip("'\"") != "linux":
            continue
        start = None
        for j in range(i - 1, -1, -1):
            if _JOB_RE.match(lines[j]):
                start = j
                break
        found = ""
        if start is not None:
            for follow in lines[start + 1 :]:
                stripped = follow.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                if len(follow) - len(follow.lstrip()) <= 2:
                    break
                runs_on = _RUNS_ON_RE.match(follow)
                if runs_on:
                    found = runs_on.group("value").strip("'\"")
                    break
        result.append(found)
    return result


def check(root: Path = REPO_ROOT) -> list[str]:
    errors: list[str] = []
    for rel, key in LEGS:
        path = root / rel
        if not path.is_file():
            errors.append(f"{rel}: missing.")
            continue
        runners = linux_leg_runners(path.read_text(encoding="utf-8"), key)
        if not runners:
            errors.append(f"{rel}: no build matrix entry '- {key}: linux' found.")
        for runner in runners:
            if runner != LINUX_BUILD_RUNNER:
                errors.append(
                    f"{rel}: the Linux build leg runs on '{runner or '(no os)'}', "
                    f"expected '{LINUX_BUILD_RUNNER}'. Its glibc is the minimum "
                    "the shipped Linux binaries need; see "
                    "docs/user/installation.md before changing it."
                )
        for runs_on in linux_leg_job_runs_on(path.read_text(encoding="utf-8"), key):
            if runs_on != MATRIX_RUNS_ON:
                errors.append(
                    f"{rel}: the job holding the Linux build leg has "
                    f"runs-on '{runs_on or '(none)'}', not '{MATRIX_RUNS_ON}', "
                    "so the pinned matrix os does not decide where it builds."
                )
    return errors


def main() -> int:
    errors = check()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print(f"OK: Linux build legs run on {LINUX_BUILD_RUNNER}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
