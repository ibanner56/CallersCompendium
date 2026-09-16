#!/usr/bin/env python3
"""Offline tests for Device Sync pull-request ownership validation."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("validate_pr.py")
SPEC = importlib.util.spec_from_file_location("validate_pr_under_test", SCRIPT)
assert SPEC and SPEC.loader
validate_pr = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validate_pr
SPEC.loader.exec_module(validate_pr)
REPOSITORY = "ibanner56/CallersCompendium"


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
    base_ref: str = "",
    head_repo: str = "",
    base_repo: str = "",
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
        base_ref=base_ref,
        head_repo=head_repo,
        base_repo=base_repo,
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


def test_admin_marker_allows_preflight_gate_and_its_supporting_files() -> None:
    assert (
        validate(
            paths=["CONTRIBUTING.md", "tools/preflight.py", "tools/test_preflight.py"],
            title="Fix preflight",
            body="<!-- tracking-admin -->",
            head_ref="preflight-fvm-repair",
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


def test_bootstrap_rejects_combined_admin_and_unit_markers() -> None:
    errors = validate(
        paths=[
            ".github/tracking/adr-004/project.json",
            ".github/tracking/adr-004/units/W1.json",
        ],
        bootstrap=True,
        body=(
            "<!-- tracking-admin -->\n"
            "<!-- tracking-unit: ADR-004/W1 -->"
        ),
        author_association="OWNER",
    )
    assert any("cannot be combined" in error for error in errors)


def test_topic_merge_allows_multiple_units_and_implementation_files() -> None:
    assert (
        validate(
            paths=[
                ".github/tracking/adr-004/units/W6.json",
                ".github/tracking/adr-004/units/W7.json",
                "packages/compendium_core/lib/src/sync/sync_merge.dart",
            ],
            body="<!-- tracking-topic-merge: athenaeum -->",
            head_ref="athenaeum",
            base_ref="main",
            head_repo=REPOSITORY,
            base_repo=REPOSITORY,
            author_association="OWNER",
        )
        == []
    )


def test_topic_merge_requires_exact_source_branch() -> None:
    errors = validate(
        paths=["packages/compendium_core/lib/src/sync/sync_merge.dart"],
        body="<!-- tracking-topic-merge: athenaeum -->",
        head_ref="feature/athenaeum",
        base_ref="main",
        head_repo=REPOSITORY,
        base_repo=REPOSITORY,
        author_association="OWNER",
    )
    assert any("source branch athenaeum" in error for error in errors)


def test_topic_merge_requires_exact_target_branch() -> None:
    errors = validate(
        paths=["packages/compendium_core/lib/src/sync/sync_merge.dart"],
        body="<!-- tracking-topic-merge: athenaeum -->",
        head_ref="athenaeum",
        base_ref="release",
        head_repo=REPOSITORY,
        base_repo=REPOSITORY,
        author_association="OWNER",
    )
    assert any("target branch main" in error for error in errors)


def test_topic_merge_requires_canonical_head_repository() -> None:
    errors = validate(
        paths=["packages/compendium_core/lib/src/sync/sync_merge.dart"],
        body="<!-- tracking-topic-merge: athenaeum -->",
        head_ref="athenaeum",
        base_ref="main",
        head_repo="contributor/CallersCompendium",
        base_repo=REPOSITORY,
        author_association="OWNER",
    )
    assert any("head repository" in error for error in errors)


def test_topic_merge_requires_canonical_base_repository() -> None:
    errors = validate(
        paths=["packages/compendium_core/lib/src/sync/sync_merge.dart"],
        body="<!-- tracking-topic-merge: athenaeum -->",
        head_ref="athenaeum",
        base_ref="main",
        head_repo=REPOSITORY,
        base_repo="ibanner56/CallersCompendium-fork",
        author_association="OWNER",
    )
    assert any("base repository" in error for error in errors)


def test_topic_merge_is_owner_only() -> None:
    errors = validate(
        paths=["packages/compendium_core/lib/src/sync/sync_merge.dart"],
        body="<!-- tracking-topic-merge: athenaeum -->",
        head_ref="athenaeum",
        base_ref="main",
        head_repo=REPOSITORY,
        base_repo=REPOSITORY,
        author_association="CONTRIBUTOR",
    )
    assert any("repository-owner association" in error for error in errors)


def test_topic_merge_cannot_combine_with_unit_marker() -> None:
    errors = validate(
        paths=[
            ".github/tracking/adr-004/units/W6.json",
            "packages/compendium_core/lib/src/sync/sync_merge.dart",
        ],
        body=(
            "<!-- tracking-topic-merge: athenaeum -->\n"
            "<!-- tracking-unit: ADR-004/W6 -->"
        ),
        head_ref="athenaeum",
        base_ref="main",
        head_repo=REPOSITORY,
        base_repo=REPOSITORY,
        author_association="OWNER",
    )
    assert any("cannot be combined" in error for error in errors)


def test_topic_merge_cannot_combine_with_admin_marker() -> None:
    errors = validate(
        paths=["packages/compendium_core/lib/src/sync/sync_merge.dart"],
        body=(
            "<!-- tracking-topic-merge: athenaeum -->\n"
            "<!-- tracking-admin -->"
        ),
        head_ref="athenaeum",
        base_ref="main",
        head_repo=REPOSITORY,
        base_repo=REPOSITORY,
        author_association="OWNER",
    )
    assert any("cannot be combined" in error for error in errors)


def test_topic_merge_rejects_tracking_control_paths() -> None:
    for path in (
        "tools/tracking/validate_pr.py",
        ".github/workflows/ci.yml",
        ".github/instructions/device-sync-tracking.instructions.md",
        ".github/tracking/adr-004/project.json",
    ):
        errors = validate(
            paths=[path],
            body="<!-- tracking-topic-merge: athenaeum -->",
            head_ref="athenaeum",
            base_ref="main",
            head_repo=REPOSITORY,
            base_repo=REPOSITORY,
            author_association="OWNER",
        )
        assert any("tracking control paths" in error for error in errors), path


def test_malformed_unit_file_reports_controlled_error() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        units = Path(tmp) / ".github" / "tracking" / "adr-004" / "units"
        units.mkdir(parents=True)
        (units / "W1.json").write_text("{", encoding="utf-8")
        try:
            validate_pr.load_pull_requests(Path(tmp))
        except RuntimeError as error:
            assert "unable to read" in str(error)
        else:
            raise AssertionError("malformed unit JSON must fail with RuntimeError")


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} tracking PR tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
