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
        rf"^  {re.escape(job_id)}:\n(?P<body>.*?)(?=^  [a-z][a-z0-9_-]*:\n|\Z)",
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


def test_job_stops_at_underscore_job_id() -> None:
    workflow = """jobs:
  first:
    name: First job
  next_job:
    name: Next job
"""
    first = job(workflow, "first")
    assert "name: First job" in first
    assert "next_job:" not in first
    assert "name: Next job" not in first


def test_ci_runs_for_pull_request_code_updates() -> None:
    """CI runs on the activity types that change code -- and not on `edited`.

    `edited` was required here while the tracking gate read the PR body
    (#1138). #1338 removed that job and #1379 removed the trigger, because a
    description edit started a second run whose concurrency group cancelled
    the first. Asserting its absence, rather than only the presence of the
    other three, is deliberate: re-adding it is the regression this guard
    exists to catch.
    """
    workflow = CI_WORKFLOW.read_text(encoding="utf-8")
    pull_request = trigger(workflow, "pull_request")
    assert "edited" not in pull_request, (
        "pull_request must not include edited: it cancels the in-flight suite "
        "for a description change, and nothing in ci.yml reads the PR body"
    )
    assert re.search(
        r"^  pull_request:\n    types: \[opened, reopened, synchronize\]$",
        workflow,
        flags=re.MULTILINE,
    ), "pull_request must run for opened, reopened and synchronize"


def test_ci_has_no_pull_request_tracking_gate() -> None:
    workflow = CI_WORKFLOW.read_text(encoding="utf-8")
    assert "tracking-gate" not in workflow
    assert "TRACKING_GATE_RESULT" not in workflow
    assert "validate_pr.py" not in workflow


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
