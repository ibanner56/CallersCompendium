#!/usr/bin/env python3
"""Validate and extract the codename carried by an annotated release tag."""

from __future__ import annotations

import argparse
import re
import sys

_PREFIX = "Release codename:"
_MAX_LENGTH = 80
_INVALID = re.compile(r"[\x00-\x1f\x7f]")


def validate_codename(codename: str) -> str:
    """Return a normalized codename or raise ValueError."""
    value = codename.strip()
    if not value:
        raise ValueError("release codename must not be empty")
    if len(value) > _MAX_LENGTH:
        raise ValueError(f"release codename must be {_MAX_LENGTH} characters or fewer")
    if _INVALID.search(value):
        raise ValueError("release codename must not contain control characters")
    return value


def extract_codename(tag_message: str) -> str | None:
    """Extract ``Release codename: ...`` from an annotated tag message."""
    matches = [
        line[len(_PREFIX) :].strip()
        for line in tag_message.splitlines()
        if line.startswith(_PREFIX)
    ]
    if not matches:
        return None
    if len(matches) != 1:
        raise ValueError("annotated tag must contain exactly one release codename")
    return validate_codename(matches[0])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--tag-message",
        action="store_true",
        help="read an annotated tag message from stdin and print its codename",
    )
    parser.add_argument(
        "--validate",
        metavar="CODENAME",
        help="validate and print a codename",
    )
    args = parser.parse_args(argv)
    if args.tag_message == bool(args.validate):
        parser.error("choose exactly one of --tag-message or --validate")

    try:
        codename = (
            extract_codename(sys.stdin.read())
            if args.tag_message
            else validate_codename(args.validate)
        )
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    if codename is not None:
        print(codename)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
