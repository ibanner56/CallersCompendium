#!/usr/bin/env python3
"""Guard the test-build workflow: built like a release, approved like a release,
never released.

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``). Run directly::

    python3 tools/release/test_sync_test_build_workflow.py

``.github/workflows/test-build.yml`` exists to hand out signed builds that are
not releases (docs/dev/releasing.md#test-builds-signed-never-released). Three
properties make that safe, and each is checked here against the committed
files and then against mutated copies, so every check is shown to fail:

1. Its ``build`` job is byte-identical to release.yml's (signed the same way).
2. It enters every environment release.yml enters (approved the same way),
   and nothing it produces exists before all of them are approved.
3. It has no trigger but a manual dispatch, no write scope, and no step that
   publishes: no release, attestation, server deploy, store upload or update
   manifest.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import sync_test_build_workflow as sync  # noqa: E402

RELEASE_TEXT = sync.RELEASE_WORKFLOW.read_text(encoding="utf-8")
TEST_BUILD_TEXT = sync.TEST_BUILD_WORKFLOW.read_text(encoding="utf-8")

# Each is how release.yml publishes something; none may appear outside a
# comment in the test build. Checked below to still occur in release.yml, so a
# renamed command cannot leave this list guarding against nothing.
PUBLISHING_TOKENS = (
    "gh release",
    "xcrun altool",
    "r0adkll/upload-google-play",
    "actions/attest",
    "publish_pages_manifest.sh",
    "deploy_athenaeum.sh",
    "secrets.UPDATE_SIGNING_KEY",
    "secrets.ATHENAEUM_DEPLOY",
    "secrets.PLAY_SERVICE_ACCOUNT_JSON",
    "contents: write",
    "attestations: write",
)

APPROVAL_JOBS = ("approve_server", "approve_publication", "approve_manifest")

_JOB_HEADING = re.compile(r"^  ([A-Za-z_][A-Za-z0-9_-]*):\n", re.MULTILINE)
_ENV_SCALAR = re.compile(r"^    environment: (\S+)\s*$", re.MULTILINE)
_ENV_MAPPING = re.compile(r"^    environment:\n      name: (\S+)\s*$", re.MULTILINE)
_NEEDS = re.compile(r"^    needs: (.+?)\s*$", re.MULTILINE)


def _code(text: str) -> str:
    """``text`` without its full-line comments."""
    return "".join(
        line for line in text.splitlines(keepends=True) if not line.lstrip().startswith("#")
    )


def _jobs(text: str) -> dict[str, str]:
    """Top-level job id -> that job's text, for the ``jobs:`` mapping."""
    jobs_start = text.index("\njobs:\n") + len("\njobs:\n")
    body = text[jobs_start:]
    headings = list(_JOB_HEADING.finditer(body))
    return {
        heading.group(1): body[
            heading.start() : headings[i + 1].start() if i + 1 < len(headings) else len(body)
        ]
        for i, heading in enumerate(headings)
    }


def _environments(text: str) -> set[str]:
    return set(_ENV_SCALAR.findall(text)) | set(_ENV_MAPPING.findall(text))


def _needs(job_text: str) -> set[str]:
    match = _NEEDS.search(job_text)
    if match is None:
        return set()
    value = match.group(1).strip()
    if value.startswith("["):
        value = value.strip("[]")
    return {name.strip() for name in value.split(",") if name.strip()}


def _ancestors(jobs: dict[str, str], job: str) -> set[str]:
    seen: set[str] = set()
    pending = [job]
    while pending:
        for parent in _needs(jobs.get(pending.pop(), "")):
            if parent not in seen:
                seen.add(parent)
                pending.append(parent)
    return seen


def problems(release_text: str, test_build_text: str) -> list[str]:
    """Every way ``test_build_text`` breaks the three properties; empty if none."""
    found: list[str] = []

    # 1. Built and signed the same way.
    try:
        if sync.synced(release_text, test_build_text) != test_build_text:
            found.append("build job differs from release.yml's (run sync_test_build_workflow.py --write)")
    except ValueError as error:
        found.append(f"build job copy unreadable: {error}")

    # 2. Approved the same way, before anything exists.
    release_envs = _environments(release_text)
    test_envs = _environments(test_build_text)
    if release_envs != test_envs:
        found.append(
            f"environments differ: release.yml {sorted(release_envs)}, "
            f"test-build.yml {sorted(test_envs)}"
        )
    jobs = _jobs(test_build_text)
    for name in APPROVAL_JOBS:
        job = jobs.get(name)
        if job is None:
            found.append(f"missing approval job {name}")
            continue
        if "      deployment: false\n" not in job:
            found.append(f"{name} must not create a deployment (deployment: false)")
        if "    permissions: {}\n" not in job:
            found.append(f"{name} must have no token scopes (permissions: {{}})")
        if "secrets." in job or "uses:" in job:
            found.append(f"{name} must reference no secret and run no action")
    for job_name, job in jobs.items():
        if job_name in APPROVAL_JOBS or job_name == "meta":
            continue
        missing = set(APPROVAL_JOBS) - _ancestors(jobs, job_name)
        if missing:
            found.append(f"{job_name} can run before approval jobs {sorted(missing)}")

    # 3. Never released.
    on_block = re.search(r"^on:\n((?:[ \t]+.*\n|\n)*)", test_build_text, re.MULTILINE)
    triggers = on_block.group(1).split() if on_block else []
    if triggers != ["workflow_dispatch:"]:
        found.append(f"the only trigger must be workflow_dispatch, found {triggers}")
    if "\npermissions:\n  contents: read\n\n" not in test_build_text:
        found.append("the workflow-level token must be exactly contents: read")
    if "workflow_call" in _code(test_build_text):
        found.append("the test build must not be callable from another workflow")
    code = _code(test_build_text)
    for token in PUBLISHING_TOKENS:
        if token in code:
            found.append(f"publishing command or scope present: {token!r}")
    return found


