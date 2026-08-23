#!/usr/bin/env python3
"""Fail when committed localizations differ from current ARB-generated output."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def run(root: Path = REPO_ROOT) -> int:
    """Regenerate l10n and report any uncommitted generated-source drift."""
    app = root / "app"
    generated = subprocess.run(
        ["flutter", "gen-l10n"],
        cwd=app,
        check=False,
    )
    if generated.returncode:
        return generated.returncode

    status = subprocess.run(
        ["git", "status", "--porcelain", "--", "lib/l10n"],
        cwd=app,
        check=False,
        capture_output=True,
        text=True,
    )
    if status.returncode:
        return status.returncode
    if not status.stdout.strip():
        print("OK: committed localizations match the ARB-generated output.")
        return 0

    print("::error::Committed localizations are out of date with the ARB files.")
    print("Run 'flutter gen-l10n' in app/ and commit lib/l10n.")
    print(status.stdout, end="")
    subprocess.run(["git", "--no-pager", "diff", "--", "lib/l10n"], cwd=app, check=False)
    return 1


if __name__ == "__main__":
    sys.exit(run())
