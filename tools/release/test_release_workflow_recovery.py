#!/usr/bin/env python3
"""Guard the existing-tag recovery path in the release workflow."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"


def _section(text: str, start: str, end: str) -> str:
    start_index = text.index(start)
    end_index = text.index(end, start_index)
    return text[start_index:end_index]


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "release_tag:" in text, "workflow_dispatch must accept a recovery tag"
    assert "is_release: ${{ steps.resolve.outputs.is_release }}" in text
    assert "recovery: ${{ steps.resolve.outputs.recovery }}" in text
    assert "release_ref: ${{ steps.resolve.outputs.release_ref }}" in text
    assert "source_sha: ${{ steps.resolve.outputs.source_sha }}" in text

    assert text.count("ref: ${{ needs.meta.outputs.release_ref }}") == 4, (
        "build, Windows, publish, and Pages jobs must all check out the release ref"
    )
    assert text.count("needs.meta.outputs.is_release == 'true'") == 3, (
        "publish, provenance verification, and Pages must share the release guard"
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

    publish = _section(
        text,
        "  publish:\n",
        "  # Close the supply-chain loop",
    )
    assert "runs-on: macos-latest" in publish
    assert "environment: release-signing" in publish
    assert "name: ios-testflight-status" in publish
    assert "      - name: Upload iOS build to TestFlight" in publish
    assert "EVENT_NAME: ${{ github.event_name }}" in publish
    assert '[[ "$REF" == refs/tags/v* ]]' in publish

    release_step = _section(
        text,
        "      - name: Create or update the DRAFT release",
        "  # Close the supply-chain loop",
    )
    assert 'TARGET_SHA: ${{ needs.meta.outputs.source_sha }}' in release_step
    assert '--target "$TARGET_SHA"' in release_step

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