def test_committed_workflow_holds_every_property() -> None:
    assert problems(RELEASE_TEXT, TEST_BUILD_TEXT) == [], problems(
        RELEASE_TEXT, TEST_BUILD_TEXT
    )


def test_publishing_tokens_still_name_what_release_does() -> None:
    release_code = _code(RELEASE_TEXT)
    stale = [token for token in PUBLISHING_TOKENS if token not in release_code]
    assert not stale, f"release.yml no longer uses {stale}; update PUBLISHING_TOKENS"


def test_release_environments_are_the_four_known_gates() -> None:
    # If release.yml gains or loses an approval, the test build must follow;
    # problems() catches the mismatch, this pins what "all four" means today.
    assert _environments(RELEASE_TEXT) == {
        "release-signing",
        "release-server",
        "release-publication",
        "release-manifest",
    }, _environments(RELEASE_TEXT)


def test_extracted_job_is_whole_and_excludes_the_next_job_comment() -> None:
    job = sync.extract_build_job(RELEASE_TEXT)
    assert job.startswith("  build:\n")
    assert "    environment: release-signing\n" in job
    assert "name: android-aab" in job, "the job's last step must be included"
    assert not job.splitlines()[-1].lstrip().startswith("#")
    assert "publish_draft" not in _code(job)
    assert sync.copied_region(TEST_BUILD_TEXT) == job


def _expect(mutated_release: str, mutated_test_build: str, needle: str) -> None:
    found = problems(mutated_release, mutated_test_build)
    assert any(needle in problem for problem in found), (needle, found)


def _replace_once(text: str, old: str, new: str) -> str:
    assert text.count(old) >= 1, f"mutation anchor not found: {old!r}"
    return text.replace(old, new, 1)


def test_drift_in_release_build_job_is_caught() -> None:
    mutated = _replace_once(RELEASE_TEXT, "          retention-days: 7\n", "          retention-days: 8\n")
    _expect(mutated, TEST_BUILD_TEXT, "build job differs")


def test_hand_edit_of_the_copy_is_caught() -> None:
    region = sync.copied_region(TEST_BUILD_TEXT)
    mutated = TEST_BUILD_TEXT.replace(region, region.replace("signing=configured", "signing=missing", 1), 1)
    _expect(RELEASE_TEXT, mutated, "build job differs")


def test_missing_marker_is_caught() -> None:
    mutated = _replace_once(TEST_BUILD_TEXT, sync.END_MARKER, "")
    _expect(RELEASE_TEXT, mutated, "copy unreadable")


def test_new_release_environment_is_caught() -> None:
    mutated = _replace_once(
        RELEASE_TEXT, "    environment: release-server\n", "    environment: release-server-v2\n"
    )
    _expect(mutated, TEST_BUILD_TEXT, "environments differ")


def test_dropped_approval_job_is_caught() -> None:
    mutated = _replace_once(
        TEST_BUILD_TEXT,
        "    needs: [meta, approve_server, approve_publication, approve_manifest]\n",
        "    needs: [meta, approve_server, approve_publication]\n",
    )
    _expect(RELEASE_TEXT, mutated, "before approval jobs ['approve_manifest']")


def test_approval_job_that_deploys_or_reads_secrets_is_caught() -> None:
    mutated = _replace_once(
        TEST_BUILD_TEXT,
        "      name: release-server\n      deployment: false\n",
        "      name: release-server\n",
    )
    _expect(RELEASE_TEXT, mutated, "approve_server must not create a deployment")
    mutated = _replace_once(
        TEST_BUILD_TEXT,
        '        run: echo "release-server approved.',
        '        env:\n          KEY: ${{ secrets.ATHENAEUM_DEPLOY_SSH_KEY }}\n        run: echo "release-server approved.',
    )
    _expect(RELEASE_TEXT, mutated, "approve_server must reference no secret")


def test_tag_trigger_is_caught() -> None:
    mutated = _replace_once(
        TEST_BUILD_TEXT, "on:\n  workflow_dispatch:\n", "on:\n  push:\n    tags: ['v*']\n  workflow_dispatch:\n"
    )
    _expect(RELEASE_TEXT, mutated, "only trigger must be workflow_dispatch")


def test_write_scope_is_caught() -> None:
    mutated = _replace_once(
        TEST_BUILD_TEXT, "\npermissions:\n  contents: read\n\n", "\npermissions:\n  contents: write\n\n"
    )
    _expect(RELEASE_TEXT, mutated, "workflow-level token")
    _expect(RELEASE_TEXT, mutated, "'contents: write'")


def test_publishing_step_is_caught() -> None:
    step = (
        "      - name: Publish\n"
        "        env:\n"
        "          GH_TOKEN: ${{ github.token }}\n"
        '        run: gh release create "v$VERSION" dist/*\n'
    )
    mutated = _replace_once(
        TEST_BUILD_TEXT, "      - name: Upload the test-build bundle\n", step + "\n      - name: Upload the test-build bundle\n"
    )
    _expect(RELEASE_TEXT, mutated, "'gh release'")


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
        print(f"ok  {test.__name__}")
    print(f"{len(tests)} test-build workflow checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
