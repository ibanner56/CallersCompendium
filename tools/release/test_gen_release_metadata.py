#!/usr/bin/env python3
"""Unit tests for ``gen_release_metadata.py``.

Pure-stdlib, assert-based (no pytest / no third-party deps), matching the
free/offline tooling constraint. Run directly::

    python3 tools/release/test_gen_release_metadata.py

Focus: prove release metadata carries the codename used by the landing page and
the ``--extra-file`` addition folds non-binary assets (the SBOM) into
``SHA256SUMS`` ONLY, while the 6-binary behavior (both ``SHA256SUMS`` binary
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

        coded_sums, coded_manifest = g.build_metadata(
            version=VERSION,
            tag=TAG,
            channel="stable",
            repo=REPO,
            dist=dist,
            pub_date=PUB_DATE,
            codename="Allemande Left",
        )
        assert coded_sums == base_sums
        assert coded_manifest["codename"] == "Allemande Left"

        empty_coded_sums, empty_coded_manifest = g.build_metadata(
            version=VERSION,
            tag=TAG,
            channel="stable",
            repo=REPO,
            dist=dist,
            pub_date=PUB_DATE,
            codename="",
        )
        assert empty_coded_sums == base_sums
        assert "codename" not in empty_coded_manifest

        fallback_sums, fallback_manifest = g.build_metadata(
            version=VERSION,
            tag=TAG,
            channel="stable",
            repo=REPO,
            dist=dist,
            pub_date=PUB_DATE,
            codename=TAG,
        )
        assert fallback_sums == base_sums
        assert "codename" not in fallback_manifest

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

    # 8. End-to-end via main(): --codename is copied into the manifest and
    #    --extra-file writes the SBOM into SHA256SUMS while leaving the manifest
    #    binary-only.
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        dist = _mkdist(tmp)
        sbom = dist / "sbom-0.1.0.cdx.json"
        sbom.write_bytes(b'{"bomFormat":"CycloneDX"}')
        rc = g.main([
            "--version", VERSION, "--tag", TAG, "--channel", "stable",
            "--repo", REPO, "--dist", str(dist), "--pub-date", PUB_DATE,
            "--codename", "Allemande Left",
            "--extra-file", str(sbom),
        ])
        assert rc == 0
        sums_text = (dist / "SHA256SUMS").read_text(encoding="utf-8")
        assert "sbom-0.1.0.cdx.json" in sums_text
        manifest = json.loads((dist / "stable.json").read_text(encoding="utf-8"))
        asset_names = [a["url"].rsplit("/", 1)[-1] for a in manifest["artifacts"]]
        assert not any("sbom" in n for n in asset_names)
        assert manifest["codename"] == "Allemande Left"


def _expect_exit(fn, fragment: str) -> None:
    try:
        fn()
    except SystemExit as exc:
        assert fragment in str(exc), f"{fragment!r} not in {exc}"
        return
    raise AssertionError(f"expected SystemExit mentioning {fragment!r}")


def _retirement_cases() -> None:
    """``--retirements``: validated, copied into every manifest, and absent
    from the output entirely when the list is empty."""
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        dist = _mkdist(tmp)
        path = tmp / "retirements.json"

        def load(entries: object, release: str = "0.8.0") -> list[dict]:
            path.write_text(json.dumps(entries), encoding="utf-8")
            return g.load_retirements(path, release_version=release)

        good = [
            {"through": "0.6.0-beta", "endOfLife": "2027-01-31"},
            {"through": "0.7.0", "endOfLife": "2027-06-30"},
        ]
        assert load(good) == good
        assert load([]) == []

        # Each entry the client would refuse fails the release instead.
        _expect_exit(lambda: load({"through": "0.7.0"}), "must be a JSON list")
        _expect_exit(lambda: load(["0.7.0"]), "is not an object")
        _expect_exit(
            lambda: load([{"through": "0.7.0"}]), "must have exactly the keys"
        )
        _expect_exit(
            lambda: load([{"through": "0.7.0", "endOfLife": "2027-01-31",
                           "endofLife": "2027-01-31"}]),
            "must have exactly the keys",
        )
        _expect_exit(
            lambda: load([{"through": "v0.7.0", "endOfLife": "2027-01-31"}]),
            "is not a SemVer version",
        )
        _expect_exit(
            lambda: load([{"through": "0.7", "endOfLife": "2027-01-31"}]),
            "is not a SemVer version",
        )
        _expect_exit(
            lambda: load([{"through": "0.7.0", "endOfLife": "2027-1-31"}]),
            "is not YYYY-MM-DD",
        )
        _expect_exit(
            lambda: load([{"through": "0.7.0", "endOfLife": "2027-02-30"}]),
            "is not a real date",
        )
        # A release can retire only older builds — not itself, and not a
        # pre-release of itself either way round.
        _expect_exit(
            lambda: load([{"through": "0.8.0", "endOfLife": "2027-01-31"}]),
            "cannot retire itself",
        )
        _expect_exit(
            lambda: load([{"through": "0.8.0", "endOfLife": "2027-01-31"}],
                         release="0.8.0-beta"),
            "cannot retire itself",
        )
        assert load([{"through": "0.8.0-beta", "endOfLife": "2027-01-31"}],
                    release="0.8.0") != []

        _, plain = g.build_metadata(
            version="0.1.0", tag=TAG, channel="stable", repo=REPO,
            dist=dist, pub_date=PUB_DATE,
        )
        _, empty = g.build_metadata(
            version="0.1.0", tag=TAG, channel="stable", repo=REPO,
            dist=dist, pub_date=PUB_DATE, retirements=[],
        )
        assert empty == plain
        assert "retirements" not in plain

        # End to end: both refreshed channel manifests carry the list.
        path.write_text(
            json.dumps([{"through": "0.0.9", "endOfLife": "2027-01-31"}]),
            encoding="utf-8",
        )
        rc = g.main([
            "--version", VERSION, "--tag", TAG, "--channel", "stable",
            "--repo", REPO, "--dist", str(dist), "--pub-date", PUB_DATE,
            "--retirements", str(path),
        ])
        assert rc == 0
        for channel in ("stable", "beta"):
            manifest = json.loads(
                (dist / f"{channel}.json").read_text(encoding="utf-8")
            )
            assert manifest["retirements"] == [
                {"through": "0.0.9", "endOfLife": "2027-01-31"}
            ], channel

    # The checked-in file the release workflow passes must itself be valid
    # for any release after it was last edited, so a typo fails here, in CI,
    # rather than on the release run.
    checked_in = Path(__file__).resolve().parent / "retirements.json"
    entries = json.loads(checked_in.read_text(encoding="utf-8"))
    newest = max(
        (e["through"] for e in entries), key=g._semver_key, default="0.0.0"
    )
    major, minor, _ = (int(x) for x in newest.split("-")[0].split("+")[0].split("."))
    g.load_retirements(checked_in, release_version=f"{major}.{minor + 1}.0")


def main() -> int:
    _cases()
    _retirement_cases()
    print("OK: all gen_release_metadata tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
