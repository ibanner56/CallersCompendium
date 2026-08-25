#!/usr/bin/env python3
"""Generate accurate SLSA provenance inputs for an existing-tag recovery."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlparse


_REPOSITORY_RE = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
_RELEASE_REF_RE = re.compile(
    r"refs/tags/v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)(?:-beta)?"
)
_SHA_RE = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})")


def _validate_sha(value: str, label: str) -> str:
    if not _SHA_RE.fullmatch(value):
        raise ValueError(f"{label} must be a 40- or 64-character lowercase hex SHA")
    return value


def build_predicate(
    *,
    repository: str,
    server_url: str,
    workflow_ref: str,
    workflow_sha: str,
    release_ref: str,
    source_sha: str,
    run_id: str,
    run_attempt: str,
) -> dict[str, object]:
    """Return a GitHub Actions SLSA v1 predicate with split source/workflow refs."""
    if not _REPOSITORY_RE.fullmatch(repository):
        raise ValueError("repository must be in owner/name form")
    parsed_url = urlparse(server_url)
    if parsed_url.scheme not in {"http", "https"} or not parsed_url.netloc:
        raise ValueError("server_url must be an absolute HTTP(S) URL")
    server_url = server_url.rstrip("/")
    if not _RELEASE_REF_RE.fullmatch(release_ref):
        raise ValueError("release_ref must be refs/tags/vX.Y.Z or refs/tags/vX.Y.Z-beta")
    _validate_sha(source_sha, "source_sha")
    _validate_sha(workflow_sha, "workflow_sha")
    if not run_id.isdigit() or not run_attempt.isdigit():
        raise ValueError("run_id and run_attempt must be decimal integers")

    prefix = f"{repository}/"
    if not workflow_ref.startswith(prefix) or "@" not in workflow_ref:
        raise ValueError("workflow_ref must identify a workflow in repository")
    workflow_path, workflow_git_ref = workflow_ref[len(prefix):].rsplit("@", 1)
    if not workflow_path.startswith(".github/workflows/"):
        raise ValueError("workflow_ref path must be under .github/workflows")
    if not workflow_git_ref.startswith("refs/"):
        raise ValueError("workflow_ref must end in a full refs/... Git ref")

    repository_url = f"{server_url}/{repository}"
    return {
        "buildDefinition": {
            "buildType": "https://actions.github.io/buildtypes/workflow/v1",
            "externalParameters": {
                "inputs": {"release_tag": release_ref.removeprefix("refs/tags/")},
                "workflow": {
                    "ref": workflow_git_ref,
                    "repository": repository_url,
                    "path": workflow_path,
                }
            },
            "internalParameters": {
                "github": {
                    "event_name": "workflow_dispatch",
                }
            },
            "resolvedDependencies": [
                {
                    "uri": f"git+{repository_url}@{release_ref}",
                    "digest": {"gitCommit": source_sha},
                },
                {
                    "uri": f"git+{repository_url}@{workflow_git_ref}",
                    "digest": {"gitCommit": workflow_sha},
                },
            ],
        },
        "runDetails": {
            "builder": {"id": f"{server_url}/{workflow_ref}"},
            "metadata": {
                "invocationId": (
                    f"{repository_url}/actions/runs/{run_id}/attempts/{run_attempt}"
                )
            },
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--server-url", required=True)
    parser.add_argument("--workflow-ref", required=True)
    parser.add_argument("--workflow-sha", required=True)
    parser.add_argument("--release-ref", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    predicate = build_predicate(
        repository=args.repository,
        server_url=args.server_url,
        workflow_ref=args.workflow_ref,
        workflow_sha=args.workflow_sha,
        release_ref=args.release_ref,
        source_sha=args.source_sha,
        run_id=args.run_id,
        run_attempt=args.run_attempt,
    )
    args.output.write_text(
        json.dumps(predicate, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
