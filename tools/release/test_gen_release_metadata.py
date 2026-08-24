#!/usr/bin/env python3
"""Unit tests for ``gen_release_metadata.py``.

Pure-stdlib, assert-based (no pytest / no third-party deps), matching the
free/offline tooling constraint. Run directly::

    python3 tools/release/test_gen_release_metadata.py

Focus: prove the ``--extra-file`` addition folds non-binary assets (the SBOM)
into ``SHA256SUMS`` ONLY, while the 6-binary behavior (both ``SHA256SUMS`` binary
lines and the ``<channel>.json`` manifest) stays byte-identical to before.
"""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_release_metadata as g  # noqa: E402

VERSION = "0.1.0"
TAG = "v0.1.0"
REPO = "ibanner56/CallersCompendium"
PUB_DATE = "2026-07-16T00:00:00Z"

# The six deterministic desktop binaries the pipeline produces.
BINARIES = {
    "CallersCompendium-0.1.0-linux-x64.AppImage": b"appimage",
    "CallersCompendium-0.1.0-linux-x64.tar.gz": b"targz",
    "CallersCompendium-0.1.0-macos-universal.dmg": b"dmg",
    "CallersCompendium-0.1.0-macos-universal.zip": b"macoszip",
    "CallersCompendium-0.1.0-windows-x64.exe": b"exe",
    "CallersCompendium-0.1.0-windows-x64.zip": b"winzip",
}


def _mkdist(tmp: Path) -> Path:
    dist = tmp / "dist"
    dist.mkdir()
    for name, content in BINARIES.items():
        (dist / name).write_bytes(content)
    return dist


