#!/usr/bin/env python3
"""Unit tests for the bounded Android release versionCode encoder."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from android_version_code import (  # noqa: E402
    PLAY_VERSION_CODE_LIMIT,
    version_code_for_tag,
)


def _raises(tag: str) -> None:
    try:
        version_code_for_tag(tag)
    except ValueError:
        return
    raise AssertionError(f"expected invalid tag to fail: {tag}")


def main() -> int:
    assert version_code_for_tag("v0.0.0-beta") == 1
    assert version_code_for_tag("v0.0.0") == 2
    assert version_code_for_tag("v1.2.3-beta") + 1 == version_code_for_tag("v1.2.3")
    assert version_code_for_tag("v0.999.999") < version_code_for_tag("v1.0.0-beta")
    assert version_code_for_tag("v1.0.999") < version_code_for_tag("v1.1.0-beta")
    assert version_code_for_tag("v1.0.0") < version_code_for_tag("v1.0.1-beta")
    assert version_code_for_tag("v999.999.999") == 2_000_000_000
    assert version_code_for_tag("v999.999.999") < PLAY_VERSION_CODE_LIMIT

    for tag in (
        "v01.2.3",
        "v1.02.3",
        "v1.2.03",
        "v1.2.3-beta.1",
        "v1.2.3-rc",
        "v1.2.3+4",
        "v1000.0.0",
        "v0.1000.0",
        "v0.0.1000",
    ):
        _raises(tag)

    print("OK: Android versionCode encoding is bounded and channel ordered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
