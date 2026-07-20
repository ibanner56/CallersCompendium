#!/usr/bin/env python3
"""Offline tests for ``publish_pages_site.sh`` — the gh-pages landing-page publisher.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/release/test_*.py``) and fully OFFLINE: it drives the real shell script
against **local bare git repos** standing in for the GitHub remote, so no network
and no GitHub Pages are needed. Run directly::

    python3 tools/release/test_publish_pages_site.py

Focus: prove the CRITICAL coexistence contract — publishing the landing page must
NOT erase the channel manifests (``beta.json`` / ``stable.json``) or ``.nojekyll``
already on ``gh-pages``, must replace STALE site files, must create the orphan
branch cleanly on first publish, and must no-op on unchanged content.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SITE_SCRIPT = HERE / "publish_pages_site.sh"
MANIFEST_SCRIPT = HERE / "publish_pages_manifest.sh"
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


def _exists(bare: Path, ref: str) -> bool:
    res = subprocess.run(
        ["git", "-c", "safe.bareRepository=all", "-C", str(bare),
         "cat-file", "-e", ref],
        capture_output=True,
    )
    return res.returncode == 0


def _show(bare: Path, ref: str) -> str:
    return _git(bare, "show", ref)


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


def _make_site(root: Path, marker: str) -> Path:
    """A minimal but shaped site tree, unique per marker."""
    site = root / "site"
    (site / "assets").mkdir(parents=True, exist_ok=True)
    (site / "index.html").write_text(f"<!doctype html><title>{marker}</title>\n", encoding="utf-8")
    (site / "styles.css").write_text(f"/* {marker} */\n", encoding="utf-8")
    (site / "assets" / "logo.svg").write_text(f"<svg><!-- {marker} --></svg>\n", encoding="utf-8")
    return site


def _publish_site(checkout: Path, worktree: Path, site: Path,
                  source_ref: str = "testsha") -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.update(
        REMOTE="origin",
        BRANCH=REMOTE_BRANCH,
        WORKTREE=str(worktree),
        PAGES_USER_NAME="Test Bot",
        PAGES_USER_EMAIL="test@example.com",
        PUSH_RETRIES="3",
        SOURCE_REF=source_ref,
    )
    return subprocess.run(
        ["bash", str(SITE_SCRIPT), "--site", str(site)],
        cwd=str(checkout), env=env, capture_output=True, text=True,
    )


def _publish_manifest(checkout: Path, worktree: Path, manifest: Path,
                      channel: str, tag: str) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.update(
        REMOTE="origin", BRANCH=REMOTE_BRANCH, WORKTREE=str(worktree),
        PAGES_USER_NAME="Test Bot", PAGES_USER_EMAIL="test@example.com",
        PUSH_RETRIES="3",
    )
    return subprocess.run(
        ["bash", str(MANIFEST_SCRIPT), "--manifest", str(manifest),
         "--channel", channel, "--tag", tag],
        cwd=str(checkout), env=env, capture_output=True, text=True,
    )


def _manifest(root: Path, channel: str, version: str) -> Path:
    p = root / f"{channel}.json"
    p.write_text(json.dumps(
        {"manifestSchemaVersion": 1, "channel": channel, "version": version, "artifacts": []},
        indent=2) + "\n", encoding="utf-8")
    return p


def _cases() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        origin, checkout = _setup(tmp)

        # 1. First-ever publish creates the orphan gh-pages with ONLY the site
        #    tree + .nojekyll — the source README must not leak in.
        site1 = _make_site(tmp / "v1", "v1")
        r = _publish_site(checkout, tmp / "wt1", site1)
        assert r.returncode == 0, f"first site publish failed:\n{r.stderr}\n{r.stdout}"
        assert _exists(origin, f"{REMOTE_BRANCH}:index.html")
        assert _exists(origin, f"{REMOTE_BRANCH}:assets/logo.svg")
        assert _exists(origin, f"{REMOTE_BRANCH}:.nojekyll")
        assert not _exists(origin, f"{REMOTE_BRANCH}:README.md"), \
            "orphan gh-pages must not carry the source tree"
        assert "v1" in _show(origin, f"{REMOTE_BRANCH}:index.html")
        assert _commit_count(origin, REMOTE_BRANCH) == 1

        # 2. A manifest publish onto the SAME branch must keep the site intact.
        man_beta = _manifest(tmp, "beta", "0.1.0-beta.2")
        r = _publish_manifest(checkout, tmp / "wt2", man_beta, "beta", "v0.1.0-beta.2")
        assert r.returncode == 0, f"manifest publish failed:\n{r.stderr}\n{r.stdout}"
        assert _exists(origin, f"{REMOTE_BRANCH}:beta.json")
        assert _exists(origin, f"{REMOTE_BRANCH}:index.html"), \
            "PRESERVATION FAILED: manifest publish erased the site"

        # 3. CRITICAL: re-publishing the site must PRESERVE beta.json, replace the
        #    stale page, and drop a removed asset.
        site2 = tmp / "v2" / "site"
        (site2 / "assets").mkdir(parents=True)
        (site2 / "index.html").write_text("<!doctype html><title>v2</title>\n", encoding="utf-8")
        (site2 / "styles.css").write_text("/* v2 */\n", encoding="utf-8")
        # note: no assets/logo.svg this time -> it should be pruned
        (site2 / "assets" / "app.js").write_text("// v2\n", encoding="utf-8")
        r = _publish_site(checkout, tmp / "wt3", site2, source_ref="v2sha")
        assert r.returncode == 0, f"republish failed:\n{r.stderr}\n{r.stdout}"
        assert _exists(origin, f"{REMOTE_BRANCH}:beta.json"), \
            "PRESERVATION FAILED: site republish erased beta.json"
        assert json.loads(_show(origin, f"{REMOTE_BRANCH}:beta.json"))["version"] == "0.1.0-beta.2"
        assert "v2" in _show(origin, f"{REMOTE_BRANCH}:index.html"), "page not updated"
        assert _exists(origin, f"{REMOTE_BRANCH}:assets/app.js"), "new asset missing"
        assert not _exists(origin, f"{REMOTE_BRANCH}:assets/logo.svg"), \
            "stale asset was not pruned"
        assert _exists(origin, f"{REMOTE_BRANCH}:.nojekyll")

        # 4. Unchanged content is a NO-OP (no new commit).
        before = _commit_count(origin, REMOTE_BRANCH)
        r = _publish_site(checkout, tmp / "wt4", site2, source_ref="v2sha")
        assert r.returncode == 0, f"no-op publish failed:\n{r.stderr}\n{r.stdout}"
        assert "no-op" in (r.stdout + r.stderr).lower()
        assert _commit_count(origin, REMOTE_BRANCH) == before, \
            "unchanged content must not create a commit"

    # 5. Argument validation: a missing site dir and a valueless flag fail loudly.
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        _, checkout = _setup(tmp)

        missing = _publish_site(checkout, tmp / "wtx", tmp / "nope")
        assert missing.returncode != 0
        assert "not found" in missing.stderr.lower()

        env = dict(os.environ, REMOTE="origin", BRANCH=REMOTE_BRANCH,
                   WORKTREE=str(tmp / "wtz"))
        no_value = subprocess.run(
            ["bash", str(SITE_SCRIPT), "--site"],
            cwd=str(checkout), env=env, capture_output=True, text=True,
        )
        assert no_value.returncode != 0
        assert "requires a value" in no_value.stderr.lower()


def main() -> int:
    _cases()
    print("OK: all publish_pages_site tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
