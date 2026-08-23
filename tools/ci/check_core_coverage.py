#!/usr/bin/env python3
"""Enforce the compendium_core generated-source-excluded 80% coverage floor."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LCOV = REPO_ROOT / "packages" / "compendium_core" / "coverage" / "lcov.info"
FLOOR = 80.0


def coverage_totals(lcov: Path) -> tuple[int, int]:
    lines_found = lines_hit = 0
    skip = False
    for line in lcov.read_text(encoding="utf-8").splitlines():
        if line.startswith("SF:"):
            source = line[3:].strip()
            skip = source.endswith(".g.dart") or source.endswith(".drift.dart")
        elif line.startswith("LF:") and not skip:
            lines_found += int(line[3:])
        elif line.startswith("LH:") and not skip:
            lines_hit += int(line[3:])
    return lines_found, lines_hit


def run(lcov: Path = DEFAULT_LCOV) -> int:
    if not lcov.exists():
        print("No coverage report (no tests?); skipping floor.")
        return 0
    lines_found, lines_hit = coverage_totals(lcov)
    percent = (100.0 * lines_hit / lines_found) if lines_found else 0.0
    print(
        "compendium_core line coverage (generated excluded): "
        f"{percent:.2f}% ({lines_hit}/{lines_found}); floor {FLOOR:.0f}%"
    )
    if percent < FLOOR:
        print(
            f"::error::core coverage {percent:.2f}% is below the "
            f"{FLOOR:.0f}% floor"
        )
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lcov", type=Path, default=DEFAULT_LCOV)
    return run(parser.parse_args().lcov)


if __name__ == "__main__":
    sys.exit(main())
