#!/usr/bin/env python3
"""Single-source guard: app version constant, pubspec, and issue-form hints.

The marketing version is intentionally duplicated in two places:

  * ``kAppVersion`` in ``app/lib/src/app_metadata.dart`` — the in-code source of
    truth surfaced by the in-app About/Licenses screen, and
  * ``version:`` in ``app/pubspec.yaml`` — the release version (``X.Y.Z``).
  * explicit build-version literals in ``.github/ISSUE_TEMPLATE/*.yml`` and
    ``*.yaml`` — static defaults and hints presented to issue reporters.

They must never drift. GitHub issue forms are static YAML: they cannot resolve a
release tag or the app pubspec when a user opens an issue. The release workflow
already requires the tag's ``X.Y.Z`` core to equal the pubspec, so matching every
literal template version to the pubspec makes the reported build version match
the latest release once that release is tagged, without making a release-prep PR
fail while it is preparing the next version.

This guard asserts that the app constant and pubspec are the same strict SemVer
core (``X.Y.Z``), with no build metadata or prerelease suffix, and that every
explicit SemVer literal in an issue-form YAML file equals that version. CI fails
on any mismatch.

Exit codes: 0 = match, 1 = mismatch, 2 = could not parse an input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
METADATA = REPO_ROOT / "app" / "lib" / "src" / "app_metadata.dart"
PUBSPEC = REPO_ROOT / "app" / "pubspec.yaml"
ISSUE_TEMPLATE_DIRECTORY = REPO_ROOT / ".github" / "ISSUE_TEMPLATE"

_APP_VERSION_RE = re.compile(
    r"""const\s+String\s+kAppVersion\s*=\s*(['"])(?P<v>[^'"]+)\1\s*;"""
)
_CORE_VERSION = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
_CORE_VERSION_RE = re.compile(rf"^{_CORE_VERSION}$")
_PUBSPEC_VERSION_RE = re.compile(
    rf"""^version:\s*(?P<v>{_CORE_VERSION})\s*$""",
    re.MULTILINE,
)
_TEMPLATE_VERSION_RE = re.compile(
    rf"(?<![0-9A-Za-z.-])(?P<v>v?{_CORE_VERSION}"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)(?![0-9A-Za-z-]|(?:\.\d))"
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


def validate_issue_template_versions(
    template: Path, text: str, app_version: str
) -> list[str]:
    """Return mismatched explicit SemVer literals in one issue-form template.

    Matching every explicit literal, rather than only a particular ``app-version``
    field, prevents a copied hint, placeholder, or newly added form from drifting
    silently. Generic placeholders such as ``X.Y.Z`` are not SemVer literals and
    are intentionally outside this check.
    """
    errors: list[str] = []
    for match in _TEMPLATE_VERSION_RE.finditer(text):
        found = match.group("v")
        if found != app_version:
            line = text.count("\n", 0, match.start()) + 1
            errors.append(
                f"{template}:{line}: build-version literal '{found}' must match "
                f"app/pubspec.yaml version '{app_version}'."
            )
    return errors


def _issue_templates() -> list[Path]:
    """Return YAML issue forms, excluding non-form files such as config.yml."""
    if not ISSUE_TEMPLATE_DIRECTORY.is_dir():
        _fail(f"missing directory: {ISSUE_TEMPLATE_DIRECTORY}")
    return sorted(
        path
        for pattern in ("*.yml", "*.yaml")
        for path in ISSUE_TEMPLATE_DIRECTORY.glob(pattern)
        if path.name != "config.yml"
    )


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

    template_errors: list[str] = []
    for template in _issue_templates():
        try:
            template_text = template.read_text(encoding="utf-8")
        except OSError as error:
            _fail(str(error))
        template_errors.extend(
            validate_issue_template_versions(template, template_text, app_version)
        )
    if template_errors:
        for error in template_errors:
            print(f"::error::{error}")
        sys.exit(1)

    print(
        "OK: app version single-sourced "
        f"('{app_version}', '{pubspec_version}', and issue-template hints)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
