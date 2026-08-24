#!/usr/bin/env python3
"""Derive a collision-free Android versionCode from a permitted release tag.

The release grammar has exactly two channels for each SemVer core:
``vX.Y.Z-beta`` and ``vX.Y.Z``. Components are bounded to three decimal digits,
so radix-1000 packing preserves SemVer core ordering without overflowing Play's
2,100,000,000 versionCode limit. The low bit distinguishes channels: beta is
lower than stable for the same core.
"""

from __future__ import annotations

import argparse
import re
import sys

MAX_COMPONENT = 999
PLAY_VERSION_CODE_LIMIT = 2_100_000_000
_TAG_RE = re.compile(
    r"^v(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?P<beta>-beta)?$"
)


def version_code_for_tag(tag: str) -> int:
    """Return the bounded Play versionCode for a stable or bare-beta tag."""
    match = _TAG_RE.fullmatch(tag)
    if not match:
        raise ValueError(
            f"invalid release tag '{tag}'; expected vX.Y.Z or vX.Y.Z-beta."
        )

    major, minor, patch = (
        int(match.group(component)) for component in ("major", "minor", "patch")
    )
    if max(major, minor, patch) > MAX_COMPONENT:
        raise ValueError(
            "release tag components must be in 0..999 for a collision-free "
            f"Android versionCode, got '{tag}'."
        )

    core = ((major * 1000) + minor) * 1000 + patch
    channel_bit = 0 if match.group("beta") else 1
    code = (core * 2) + channel_bit + 1
    if code >= PLAY_VERSION_CODE_LIMIT:
        raise AssertionError(f"derived Android versionCode exceeds Play limit: {code}")
    return code


def main() -> int:
    parser = argparse.ArgumentParser(
        description="derive a bounded Android versionCode from a release tag"
    )
    parser.add_argument("--tag", required=True, help="vX.Y.Z or vX.Y.Z-beta")
    args = parser.parse_args()
    try:
        print(version_code_for_tag(args.tag))
    except ValueError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    sys.exit(main())
