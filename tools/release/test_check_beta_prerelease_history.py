#!/usr/bin/env python3
"""Unit tests for the bare-beta prerelease-history guard."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_beta_prerelease_history import (  # noqa: E402
    conflicting_prerelease_tags,
)


def _raises(candidate: str) -> None:
    try:
        conflicting_prerelease_tags(candidate, ())
    except ValueError:
        return
    raise AssertionError(f"expected invalid candidate to fail: {candidate}")


def main() -> int:
    assert conflicting_prerelease_tags(
        "v0.1.0-beta",
        ("v0.1.0-beta", "v0.1.0", "v0.1.1-beta.1"),
    ) == []
    assert conflicting_prerelease_tags(
        "v0.1.0-beta",
        (
            "v0.1.0-beta.9",
            "v0.1.0-alpha",
            "v0.1.0-beta.1",
            "v0.1.0",
        ),
    ) == ["v0.1.0-alpha", "v0.1.0-beta.1", "v0.1.0-beta.9"]

    for candidate in ("v0.1.0", "v0.1.0-beta.1", "v01.1.0-beta"):
        _raises(candidate)

    print("OK: bare beta prerelease-history guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
