#!/usr/bin/env python3
"""Guard the existing-tag recovery path in the release workflow."""

import re
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


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "release_tag:" in text, "workflow_dispatch must accept a recovery tag"
    assert "is_release: ${{ steps.resolve.outputs.is_release }}" in text
    assert "recovery: ${{ steps.resolve.outputs.recovery }}" in text
    assert "release_ref: ${{ steps.resolve.outputs.release_ref }}" in text
    assert "source_sha: ${{ steps.resolve.outputs.source_sha }}" in text
    assert 'if [ "$GITHUB_REF" != "refs/heads/main" ]; then' in text
    assert "::error::existing-tag recovery must be dispatched from main" in text

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
    assert 'TARGET_SHA: ${{ needs.meta.outputs.source_sha }}' in publish_draft
    assert '--target "$TARGET_SHA"' in publish_draft

    publish_mobile = _job_section(text, "publish_mobile")
    assert "runs-on: macos-latest" in publish_mobile
    assert "environment: release-signing" in publish_mobile
    assert "needs: [meta, verify]" in publish_mobile
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
    assert provenance.count("actions/attest-build-provenance@") == 2
    assert "needs.meta.outputs.recovery != 'true'" in provenance
    assert "needs.meta.outputs.recovery == 'true'" in provenance
    assert "predicate-path: recovery-provenance.json" in provenance

    print("release workflow recovery guards: OK")


if __name__ == "__main__":
    main()
