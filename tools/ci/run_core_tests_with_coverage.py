#!/usr/bin/env python3
"""Run compendium_core tests and produce CI-equivalent LCOV output when tests exist."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE_DIR = REPO_ROOT / "packages" / "compendium_core"


def run(core_dir: Path = CORE_DIR) -> int:
    if not any((core_dir / "test").rglob("*_test.dart")):
        print("No tests yet; skipping coverage.")
        return 0

    coverage_dir = core_dir / "coverage"
    if coverage_dir.exists():
        shutil.rmtree(coverage_dir)

    commands = (
        ["dart", "test", "--coverage=coverage"],
        ["dart", "pub", "global", "activate", "coverage"],
        [
            "dart",
            "pub",
            "global",
            "run",
            "coverage:format_coverage",
            "--lcov",
            "--in=coverage",
            "--out=coverage/lcov.info",
            "--report-on=lib",
            "--packages=../../.dart_tool/package_config.json",
        ],
    )
    for command in commands:
        result = subprocess.run(command, cwd=core_dir, check=False)
        if result.returncode:
            return result.returncode
    return 0


if __name__ == "__main__":
    sys.exit(run())
