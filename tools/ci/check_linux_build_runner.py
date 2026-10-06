#!/usr/bin/env python3
"""Guard: the Linux build legs run on the runner that sets the glibc floor.

The Linux tar.gz and AppImage are not self-contained: glibc, GTK 3 and the
rest of the desktop stack come from the user's system, and every binary
compiled in CI (the runner executable and the plugin ``.so`` files) requires
the glibc version of the machine that built it. Building on ``ubuntu-24.04``
(glibc 2.39) produced binaries that need ``GLIBC_2.38`` and refuse to start on
Ubuntu 22.04, Debian 12 or RHEL 9 (post-audit finding platform-3).

So the release workflow's Linux leg is pinned to ``ubuntu-22.04`` (glibc
2.35), and that is the minimum the user guide states
(``docs/user/installation.md``). ``ubuntu-latest`` would silently move the
floor up the next time GitHub repoints it. ``ci.yml``'s Linux build leg is
pinned to the same image so main's push build proves the release toolchain
still builds before a tag does.

This walks each workflow's build matrix: it finds the ``include`` entry for
the Linux leg and reads that entry's own ``os`` key, stopping at the next
entry, so an ``os`` belonging to a neighbouring leg is never read as Linux's.

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
