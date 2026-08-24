#!/usr/bin/env python3
"""Unit tests for the app/pubspec release-version guard."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_app_version as check  # noqa: E402


def _cases() -> None:
    assert check.validate_versions("1.2.3", "1.2.3") is None

    for pubspec_version in (
        "01.2.3",
        "1.02.3",
        "1.2.03",
        "1.2.3+4",
        "1.2.3+",
        "1.2.3+build",
        "1.2.3-beta",
    ):
        assert check.validate_versions("1.2.3", pubspec_version) is not None

    assert check.validate_versions("1.2.3-beta", "1.2.3") is not None
    assert check.validate_versions("1.2.4", "1.2.3") is not None


def main() -> int:
    _cases()
    print("OK: all app version guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
