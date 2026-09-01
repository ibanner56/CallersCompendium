#!/usr/bin/env python3
"""Validate Device Sync pull-request ownership metadata."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARKER = re.compile(r"<!--\s*tracking-unit:\s*(ADR-004/W(?:0|[1-9]|1[0-8]))\s*-->")
ADMIN_MARKER = re.compile(r"<!--\s*tracking-admin\s*-->")
UNIT_PATH = re.compile(r"\.github/tracking/adr-004/units/(W(?:0|[1-9]|1[0-8]))\.json\Z")
ADMIN_PATH_PREFIXES = (
    ".github/tracking/",
    "tools/tracking/",
)
ADMIN_PATHS = {
    ".github/instructions/device-sync-tracking.instructions.md",
    ".github/workflows/_checks.yml",
    ".github/workflows/ci.yml",
    ".github/workflows/device-sync-tracking.yml",
    "docs/adr/004-device-sync-and-athenaeum.md",
    "docs/design/sync-implementation.md",
    "docs/design/sync-spec.md",
    "docs/design/sync.md",
    "tools/preflight.py",
}
CONTROL_PATH_PREFIXES = ("tools/tracking/",)
CONTROL_PATHS = {
    ".github/instructions/device-sync-tracking.instructions.md",
    ".github/tracking/README.md",
    ".github/tracking/adr-004/project.json",
    ".github/workflows/_checks.yml",
    ".github/workflows/ci.yml",
    ".github/workflows/device-sync-tracking.yml",
    "tools/preflight.py",
}


def is_admin_path(path: str) -> bool:
    return path in ADMIN_PATHS or any(
        path.startswith(prefix) for prefix in ADMIN_PATH_PREFIXES
    )


def is_control_path(path: str) -> bool:
    return path in CONTROL_PATHS or any(
        path.startswith(prefix) for prefix in CONTROL_PATH_PREFIXES
    )


def validate_pull_request(
    *,
    changed_paths: list[str],
    title: str,
    body: str,
    head_ref: str,
    number: int,
    pull_requests: dict[str, list[int]],
    bootstrap: bool,
    author_association: str,
) -> list[str]:
    errors: list[str] = []
    markers = sorted(set(MARKER.findall(body)))
    admin = bool(ADMIN_MARKER.search(body))
    changed_units = [
        (match.group(1), path)
        for path in changed_paths
        if (match := UNIT_PATH.fullmatch(path))
    ]

    if admin and markers:
        errors.append("tracking-admin and tracking-unit markers cannot be combined")
        return errors
    if bootstrap:
        if not admin or author_association != "OWNER":
            errors.append("tracking bootstrap requires repository-owner tracking-admin")
        invalid_paths = [path for path in changed_paths if not is_admin_path(path)]
        if invalid_paths:
            errors.append(
                "tracking bootstrap is limited to the administrative path set: "
                + ", ".join(sorted(invalid_paths))
            )
        return errors

    control_paths = [path for path in changed_paths if is_control_path(path)]
    if control_paths and not admin:
        errors.append(
            "tracking control paths require tracking-admin: "
            + ", ".join(sorted(control_paths))
        )
        return errors
    if admin:
        if author_association != "OWNER":
            errors.append("tracking-admin requires repository-owner association")
        invalid_paths = [
            path
            for path in changed_paths
            if not is_admin_path(path)
        ]
        if invalid_paths:
            errors.append(
                "tracking-admin is limited to the administrative path set: "
                + ", ".join(sorted(invalid_paths))
            )
        return errors
    if not changed_units and not markers:
        return errors
    if len(markers) != 1:
        errors.append("a work-unit change requires one tracking-unit marker")
        return errors

    unit_id = markers[0]
    short_id = unit_id.rsplit("/", 1)[1]
    expected_path = f".github/tracking/adr-004/units/{short_id}.json"
    if len(changed_units) != 1 or changed_units[0][1] != expected_path:
        errors.append(
            f"{unit_id} must change its owning unit file {expected_path} and no other unit file"
        )
    if not title.startswith(f"[{unit_id}] "):
        errors.append(f"pull request title must start with [{unit_id}] ")
    branch_token = f"adr-004-{short_id.lower()}-"
    if branch_token not in head_ref.lower():
        errors.append(f"branch name must contain {branch_token}")
    if number not in pull_requests.get(unit_id, []):
        errors.append(f"{unit_id} must include pull request #{number} in pullRequests")
    return errors


def changed_paths(base: str, head: str) -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", f"{base}...{head}"],
        check=False,
        capture_output=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return [
        value.decode("utf-8")
        for value in result.stdout.split(b"\0")
        if value
    ]


def is_bootstrap(base: str) -> bool:
    result = subprocess.run(
        [
            "git",
            "cat-file",
            "-e",
            f"{base}:.github/tracking/adr-004/project.json",
        ],
        check=False,
        capture_output=True,
    )
    return result.returncode != 0


def load_pull_requests(root: Path) -> dict[str, list[int]]:
    result = {}
    for path in (root / ".github" / "tracking" / "adr-004" / "units").glob("*.json"):
        try:
            unit = json.loads(path.read_text(encoding="utf-8"))
            unit_id = unit["id"]
            pull_requests = unit["pullRequests"]
        except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError) as error:
            raise RuntimeError(f"unable to read {path}: {error}") from error
        if not isinstance(unit_id, str) or not isinstance(pull_requests, list):
            raise RuntimeError(f"unable to read {path}: invalid id or pullRequests")
        result[unit_id] = pull_requests
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("base_sha")
    parser.add_argument("head_sha")
    parser.add_argument("event_path", type=Path)
    parser.add_argument("--root", type=Path, default=ROOT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        event = json.loads(args.event_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"ERROR: unable to read pull request event: {error}")
        return 2
    pull_request = event.get("pull_request")
    if not isinstance(pull_request, dict):
        print("ERROR: event has no pull_request object")
        return 2
    try:
        paths = changed_paths(args.base_sha, args.head_sha)
        bootstrap = is_bootstrap(args.base_sha)
        pull_requests = load_pull_requests(args.root)
    except RuntimeError as error:
        print(f"ERROR: unable to inspect pull request: {error}")
        return 2
    errors = validate_pull_request(
        changed_paths=paths,
        title=pull_request.get("title") or "",
        body=pull_request.get("body") or "",
        head_ref=pull_request.get("head", {}).get("ref") or "",
        number=pull_request.get("number") or 0,
        pull_requests=pull_requests,
        bootstrap=bootstrap,
        author_association=pull_request.get("author_association") or "",
    )
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("OK: Device Sync pull-request ownership is valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
