#!/usr/bin/env python3
"""Offline tests for compendium_core coverage-floor calculation."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_core_coverage import coverage_totals, run  # noqa: E402


def write_lcov(root: Path, content: str) -> Path:
    lcov = root / "lcov.info"
    lcov.write_text(content, encoding="utf-8")
    return lcov


def test_generated_sources_do_not_count_toward_floor() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        lcov = write_lcov(
            Path(temporary),
            "SF:lib/real.dart\nLF:10\nLH:8\n"
            "SF:lib/generated.g.dart\nLF:100\nLH:0\n"
            "SF:lib/db.drift.dart\nLF:100\nLH:0\n",
        )
        assert coverage_totals(lcov) == (10, 8)
        assert run(lcov) == 0


def test_below_floor_fails() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        lcov = write_lcov(Path(temporary), "SF:lib/real.dart\nLF:10\nLH:7\n")
        assert run(lcov) == 1


def test_missing_report_matches_ci_skip() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        assert run(Path(temporary) / "missing.info") == 0


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} core-coverage tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
