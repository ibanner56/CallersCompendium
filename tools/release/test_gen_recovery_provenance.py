#!/usr/bin/env python3
"""Unit tests for ``gen_recovery_provenance.py``."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_recovery_provenance as provenance  # noqa: E402


REPOSITORY = "ibanner56/CallersCompendium"
SERVER_URL = "https://github.com"
WORKFLOW_REF = (
    "ibanner56/CallersCompendium/.github/workflows/release.yml@refs/heads/main"
)
WORKFLOW_SHA = "0" * 40
RELEASE_REF = "refs/tags/v0.1.1-beta"
SOURCE_SHA = "f" * 40


def _build(**overrides: str) -> dict[str, object]:
    values = {
        "repository": REPOSITORY,
        "server_url": SERVER_URL,
        "workflow_ref": WORKFLOW_REF,
        "workflow_sha": WORKFLOW_SHA,
        "release_ref": RELEASE_REF,
        "source_sha": SOURCE_SHA,
        "run_id": "123",
        "run_attempt": "2",
    }
    values.update(overrides)
    return provenance.build_predicate(**values)


def main() -> None:
    predicate = _build()
    definition = predicate["buildDefinition"]
    assert isinstance(definition, dict)
    assert definition["externalParameters"] == {
        "inputs": {"release_tag": "v0.1.1-beta"},
        "workflow": {
            "path": ".github/workflows/release.yml",
            "ref": "refs/heads/main",
            "repository": "https://github.com/ibanner56/CallersCompendium",
        }
    }
    assert definition["internalParameters"] == {
        "github": {"event_name": "workflow_dispatch"}
    }
    assert definition["resolvedDependencies"] == [
        {
            "uri": (
                "git+https://github.com/ibanner56/CallersCompendium"
                "@refs/tags/v0.1.1-beta"
            ),
            "digest": {"gitCommit": SOURCE_SHA},
        },
        {
            "uri": (
                "git+https://github.com/ibanner56/CallersCompendium"
                "@refs/heads/main"
            ),
            "digest": {"gitCommit": WORKFLOW_SHA},
        },
    ]
    assert predicate["runDetails"] == {
        "builder": {"id": f"{SERVER_URL}/{WORKFLOW_REF}"},
        "metadata": {
            "invocationId": (
                "https://github.com/ibanner56/CallersCompendium/"
                "actions/runs/123/attempts/2"
            )
        },
    }

    invalid = (
        {"release_ref": "refs/heads/main"},
        {"release_ref": "refs/tags/v0.1.1-beta.2"},
        {"source_sha": "not-a-sha"},
        {"workflow_ref": "other/repo/.github/workflows/release.yml@refs/heads/main"},
        {"server_url": "file:///tmp/repo"},
    )
    for override in invalid:
        try:
            _build(**override)
        except ValueError:
            pass
        else:
            raise AssertionError(f"accepted invalid recovery provenance: {override}")

    print("gen_recovery_provenance: OK")


if __name__ == "__main__":
    main()
