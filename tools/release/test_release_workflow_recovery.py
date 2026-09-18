#!/usr/bin/env python3
"""Guard the existing-tag recovery path in the release workflow."""

import os
import re
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
JOB_HEADING = re.compile(r"^  [a-z][a-z0-9_]*:\n", re.MULTILINE)


def _section(text: str, start: str, end: str) -> str:
    start_index = text.index(start)
    end_index = text.index(end, start_index)
    return text[start_index:end_index]


def _job_section(text: str, job: str) -> str:
    match = re.search(rf"^  {re.escape(job)}:\n", text, re.MULTILINE)
    if match is None:
        raise AssertionError(f"missing {job} job")
    next_job = JOB_HEADING.search(text, match.end())
    return text[match.start() : next_job.start() if next_job else len(text)]


def _publish_script(text: str) -> str:
    publish_step = _section(
        text,
        "      - name: Create or update the DRAFT release\n",
        "  # Close the supply-chain loop (#300):",
    )
    run_marker = "        run: |\n"
    _, body = publish_step.split(run_marker, 1)
    lines: list[str] = []
    for line in body.splitlines():
        if line and not line.startswith("          "):
            break
        lines.append(line[10:] if line else "")
    return "\n".join(lines) + "\n"


def _run_publish_script(
    script: str, release_state: str
) -> tuple[subprocess.CompletedProcess[str], list[str], list[str]]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        calls_path = root / "calls"
        actions_path = root / "actions"
        fake_gh = fake_bin / "gh"
        fake_gh.write_text(
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1" != "release" ]; then
  exit 2
fi
case "$2" in
  view)
    if [ "$RELEASE_STATE" = "missing" ]; then
      exit 1
    fi
    if [ "$RELEASE_STATE" = "draft" ]; then
      printf 'true\n'
    else
      printf 'false\n'
    fi
    ;;
  upload)
    printf 'upload\n' >> "$GH_ACTIONS"
    ;;
  create)
    printf 'create\n' >> "$GH_ACTIONS"
    ;;
  *)
    exit 2
    ;;
