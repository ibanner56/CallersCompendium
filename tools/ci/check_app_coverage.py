#!/usr/bin/env python3
"""Enforce the Flutter app's line-coverage floor, generated sources excluded.

``CONTRIBUTING.md`` ("Testing expectations") asks for comprehensive tests. Only
``compendium_core`` had a floor (``check_core_coverage.py``); this is the app's.
It reads ``app/coverage/lcov.info`` as ``flutter test --coverage`` writes it.

It is shaped after the core gate and deliberately differs from it in the places
where the core gate fails open:

- A **missing report is exit 2**, never a skip. The core gate prints "skipping
  floor" and passes when the file is absent, so a CI step that stopped producing
  coverage would pass for ever. Here, no report means the floor was not
  measured, and the gate says so. (A machine without the Flutter SDK skips the
  *step* in ``tools/preflight.py``, visibly, instead; this script never skips.)
- An **empty report is exit 2**, never 100%. After generated sources are
  excluded there must be at least one instrumented line; zero is a report that
  measured nothing, not a perfect one.
- A **malformed or truncated report is exit 2** and names the line. A record
  that never reaches ``end_of_record`` (a killed test run) would otherwise be
  counted as if it were complete.

Percentages are compared as exact fractions, so a report exactly at the floor
passes and one a hundredth of a point below it does not, whatever floating
point would have rounded to.

**What is excluded, and why:** ``lib/l10n/`` holds only Dart that ``flutter
gen-l10n`` writes from the ARB files (``app/l10n.yaml``): thousands of generated
getters that no test is meant to cover. An exemption by directory is by name; it
is not a loosened pattern, and any other path counts.

**What this cannot see:** ``flutter test --coverage`` reports only files a test
loads. A source file that no test imports is absent from the report, not at 0%,
so the measured percentage overstates the share of the whole tree. The floor is
a ratchet on what is measured, not a claim about the unmeasured.

Usage:
    check_app_coverage.py [--lcov PATH] [--floor PERCENT]

Exit codes: 0 = at or above the floor, 1 = below it, 2 = the floor could not be
measured (missing, empty, malformed or unreadable report).
"""

from __future__ import annotations

import argparse
import re
import sys
from fractions import Fraction
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LCOV = REPO_ROOT / "app" / "coverage" / "lcov.info"

# Line coverage of `flutter test --coverage` in app/, generated l10n excluded.
# Set in #2258 from a measured baseline of 92.91% (50,941 of 54,831 lines, 8,106
# tests), with about three points of headroom so ordinary churn does not flip the
# gate. Raise it when the measured number rises; do not lower it to land a change.
FLOOR = "90"

# Dart that `flutter gen-l10n` writes (app/l10n.yaml: output next to the ARBs).
EXCLUDED_DIR = "lib/l10n/"

DA = re.compile(r"^DA:(\d+),(\d+)(?:,[^,]*)?$")


class Unmeasurable(Exception):
    """The floor could not be measured; the message says why."""


def _normal(source: str) -> str:
    return source.strip().replace("\\", "/")


def is_excluded(source: str) -> bool:
    path = _normal(source)
    return path.startswith(EXCLUDED_DIR) or f"/{EXCLUDED_DIR}" in path


def coverage_totals(text: str) -> tuple[int, int]:
    """``(instrumented, hit)`` line counts over every non-excluded source."""
    found = hit = 0
    source: str | None = None
    skip = False
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("SF:"):
            if source is not None:
                raise Unmeasurable(f"line {number}: record for {source!r} has no end_of_record")
            source = line[3:]
            if not source.strip():
                raise Unmeasurable(f"line {number}: SF: with no path")
            skip = is_excluded(source)
        elif line == "end_of_record":
            if source is None:
                raise Unmeasurable(f"line {number}: end_of_record with no SF:")
            source = None
        elif line.startswith("DA:"):
            if source is None:
                raise Unmeasurable(f"line {number}: DA: outside a record")
            match = DA.match(line)
            if match is None:
                raise Unmeasurable(f"line {number}: malformed DA record {line!r}")
            if not skip:
                found += 1
                if int(match.group(2)) > 0:
                    hit += 1
    if source is not None:
        raise Unmeasurable(f"report ends inside the record for {source!r} (truncated?)")
    return found, hit


def measure(lcov: Path) -> tuple[int, int]:
    if not lcov.exists():
        raise Unmeasurable(
            f"no coverage report at {lcov}. The floor was not measured; run "
            "`flutter test --coverage` in app/ first (tools/ci/run_app_tests_with_coverage.py)."
        )
    try:
        text = lcov.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise Unmeasurable(f"cannot read {lcov}: {error}") from error
    found, hit = coverage_totals(text)
    if found == 0:
        raise Unmeasurable(
            f"{lcov} has no instrumented lines outside {EXCLUDED_DIR}; an empty "
            "report is not 100% covered, it measured nothing."
        )
    return found, hit


def run(lcov: Path = DEFAULT_LCOV, floor: str = FLOOR) -> int:
    try:
        threshold = Fraction(floor)
    except (ValueError, ZeroDivisionError):
        print(f"::error::coverage floor {floor!r} is not a number")
        return 2
    try:
        found, hit = measure(lcov)
    except Unmeasurable as error:
        print(f"::error::app coverage unmeasured: {error}")
        return 2
    percent = Fraction(100 * hit, found)
    print(
        "app line coverage (generated l10n excluded): "
        f"{float(percent):.2f}% ({hit}/{found}); floor {float(threshold):.2f}%"
    )
    if percent < threshold:
        print(
            f"::error::app coverage is below the floor: {float(threshold):.2f}% "
            f"required, {float(percent):.2f}% measured "
            f"(short by {float(threshold - percent):.2f} points, "
            f"{-(-threshold * found // 100) - hit} more covered line(s))."
        )
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lcov", type=Path, default=DEFAULT_LCOV)
    parser.add_argument("--floor", default=FLOOR, help="percent; defaults to the repository's floor")
    args = parser.parse_args(argv)
    return run(args.lcov, args.floor)


if __name__ == "__main__":
    sys.exit(main())
