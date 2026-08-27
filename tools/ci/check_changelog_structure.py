#!/usr/bin/env python3
"""Structural gate for the two hand-maintained CHANGELOGs.

``app/CHANGELOG.md`` and ``packages/compendium_core/CHANGELOG.md`` are written
by hand, read by ``tools/release/gen_release_notes.py``, and drained at release
time *as written*. Two structural mistakes are invisible to every other gate and
to a rendered preview, because both of them render as valid Markdown:

**A repeated category inside one version section.** Appending a second
``### Fixed`` to a section that already has one produces two separate lists under
two identical headings. Nothing is lost from the file, but a reader -- and the
release notes -- see the first list and stop, so entries added to the second one
are effectively invisible. This is not hypothetical: ``compendium_core``'s
``## Unreleased`` on ``main`` accumulated three ``### Fixed`` blocks and two
``### Changed`` blocks before anyone noticed.

**A version heading out of order.** The notes generator resolves a section by
SemVer core and is happy to find one anywhere in the file, so a section inserted
at the wrong depth -- or numbered below the one beneath it -- renders correctly
under the wrong banner. Requiring strict descent makes the file's order the same
order SemVer would compute, which is the property every reader already assumes.

Ordering is by SemVer precedence, prereleases included, so
``0.1.1 > 0.1.0-beta.9 > 0.1.0-beta.1 > 0.1.0-beta.0`` holds and equal versions
fail: a duplicate heading is an ordering violation, not a special case.

A ``##`` heading this tool cannot parse is an **error**, never a skip. A heading
that is silently ignored is a heading that is not checked, which is the failure
mode this gate exists to remove.

Usage:
    check_changelog_structure.py [path ...]

With no arguments it checks both changelogs, relative to the current directory.
Exit codes: 0 = OK, 1 = structural violation, 2 = usage / unreadable file.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

DEFAULT_CHANGELOGS = (
    Path("app/CHANGELOG.md"),
    Path("packages/compendium_core/CHANGELOG.md"),
)

UNRELEASED_HEADING = "## [Unreleased]"

# "## [0.1.0-beta.9] - 2026-08-21". The date is required so that a section can
# never be dateless; ``## [Unreleased]`` is matched separately, before this.
VERSION_HEADING = re.compile(r"^## \[(?P<version>[^\]]+)\] - (?P<date>\d{4}-\d{2}-\d{2})$")

SEMVER = re.compile(
    r"^(?P<major>0|[1-9]\d*)"
    r"\.(?P<minor>0|[1-9]\d*)"
    r"\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+(?P<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)

NUMERIC_IDENTIFIER = re.compile(r"^(?:0|[1-9]\d*)$")


def precedence(version: str) -> tuple:
    """Return a sort key implementing SemVer 2.0.0 precedence.

    Build metadata is ignored, per spec. A version with no prerelease outranks
    the same core with one, so ``0.1.0`` sorts above ``0.1.0-beta.9``; among
    prereleases, numeric identifiers compare numerically and rank below
    alphanumeric ones.
    """
    match = SEMVER.match(version)
    if match is None:
        raise ValueError(f"{version!r} is not a valid semantic version")
    core = (int(match["major"]), int(match["minor"]), int(match["patch"]))
    prerelease = match["prerelease"]
    if prerelease is None:
        # 1 outranks the 0 given to any prerelease of the same core.
        return (core, 1, ())
    identifiers = []
    for identifier in prerelease.split("."):
        if NUMERIC_IDENTIFIER.match(identifier):
            identifiers.append((0, int(identifier), ""))
        else:
            identifiers.append((1, 0, identifier))
    return (core, 0, tuple(identifiers))


@dataclass(frozen=True)
class Heading:
    line: int
    text: str
    version: str | None


def _headings(text: str) -> tuple[list[Heading], list[str]]:
    """Split ``text`` into ``##`` sections, reporting unparseable headings."""
    headings: list[Heading] = []
    errors: list[str] = []
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.startswith("## "):
            continue
        stripped = line.rstrip()
        if stripped == UNRELEASED_HEADING:
            headings.append(Heading(number, stripped, None))
            continue
        match = VERSION_HEADING.match(stripped)
        if match is None:
            errors.append(
                f"line {number}: {stripped!r} is not a recognised section "
                f"heading. Expected '{UNRELEASED_HEADING}' or "
                f"'## [X.Y.Z] - YYYY-MM-DD'."
            )
            continue
        version = match["version"]
        try:
            precedence(version)
        except ValueError:
            errors.append(
                f"line {number}: {version!r} in {stripped!r} is not a valid "
                f"semantic version."
            )
            continue
        headings.append(Heading(number, stripped, version))
    return headings, errors


