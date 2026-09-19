#!/usr/bin/env python3
"""Pull-request path classifier: decides which CI validation is required.

``ci.yml``'s ``classify`` job needs this to answer one question per changed-path
set: which of the expensive validation/build jobs actually have to run? Getting
it wrong in either direction is a real cost — too broad wastes runner minutes on
every PR, too narrow lets a real defect merge past its own guard. The decision
itself (``classify()`` below) is a pure function of the changed-path list, kept
separate from the git/GitHub plumbing in ``main()`` so it can be unit-tested
directly (see ``test_classify_changes.py``) rather than only exercised by a real
Actions run.

Usage (as invoked from ``.github/workflows/ci.yml``):

    classify_changes.py <base_sha> <head_sha> <before_sha>

Reads ``BASE_SHA``/``HEAD_SHA``/``BEFORE_SHA`` semantics from argv (mirroring the
pull_request event's base/head and the push event's ``before``), and the
``GITHUB_TOKEN``/``GITHUB_REPOSITORY``/``GITHUB_OUTPUT`` environment variables
set by Actions. Writes each output as ``name=value`` (lowercase bool) to
``GITHUB_OUTPUT``, matching the job's declared ``outputs:``.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# Paths that affect every suite regardless of which directory they sit in:
# the pinned Flutter version, the workspace pubspec (and its lockfile), the
# shared analyzer config, and the reusable checks workflow itself.
SHARED_RUNTIME_PATHS = {
    b".fvmrc",
    b"pubspec.yaml",
    b"pubspec.lock",
    b"analysis_options.yaml",
    b".github/workflows/_checks.yml",
}

# The core suite's own coverage/guard drivers: a change here can break core
# validation without touching anything under packages/compendium_core/.
CORE_TEST_DRIVER_PATHS = {
    b"tools/ci/run_core_tests_with_coverage.py",
    b"tools/ci/check_core_coverage.py",
    b"tools/ci/check_core_flutter_free.py",
}

# Generated Markdown that is actually code: docs/dev/data-classification.md is
# rendered from field_registry.dart by generate_data_classification_doc.dart,
# and packages/compendium_core/test/privacy/data_classification_doc_test.dart
# is the freshness guard that catches drift between the two. Without this,
# an all-Markdown diff limited to this one file sets validation_changed=false
# (every changed path ends in .md) and the guard that exists specifically to
# catch a hand-edit of this file never runs.
GENERATED_MARKDOWN_PATHS = {
    b"docs/dev/data-classification.md",
}

OUTPUT_KEYS = (
    "validation_changed",
    "core_tests_changed",
    "app_tests_changed",
    "server_tests_changed",
    "builds_changed",
)


def classify(paths):
    """Computes the classify job's outputs for a set of changed paths.

    ``paths`` is an iterable of repo-relative paths as ``bytes`` (matching
    ``git diff --name-only -z`` output), with no leading slash.

    Returns a ``dict`` mapping each of ``OUTPUT_KEYS`` to a ``bool``.
    """
    paths = tuple(paths)
    validation_changed = any(
        not path.endswith(b".md") or path in GENERATED_MARKDOWN_PATHS
        for path in paths
    )
    core_tests_changed = validation_changed and any(
        path.startswith(b"packages/compendium_core/")
        or path in SHARED_RUNTIME_PATHS
        or path in CORE_TEST_DRIVER_PATHS
        or path in GENERATED_MARKDOWN_PATHS
        for path in paths
    )
    app_tests_changed = validation_changed and any(
        path.startswith(b"app/")
        or path.startswith(b"packages/compendium_core/")
        or path in SHARED_RUNTIME_PATHS
        for path in paths
    )
    server_tests_changed = validation_changed and any(
        path.startswith(b"server/") or path in SHARED_RUNTIME_PATHS
        for path in paths
    )
    builds_changed = app_tests_changed
    return {
        "validation_changed": validation_changed,
        "core_tests_changed": core_tests_changed,
        "app_tests_changed": app_tests_changed,
        "server_tests_changed": server_tests_changed,
        "builds_changed": builds_changed,
    }


def _resolve_commit(ref: str) -> bool:
    resolved = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        capture_output=True,
        check=False,
    )
    return resolved.returncode == 0


def _prior_merge_gate_succeeded(sha: str) -> bool:
    token = os.environ.get("GITHUB_TOKEN")
    repository = os.environ.get("GITHUB_REPOSITORY")
    if not token or not repository:
        print(
            "::notice::Cannot confirm the previous Merge gate; "
            "checking the full pull request diff."
        )
        return False
    request = Request(
        f"https://api.github.com/repos/{repository}/commits/{sha}/check-runs"
        "?check_name=Merge%20gate",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urlopen(request, timeout=10) as response:
            check_runs = json.load(response)["check_runs"]
    except (HTTPError, URLError, KeyError, json.JSONDecodeError) as error:
        print(
            "::notice::Cannot confirm the previous Merge gate "
            f"({error}); checking the full pull request diff."
        )
        return False
    return any(
        check_run.get("name") == "Merge gate"
        and check_run.get("status") == "completed"
        and check_run.get("conclusion") == "success"
        and (check_run.get("app") or {}).get("slug") == "github-actions"
        for check_run in check_runs
    )


def main(argv: list[str]) -> int:
    base, head, before = argv[1], argv[2], argv[3]

    for label, ref in (("Pull request base", base), ("Pull request head", head)):
        if not _resolve_commit(ref):
            print(f"::error::{label} SHA does not resolve.")
            return 1

    diff_range = f"{base}...{head}"
    if before and before != head:
        before_resolved = _resolve_commit(before)
        is_ancestor = subprocess.run(
            ["git", "merge-base", "--is-ancestor", before, head],
            capture_output=True,
            check=False,
        )
        if (
            before_resolved
            and is_ancestor.returncode == 0
            and _prior_merge_gate_succeeded(before)
        ):
            diff_range = f"{before}..{head}"
            print("Classifying only changes since the successful previous Merge gate.")

    result = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", diff_range],
        capture_output=True,
        check=False,
    )
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()
        print(f"::error::Unable to determine pull request changes: {detail}")
        return 1

    paths = tuple(path for path in result.stdout.split(b"\0") if path)
    if not paths:
        print("::error::Pull request has no changed paths; refusing to skip validation.")
        return 1

    outputs = classify(paths)
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output_file:
        for name in OUTPUT_KEYS:
            output_file.write(f"{name}={str(outputs[name]).lower()}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
