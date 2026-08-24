#!/usr/bin/env python3
"""Single-source guard: app version constant vs pubspec.

The marketing version is intentionally duplicated in two places:

  * ``kAppVersion`` in ``app/lib/src/app_metadata.dart`` — the in-code source of
    truth surfaced by the in-app About/Licenses screen, and
  * ``version:`` in ``app/pubspec.yaml`` — the release version (``X.Y.Z``).

They must never drift. This guard asserts that both are the same strict SemVer
core (``X.Y.Z``), with no build metadata or prerelease suffix. CI fails on any
mismatch.

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
_CORE_VERSION = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
_CORE_VERSION_RE = re.compile(rf"^{_CORE_VERSION}$")
_PUBSPEC_VERSION_RE = re.compile(
    rf"""^version:\s*(?P<v>{_CORE_VERSION})\s*$""",
    re.MULTILINE,
)


def _fail(msg: str, code: int = 2) -> None:
    # `::error::` renders as an annotation in the GitHub Actions UI.
    print(f"::error::{msg}")
    sys.exit(code)


def validate_versions(app_version: str, pubspec_version: str) -> str | None:
    """Return a format/mismatch error, or None for a valid matching pair."""
    if not _CORE_VERSION_RE.fullmatch(app_version):
        return f"kAppVersion must be a valid X.Y.Z core version, got '{app_version}'."
    if not _CORE_VERSION_RE.fullmatch(pubspec_version):
        return (
            "app/pubspec.yaml version must be valid X.Y.Z with no build metadata "
            "or prerelease suffix, "
            f"got '{pubspec_version}'."
        )
    if app_version != pubspec_version:
        return (
            "app version mismatch: kAppVersion="
            f"'{app_version}' (app/lib/src/app_metadata.dart) != "
            f"'{pubspec_version}' (app/pubspec.yaml). Update both to the same X.Y.Z."
        )
    return None


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
    pubspec_version = p.group("v")

    error = validate_versions(app_version, pubspec_version)
    if error:
        _fail(error, code=1)

    print(
        f"OK: app version single-sourced ('{app_version}' and '{pubspec_version}')."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
