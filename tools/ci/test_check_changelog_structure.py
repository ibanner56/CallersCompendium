#!/usr/bin/env python3
"""Offline tests for ``check_changelog_structure.py``.

Every negative case here is a file that renders as perfectly valid Markdown --
that is the point of the gate, and the reason a rendered preview cannot stand in
for it.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_changelog_structure.py"

PREAMBLE = """# Changelog

All notable changes are documented in this file.

### Platforms & install

- Preamble subheadings belong to no release section.

"""


def changelog(*sections: str) -> str:
    return PREAMBLE + "\n".join(sections)


def section(heading: str, *bodies: str) -> str:
    return f"{heading}\n\n" + "".join(bodies)


def category(name: str, *entries: str) -> str:
    return f"### {name}\n\n" + "".join(f"- {entry}\n" for entry in entries) + "\n"


def run(text: str) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "CHANGELOG.md"
        path.write_text(text, encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path)],
            check=False,
            capture_output=True,
            encoding="utf-8",
        )


FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


UNRELEASED = "## [Unreleased]\n\n"
V013 = section("## [0.1.3] - 2026-08-26", category("Fixed", "a fix"))
V012 = section("## [0.1.2] - 2026-08-25", category("Changed", "a change"))
V011 = section("## [0.1.1] - 2026-08-24", category("Added", "an addition"))
BETA9 = section("## [0.1.0-beta.9] - 2026-08-21", category("Fixed", "a beta fix"))
BETA1 = section("## [0.1.0-beta.1] - 2026-07-17", category("Added", "first"))
BETA0 = section("## [0.1.0-beta.0] - 2026-07-10", category("Added", "scaffold"))


def main() -> int:
    FAILURES.clear()

    valid = run(changelog(UNRELEASED, V013, V012, V011, BETA9, BETA1, BETA0))
    check("a well-formed changelog passes", valid.returncode == 0, valid.stderr)

    # The ordering the core changelog actually has: a release outranks every
    # prerelease of the same core, and prerelease counters compare numerically.
    # A naive string sort ranks "0.1.0-beta.9" above "0.1.0-beta.1" correctly but
    # ranks "0.1.0-beta.9" above "0.1.1" wrongly, so this is a real distinction.
    check(
        "0.1.1 outranks 0.1.0-beta.9 and beta.9 outranks beta.0",
        run(changelog(UNRELEASED, V011, BETA9, BETA0)).returncode == 0,
    )

    swapped = run(changelog(UNRELEASED, V012, V013, V011, BETA9, BETA1, BETA0))
    check("a version section out of order fails", swapped.returncode == 1, swapped.stderr)
    check(
        "the ordering error names both versions",
        "[0.1.2] sorts below [0.1.3]" in swapped.stderr,
        swapped.stderr,
    )

    duplicate_version = run(changelog(UNRELEASED, V013, V013, V011))
    check(
        "a repeated version heading fails",
        duplicate_version.returncode == 1,
        duplicate_version.stderr,
    )
    check(
        "a repeated version heading is reported as a duplicate",
        "duplicates [0.1.3]" in duplicate_version.stderr,
        duplicate_version.stderr,
    )

    # A prerelease sorts *below* its release, so a beta listed above the release
    # it precedes is the one ordering mistake a chronological reading invites.
    release_above_prerelease = run(
        changelog(UNRELEASED, section("## [0.1.0] - 2026-08-21", category("Fixed", "x")), BETA9)
    )
    check(
        "0.1.0 may sit above 0.1.0-beta.9",
        release_above_prerelease.returncode == 0,
        release_above_prerelease.stderr,
    )
    prerelease_above_release = run(
        changelog(UNRELEASED, BETA9, section("## [0.1.0] - 2026-07-10", category("Fixed", "x")))
    )
    check(
        "0.1.0-beta.9 above 0.1.0 fails",
        prerelease_above_release.returncode == 1
        and "[0.1.0-beta.9] sorts below [0.1.0]" in prerelease_above_release.stderr,
        prerelease_above_release.stderr,
    )

    repeated_category = run(
        changelog(
            UNRELEASED,
            section(
                "## [0.1.3] - 2026-08-26",
                category("Fixed", "first list"),
                category("Added", "unrelated"),
                category("Fixed", "second list, invisible below the first"),
            ),
        )
    )
    check(
        "a category repeated in one section fails",
        repeated_category.returncode == 1,
        repeated_category.stderr,
    )
    check(
        "the duplicate-category error names the first occurrence",
        "repeats inside '## [0.1.3] - 2026-08-26'" in repeated_category.stderr
        and "first at line" in repeated_category.stderr,
        repeated_category.stderr,
    )

    check(
        "the same category in different sections is fine",
        run(changelog(UNRELEASED, V013, BETA9)).returncode == 0,
    )

    unreleased_duplicate = run(
        changelog(
            section("## [Unreleased]", category("Fixed", "a"), category("Fixed", "b")),
            V013,
        )
    )
    check(
        "a repeated category under [Unreleased] fails",
        unreleased_duplicate.returncode == 1
        and "repeats inside '## [Unreleased]'" in unreleased_duplicate.stderr,
        unreleased_duplicate.stderr,
    )

    # Preamble '###' headings precede every '##' and belong to no section; a
    # boundary bug that attributed them to the first section would fail here.
    check(
        "a preamble subheading repeated in a section is not a duplicate",
        run(
            changelog(
                UNRELEASED,
                section("## [0.1.3] - 2026-08-26", category("Platforms & install", "a")),
            )
        ).returncode
        == 0,
    )

    unparseable = (
        ("## Unreleased", "is not a recognised section heading"),
        ("## [0.1.3]", "is not a recognised section heading"),
        ("## 0.1.3 - 2026-08-26", "is not a recognised section heading"),
        ("## [0.1] - 2026-08-26", "is not a valid semantic version"),
    )
    for heading, expected in unparseable:
        result = run(changelog(UNRELEASED, section(heading, category("Fixed", "x"))))
        check(
            f"unparseable heading {heading!r} fails rather than being skipped",
            result.returncode == 1 and expected in result.stderr,
            result.stderr,
        )

    # The regression this gate was written for: main's core changelog had
    # malformed headings *and* repeated categories. Reporting only the headings
    # would hide the defect that motivated the check.
    both = run(
        changelog(
            section("## Unreleased", category("Fixed", "a"), category("Fixed", "b")),
        )
    )
    check(
        "a malformed heading does not suppress the duplicate-category report",
        both.returncode == 1 and "repeats inside" in both.stderr,
        both.stderr,
    )

    missing = run(changelog(V013, V011))
    check(
        "a changelog with no [Unreleased] fails",
        missing.returncode == 1 and "no '## [Unreleased]' section" in missing.stderr,
        missing.stderr,
    )

    misplaced = run(changelog(V013, UNRELEASED, V011))
    check(
        "[Unreleased] below a version section fails",
        misplaced.returncode == 1 and "must be the first section" in misplaced.stderr,
        misplaced.stderr,
    )

    twice = run(changelog(UNRELEASED, V013, UNRELEASED, V011))
    check(
        "a second [Unreleased] fails",
        twice.returncode == 1 and "appears 2 times" in twice.stderr,
        twice.stderr,
    )

    unreadable = subprocess.run(
        [sys.executable, str(SCRIPT), "no/such/CHANGELOG.md"],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )
    check(
        "an unreadable file exits 2, not 0",
        unreadable.returncode == 2,
        unreadable.stderr,
    )

    repo_root = HERE.parent.parent
    committed = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=repo_root,
        check=False,
        capture_output=True,
        encoding="utf-8",
    )
    check(
        "the repository's own changelogs pass",
        committed.returncode == 0,
        committed.stderr,
    )

    if FAILURES:
        for failure in FAILURES:
            print(f"::error::{failure}")
        print(f"{len(FAILURES)} check(s) failed")
        return 1
    print("OK: all changelog structure gate tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
