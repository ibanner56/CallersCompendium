#!/usr/bin/env python3
"""Run the Flutter app's tests with coverage, for ``check_app_coverage.py``.

Deletes a stale ``app/coverage/`` first, as ``run_core_tests_with_coverage.py``
does. A report left by an earlier run would otherwise satisfy the floor check
when this run died before writing its own (``flutter test`` exits non-zero then,
but a caller that ignored the status would read the old file).

Usage:
    run_app_tests_with_coverage.py [-j JOBS]

Needs ``flutter`` on PATH (``fvm exec`` supplies the pinned one locally; the CI
job's flutter-action supplies it there). Exits with ``flutter test``'s status.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
APP_DIR = REPO_ROOT / "app"
DEFAULT_JOBS = 4


def run(app_dir: Path = APP_DIR, jobs: int = DEFAULT_JOBS, runner=subprocess.run) -> int:
    coverage_dir = app_dir / "coverage"
    if coverage_dir.exists():
        shutil.rmtree(coverage_dir)
    # which() applies PATHEXT, so Windows resolves the flutter.bat shim.
    flutter = shutil.which("flutter") or "flutter"
    command = [flutter, "test", f"--concurrency={jobs}", "--coverage"]
    return runner(command, cwd=app_dir, check=False).returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-j", "--jobs", type=int, default=DEFAULT_JOBS, help=f"test concurrency (default {DEFAULT_JOBS})")
    args = parser.parse_args(argv)
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    return run(jobs=args.jobs)


if __name__ == "__main__":
    sys.exit(main())
