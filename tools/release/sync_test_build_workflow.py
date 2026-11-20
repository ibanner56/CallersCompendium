#!/usr/bin/env python3
"""Keep the test-build workflow's build job identical to the release build job.

``.github/workflows/test-build.yml`` packages signed test builds without
releasing them (docs/dev/releasing.md#test-builds-signed-never-released). Its
``build`` job is not written by hand: it is a byte-for-byte copy of the
``build`` job in ``.github/workflows/release.yml``, so a test build is built,
packaged and signed exactly as the release would be. The copy sits between two
marker comments; everything outside the markers is ordinary hand-maintained
YAML (Dependabot can bump its action pins like any other workflow).

Usage:

    python3 tools/release/sync_test_build_workflow.py           # check (exit 1 if stale)
    python3 tools/release/sync_test_build_workflow.py --write   # refresh the copy

Edit the build job in release.yml, never the copy, then run ``--write``.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELEASE_WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
TEST_BUILD_WORKFLOW = ROOT / ".github" / "workflows" / "test-build.yml"

BEGIN_MARKER = (
    "  # >>> BEGIN copy of release.yml's `build` job, written by "
    "tools/release/sync_test_build_workflow.py --write. Do not edit by hand.\n"
)
END_MARKER = "  # <<< END copy of release.yml's `build` job.\n"

_BUILD_HEADING = re.compile(r"^  build:\n", re.MULTILINE)
_JOB_HEADING = re.compile(r"^  [A-Za-z_][A-Za-z0-9_-]*:", re.MULTILINE)


def extract_build_job(release_text: str) -> str:
    """Return release.yml's ``build`` job, heading to last line, newline-terminated.

    The job ends where the next job heading starts. The comment block that
    introduces that next job sits at job-heading indentation just above it, so
    trailing blank lines and two-space comment lines are trimmed back off.
    """
    matches = list(_BUILD_HEADING.finditer(release_text))
    if len(matches) != 1:
        raise ValueError(
            f"release.yml must have exactly one top-level `build:` job, found {len(matches)}"
        )
    start = matches[0].start()
    following = _JOB_HEADING.search(release_text, matches[0].end())
    end = following.start() if following else len(release_text)
    lines = release_text[start:end].splitlines(keepends=True)
    while lines and (not lines[-1].strip() or lines[-1].startswith("  #")):
        lines.pop()
    if len(lines) < 2:
        raise ValueError("release.yml's `build:` job is empty")
    text = "".join(lines)
    return text if text.endswith("\n") else text + "\n"


def _region_bounds(test_build_text: str) -> tuple[int, int]:
    """Character offsets of the text strictly between the two markers."""
    if test_build_text.count(BEGIN_MARKER) != 1 or test_build_text.count(END_MARKER) != 1:
        raise ValueError(
            "test-build.yml must contain each copy marker exactly once:\n"
            f"  {BEGIN_MARKER.strip()}\n  {END_MARKER.strip()}"
        )
    begin = test_build_text.index(BEGIN_MARKER) + len(BEGIN_MARKER)
    end = test_build_text.index(END_MARKER)
    if end < begin:
        raise ValueError("test-build.yml's END marker comes before its BEGIN marker")
    return begin, end


def copied_region(test_build_text: str) -> str:
    begin, end = _region_bounds(test_build_text)
    return test_build_text[begin:end]


def synced(release_text: str, test_build_text: str) -> str:
    """``test_build_text`` with its copy replaced by release.yml's current build job."""
    begin, end = _region_bounds(test_build_text)
    return test_build_text[:begin] + extract_build_job(release_text) + test_build_text[end:]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--write", action="store_true", help="rewrite the copy instead of checking it"
    )
    args = parser.parse_args(argv)

    release_text = RELEASE_WORKFLOW.read_text(encoding="utf-8")
    test_build_text = TEST_BUILD_WORKFLOW.read_text(encoding="utf-8")
    try:
        expected = synced(release_text, test_build_text)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if expected == test_build_text:
        print("test-build.yml's build job matches release.yml's.")
        return 0
    if args.write:
        TEST_BUILD_WORKFLOW.write_text(expected, encoding="utf-8", newline="\n")
        print("Rewrote test-build.yml's build job from release.yml.")
        return 0
    print(
        "error: test-build.yml's build job differs from release.yml's `build` job.\n"
        "Edit release.yml (never the copy), then run:\n"
        "  python3 tools/release/sync_test_build_workflow.py --write",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
