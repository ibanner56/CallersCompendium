#!/usr/bin/env python3
"""Offline tests for Device Sync Project desired-state generation."""

from __future__ import annotations

import importlib.util
import base64
import json
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("sync_project.py")
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("sync_project_under_test", SCRIPT)
assert SPEC and SPEC.loader
sync_project = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = sync_project
SPEC.loader.exec_module(sync_project)


def unit(
    unit_id: str,
    *,
    complete: bool = False,
    depends_on: list[str] | None = None,
    pull_requests: list[int] | None = None,
    hold: dict[str, str] | None = None,
) -> dict[str, object]:
    return {
        "id": unit_id,
        "title": unit_id,
        "phase": 1,
        "sequence": int(unit_id.rsplit("W", 1)[1]),
        "summary": "Summary.",
        "specReferences": [{"path": "docs/spec.md", "heading": "Rule"}],
        "dependsOn": depends_on or [],
        "completionDependsOn": [],
        "checkpoints": ["C1"],
        "produces": ["Artifact"],
        "pullRequests": pull_requests or [],
        "hold": hold,
        "completion": {
            "complete": complete,
            "conditions": ["Condition"],
            "summary": "Done." if complete else None,
            "evidence": ["Evidence"] if complete else [],
        },
    }


def test_done_comes_from_repository_state() -> None:
    units = {
        "ADR-004/W0": unit("ADR-004/W0", complete=True, pull_requests=[10]),
    }
    desired = sync_project.build_desired_items(units, [])
    assert desired["ADR-004/W0"].status == "Done"


def test_ready_requires_completed_dependencies() -> None:
    units = {
        "ADR-004/W0": unit("ADR-004/W0", complete=True, pull_requests=[10]),
        "ADR-004/W1": unit("ADR-004/W1", depends_on=["ADR-004/W0"]),
        "ADR-004/W2": unit("ADR-004/W2", depends_on=["ADR-004/W1"]),
    }
    desired = sync_project.build_desired_items(units, [])
    assert desired["ADR-004/W1"].status == "Ready"
    assert desired["ADR-004/W2"].status == "Planned"


def test_draft_and_ready_pull_requests_supply_active_states() -> None:
    units = {
        "ADR-004/W1": unit("ADR-004/W1"),
        "ADR-004/W2": unit("ADR-004/W2"),
    }
    pull_requests = [
        {"number": 20, "isDraft": True, "body": "<!-- tracking-unit: ADR-004/W1 -->", "url": "u1"},
        {"number": 21, "isDraft": False, "body": "<!-- tracking-unit: ADR-004/W2 -->", "url": "u2"},
    ]
    desired = sync_project.build_desired_items(units, pull_requests)
    assert desired["ADR-004/W1"].status == "In progress"
    assert desired["ADR-004/W2"].status == "In review"


def test_non_draft_wins_when_a_unit_has_multiple_open_pull_requests() -> None:
    units = {"ADR-004/W1": unit("ADR-004/W1")}
    pull_requests = [
        {"number": 20, "isDraft": True, "body": "<!-- tracking-unit: ADR-004/W1 -->", "url": "u1"},
        {"number": 21, "isDraft": False, "body": "<!-- tracking-unit: ADR-004/W1 -->", "url": "u2"},
    ]
    desired = sync_project.build_desired_items(units, pull_requests)
    assert desired["ADR-004/W1"].status == "In review"
    assert desired["ADR-004/W1"].pull_requests == (20, 21)


def test_blocking_is_orthogonal_to_lifecycle() -> None:
    units = {
        "ADR-004/W1": unit(
            "ADR-004/W1",
            hold={"reason": "Awaiting infrastructure.", "since": "2026-09-01"},
        )
    }
    desired = sync_project.build_desired_items(units, [])
    assert desired["ADR-004/W1"].status == "Ready"
    assert desired["ADR-004/W1"].blocked
    assert desired["ADR-004/W1"].blocked_reason == "Awaiting infrastructure."


def test_unrelated_pull_request_is_ignored() -> None:
    units = {"ADR-004/W1": unit("ADR-004/W1")}
    pull_requests = [
        {"number": 20, "isDraft": False, "body": "Ordinary PR", "url": "u1"},
    ]
    desired = sync_project.build_desired_items(units, pull_requests)
    assert desired["ADR-004/W1"].status == "Ready"
    assert desired["ADR-004/W1"].pull_requests == ()


def test_matching_project_fields_need_no_update() -> None:
    fields = {
        "Status": {"name": "Status", "options": [{"name": "Ready", "id": "ready"}]},
        "Work Unit ID": {"name": "Work Unit ID"},
        "Phase": {
            "name": "Phase",
            "options": [
                {
                    "name": "Phase 1 - Shared contract",
                    "id": "phase-1",
                }
            ],
        },
        "Sequence": {"name": "Sequence"},
        "Dependencies": {"name": "Dependencies"},
        "Blocked": {
            "name": "Blocked",
            "options": [{"name": "No", "id": "no"}, {"name": "Yes", "id": "yes"}],
        },
        "Blocked reason": {"name": "Blocked reason"},
        "Pull requests": {"name": "Pull requests"},
        "Checkpoints": {"name": "Checkpoints"},
    }
    item = sync_project.build_desired_items(
        {"ADR-004/W1": unit("ADR-004/W1")},
        [],
    )["ADR-004/W1"]
    desired = sync_project.desired_field_values(fields, item)
    current = {
        "Status": {"optionId": "ready"},
        "Work Unit ID": {"text": "ADR-004/W1"},
        "Phase": {"optionId": "phase-1"},
        "Sequence": {"number": 1},
        "Dependencies": {"text": "Start: None; completion: None"},
        "Blocked": {"optionId": "no"},
        "Blocked reason": {"text": "None"},
        "Pull requests": {"text": "None"},
        "Checkpoints": {"text": "C1"},
    }
    assert sync_project.changed_field_values(current, desired) == {}


