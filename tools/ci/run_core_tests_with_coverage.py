#!/usr/bin/env python3
"""Run compendium_core tests and produce CI-equivalent LCOV output when tests exist."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE_DIR = REPO_ROOT / "packages" / "compendium_core"
DEFAULT_JOBS = 4


def run(core_dir: Path = CORE_DIR, jobs: int = DEFAULT_JOBS) -> int:
    if not any((core_dir / "test").rglob("*_test.dart")):
        print("No tests yet; skipping coverage.")
        return 0

    coverage_dir = core_dir / "coverage"
    if coverage_dir.exists():
        shutil.rmtree(coverage_dir)

    # which() applies PATHEXT, so Windows resolves the dart.bat shim.
    dart = shutil.which("dart") or "dart"
    # One pass: `dart test` writes the LCOV itself, so there is no separate
    # (and unpinned) `coverage` package to activate and format with.
    command = [dart, "test", "-j", str(jobs), "--coverage-path=coverage/lcov.info"]
    return subprocess.run(command, cwd=core_dir, check=False).returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=DEFAULT_JOBS,
        help=f"concurrent test processes (default {DEFAULT_JOBS})",
    )
    args = parser.parse_args(argv)
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    return run(jobs=args.jobs)


if __name__ == "__main__":
    sys.exit(main())
