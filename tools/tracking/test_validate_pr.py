#!/usr/bin/env python3
"""Offline tests for Device Sync pull-request ownership validation."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("validate_pr.py")
SPEC = importlib.util.spec_from_file_location("validate_pr_under_test", SCRIPT)
assert SPEC and SPEC.loader
validate_pr = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validate_pr
SPEC.loader.exec_module(validate_pr)


def validate(
    *,
    paths: list[str],
    title: str = "Ordinary change",
    body: str = "",
    head_ref: str = "ordinary-change",
    number: int = 42,
    pull_requests: dict[str, list[int]] | None = None,
    bootstrap: bool = False,
    author_association: str = "CONTRIBUTOR",
) -> list[str]:
    return validate_pr.validate_pull_request(
        changed_paths=paths,
        title=title,
        body=body,
        head_ref=head_ref,
        number=number,
        pull_requests=pull_requests or {},
        bootstrap=bootstrap,
        author_association=author_association,
    )


def test_unrelated_pull_request_passes() -> None:
    assert validate(paths=["app/lib/main.dart"]) == []


def test_matching_work_unit_identity_passes() -> None:
    assert (
        validate(
            paths=["app/lib/main.dart", ".github/tracking/adr-004/units/W10.json"],
            title="[ADR-004/W10] Build service",
            body="<!-- tracking-unit: ADR-004/W10 -->",
            head_ref="adr-004-w10-build-service",
            pull_requests={"ADR-004/W10": [42]},
        )
        == []
    )


def test_marker_requires_matching_unit_file() -> None:
    errors = validate(
        paths=["app/lib/main.dart"],
        title="[ADR-004/W10] Build service",
        body="<!-- tracking-unit: ADR-004/W10 -->",
        head_ref="adr-004-w10-build-service",
    )
    assert any("must change its owning unit file" in error for error in errors)


def test_unit_file_requires_marker() -> None:
    errors = validate(paths=[".github/tracking/adr-004/units/W10.json"])
    assert any("requires one tracking-unit marker" in error for error in errors)


def test_pull_request_number_must_be_recorded() -> None:
    errors = validate(
        paths=[".github/tracking/adr-004/units/W10.json"],
        title="[ADR-004/W10] Build service",
        body="<!-- tracking-unit: ADR-004/W10 -->",
        head_ref="adr-004-w10-build-service",
    )
    assert any("must include pull request #42" in error for error in errors)


def test_admin_marker_allows_tracking_maintenance() -> None:
    assert (
        validate(
            paths=[
                ".github/tracking/adr-004/project.json",
                ".github/tracking/adr-004/units/W10.json",
            ],
            title="Update tracking",
            body="<!-- tracking-admin -->",
            head_ref="tracking-maintenance",
            author_association="OWNER",
        )
        == []
    )


def test_admin_marker_is_owner_only() -> None:
    errors = validate(
        paths=[".github/tracking/adr-004/units/W10.json"],
        body="<!-- tracking-admin -->",
        author_association="CONTRIBUTOR",
    )
    assert any("requires repository-owner association" in error for error in errors)


def test_admin_marker_cannot_bypass_implementation_ownership() -> None:
    errors = validate(
        paths=[
            ".github/tracking/adr-004/units/W10.json",
            "packages/compendium_core/lib/service.dart",
        ],
        body="<!-- tracking-admin -->",
        author_association="OWNER",
    )
    assert any("administrative path set" in error for error in errors)


def test_admin_paths_require_marker_even_when_omitted() -> None:
    errors = validate(
        paths=[".github/tracking/adr-004/project.json"],
        author_association="CONTRIBUTOR",
    )
    assert any("require tracking-admin" in error for error in errors)


def test_unit_pr_cannot_change_tracking_control_paths() -> None:
    errors = validate(
        paths=[
            ".github/tracking/adr-004/units/W10.json",
            ".github/workflows/ci.yml",
        ],
        title="[ADR-004/W10] Build service",
        body="<!-- tracking-unit: ADR-004/W10 -->",
        head_ref="adr-004-w10-build-service",
        pull_requests={"ADR-004/W10": [42]},
    )
    assert any("require tracking-admin" in error for error in errors)


def test_bootstrap_requires_owner_admin_marker() -> None:
    errors = validate(
        paths=[
            ".github/tracking/adr-004/project.json",
            ".github/tracking/adr-004/units/W1.json",
        ],
        bootstrap=True,
    )
    assert any("bootstrap requires repository-owner tracking-admin" in error for error in errors)


def test_owner_admin_bootstrap_allows_initial_multi_unit_change() -> None:
    assert (
        validate(
            paths=[
                ".github/tracking/adr-004/project.json",
                ".github/tracking/adr-004/units/W1.json",
                ".github/tracking/adr-004/units/W2.json",
            ],
            bootstrap=True,
            body="<!-- tracking-admin -->",
            author_association="OWNER",
        )
        == []
    )


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} tracking PR tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