def _check_unreleased(headings: list[Heading]) -> list[str]:
    positions = [h for h in headings if h.version is None]
    if not positions:
        return [
            f"no '{UNRELEASED_HEADING}' section. Contributors write there and "
            f"release prep drains it; without it, entries have nowhere to go."
        ]
    if len(positions) > 1:
        lines = ", ".join(str(h.line) for h in positions)
        return [f"'{UNRELEASED_HEADING}' appears {len(positions)} times (lines {lines})."]
    if headings[0] is not positions[0]:
        return [
            f"'{UNRELEASED_HEADING}' is at line {positions[0].line}, below "
            f"{headings[0].text!r} at line {headings[0].line}. It must be the "
            f"first section."
        ]
    return []


def _check_ordering(headings: list[Heading]) -> list[str]:
    errors: list[str] = []
    versioned = [h for h in headings if h.version is not None]
    for newer, older in zip(versioned, versioned[1:]):
        if precedence(newer.version) > precedence(older.version):
            continue
        relation = "duplicates" if newer.version == older.version else "sorts below"
        errors.append(
            f"line {newer.line}: [{newer.version}] {relation} [{older.version}] "
            f"at line {older.line}, but appears above it. Version sections must "
            f"descend by semantic version."
        )
    return errors


def _check_duplicate_categories(text: str) -> list[str]:
    """Flag a ``###`` repeated inside one ``##`` section.

    This works off raw ``##`` lines rather than parsed headings, so it still
    reports on a file whose headings are malformed -- which is precisely the
    file that motivated the check.

    Content above the first ``##`` is preamble -- ``app/CHANGELOG.md``'s
    '### Platforms & install' lives there -- and belongs to no release, so it is
    not part of any section's categories.
    """
    errors: list[str] = []
    section: str | None = None
    seen: dict[str, int] = {}

    for number, line in enumerate(text.splitlines(), start=1):
        if line.startswith("## "):
            seen.clear()
            section = line.rstrip()
            continue
        if section is None or not line.startswith("### "):
            continue
        category = line.rstrip()
        first = seen.get(category)
        if first is None:
            seen[category] = number
            continue
        errors.append(
            f"line {number}: {category!r} repeats inside {section!r} "
            f"(first at line {first}). A category may appear once per section; "
            f"a second one renders as a separate list and hides the first."
        )
    return errors


def validate(text: str) -> list[str]:
    headings, errors = _headings(text)
    # Ordering and section membership are meaningless while a heading is
    # unparseable, so those two checks are skipped -- but duplicate categories
    # need only the ``##`` boundaries, which survive a malformed heading, so
    # that check always runs and the report is never narrower than it can be.
    if not errors:
        errors.extend(_check_unreleased(headings))
        errors.extend(_check_ordering(headings))
    errors.extend(_check_duplicate_categories(text))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "changelogs",
        nargs="*",
        type=Path,
        default=list(DEFAULT_CHANGELOGS),
        help="changelogs to check (default: the app and compendium_core ones)",
    )
    args = parser.parse_args(argv)
    changelogs = args.changelogs or list(DEFAULT_CHANGELOGS)

    failed = False
    for changelog in changelogs:
        try:
            text = changelog.read_text(encoding="utf-8")
        except OSError as error:
            print(f"::error::{error}", file=sys.stderr)
            return 2
        for message in validate(text):
            failed = True
            print(f"::error file={changelog}::{changelog}: {message}", file=sys.stderr)
    if failed:
        return 1
    print(
        "OK: "
        + ", ".join(str(changelog) for changelog in changelogs)
        + " — version sections descend by semantic version and no category "
        "repeats within a section."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
