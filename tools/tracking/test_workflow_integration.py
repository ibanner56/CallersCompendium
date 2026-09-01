#!/usr/bin/env python3
"""Structural guards for Device Sync tracking workflow integration."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
SYNC_WORKFLOW = ROOT / ".github" / "workflows" / "device-sync-tracking.yml"


def job(workflow: str, job_id: str) -> str:
    match = re.search(
        rf"^  {re.escape(job_id)}:\n(?P<body>.*?)(?=^  [a-z][a-z0-9-]*:\n|\Z)",
        workflow,
        flags=re.MULTILINE | re.DOTALL,
    )
    assert match, f"missing {job_id} job"
    return match.group(0)


def trigger(workflow: str, event: str) -> str:
    match = re.search(
        rf"^  {re.escape(event)}:\n(?P<body>.*?)(?=^  [a-z][a-z0-9_-]*:\n|\Z)",
        workflow,
        flags=re.MULTILINE | re.DOTALL,
    )
    assert match, f"missing {event} trigger"
    return match.group(0)


def test_ci_runs_for_all_pull_request_updates() -> None:
    workflow = CI_WORKFLOW.read_text(encoding="utf-8")
    assert re.search(
        r"^  pull_request:\n    types: \[opened, reopened, synchronize, edited\]$",
        workflow,
        flags=re.MULTILINE,
    ), "pull_request must include edited and the default-equivalent activity types"



def test_ci_executes_base_tracking_validator() -> None:
    workflow = CI_WORKFLOW.read_text(encoding="utf-8")
    tracking = job(workflow, "tracking-gate")
    assert "name: Device Sync tracking gate" in tracking
    assert "if: github.event_name == 'pull_request'" in tracking
    assert "ref: ${{ github.event.pull_request.head.sha }}" in tracking
    assert "fetch-depth: 0" in tracking
    assert (
        "persist-credentials: false" in tracking
    ), "tracking-gate checkout must not persist credentials"
    assert "set -euo pipefail" in tracking
    assert 'git show "$BASE_SHA:tools/tracking/validate_pr.py" > "$validator"' in tracking
    base_validation = (
        'python3 "$validator" "$BASE_SHA" "$HEAD_SHA" "$GITHUB_EVENT_PATH" \\'
    )
    head_validation = "python3 tools/tracking/validate.py"
    assert base_validation in tracking
    assert '--root "$GITHUB_WORKSPACE"' in tracking
    assert (
        head_validation in tracking
    ), "tracking-gate must validate canonical head tracking after ownership"
    assert tracking.index(base_validation) < tracking.index(
        head_validation
    ), "base ownership validation must run before head canonical validation"
    assert "python3 tools/tracking/validate_pr.py" not in tracking
    assert "||" not in tracking, "trusted validator loading must not have a fallback"


def test_merge_gate_fails_closed_on_tracking_result() -> None:
    workflow = CI_WORKFLOW.read_text(encoding="utf-8")
    merge = job(workflow, "merge-gate")
    needs = re.search(r"^    needs: \[(?P<jobs>[^\]]+)\]$", merge, flags=re.MULTILINE)
    assert needs and "tracking-gate" in needs.group("jobs").split(", ")
    assert "TRACKING_GATE_RESULT: ${{ needs.tracking-gate.result }}" in merge
    assert "require_success 'Device Sync tracking gate' \"$TRACKING_GATE_RESULT\"" in merge


def test_reconciler_workflow_uses_only_trusted_main_content() -> None:
    workflow = SYNC_WORKFLOW.read_text(encoding="utf-8")
    push = trigger(workflow, "push")
    pull_request_target = trigger(workflow, "pull_request_target")
    assert "branches: [main]" in push
    assert (
        "branches: [main]" in pull_request_target
    ), "pull_request_target must be limited to PRs targeting main"
    assert (
        "types: [opened, reopened, synchronize, edited, converted_to_draft, "
        "ready_for_review, closed]"
    ) in pull_request_target
    assert "schedule:" in workflow
    assert "workflow_dispatch:" in workflow
    assert "group: device-sync-tracking" in workflow
    assert "cancel-in-progress: false" in workflow
    assert re.search(
        r"^permissions:\n  contents: read\n  pull-requests: read$",
        workflow,
        flags=re.MULTILINE,
    )
    assert workflow.count("permissions:") == 1

    assert workflow.count("uses: actions/checkout@") == 1
    assert workflow.count("ref: refs/heads/main") == 1
    assert "persist-credentials: false" in workflow
    assert "python3 tools/tracking/validate.py" in workflow
    assert "python3 tools/tracking/sync_project.py --apply" in workflow
    assert workflow.index("python3 tools/tracking/validate.py") < workflow.index(
        "python3 tools/tracking/sync_project.py --apply"
    )
    assert "GITHUB_TOKEN: ${{ github.token }}" in workflow
    assert "DEVICE_SYNC_PROJECT_TOKEN: ${{ secrets.DEVICE_SYNC_PROJECT_TOKEN }}" in workflow
    assert 'if [ -z "$DEVICE_SYNC_PROJECT_TOKEN" ]; then' in workflow
    apply_step = workflow.split("      - name: Reconcile generated Project state\n", 1)
    assert len(apply_step) == 2
    assert "DEVICE_SYNC_PROJECT_TOKEN" not in apply_step[0]

    forbidden = (
        "github.event.pull_request.head",
        "github.head_ref",
        "refs/pull/",
        "actions/download-artifact",
    )
    for value in forbidden:
        assert value not in workflow, f"privileged workflow must not use {value}"


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    failures = 0
    for test in tests:
        try:
            test()
        except (AssertionError, FileNotFoundError) as error:
            failures += 1
            print(f"FAIL: {test.__name__}: {error}")
    if failures:
        print(f"FAILED: {failures} of {len(tests)} tracking workflow tests failed")
        return 1
    print(f"OK: {len(tests)} tracking workflow tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
