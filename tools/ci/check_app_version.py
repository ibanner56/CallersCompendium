#!/usr/bin/env python3
"""Single-source guard: app version constant vs pubspec.

The marketing version is intentionally duplicated in two places:

  * ``kAppVersion`` in ``app/lib/src/app_metadata.dart`` — the in-code source of
    truth surfaced by the in-app About/Licenses screen, and
  * ``version:`` in ``app/pubspec.yaml`` — the build/store version (``X.Y.Z+build``).

They must never drift. This guard asserts that ``kAppVersion`` equals the
semver (``X.Y.Z``) portion of the pubspec ``version:`` (the ``+build`` suffix is
ignored). CI fails on any mismatch.

Exit codes: 0 = match, 1 = mismatch, 2 = could not parse an input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METADATA = REPO_ROOT / "app" / "lib" / "src" / "app_metadata.dart"
PUBSPEC = REPO_ROOT / "app" / "pubspec.yaml"

_APP_VERSION_RE = re.compile(
    r"""const\s+String\s+kAppVersion\s*=\s*(['"])(?P<v>[^'"]+)\1\s*;"""
)
# pubspec `version:` — capture the leading semver, dropping any +build suffix.
_PUBSPEC_VERSION_RE = re.compile(
    r"""^version:\s*(?P<v>\d+\.\d+\.\d+)(?:\+\S+)?\s*$""",
    re.MULTILINE,
)


def _fail(msg: str, code: int = 2) -> None:
    # `::error::` renders as an annotation in the GitHub Actions UI.
    print(f"::error::{msg}")
    sys.exit(code)


def main() -> int:
    if not METADATA.is_file():
        _fail(f"missing file: {METADATA}")
    if not PUBSPEC.is_file():
        _fail(f"missing file: {PUBSPEC}")

    m = _APP_VERSION_RE.search(METADATA.read_text(encoding="utf-8"))
    if not m:
        _fail(f"could not find `kAppVersion` in {METADATA}")
    app_version = m.group("v")

    p = _PUBSPEC_VERSION_RE.search(PUBSPEC.read_text(encoding="utf-8"))
    if not p:
        _fail(f"could not find a semver `version:` in {PUBSPEC}")
    pubspec_semver = p.group("v")

    if app_version != pubspec_semver:
        _fail(
            "app version mismatch: kAppVersion="
            f"'{app_version}' (app/lib/src/app_metadata.dart) != "
            f"'{pubspec_semver}' (semver of version: in app/pubspec.yaml). "
            "Update both to the same X.Y.Z.",
            code=1,
        )

    print(
        f"OK: app version single-sourced ('{app_version}' in both "
        "app_metadata.dart and pubspec.yaml)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
