#!/usr/bin/env python3
"""Regression tests for Device Sync tracking validation."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "tracking" / "validate.py"


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def unit(
    number: int,
    *,
    depends_on: list[str] | None = None,
    pull_requests: list[int] | None = None,
    complete: bool = False,
    evidence: list[str] | None = None,
) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "id": f"ADR-004/W{number}",
        "title": f"Work {number}",
        "phase": number,
        "sequence": number,
        "summary": f"Deliver work {number}.",
        "specReferences": [
            {
                "path": "docs/design/plan.md",
                "heading": f"W{number} heading",
            }
        ],
        "dependsOn": depends_on or [],
        "completionDependsOn": [],
        "checkpoints": ["C0"],
        "produces": [f"Artifact {number}"],
        "pullRequests": pull_requests or [],
        "hold": None,
        "completion": {
            "complete": complete,
            "conditions": [f"Condition {number}"],
            "summary": "Delivered." if complete else None,
            "evidence": evidence or [],
        },
    }


def build_repo(tmp: Path) -> Path:
    repo = tmp / "repo"
    plan = repo / "docs" / "design" / "plan.md"
    plan.parent.mkdir(parents=True)
    plan.write_text("# Plan\n\n## W0 heading\n\n## W1 heading\n", encoding="utf-8")
    write_json(
        repo / ".github" / "tracking" / "adr-004" / "project.json",
        {
            "schemaVersion": 1,
            "id": "ADR-004",
            "title": "Device Sync",
            "project": {
                "owner": "ibanner56",
                "number": 1,
                "url": "https://github.com/users/ibanner56/projects/1",
            },
            "repository": "ibanner56/CallersCompendium",
            "expectedWorkUnits": ["ADR-004/W0", "ADR-004/W1"],
            "phases": [
                {"id": 0, "name": "Phase 0"},
                {"id": 1, "name": "Phase 1"},
            ],
            "checkpoints": [
                {
                    "id": "C0",
                    "title": "Checkpoint zero",
                    "dependsOnUnits": ["ADR-004/W0"],
                    "dependsOnCheckpoints": [],
                    "criteria": ["The prerequisite is delivered."],
                    "sourceReference": {
                        "path": "docs/design/plan.md",
                        "heading": "Plan",
                    },
                }
            ],
            "decisions": [],
        },
    )
    units = repo / ".github" / "tracking" / "adr-004" / "units"
    write_json(units / "W0.json", unit(0, pull_requests=[10], complete=True, evidence=["PR #10"]))
    write_json(units / "W1.json", unit(1, depends_on=["ADR-004/W0"]))
    return repo


def run(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(repo), *args],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )


def test_valid_repository_passes() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        result = run(build_repo(Path(tmp)))
        assert result.returncode == 0, result.stdout + result.stderr
        assert "2 work units" in result.stdout


def test_missing_dependency_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "units" / "W1.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["dependsOn"] = ["ADR-004/W99"]
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "unknown dependency ADR-004/W99" in result.stdout


def test_dependency_cycle_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "units" / "W0.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["dependsOn"] = ["ADR-004/W1"]
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "dependency cycle" in result.stdout


def test_duplicate_pull_request_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "units" / "W1.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["pullRequests"] = [10]
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "pull request #10 belongs to both" in result.stdout


def test_completed_unit_requires_evidence() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "units" / "W1.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["completion"]["complete"] = True
        value["completion"]["summary"] = "Done."
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "completed unit requires evidence" in result.stdout


def test_completed_unit_requires_completed_dependencies() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        first = repo / ".github" / "tracking" / "adr-004" / "units" / "W0.json"
        first_value = json.loads(first.read_text(encoding="utf-8"))
        first_value["completion"]["complete"] = False
        first_value["completion"]["summary"] = None
        first_value["completion"]["evidence"] = []
        write_json(first, first_value)
        second = repo / ".github" / "tracking" / "adr-004" / "units" / "W1.json"
        second_value = json.loads(second.read_text(encoding="utf-8"))
        second_value["pullRequests"] = [11]
        second_value["completion"]["complete"] = True
        second_value["completion"]["summary"] = "Done."
        second_value["completion"]["evidence"] = ["PR #11"]
        write_json(second, second_value)
        result = run(repo)
        assert result.returncode == 1
        assert "cannot complete before dependency ADR-004/W0" in result.stdout


def test_derived_status_field_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "units" / "W1.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["status"] = "in progress"
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "unknown key status" in result.stdout


def test_missing_source_heading_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "units" / "W1.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["specReferences"][0]["heading"] = "Missing"
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "heading not found" in result.stdout


def test_unknown_checkpoint_dependency_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "project.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["checkpoints"][0]["dependsOnCheckpoints"] = ["C7"]
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "unknown checkpoint dependency C7" in result.stdout


def test_checkpoint_dependency_cycle_fails() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build_repo(Path(tmp))
        path = repo / ".github" / "tracking" / "adr-004" / "project.json"
        value = json.loads(path.read_text(encoding="utf-8"))
        value["checkpoints"].append(
            {
                "id": "C1",
                "title": "Checkpoint one",
                "dependsOnUnits": ["ADR-004/W1"],
                "dependsOnCheckpoints": ["C0"],
                "criteria": ["Work one is complete."],
                "sourceReference": {
                    "path": "docs/design/plan.md",
                    "heading": "Plan",
                },
            }
        )
        value["checkpoints"][0]["dependsOnCheckpoints"] = ["C1"]
        write_json(path, value)
        result = run(repo)
        assert result.returncode == 1
        assert "checkpoint dependency cycle" in result.stdout


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} tracking validation tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
