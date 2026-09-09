#!/usr/bin/env python3
"""Unit tests for ``resolve_release_codename.py``."""

from __future__ import annotations

import contextlib
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import resolve_release_codename as c  # noqa: E402


def main() -> None:
    assert c.extract_codename("Release 0.3.0\n\nRelease codename: Autumn Waltz\n") == (
        "Autumn Waltz"
    )
    assert c.extract_codename("Release codename:  First Light  ") == "First Light"
    assert c.extract_codename("Release 0.2.0\n") is None

    for invalid in ("", "   ", "bad\nname", "x" * 81):
        try:
            c.validate_codename(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"expected invalid codename: {invalid!r}")

    try:
        c.extract_codename("Release codename: One\nRelease codename: Two")
    except ValueError:
        pass
    else:
        raise AssertionError("duplicate codenames must fail")

    try:
        c.main(["--tag-message", "--validate", "Two"])
    except SystemExit:
        pass
    else:
        raise AssertionError("mutually exclusive CLI modes must fail")

    with contextlib.redirect_stderr(io.StringIO()):
        assert c.main(["--validate", ""]) == 1

    print("release codename tooling: OK")


if __name__ == "__main__":
    main()
