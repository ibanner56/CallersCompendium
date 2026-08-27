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

    template = Path(".github/ISSUE_TEMPLATE/bug_report.yml")
    assert check.validate_issue_template_versions(
        template,
        'description: "Running 1.2.3."\nvalue: "1.2.3"\n',
        "1.2.3",
    ) == []
    assert check.validate_issue_template_versions(
        template,
        'description: "Running 1.2.2."\nvalue: "1.2.2"\n',
        "1.2.3",
    ) == [
        ".github/ISSUE_TEMPLATE/bug_report.yml:1: build-version literal '1.2.2' "
        "must match app/pubspec.yaml version '1.2.3'.",
        ".github/ISSUE_TEMPLATE/bug_report.yml:2: build-version literal '1.2.2' "
        "must match app/pubspec.yaml version '1.2.3'.",
    ]
    # Prefixes and prerelease/build suffixes are literals too: the issue form
    # asks for the app build version, which is always the bare pubspec X.Y.Z.
    for version in ("v1.2.3", "1.2.3-beta", "1.2.3+4"):
        errors = check.validate_issue_template_versions(
            template, f'value: "{version}"\n', "1.2.3"
        )
        assert len(errors) == 1
        assert f"'{version}'" in errors[0]
    assert check.validate_issue_template_versions(
        template, 'description: "Use X.Y.Z, not a version."\n', "1.2.3"
    ) == []

def main() -> int:
    _cases()
    print("OK: all app version guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
