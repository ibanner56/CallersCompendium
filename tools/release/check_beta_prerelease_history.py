#!/usr/bin/env python3
"""Reject a bare beta tag whose SemVer core already has another prerelease."""

from __future__ import annotations

import argparse
import re
import sys
from collections.abc import Iterable

_CORE = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
_BARE_BETA_RE = re.compile(rf"^v(?P<core>{_CORE})-beta$")


def conflicting_prerelease_tags(candidate_tag: str, tags: Iterable[str]) -> list[str]:
    """Return non-identical prerelease tags with the candidate's SemVer core."""
    match = _BARE_BETA_RE.fullmatch(candidate_tag)
    if not match:
        raise ValueError(
            f"invalid bare beta tag '{candidate_tag}'; expected vX.Y.Z-beta."
        )
    prefix = f"v{match.group('core')}-"
    return sorted(
        tag
        for tag in tags
        if tag.startswith(prefix) and tag != candidate_tag
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="reject a bare beta core with an existing prerelease tag"
    )
    parser.add_argument("--candidate-tag", required=True)
    args = parser.parse_args()

    try:
        conflicts = conflicting_prerelease_tags(
            args.candidate_tag, (line.strip() for line in sys.stdin)
        )
    except ValueError as error:
        parser.error(str(error))

    if conflicts:
        print(
            "::error::cannot create "
            f"{args.candidate_tag}: its SemVer core already has prerelease tag(s): "
            f"{', '.join(conflicts)}. Choose a newer X.Y.Z core.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