def _sha(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def _cases() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        dist = _mkdist(tmp)

        # --- Baseline: no extra files -----------------------------------
        base_sums, base_manifest = g.build_metadata(
            version=VERSION, tag=TAG, channel="stable", repo=REPO,
            dist=dist, pub_date=PUB_DATE,
        )

        # 1. SHA256SUMS has exactly the six binaries, sorted, correct digests.
        base_lines = base_sums.strip().split("\n")
        assert len(base_lines) == 6
        assert base_lines == sorted(base_lines)
        for name, content in BINARIES.items():
            assert f"{_sha(content)}  {name}" in base_lines

        # 2. Manifest lists the primary artifact per (platform, arch):
        #    AppImage over tar.gz, dmg over zip, exe over zip.
        primaries = {
            (a["platform"], a["arch"]): a["url"].rsplit("/", 1)[-1]
            for a in base_manifest["artifacts"]
        }
        assert primaries[("linux", "x64")].endswith(".AppImage")
        assert primaries[("macos", "universal")].endswith(".dmg")
        assert primaries[("windows", "x64")].endswith(".exe")
        assert base_manifest["manifestSchemaVersion"] == 1
        assert base_manifest["channel"] == "stable"
        assert base_manifest["version"] == VERSION

        # A stable release also refreshes beta opt-ins with the same release
        # identity; a beta release produces only beta.json.
        stable_manifests = g.build_channel_manifests(
            version=VERSION, tag=TAG, channel="stable", repo=REPO,
            dist=dist, pub_date=PUB_DATE,
        )
        assert set(stable_manifests) == {"stable", "beta"}
        assert all(manifest["version"] == VERSION
                   for manifest in stable_manifests.values())
        assert all(manifest["releaseNotesUrl"].endswith(f"/{TAG}")
                   for manifest in stable_manifests.values())
        beta_manifests = g.build_channel_manifests(
            version=VERSION, tag="v0.1.0-beta", channel="beta",
            repo=REPO, dist=dist, pub_date=PUB_DATE,
        )
        assert set(beta_manifests) == {"beta"}

        # Channel selection only changes the manifest's channel field. A stable
        # release must hash the artifacts once, not once per refreshed channel.
        original_build_metadata = g.build_metadata
        metadata_builds: list[str] = []

        def count_metadata_builds(**kwargs: object) -> tuple[str, dict]:
            metadata_builds.append(str(kwargs["channel"]))
            return original_build_metadata(**kwargs)

        g.build_metadata = count_metadata_builds
        try:
            counted_manifests = g.build_channel_manifests(
                version=VERSION, tag=TAG, channel="stable", repo=REPO,
                dist=dist, pub_date=PUB_DATE,
            )
        finally:
            g.build_metadata = original_build_metadata
        assert metadata_builds == ["stable"]
        assert set(counted_manifests) == {"stable", "beta"}
        assert counted_manifests["stable"]["channel"] == "stable"
        assert counted_manifests["beta"]["channel"] == "beta"

        # --- With an extra (SBOM) asset ---------------------------------
        sbom = dist / "sbom-0.1.0.cdx.json"
        sbom_content = b'{"bomFormat":"CycloneDX"}'
        sbom.write_bytes(sbom_content)

        extra_sums, extra_manifest = g.build_metadata(
            version=VERSION, tag=TAG, channel="stable", repo=REPO,
            dist=dist, pub_date=PUB_DATE, extra_files=[sbom],
        )

        # 3. The manifest is IDENTICAL with or without the extra file — the SBOM
        #    is never classified as a platform artifact.
        assert extra_manifest == base_manifest

        # 4. SHA256SUMS now has 7 lines: the original six (unchanged) + the SBOM.
        extra_lines = extra_sums.strip().split("\n")
        assert len(extra_lines) == 7
        assert extra_lines == sorted(extra_lines)
        assert f"{_sha(sbom_content)}  sbom-0.1.0.cdx.json" in extra_lines
        # Every original binary line is still present, byte-for-byte.
        for line in base_lines:
            assert line in extra_lines

        # 5. A missing --extra-file fails the release loudly.
        missing = dist / "does-not-exist.cdx.json"
        try:
            g.build_metadata(
                version=VERSION, tag=TAG, channel="stable", repo=REPO,
                dist=dist, pub_date=PUB_DATE, extra_files=[missing],
            )
            raise AssertionError("expected SystemExit for missing --extra-file")
        except SystemExit as exc:
            assert "not found" in str(exc)

    # 6. The SBOM must NOT be discovered as a binary: because it is not
    #    CallersCompendium-*-prefixed it is ignored by binary discovery even if
    #    it sits in dist/ and is NOT passed via --extra-file (no name-contract
    #    failure, not in SHA256SUMS).
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        dist = _mkdist(tmp)
        (dist / "sbom-0.1.0.cdx.json").write_bytes(b"{}")
        sums, _ = g.build_metadata(
            version=VERSION, tag=TAG, channel="stable", repo=REPO,
            dist=dist, pub_date=PUB_DATE,
        )
        assert "sbom-0.1.0.cdx.json" not in sums
        assert len(sums.strip().split("\n")) == 6

    # 7. A CallersCompendium-*-prefixed file that violates the name contract
    #    still fails the release (guard behavior unchanged).
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        dist = _mkdist(tmp)
        (dist / "CallersCompendium-0.1.0-bogus.txt").write_bytes(b"x")
        try:
            g.build_metadata(
                version=VERSION, tag=TAG, channel="stable", repo=REPO,
                dist=dist, pub_date=PUB_DATE,
            )
            raise AssertionError("expected SystemExit for bad-contract asset")
        except SystemExit as exc:
            assert "name contract" in str(exc)

    # 8. End-to-end via main(): --extra-file writes the SBOM into SHA256SUMS on
    #    disk but leaves the manifest binary-only.
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        dist = _mkdist(tmp)
        sbom = dist / "sbom-0.1.0.cdx.json"
        sbom.write_bytes(b'{"bomFormat":"CycloneDX"}')
        rc = g.main([
            "--version", VERSION, "--tag", TAG, "--channel", "stable",
            "--repo", REPO, "--dist", str(dist), "--pub-date", PUB_DATE,
            "--extra-file", str(sbom),
        ])
        assert rc == 0
        sums_text = (dist / "SHA256SUMS").read_text(encoding="utf-8")
        assert "sbom-0.1.0.cdx.json" in sums_text
        manifest = json.loads((dist / "stable.json").read_text(encoding="utf-8"))
        asset_names = [a["url"].rsplit("/", 1)[-1] for a in manifest["artifacts"]]
        assert not any("sbom" in n for n in asset_names)


def main() -> int:
    _cases()
    print("OK: all gen_release_metadata tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
