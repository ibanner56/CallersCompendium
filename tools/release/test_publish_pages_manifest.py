#!/usr/bin/env python3
"""Offline tests for ``publish_pages_manifest.sh`` — the gh-pages publisher.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/release/test_*.py``) and fully OFFLINE: it drives the real shell script
against **local bare git repos** standing in for the GitHub remote, so no network
and no GitHub Pages are needed. Run directly::

    python3 tools/release/test_publish_pages_manifest.py

Focus: prove the CRITICAL cross-channel-preservation contract of A11c — a STABLE
release must not erase ``beta.json`` and a BETA release must not erase
``stable.json`` — plus first-publish orphan creation and the unchanged-content
no-op.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "publish_pages_manifest.sh"
REMOTE_BRANCH = "gh-pages"


def _git(cwd: Path, *args: str, check: bool = True) -> str:
    res = subprocess.run(
        ["git", "-c", "safe.bareRepository=all", *args],
        cwd=str(cwd),
        check=check,
        capture_output=True,
        text=True,
    )
    return res.stdout.strip()


def _manifest(channel: str, version: str) -> str:
    """A minimal but schema-shaped manifest, unique per (channel, version)."""
    return json.dumps(
        {
            "manifestSchemaVersion": 1,
            "channel": channel,
            "version": version,
            "artifacts": [],
        },
        indent=2,
    ) + "\n"


def _publish(checkout: Path, worktree: Path, manifest_path: Path,
             channel: str, tag: str,
             signature_path: Path | None = None) -> subprocess.CompletedProcess:
    """Run the publisher from within ``checkout`` (a working clone of origin)."""
    env = dict(os.environ)
    env.update(
        REMOTE="origin",
        BRANCH=REMOTE_BRANCH,
        WORKTREE=str(worktree),
        PAGES_USER_NAME="Test Bot",
        PAGES_USER_EMAIL="test@example.com",
        # Deterministic + fast; the test never actually races.
        PUSH_RETRIES="3",
    )
    args = [
        "bash", str(SCRIPT),
        "--manifest", str(manifest_path),
        "--channel", channel,
        "--tag", tag,
    ]
    if signature_path is not None:
        args += ["--signature", str(signature_path)]
    return subprocess.run(
        args,
        cwd=str(checkout),
        env=env,
        capture_output=True,
        text=True,
    )


def _show(bare: Path, ref: str) -> str:
    return _git(bare, "show", ref)


def _exists(bare: Path, ref: str) -> bool:
    res = subprocess.run(
        ["git", "-c", "safe.bareRepository=all", "-C", str(bare),
         "cat-file", "-e", ref],
        capture_output=True,
    )
    return res.returncode == 0


def _commit_count(bare: Path, branch: str) -> int:
    return int(_git(bare, "rev-list", "--count", branch))


def _setup(tmp: Path) -> tuple[Path, Path]:
    """Create a bare 'origin' seeded with a main branch + a working clone."""
    origin = tmp / "origin.git"
    _git(tmp, "init", "--quiet", "--bare", "-b", "main", str(origin))

    seed = tmp / "seed"
    _git(tmp, "clone", "--quiet", str(origin), str(seed))
    _git(seed, "config", "user.email", "seed@example.com")
    _git(seed, "config", "user.name", "Seed")
    (seed / "README.md").write_text("seed\n", encoding="utf-8")
    _git(seed, "add", "README.md")
    _git(seed, "commit", "--quiet", "-m", "init")
    _git(seed, "push", "--quiet", "origin", "HEAD:main")

    checkout = tmp / "checkout"
    _git(tmp, "clone", "--quiet", str(origin), str(checkout))
    return origin, checkout


def _write(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    return path


def _cases() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        origin, checkout = _setup(tmp)
        man = tmp / "manifests"
        man.mkdir()

        # 1. First-ever publish (stable) creates the orphan gh-pages branch
        #    containing ONLY stable.json + .nojekyll (no seed README leaks in).
        stable_v1 = _write(man / "stable.json", _manifest("stable", "0.1.0"))
        r = _publish(checkout, tmp / "wt1", stable_v1, "stable", "v0.1.0")
        assert r.returncode == 0, f"stable publish failed:\n{r.stderr}\n{r.stdout}"
        assert _exists(origin, f"{REMOTE_BRANCH}:stable.json")
        assert _exists(origin, f"{REMOTE_BRANCH}:.nojekyll")
        assert not _exists(origin, f"{REMOTE_BRANCH}:beta.json")
        assert not _exists(origin, f"{REMOTE_BRANCH}:README.md"), \
            "orphan gh-pages must not carry the source tree"
        assert json.loads(_show(origin, f"{REMOTE_BRANCH}:stable.json"))["version"] == "0.1.0"
        assert _commit_count(origin, REMOTE_BRANCH) == 1

        # 2. CROSS-CHANNEL PRESERVATION: publishing beta.json must NOT erase the
        #    existing stable.json.
        beta_v1 = _write(man / "beta.json", _manifest("beta", "0.2.0-beta.1"))
        r = _publish(checkout, tmp / "wt2", beta_v1, "beta", "v0.2.0-beta.1")
        assert r.returncode == 0, f"beta publish failed:\n{r.stderr}\n{r.stdout}"
        assert _exists(origin, f"{REMOTE_BRANCH}:beta.json"), "beta.json missing"
        assert _exists(origin, f"{REMOTE_BRANCH}:stable.json"), \
            "PRESERVATION FAILED: beta publish erased stable.json"
        # .nojekyll must survive a 2nd (real, committing) publish — never deleted.
        assert _exists(origin, f"{REMOTE_BRANCH}:.nojekyll"), \
            ".nojekyll was dropped on republish"
        assert json.loads(_show(origin, f"{REMOTE_BRANCH}:stable.json"))["version"] == "0.1.0"
        assert json.loads(_show(origin, f"{REMOTE_BRANCH}:beta.json"))["version"] == "0.2.0-beta.1"
        assert _commit_count(origin, REMOTE_BRANCH) == 2

        # 3. Reverse direction: a later STABLE release must NOT erase beta.json.
        stable_v2 = _write(man / "stable.json", _manifest("stable", "0.3.0"))
        r = _publish(checkout, tmp / "wt3", stable_v2, "stable", "v0.3.0")
        assert r.returncode == 0, f"stable v2 publish failed:\n{r.stderr}\n{r.stdout}"
        assert _exists(origin, f"{REMOTE_BRANCH}:beta.json"), \
            "PRESERVATION FAILED: stable publish erased beta.json"
        assert _exists(origin, f"{REMOTE_BRANCH}:.nojekyll"), \
            ".nojekyll was dropped on a later republish"
        assert json.loads(_show(origin, f"{REMOTE_BRANCH}:stable.json"))["version"] == "0.3.0"
        assert json.loads(_show(origin, f"{REMOTE_BRANCH}:beta.json"))["version"] == "0.2.0-beta.1"
        assert _commit_count(origin, REMOTE_BRANCH) == 3

        # 4. Unchanged content is a NO-OP: re-publishing the identical stable.json
        #    must not add a commit.
        r = _publish(checkout, tmp / "wt4", stable_v2, "stable", "v0.3.0")
        assert r.returncode == 0, f"no-op publish failed:\n{r.stderr}\n{r.stdout}"
        assert "no-op" in (r.stdout + r.stderr).lower()
        assert _commit_count(origin, REMOTE_BRANCH) == 3, \
            "unchanged content must not create a commit"

        # 6. SIGNATURE PUBLISH (issue #431): a stable release carrying a detached
        #    signature publishes <channel>.json.sig alongside the manifest and
        #    must NOT disturb the other channel's manifest or its .sig-lessness.
        stable_v3 = _write(man / "stable.json", _manifest("stable", "0.4.0"))
        sig = _write(man / "stable.json.sig", "c2lnbmF0dXJlLWJ5dGVz\n")
        r = _publish(checkout, tmp / "wt5", stable_v3, "stable", "v0.4.0",
                     signature_path=sig)
        assert r.returncode == 0, f"signed publish failed:\n{r.stderr}\n{r.stdout}"
        assert _exists(origin, f"{REMOTE_BRANCH}:stable.json.sig"), \
            "stable.json.sig was not published"
        assert _show(origin, f"{REMOTE_BRANCH}:stable.json.sig") == \
            "c2lnbmF0dXJlLWJ5dGVz", "published signature body mismatch"
        # The signed publish must still preserve the other channel.
        assert _exists(origin, f"{REMOTE_BRANCH}:beta.json"), \
            "PRESERVATION FAILED: signed stable publish erased beta.json"
        # beta had no signature published, so beta.json.sig must not exist.
        assert not _exists(origin, f"{REMOTE_BRANCH}:beta.json.sig"), \
            "beta.json.sig must not appear when no beta signature was published"

        # 7. Publishing WITHOUT --signature must not disturb an existing .sig
        #    (the manifest changes; the previously published sig is left as-is).
        stable_v4 = _write(man / "stable.json", _manifest("stable", "0.5.0"))
        r = _publish(checkout, tmp / "wt6", stable_v4, "stable", "v0.5.0")
        assert r.returncode == 0, f"unsigned republish failed:\n{r.stderr}\n{r.stdout}"
        assert json.loads(_show(origin, f"{REMOTE_BRANCH}:stable.json"))["version"] == "0.5.0"
        assert _exists(origin, f"{REMOTE_BRANCH}:stable.json.sig"), \
            "an unsigned republish must not delete the existing signature"

    # 8. Argument validation: bad channel and missing manifest fail loudly.
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        _, checkout = _setup(tmp)
        good = _write(tmp / "stable.json", _manifest("stable", "0.1.0"))

        bad_channel = _publish(checkout, tmp / "wtx", good, "nightly", "v0.1.0")
        assert bad_channel.returncode != 0
        assert "channel" in bad_channel.stderr.lower()

        missing = _publish(checkout, tmp / "wty", tmp / "nope.json", "stable", "v0.1.0")
        assert missing.returncode != 0
        assert "not found" in missing.stderr.lower()

        # A flag with no value must fail with a CLEAR message, not a bare
        # set -u "unbound variable" error.
        env = dict(os.environ, REMOTE="origin", BRANCH=REMOTE_BRANCH,
                   WORKTREE=str(tmp / "wtz"))
        no_value = subprocess.run(
            ["bash", str(SCRIPT), "--manifest"],
            cwd=str(checkout), env=env, capture_output=True, text=True,
        )
        assert no_value.returncode != 0
        assert "requires a value" in no_value.stderr.lower()

        # A missing signature file (when --signature is given) fails loudly.
        good2 = _write(tmp / "stable.json", _manifest("stable", "0.1.0"))
        missing_sig = _publish(checkout, tmp / "wts", good2, "stable", "v0.1.0",
                               signature_path=tmp / "nope.sig")
        assert missing_sig.returncode != 0
        assert "signature file not found" in missing_sig.stderr.lower()

        # --signature with no value fails with a CLEAR message.
        env2 = dict(os.environ, REMOTE="origin", BRANCH=REMOTE_BRANCH,
                    WORKTREE=str(tmp / "wtsv"))
        sig_no_value = subprocess.run(
            ["bash", str(SCRIPT), "--manifest", str(good2),
             "--channel", "stable", "--tag", "v0.1.0", "--signature"],
            cwd=str(checkout), env=env2, capture_output=True, text=True,
        )
        assert sig_no_value.returncode != 0
        assert "requires a value" in sig_no_value.stderr.lower()


def main() -> int:
    _cases()
    print("OK: all publish_pages_manifest tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
