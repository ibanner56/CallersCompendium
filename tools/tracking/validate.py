#!/usr/bin/env python3
"""Validate repository-backed Device Sync work tracking."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

UNIT_KEYS = {
    "schemaVersion",
    "id",
    "title",
    "phase",
    "sequence",
    "summary",
    "specReferences",
    "dependsOn",
    "completionDependsOn",
    "checkpoints",
    "produces",
    "pullRequests",
    "hold",
    "completion",
}
PROJECT_KEYS = {
    "schemaVersion",
    "id",
    "title",
    "project",
    "repository",
    "expectedWorkUnits",
    "phases",
    "checkpoints",
    "decisions",
}
REFERENCE_KEYS = {"path", "heading"}
COMPLETION_KEYS = {"complete", "conditions", "summary", "evidence"}
HOLD_KEYS = {"reason", "since"}
UNIT_ID = re.compile(r"ADR-004/W(?:0|[1-9]|1[0-8])\Z")
CHECKPOINT_ID = re.compile(r"C[0-7]\Z")


class Validator:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.errors: list[str] = []

    def error(self, location: str, message: str) -> None:
        self.errors.append(f"{location}: {message}")

    def load_json(self, path: Path) -> Any:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            self.error(str(path.relative_to(self.root)), "file is missing")
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            self.error(str(path.relative_to(self.root)), f"invalid JSON: {error}")
        return None

    def exact_keys(
        self,
        value: object,
        expected: set[str],
        location: str,
    ) -> bool:
        if not isinstance(value, dict):
            self.error(location, "must be an object")
            return False
        for key in sorted(set(value) - expected):
            self.error(location, f"unknown key {key}")
        for key in sorted(expected - set(value)):
            self.error(location, f"missing key {key}")
        return set(value) == expected

    def non_empty_string(self, value: object, location: str) -> bool:
        if not isinstance(value, str) or not value.strip():
            self.error(location, "must be a non-empty string")
            return False
        return True

    def string_list(
        self,
        value: object,
        location: str,
        *,
        allow_empty: bool = True,
    ) -> list[str]:
        if not isinstance(value, list) or any(
            not isinstance(item, str) or not item.strip() for item in value
        ):
            self.error(location, "must be a list of non-empty strings")
            return []
        if not allow_empty and not value:
            self.error(location, "must not be empty")
        if len(value) != len(set(value)):
            self.error(location, "must not contain duplicates")
        return value

    def validate_reference(self, value: object, location: str) -> None:
        if not self.exact_keys(value, REFERENCE_KEYS, location):
            return
        assert isinstance(value, dict)
        relative = value["path"]
        heading = value["heading"]
        if not self.non_empty_string(relative, f"{location}.path"):
            return
        if not self.non_empty_string(heading, f"{location}.heading"):
            return
        path = (self.root / relative).resolve()
        try:
            path.relative_to(self.root)
        except ValueError:
            self.error(location, "path escapes the repository")
            return
        if not path.is_file():
            self.error(location, f"source file does not exist: {relative}")
            return
        headings = []
        for line in path.read_text(encoding="utf-8").splitlines():
            match = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line)
            if match:
                headings.append(match.group(1))
        count = headings.count(heading)
        if count == 0:
            self.error(location, f"heading not found in {relative}: {heading}")
        elif count > 1:
            self.error(location, f"heading is ambiguous in {relative}: {heading}")

    def validate_project(self, value: object, location: str) -> dict[str, Any] | None:
        if not self.exact_keys(value, PROJECT_KEYS, location):
            return value if isinstance(value, dict) else None
        assert isinstance(value, dict)
        if value["schemaVersion"] != 1:
            self.error(location, "schemaVersion must be 1")
        if value["id"] != "ADR-004":
            self.error(location, "id must be ADR-004")
        self.non_empty_string(value["title"], f"{location}.title")
        if value["repository"] != "ibanner56/CallersCompendium":
            self.error(location, "repository must be ibanner56/CallersCompendium")
        project = value["project"]
        if self.exact_keys(project, {"owner", "number", "url"}, f"{location}.project"):
            assert isinstance(project, dict)
            if project["owner"] != "ibanner56":
                self.error(f"{location}.project.owner", "must be ibanner56")
            if not isinstance(project["number"], int) or project["number"] < 1:
                self.error(f"{location}.project.number", "must be a positive integer")
            self.non_empty_string(project["url"], f"{location}.project.url")

        expected = self.string_list(
            value["expectedWorkUnits"],
            f"{location}.expectedWorkUnits",
            allow_empty=False,
        )
        for unit_id in expected:
            if not UNIT_ID.fullmatch(unit_id):
                self.error(f"{location}.expectedWorkUnits", f"invalid unit ID {unit_id}")

        phase_ids: list[int] = []
        if not isinstance(value["phases"], list) or not value["phases"]:
            self.error(f"{location}.phases", "must be a non-empty list")
        else:
            for index, phase in enumerate(value["phases"]):
                phase_location = f"{location}.phases[{index}]"
                if not self.exact_keys(phase, {"id", "name"}, phase_location):
                    continue
                assert isinstance(phase, dict)
                if not isinstance(phase["id"], int) or phase["id"] < 0:
                    self.error(f"{phase_location}.id", "must be a non-negative integer")
                else:
                    phase_ids.append(phase["id"])
                self.non_empty_string(phase["name"], f"{phase_location}.name")
        if len(phase_ids) != len(set(phase_ids)):
            self.error(f"{location}.phases", "phase IDs must be unique")

        checkpoint_ids: list[str] = []
        if not isinstance(value["checkpoints"], list):
            self.error(f"{location}.checkpoints", "must be a list")
        else:
            checkpoint_keys = {
                "id",
                "title",
                "dependsOnUnits",
                "dependsOnCheckpoints",
                "criteria",
                "sourceReference",
            }
            for index, checkpoint in enumerate(value["checkpoints"]):
                checkpoint_location = f"{location}.checkpoints[{index}]"
                if not self.exact_keys(checkpoint, checkpoint_keys, checkpoint_location):
                    continue
                assert isinstance(checkpoint, dict)
                checkpoint_id = checkpoint["id"]
                if not isinstance(checkpoint_id, str) or not CHECKPOINT_ID.fullmatch(
                    checkpoint_id
                ):
                    self.error(f"{checkpoint_location}.id", "must be C0 through C7")
                else:
                    checkpoint_ids.append(checkpoint_id)
                self.non_empty_string(checkpoint["title"], f"{checkpoint_location}.title")
                self.string_list(
                    checkpoint["dependsOnUnits"],
                    f"{checkpoint_location}.dependsOnUnits",
                )
                self.string_list(
                    checkpoint["dependsOnCheckpoints"],
                    f"{checkpoint_location}.dependsOnCheckpoints",
                )
                self.string_list(
                    checkpoint["criteria"],
                    f"{checkpoint_location}.criteria",
                    allow_empty=False,
                )
                self.validate_reference(
                    checkpoint["sourceReference"],
                    f"{checkpoint_location}.sourceReference",
                )
        if len(checkpoint_ids) != len(set(checkpoint_ids)):
            self.error(f"{location}.checkpoints", "checkpoint IDs must be unique")
        checkpoint_set = set(checkpoint_ids)
        checkpoint_graph: dict[str, list[str]] = {}
        for checkpoint in value["checkpoints"]:
            if not isinstance(checkpoint, dict) or checkpoint.get("id") not in checkpoint_set:
                continue
            dependencies = checkpoint.get("dependsOnCheckpoints", [])
            checkpoint_graph[checkpoint["id"]] = dependencies
            for dependency in dependencies:
                if dependency not in checkpoint_set:
                    self.error(
                        f"{location}.checkpoints",
                        f"unknown checkpoint dependency {dependency}",
                    )

        checkpoint_visiting: list[str] = []
        checkpoint_visited: set[str] = set()

        def visit_checkpoint(checkpoint_id: str) -> None:
            if checkpoint_id in checkpoint_visited:
                return
            if checkpoint_id in checkpoint_visiting:
                cycle = checkpoint_visiting[
                    checkpoint_visiting.index(checkpoint_id) :
                ] + [checkpoint_id]
                self.error(
                    f"{location}.checkpoints",
                    f"checkpoint dependency cycle: {' -> '.join(cycle)}",
                )
                return
            checkpoint_visiting.append(checkpoint_id)
            for dependency in checkpoint_graph.get(checkpoint_id, []):
                if dependency in checkpoint_graph:
                    visit_checkpoint(dependency)
            checkpoint_visiting.pop()
            checkpoint_visited.add(checkpoint_id)

        for checkpoint_id in sorted(checkpoint_graph):
            visit_checkpoint(checkpoint_id)

        if not isinstance(value["decisions"], list):
            self.error(f"{location}.decisions", "must be a list")
        else:
            decision_keys = {"id", "decision", "effect", "decidedBy", "decidedOn"}
            decision_ids: list[str] = []
            for index, decision in enumerate(value["decisions"]):
                decision_location = f"{location}.decisions[{index}]"
                if not self.exact_keys(decision, decision_keys, decision_location):
                    continue
                assert isinstance(decision, dict)
                for key in decision_keys:
                    self.non_empty_string(decision[key], f"{decision_location}.{key}")
                if isinstance(decision["id"], str):
                    decision_ids.append(decision["id"])
            if len(decision_ids) != len(set(decision_ids)):
                self.error(f"{location}.decisions", "decision IDs must be unique")
        return value

    def validate_unit(
        self,
        value: object,
        path: Path,
        valid_phase_ids: set[int],
        valid_checkpoint_ids: set[str],
    ) -> dict[str, Any] | None:
        location = str(path.relative_to(self.root))
        if not self.exact_keys(value, UNIT_KEYS, location):
            return value if isinstance(value, dict) else None
        assert isinstance(value, dict)
        if value["schemaVersion"] != 1:
            self.error(location, "schemaVersion must be 1")
        unit_id = value["id"]
        if not isinstance(unit_id, str) or not UNIT_ID.fullmatch(unit_id):
            self.error(f"{location}.id", "must be ADR-004/W0 through ADR-004/W18")
        elif path.stem != unit_id.rsplit("/", 1)[1]:
            self.error(f"{location}.id", "must match the filename")
        self.non_empty_string(value["title"], f"{location}.title")
        self.non_empty_string(value["summary"], f"{location}.summary")
        if value["phase"] not in valid_phase_ids:
            self.error(f"{location}.phase", "does not name a configured phase")
        if not isinstance(value["sequence"], int) or value["sequence"] < 0:
            self.error(f"{location}.sequence", "must be a non-negative integer")

        references = value["specReferences"]
        if not isinstance(references, list) or not references:
            self.error(f"{location}.specReferences", "must be a non-empty list")
        else:
            for index, reference in enumerate(references):
                self.validate_reference(
                    reference,
                    f"{location}.specReferences[{index}]",
                )

        dependencies = self.string_list(
            value["dependsOn"], f"{location}.dependsOn"
        )
        for dependency in dependencies:
            if not UNIT_ID.fullmatch(dependency):
                self.error(f"{location}.dependsOn", f"invalid unit ID {dependency}")
        completion_dependencies = self.string_list(
            value["completionDependsOn"],
            f"{location}.completionDependsOn",
        )
        for dependency in completion_dependencies:
            if not UNIT_ID.fullmatch(dependency):
                self.error(
                    f"{location}.completionDependsOn",
                    f"invalid unit ID {dependency}",
                )
        checkpoints = self.string_list(
            value["checkpoints"], f"{location}.checkpoints"
        )
        for checkpoint in checkpoints:
            if checkpoint not in valid_checkpoint_ids:
                self.error(
                    f"{location}.checkpoints",
                    f"unknown checkpoint {checkpoint}",
                )
        self.string_list(
            value["produces"],
            f"{location}.produces",
            allow_empty=False,
        )

        pull_requests = value["pullRequests"]
        if not isinstance(pull_requests, list) or any(
            not isinstance(number, int) or number < 1 for number in pull_requests
        ):
            self.error(
                f"{location}.pullRequests",
                "must be a list of positive integers",
            )
        elif len(pull_requests) != len(set(pull_requests)):
            self.error(f"{location}.pullRequests", "must not contain duplicates")

        hold = value["hold"]
        if hold is not None:
            if self.exact_keys(hold, HOLD_KEYS, f"{location}.hold"):
                assert isinstance(hold, dict)
                self.non_empty_string(hold["reason"], f"{location}.hold.reason")
                if not isinstance(hold["since"], str) or not re.fullmatch(
                    r"\d{4}-\d{2}-\d{2}", hold["since"]
                ):
                    self.error(
                        f"{location}.hold.since",
                        "must be an ISO date (YYYY-MM-DD)",
                    )

        completion = value["completion"]
        if self.exact_keys(completion, COMPLETION_KEYS, f"{location}.completion"):
            assert isinstance(completion, dict)
            if not isinstance(completion["complete"], bool):
                self.error(f"{location}.completion.complete", "must be boolean")
            self.string_list(
                completion["conditions"],
                f"{location}.completion.conditions",
                allow_empty=False,
            )
            evidence = self.string_list(
                completion["evidence"],
                f"{location}.completion.evidence",
            )
            if completion["complete"]:
                if not self.non_empty_string(
                    completion["summary"],
                    f"{location}.completion.summary",
                ):
                    pass
                if not evidence:
                    self.error(location, "completed unit requires evidence")
            elif completion["summary"] is not None:
                self.error(
                    f"{location}.completion.summary",
                    "must be null until the unit is complete",
                )
        return value

    def validate(self) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
        tracking = self.root / ".github" / "tracking" / "adr-004"
        project_path = tracking / "project.json"
        project_value = self.load_json(project_path)
        project = self.validate_project(project_value, str(project_path.relative_to(self.root)))
        if not isinstance(project, dict):
            return {}, {}

        valid_phase_ids = {
            phase["id"]
            for phase in project.get("phases", [])
            if isinstance(phase, dict) and isinstance(phase.get("id"), int)
        }
        valid_checkpoint_ids = {
            checkpoint["id"]
            for checkpoint in project.get("checkpoints", [])
            if isinstance(checkpoint, dict) and isinstance(checkpoint.get("id"), str)
        }

        units: dict[str, dict[str, Any]] = {}
        sequences: dict[int, str] = {}
        pull_requests: dict[int, str] = {}
        for path in sorted((tracking / "units").glob("*.json")):
            value = self.load_json(path)
            unit = self.validate_unit(
                value,
                path,
                valid_phase_ids,
                valid_checkpoint_ids,
            )
            if not isinstance(unit, dict) or not isinstance(unit.get("id"), str):
                continue
            unit_id = unit["id"]
            if unit_id in units:
                self.error(str(path.relative_to(self.root)), f"duplicate unit ID {unit_id}")
            units[unit_id] = unit
            sequence = unit.get("sequence")
            if isinstance(sequence, int):
                if sequence in sequences:
                    self.error(
                        str(path.relative_to(self.root)),
                        f"sequence {sequence} is also used by {sequences[sequence]}",
                    )
                sequences[sequence] = unit_id
            for number in unit.get("pullRequests", []):
                if not isinstance(number, int):
                    continue
                if number in pull_requests:
                    self.error(
                        str(path.relative_to(self.root)),
                        f"pull request #{number} belongs to both "
                        f"{pull_requests[number]} and {unit_id}",
                    )
                pull_requests[number] = unit_id

        expected = set(project.get("expectedWorkUnits", []))
        actual = set(units)
        for missing in sorted(expected - actual):
            self.error("project.json", f"expected work unit is missing: {missing}")
        for extra in sorted(actual - expected):
            self.error("project.json", f"unexpected work unit exists: {extra}")

        for unit_id, unit in units.items():
            for dependency in (
                unit.get("dependsOn", []) + unit.get("completionDependsOn", [])
            ):
                if dependency not in units:
                    self.error(unit_id, f"unknown dependency {dependency}")
            if unit.get("completion", {}).get("complete"):
                for dependency in (
                    unit.get("dependsOn", []) + unit.get("completionDependsOn", [])
                ):
                    if (
                        dependency in units
                        and not units[dependency].get("completion", {}).get("complete")
                    ):
                        self.error(
                            unit_id,
                            f"cannot complete before dependency {dependency}",
                        )
            for checkpoint in project.get("checkpoints", []):
                if not isinstance(checkpoint, dict):
                    continue
                for dependency in checkpoint.get("dependsOnUnits", []):
                    if dependency not in units:
                        self.error(
                            f"checkpoint {checkpoint.get('id', '?')}",
                            f"unknown unit dependency {dependency}",
                        )

        visiting: list[str] = []
        visited: set[str] = set()

        def visit(unit_id: str) -> None:
            if unit_id in visited:
                return
            if unit_id in visiting:
                cycle = visiting[visiting.index(unit_id) :] + [unit_id]
                self.error("dependencies", f"dependency cycle: {' -> '.join(cycle)}")
                return
            visiting.append(unit_id)
            dependencies = (
                units[unit_id].get("dependsOn", [])
                + units[unit_id].get("completionDependsOn", [])
            )
            for dependency in dependencies:
                if dependency in units:
                    visit(dependency)
            visiting.pop()
            visited.add(unit_id)

        for unit_id in sorted(units):
            visit(unit_id)
        return project, units


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    validator = Validator(args.root)
    project, units = validator.validate()
    if validator.errors:
        for error in validator.errors:
            print(f"ERROR: {error}")
        return 1
    print(
        f"OK: {project['id']} tracking is valid "
        f"({len(units)} work units, {len(project['checkpoints'])} checkpoints)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
