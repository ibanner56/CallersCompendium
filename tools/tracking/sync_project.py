#!/usr/bin/env python3
"""Reconcile ADR-004 repository tracking into a GitHub Project."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from validate_pr import validate_pull_request

ROOT = Path(__file__).resolve().parents[2]
TRACKING = Path(".github/tracking/adr-004")
MARKER = re.compile(r"<!--\s*tracking-unit:\s*(ADR-004/W(?:0|[1-9]|1[0-8]))\s*-->")
CARD_MARKER = re.compile(r"<!--\s*tracking-card:\s*(ADR-004/W(?:0|[1-9]|1[0-8]))\s*-->")
PHASE_NAMES = {
    0: "Phase 0 - Shipped prerequisite",
    1: "Phase 1 - Shared contract",
    2: "Phase 2 - Foundations and server core",
    3: "Phase 3 - Sync engine",
    4: "Phase 4 - Server hardening and operations",
}
FIELD_NAMES = (
    "Status",
    "Work Unit ID",
    "Phase",
    "Sequence",
    "Dependencies",
    "Blocked",
    "Blocked reason",
    "Pull requests",
    "Checkpoints",
)


@dataclass(frozen=True)
class DesiredItem:
    unit_id: str
    title: str
    body: str
    status: str
    phase: str
    sequence: int
    dependencies: str
    blocked: bool
    blocked_reason: str
    pull_requests: tuple[int, ...]
    pull_request_text: str
    checkpoints: str


def load_tracking(root: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    tracking = root / TRACKING
    project = json.loads((tracking / "project.json").read_text(encoding="utf-8"))
    units = {}
    for path in sorted((tracking / "units").glob("*.json")):
        unit = json.loads(path.read_text(encoding="utf-8"))
        units[unit["id"]] = unit
    return project, units


def pull_request_units(pull_requests: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for pull_request in pull_requests:
        matches = set(MARKER.findall(pull_request.get("body") or ""))
        for unit_id in matches:
            result.setdefault(unit_id, []).append(pull_request)
    return result


def render_body(unit: dict[str, Any], pull_requests: tuple[int, ...]) -> str:
    dependencies = unit["dependsOn"] or ["None"]
    completion_dependencies = unit["completionDependsOn"] or ["None"]
    checkpoints = unit["checkpoints"] or ["None"]
    references = [
        f"[`{reference['path']}` - {reference['heading']}](https://github.com/"
        f"ibanner56/CallersCompendium/blob/main/{reference['path']})"
        for reference in unit["specReferences"]
    ]
    checkbox = "x" if unit["completion"]["complete"] else " "
    conditions = "\n".join(
        f"- [{checkbox}] {condition}" for condition in unit["completion"]["conditions"]
    )
    evidence = unit["completion"]["evidence"]
    evidence_text = "\n".join(f"- {item}" for item in evidence) if evidence else "- None yet"
    prs = (
        "\n".join(
            f"- [#{number}](https://github.com/ibanner56/CallersCompendium/pull/{number})"
            for number in pull_requests
        )
        if pull_requests
        else "- None yet"
    )
    hold = unit["hold"]
    blocked = hold["reason"] if hold else "No"
    return "\n".join(
        [
            "<!-- generated from repository tracking; direct edits are overwritten -->",
            f"<!-- tracking-card: {unit['id']} -->",
            "",
            unit["summary"],
            "",
            f"**Work unit:** `{unit['id']}`  ",
            f"**Dependencies:** {', '.join(dependencies)}  ",
            f"**Required before completion:** {', '.join(completion_dependencies)}  ",
            f"**Checkpoints:** {', '.join(checkpoints)}  ",
            f"**Blocked:** {blocked}",
            "",
            "**Produces**",
            *[f"- {item}" for item in unit["produces"]],
            "",
            "**Completion conditions**",
            conditions,
            "",
            "**Evidence**",
            evidence_text,
            "",
            "**Pull requests**",
            prs,
            "",
            "**Source sections**",
            *[f"- {reference}" for reference in references],
        ]
    )


def build_desired_items(
    units: dict[str, dict[str, Any]],
    pull_requests: list[dict[str, Any]],
) -> dict[str, DesiredItem]:
    active_by_unit = pull_request_units(pull_requests)
    desired: dict[str, DesiredItem] = {}
    for unit_id, unit in units.items():
        active = active_by_unit.get(unit_id, [])
        complete = unit["completion"]["complete"]
        if complete:
            status = "Done"
        elif any(not pull_request["isDraft"] for pull_request in active):
            status = "In review"
        elif active:
            status = "In progress"
        elif all(units[dependency]["completion"]["complete"] for dependency in unit["dependsOn"]):
            status = "Ready"
        else:
            status = "Planned"

        all_pull_requests = tuple(
            sorted(
                set(unit["pullRequests"])
                | {pull_request["number"] for pull_request in active}
            )
        )
        hold = unit["hold"]
        desired[unit_id] = DesiredItem(
            unit_id=unit_id,
            title=f"{unit_id.split('/')[-1]} - {unit['title']}",
            body=render_body(unit, all_pull_requests),
            status=status,
            phase=PHASE_NAMES[unit["phase"]],
            sequence=unit["sequence"],
            dependencies=(
                "Start: "
                + (", ".join(unit["dependsOn"]) if unit["dependsOn"] else "None")
                + "; completion: "
                + (
                    ", ".join(unit["completionDependsOn"])
                    if unit["completionDependsOn"]
                    else "None"
                )
            ),
            blocked=hold is not None,
            blocked_reason=hold["reason"] if hold else "None",
            pull_requests=all_pull_requests,
            pull_request_text=(
                ", ".join(f"#{number}" for number in all_pull_requests)
                if all_pull_requests
                else "None"
            ),
            checkpoints=", ".join(unit["checkpoints"]) if unit["checkpoints"] else "None",
        )
    return desired


def qualified_pull_requests(
    pull_requests: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    qualified = []
    for pull_request in pull_requests:
        if not isinstance(pull_request, dict):
            continue
        number = pull_request.get("number")
        body = pull_request.get("body")
        title = pull_request.get("title")
        head_ref = pull_request.get("headRefName")
        paths = pull_request.get("changedPaths")
        head_unit = pull_request.get("headUnit")
        if (
            not isinstance(number, int)
            or not isinstance(body, str)
            or not isinstance(title, str)
            or not isinstance(head_ref, str)
            or not isinstance(paths, list)
            or any(not isinstance(path, str) for path in paths)
            or not isinstance(head_unit, dict)
        ):
            continue
        pull_request_numbers = head_unit.get("pullRequests")
        if not isinstance(pull_request_numbers, list) or any(
            not isinstance(value, int) for value in pull_request_numbers
        ):
            continue
        matches = sorted(set(MARKER.findall(body)))
        if len(matches) != 1:
            continue
        unit_id = matches[0]
        short_id = unit_id.rsplit("/", 1)[1]
        expected_path = f".github/tracking/adr-004/units/{short_id}.json"
        unit_paths = [
            path
            for path in paths
            if re.fullmatch(
                r"\.github/tracking/adr-004/units/W(?:0|[1-9]|1[0-8])\.json",
                path,
            )
        ]
        if unit_paths != [expected_path]:
            continue
        if not title.startswith(f"[{unit_id}] "):
            continue
        if f"adr-004-{short_id.lower()}-" not in head_ref.lower():
            continue
        if head_unit.get("id") != unit_id:
            continue
        if number not in pull_request_numbers:
            continue
        errors = validate_pull_request(
            changed_paths=paths,
            title=title,
            body=body,
            head_ref=head_ref,
            number=number,
            pull_requests={unit_id: pull_request_numbers},
            bootstrap=False,
            author_association=pull_request.get("authorAssociation") or "",
        )
        if errors:
            continue
        qualified.append(pull_request)
    return qualified


def decode_head_unit_blob(blob: dict[str, Any]) -> dict[str, Any] | None:
    if (
        blob.get("encoding") != "base64"
        or not isinstance(blob.get("size"), int)
        or blob["size"] > 65536
        or not isinstance(blob.get("content"), str)
    ):
        return None
    compact = re.sub(r"[ \t\r\n]", "", blob["content"])
    try:
        decoded = base64.b64decode(compact, validate=True)
        value = json.loads(decoded.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError, RecursionError):
        return None
    return value if isinstance(value, dict) else None


def gh_json(args: list[str], token: str, *, input_value: object | None = None) -> Any:
    environment = os.environ.copy()
    environment["GH_TOKEN"] = token
    encoded = None
    if input_value is not None:
        encoded = json.dumps(input_value)
    result = subprocess.run(
        ["gh", *args],
        input=encoded,
        check=False,
        capture_output=True,
        encoding="utf-8",
        env=environment,
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"gh {' '.join(args[:3])} failed: {detail}")
    return json.loads(result.stdout) if result.stdout.strip() else None


def graphql(query: str, variables: dict[str, Any], token: str) -> Any:
    response = gh_json(
        ["api", "graphql", "--input", "-"],
        token,
        input_value={"query": query, "variables": variables},
    )
    if response.get("errors"):
        raise RuntimeError(f"GraphQL failed: {response['errors']}")
    return response["data"]


def list_open_pull_requests(repository: str, token: str) -> list[dict[str, Any]]:
    response = gh_json(
        [
            "pr",
            "list",
            "--repo",
            repository,
            "--state",
            "open",
            "--limit",
            "200",
            "--json",
            "number,isDraft,title,body,url,headRefName,changedFiles,authorAssociation",
        ],
        token,
    )
    assert isinstance(response, list)
    for pull_request in response:
        if pull_request["changedFiles"] > 100:
            pull_request["changedPaths"] = []
            continue
        files = gh_json(
            [
                "api",
                f"repos/{repository}/pulls/{pull_request['number']}/files?per_page=100",
            ],
            token,
        )
        pull_request["changedPaths"] = [file["filename"] for file in files]
        matches = sorted(set(MARKER.findall(pull_request.get("body") or "")))
        if len(matches) != 1:
            continue
        expected_path = (
            ".github/tracking/adr-004/units/"
            + matches[0].rsplit("/", 1)[1]
            + ".json"
        )
        matching_files = [file for file in files if file["filename"] == expected_path]
        if len(matching_files) != 1:
            continue
        blob = gh_json(
            [
                "api",
                f"repos/{repository}/git/blobs/{matching_files[0]['sha']}",
            ],
            token,
        )
        head_unit = decode_head_unit_blob(blob)
        if head_unit is None:
            continue
        pull_request["headUnit"] = head_unit
    return qualified_pull_requests(response)


def project_state(owner: str, number: int, token: str) -> dict[str, Any]:
    query = """
    query($login: String!, $number: Int!) {
      user(login: $login) {
        projectV2(number: $number) {
          id
          fields(first: 100) {
            nodes {
              ... on ProjectV2Field { id name dataType }
              ... on ProjectV2SingleSelectField {
                id
                name
                options { id name }
              }
            }
          }
          items(first: 100) {
            nodes {
              id
              content {
                ... on DraftIssue { id title body }
              }
              fieldValues(first: 50) {
                nodes {
                  ... on ProjectV2ItemFieldTextValue {
                    text
                    field { ... on ProjectV2Field { id name } }
                  }
                  ... on ProjectV2ItemFieldNumberValue {
                    number
                    field { ... on ProjectV2Field { id name } }
                  }
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name
                    optionId
                    field { ... on ProjectV2SingleSelectField { id name } }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
    data = graphql(query, {"login": owner, "number": number}, token)
    project = data.get("user", {}).get("projectV2")
    if not project:
        raise RuntimeError(f"Project {owner}/{number} was not found")
    return project


def project_item_unit_id(item: dict[str, Any]) -> str | None:
    values = {}
    for value in item["fieldValues"]["nodes"]:
        if not value:
            continue
        field = value.get("field")
        if field and field.get("name"):
            values[field["name"]] = value
    unit_value = values.get("Work Unit ID")
    field_unit = unit_value.get("text") if unit_value else None
    if not isinstance(field_unit, str) or not MARKER.fullmatch(
        f"<!-- tracking-unit: {field_unit} -->"
    ):
        field_unit = None
    content = item.get("content") or {}
    matches = sorted(set(CARD_MARKER.findall(content.get("body") or "")))
    card_unit = matches[0] if len(matches) == 1 else None
    if field_unit and card_unit and field_unit != card_unit:
        raise RuntimeError(
            f"Project item {item.get('id', '?')} has conflicting generated identities "
            f"{field_unit} and {card_unit}"
        )
    return card_unit or field_unit


def parse_project(project: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    fields = {
        field["name"]: field
        for field in project["fields"]["nodes"]
        if field and field.get("name") in FIELD_NAMES
    }
    missing = sorted(set(FIELD_NAMES) - set(fields))
    if missing:
        raise RuntimeError(f"Project is missing fields: {', '.join(missing)}")

    items: dict[str, Any] = {}
    for item in project["items"]["nodes"]:
        values = {}
        for value in item["fieldValues"]["nodes"]:
            if not value:
                continue
            field = value.get("field")
            if field and field.get("name"):
                values[field["name"]] = value
        unit_id = project_item_unit_id(item)
        if not unit_id:
            raise RuntimeError(
                f"Project item {item['id']} has no Work Unit ID; "
                "all cards must be generated"
            )
        if unit_id in items:
            raise RuntimeError(f"Project contains duplicate Work Unit ID {unit_id}")
        content = item.get("content")
        if not content or not content.get("id"):
            raise RuntimeError(f"Project item {item['id']} is not a draft item")
        items[unit_id] = {
            "itemId": item["id"],
            "contentId": content["id"],
            "title": content.get("title") or "",
            "body": content.get("body") or "",
            "values": values,
        }
    return fields, items


def create_item(
    project_id: str,
    title: str,
    body: str,
    token: str,
) -> tuple[str, str]:
    query = """
    mutation($project: ID!, $title: String!, $body: String!) {
      addProjectV2DraftIssue(
        input: {projectId: $project, title: $title, body: $body}
      ) {
        projectItem {
          id
          content { ... on DraftIssue { id } }
        }
      }
    }
    """
    data = graphql(
        query,
        {"project": project_id, "title": title, "body": body},
        token,
    )
    item = data["addProjectV2DraftIssue"]["projectItem"]
    return item["id"], item["content"]["id"]


def update_draft(
    content_id: str,
    title: str,
    body: str,
    token: str,
) -> None:
    query = """
    mutation($id: ID!, $title: String!, $body: String!) {
      updateProjectV2DraftIssue(
        input: {draftIssueId: $id, title: $title, body: $body}
      ) { draftIssue { id } }
    }
    """
    graphql(query, {"id": content_id, "title": title, "body": body}, token)


def option_id(field: dict[str, Any], name: str) -> str:
    options = {option["name"]: option["id"] for option in field.get("options", [])}
    if name not in options:
        raise RuntimeError(f"Field {field['name']} has no option {name}")
    return options[name]


def desired_field_values(
    fields: dict[str, Any],
    desired: DesiredItem,
) -> dict[str, dict[str, Any]]:
    return {
        "Status": {"singleSelectOptionId": option_id(fields["Status"], desired.status)},
        "Work Unit ID": {"text": desired.unit_id},
        "Phase": {"singleSelectOptionId": option_id(fields["Phase"], desired.phase)},
        "Sequence": {"number": desired.sequence},
        "Dependencies": {"text": desired.dependencies},
        "Blocked": {
            "singleSelectOptionId": option_id(
                fields["Blocked"], "Yes" if desired.blocked else "No"
            )
        },
        "Blocked reason": {"text": desired.blocked_reason},
        "Pull requests": {"text": desired.pull_request_text},
        "Checkpoints": {"text": desired.checkpoints},
    }


def current_field_value(value: dict[str, Any] | None) -> object:
    if not value:
        return None
    if "text" in value:
        return value["text"]
    if "number" in value:
        return value["number"]
    if "optionId" in value:
        return value["optionId"]
    return None


def changed_field_values(
    current: dict[str, Any],
    desired: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    result = {}
    for name, value in desired.items():
        expected = next(iter(value.values()))
        if current_field_value(current.get(name)) != expected:
            result[name] = value
    return result


def update_fields(
    project_id: str,
    item_id: str,
    fields: dict[str, Any],
    values: dict[str, dict[str, Any]],
    token: str,
) -> None:
    if not values:
        return
    definitions = ["$project: ID!", "$item: ID!"]
    selections = []
    variables: dict[str, Any] = {"project": project_id, "item": item_id}
    for index, (name, value) in enumerate(values.items()):
        definitions.extend(
            [f"$field{index}: ID!", f"$value{index}: ProjectV2FieldValue!"]
        )
        selections.append(
            f"""f{index}: updateProjectV2ItemFieldValue(
              input: {{
                projectId: $project
                itemId: $item
                fieldId: $field{index}
                value: $value{index}
              }}
            ) {{ projectV2Item {{ id }} }}"""
        )
        variables[f"field{index}"] = fields[name]["id"]
        variables[f"value{index}"] = value
    query = f"mutation({', '.join(definitions)}) {{ {' '.join(selections)} }}"
    graphql(query, variables, token)


def reconcile(
    project_config: dict[str, Any],
    desired_items: dict[str, DesiredItem],
    project_token: str,
) -> None:
    owner = project_config["project"]["owner"]
    number = project_config["project"]["number"]
    current = project_state(owner, number, project_token)
    fields, items = parse_project(current)
    unknown = sorted(set(items) - set(desired_items))
    if unknown:
        raise RuntimeError(
            "Project contains unknown work units; refusing to delete them: "
            + ", ".join(unknown)
        )

    for unit_id in sorted(desired_items, key=lambda key: desired_items[key].sequence):
        desired = desired_items[unit_id]
        item = items.get(unit_id)
        content_changed = False
        if item is None:
            item_id, content_id = create_item(
                current["id"],
                desired.title,
                desired.body,
                project_token,
            )
            time.sleep(1)
            content_changed = True
        else:
            item_id = item["itemId"]
            content_id = item["contentId"]
            if item["title"] != desired.title or item["body"] != desired.body:
                update_draft(content_id, desired.title, desired.body, project_token)
                content_changed = True
        desired_values = desired_field_values(fields, desired)
        current_values = item["values"] if item is not None else {}
        changes = changed_field_values(current_values, desired_values)
        update_fields(
            current["id"],
            item_id,
            fields,
            changes,
            project_token,
        )
        action = "SYNCED" if changes or content_changed else "UNCHANGED"
        print(f"{action}: {unit_id} -> {desired.status}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="write desired state to GitHub; default prints it",
    )
    parser.add_argument(
        "--project-token-env",
        default="DEVICE_SYNC_PROJECT_TOKEN",
    )
    parser.add_argument(
        "--repository-token-env",
        default="GITHUB_TOKEN",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    project, units = load_tracking(args.root)
    repository_token = os.environ.get(args.repository_token_env) or os.environ.get(
        "GH_TOKEN"
    )
    pull_requests: list[dict[str, Any]] = []
    if repository_token:
        pull_requests = list_open_pull_requests(project["repository"], repository_token)
    desired = build_desired_items(units, pull_requests)

    if not args.apply:
        print(
            json.dumps(
                {
                    unit_id: {
                        "status": item.status,
                        "blocked": item.blocked,
                        "pullRequests": item.pull_requests,
                    }
                    for unit_id, item in desired.items()
                },
                indent=2,
            )
        )
        return 0

    project_token = os.environ.get(args.project_token_env)
    if not project_token:
        print(
            f"ERROR: {args.project_token_env} is required with --apply",
            file=sys.stderr,
        )
        return 2
    reconcile(project, desired, project_token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