esac
""",
            encoding="utf-8",
        )
        fake_gh.chmod(0o755)

        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{fake_bin}{os.pathsep}{environment.get('PATH', '')}",
                "GH_CALLS": str(calls_path),
                "GH_ACTIONS": str(actions_path),
                "RELEASE_STATE": release_state,
                "TAG": "v0.1.0",
                "VERSION": "0.1.0",
                "CHANNELS": "stable beta",
                "PRERELEASE": "true",
                "CODENAME": "v0.1.0",
                "GITHUB_REPOSITORY": "ibanner56/CallersCompendium",
            }
        )
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=root,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        calls = (
            calls_path.read_text(encoding="utf-8").splitlines()
            if calls_path.exists()
            else []
        )
        actions = (
            actions_path.read_text(encoding="utf-8").splitlines()
            if actions_path.exists()
            else []
        )
        return result, calls, actions


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "release_tag:" in text, "workflow_dispatch must accept a recovery tag"
    assert "is_release: ${{ steps.resolve.outputs.is_release }}" in text
    assert "recovery: ${{ steps.resolve.outputs.recovery }}" in text
    assert "release_ref: ${{ steps.resolve.outputs.release_ref }}" in text
    assert "source_sha: ${{ steps.resolve.outputs.source_sha }}" in text
    assert "codename: ${{ steps.resolve.outputs.codename }}" in text
    assert "resolve_release_codename.py --tag-message" in text
    assert 'tag_object_type="$(git cat-file -t "$release_ref")"' in text
    assert "codename_required=false" in text
    assert "codename_required=true" in text
    assert '--title "$CODENAME"' in text
    assert 'if [ "$GITHUB_REF" != "refs/heads/main" ]; then' in text
    assert "::error::existing-tag recovery must be dispatched from main" in text

    metadata_step = _section(
        text,
        "      - name: Generate SHA256SUMS + channel manifests",
        "      # The manifest signature is a publication gate.",
    )
    assert "          RELEASE_CODENAME: ${{ needs.meta.outputs.codename }}" in metadata_step
    assert "metadata_args=(" in metadata_step
    assert "gen_release_metadata.py --help" in metadata_step
    assert 'metadata_args+=(--codename "$RELEASE_CODENAME")' in metadata_step
    assert 'gen_release_metadata.py "${metadata_args[@]}"' in metadata_step
    assert '--codename "$RELEASE_CODENAME"' in metadata_step
    assert '--codename "${{ needs.meta.outputs.codename }}"' not in metadata_step

    codename_define = (
        '--dart-define=CALLERS_COMPENDIUM_RELEASE_CODENAME="$CODENAME"'
    )
    assert text.count(codename_define) == 6

    build_job = _job_section(text, "build")
    assert "      CODENAME: ${{ needs.meta.outputs.codename }}" in build_job
    build_windows_job = _job_section(text, "build_windows")
    assert "      CODENAME: ${{ needs.meta.outputs.codename }}" in build_windows_job

    assert text.count("ref: ${{ needs.meta.outputs.release_ref }}") == 4, (
        "build, Windows, publish, and Pages jobs must all check out the release ref"
    )
    assert text.count("needs.meta.outputs.is_release == 'true'") == 4, (
        "draft, mobile, provenance verification, and Pages must share the release guard"
    )

    ios_gate = _section(
        text,
        "      - name: Determine iOS signing availability",
        "      - name: Install Linux desktop dependencies",
    )
    assert 'if [ "$RECOVERY" = "true" ]; then' in ios_gate
    assert "signing=skipped-recovery" in ios_gate

    ios_build = _section(
        text,
        "      - name: Build signed iOS .ipa (App Store archive)",
        "      - name: Clean up iOS signing material",
    )
    assert "Upload iOS build to TestFlight" not in ios_build
    assert "ios-testflight-status" in ios_build

    publish_draft = _job_section(text, "publish_draft")
    assert "runs-on: ubuntu-latest" in publish_draft
    assert "environment: release-signing" not in publish_draft
    assert "      - name: Create or update the DRAFT release" in publish_draft
    assert 'TARGET_SHA: ${{ needs.meta.outputs.source_sha }}' not in publish_draft
    assert '--target "$TARGET_SHA"' not in publish_draft

    publish_script = _publish_script(text)
    published_result, published_calls, published_actions = _run_publish_script(
        publish_script, "published"
    )
    published_output = published_result.stdout + published_result.stderr
    assert published_result.returncode != 0, published_output
    assert (
        "::error::Release v0.1.0 is already published; refusing to overwrite assets."
        in published_output
    ), published_output
    assert not any(call.startswith("release upload ") for call in published_calls), (
        published_calls,
        published_actions,
    )
    assert 'gh release view "$TAG" --json isDraft --jq \'.isDraft\'' in publish_draft
    assert 'if [ "$is_draft" != "true" ]; then' in publish_draft

    draft_result, draft_calls, draft_actions = _run_publish_script(
        publish_script, "draft"
    )
    assert draft_result.returncode == 0, (
        draft_result.stdout,
        draft_result.stderr,
    )
    assert any(
        call.startswith("release view v0.1.0 --json isDraft --jq .isDraft")
        for call in draft_calls
    ), draft_calls
    assert any(
        call.startswith("release upload ") and "--clobber" in call
        for call in draft_calls
    ), draft_calls
    assert "upload" in draft_actions, draft_actions

    missing_result, missing_calls, missing_actions = _run_publish_script(
        publish_script, "missing"
    )
    assert missing_result.returncode == 0, (
        missing_result.stdout,
        missing_result.stderr,
    )
    assert any(
        call.startswith("release create ") and "--draft" in call
        for call in missing_calls
    ), missing_calls
    assert "create" in missing_actions, missing_actions

    publish_mobile = _job_section(text, "publish_mobile")
    assert "runs-on: macos-latest" in publish_mobile
    assert "environment: release-publication" in publish_mobile
    needs_match = re.search(r"^\s*needs:\s*\[([^\]]+)\]\s*$", publish_mobile, re.MULTILINE)
    assert needs_match is not None and {"meta", "verify"}.issubset(
        {item.strip() for item in needs_match.group(1).split(",")}
    )
    assert "needs.meta.outputs.recovery != 'true'" in publish_mobile
    assert "name: ios-testflight-status" in publish_mobile
    assert "      - name: Upload iOS build to TestFlight" in publish_mobile
    assert "EVENT_NAME: ${{ github.event_name }}" in publish_mobile
    assert '[[ "$REF" == refs/tags/v* ]]' in publish_mobile

    provenance = _section(
        text,
        "      # A recovery run's workflow comes from main",
        "      # Attest the SBOM",
    )
    assert "      - name: Check out recovery provenance helper" in provenance
    assert "path: workflow-tools" in provenance
    assert "ref: ${{ github.sha }}" in provenance
    assert "python3 workflow-tools/tools/release/gen_recovery_provenance.py" in provenance
    assert "REPOSITORY_ID: ${{ github.repository_id }}" in provenance
    assert "REPOSITORY_OWNER_ID: ${{ github.repository_owner_id }}" in provenance
    assert "RUNNER_ENVIRONMENT: ${{ runner.environment }}" in provenance
    assert '--repository-id "$REPOSITORY_ID"' in provenance
    assert '--repository-owner-id "$REPOSITORY_OWNER_ID"' in provenance
    assert '--runner-environment "$RUNNER_ENVIRONMENT"' in provenance
    assert provenance.count("actions/attest-build-provenance@") == 2
    assert "needs.meta.outputs.recovery != 'true'" in provenance
    assert "needs.meta.outputs.recovery == 'true'" in provenance
    assert "predicate-path: recovery-provenance.json" in provenance

    print("release workflow recovery guards: OK")


if __name__ == "__main__":
    main()