def test_untrusted_marker_does_not_supply_active_state() -> None:
    units = {"ADR-004/W1": unit("ADR-004/W1")}
    pull_requests = [
        {
            "number": 20,
            "isDraft": False,
            "title": "[ADR-004/W1] Untrusted",
            "body": "<!-- tracking-unit: ADR-004/W1 -->",
            "headRefName": "adr-004-w1-untrusted",
            "changedPaths": ["app/lib/main.dart"],
            "headUnit": {"id": "ADR-004/W1", "pullRequests": [20]},
            "authorAssociation": "CONTRIBUTOR",
            "url": "u1",
        }
    ]
    qualified = sync_project.qualified_pull_requests(pull_requests)
    desired = sync_project.build_desired_items(units, qualified)
    assert qualified == []
    assert desired["ADR-004/W1"].status == "Ready"


def test_verified_head_unit_supplies_active_state() -> None:
    pull_requests = [
        {
            "number": 20,
            "isDraft": True,
            "title": "[ADR-004/W1] Implement",
            "body": "<!-- tracking-unit: ADR-004/W1 -->",
            "headRefName": "adr-004-w1-implement",
            "changedPaths": [
                "app/lib/main.dart",
                ".github/tracking/adr-004/units/W1.json",
            ],
            "headUnit": {"id": "ADR-004/W1", "pullRequests": [20]},
            "authorAssociation": "CONTRIBUTOR",
            "url": "u1",
        }
    ]
    qualified = sync_project.qualified_pull_requests(pull_requests)
    assert [pull_request["number"] for pull_request in qualified] == [20]


def test_control_path_change_is_not_qualified() -> None:
    pull_requests = [
        {
            "number": 20,
            "isDraft": True,
            "title": "[ADR-004/W1] Implement",
            "body": "<!-- tracking-unit: ADR-004/W1 -->",
            "headRefName": "adr-004-w1-implement",
            "changedPaths": [
                ".github/tracking/adr-004/units/W1.json",
                "tools/tracking/validate.py",
            ],
            "headUnit": {"id": "ADR-004/W1", "pullRequests": [20]},
            "authorAssociation": "CONTRIBUTOR",
            "url": "u1",
        }
    ]
    assert sync_project.qualified_pull_requests(pull_requests) == []


def test_malformed_head_unit_is_ignored() -> None:
    pull_requests = [
        {
            "number": 20,
            "isDraft": True,
            "title": "[ADR-004/W1] Implement",
            "body": "<!-- tracking-unit: ADR-004/W1 -->",
            "headRefName": "adr-004-w1-implement",
            "changedPaths": [".github/tracking/adr-004/units/W1.json"],
            "headUnit": {"id": "ADR-004/W1", "pullRequests": 20},
            "authorAssociation": "CONTRIBUTOR",
            "url": "u1",
        }
    ]
    assert sync_project.qualified_pull_requests(pull_requests) == []


def test_generated_card_marker_recovers_partial_creation() -> None:
    body = (
        "<!-- generated from repository tracking; direct edits are overwritten -->\n"
        "<!-- tracking-card: ADR-004/W1 -->"
    )
    assert (
        sync_project.project_item_unit_id(
            {"content": {"body": body}, "fieldValues": {"nodes": []}}
        )
        == "ADR-004/W1"
    )


def test_generated_marker_repairs_edited_identity_field() -> None:
    body = "<!-- tracking-card: ADR-004/W1 -->"
    assert (
        sync_project.project_item_unit_id(
            {
                "content": {"body": body},
                "fieldValues": {
                    "nodes": [
                        {
                            "text": "not-a-unit",
                            "field": {"name": "Work Unit ID"},
                        }
                    ]
                },
            }
        )
        == "ADR-004/W1"
    )


def test_conflicting_valid_identities_are_rejected() -> None:
    body = "<!-- tracking-card: ADR-004/W1 -->"
    try:
        sync_project.project_item_unit_id(
            {
                "content": {"body": body},
                "fieldValues": {
                    "nodes": [
                        {
                            "text": "ADR-004/W2",
                            "field": {"name": "Work Unit ID"},
                        }
                    ]
                },
            }
        )
    except RuntimeError as error:
        assert "conflicting generated identities" in str(error)
    else:
        raise AssertionError("conflicting identities were accepted")


def test_wrapped_github_blob_decodes_strictly() -> None:
    value = {
        "id": "ADR-004/W1",
        "pullRequests": [20],
        "padding": "x" * 200,
    }
    encoded = base64.encodebytes(json.dumps(value).encode("utf-8")).decode("ascii")
    assert "\n" in encoded
    assert sync_project.decode_head_unit_blob(
        {"encoding": "base64", "size": 300, "content": encoded}
    ) == value


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} Project sync tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
