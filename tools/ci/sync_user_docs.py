#!/usr/bin/env python3
"""Single-source guard + generator: the in-app User Guide's bundled docs.

The app renders its user documentation fully offline, from assets bundled into
the Flutter package (``app/``). The canonical source of that documentation lives
at the repo root under ``docs/user/`` — outside the Flutter package — so Flutter
cannot bundle it directly. This script mirrors the user-facing guides into
``app/assets/docs/`` so they ship with the app, keeping ``docs/user/`` the
single source of truth.

What gets mirrored, from ``docs/`` into ``app/assets/docs/`` (paths preserved):

  * every ``docs/user/*.md`` guide **except** ``style-guide.md`` (a contributor
    authoring-conventions doc, not user-facing);
  * every ``*.png`` under ``docs/user/images/``, so the screenshots the guides
    embed render in the app. Nothing else there is mirrored: the folder's
    ``README.md`` is a contributor doc, and SVG diagrams are for GitHub and
    Pages only, because the in-app reader cannot decode SVG. A guide's image
    that is not mirrored falls back to an alt-text caption in the app, so a
    missing file degrades gracefully but should still be fixed.

Guides are **discovered**, never hard-coded, so a new ``docs/user/*.md`` guide
is picked up automatically and the drift-check then enforces that the committed
bundle stays in sync.

Modes:

  * ``--check`` (CI): regenerate into a temp dir and compare, byte-for-byte, with
    the committed ``app/assets/docs/``. Fails on any drift — a changed, missing,
    or stale file — so a docs edit that forgets to regenerate can't ship.
    It also fails when a guide references a bundled ``images/*.png`` that does
    not exist, because the app suite that checks this too is skipped for a
    Markdown-only change.
  * ``--write`` / default (local fix): (re)write ``app/assets/docs/`` in place.

Exit codes: 0 = in sync / written, 1 = drift (``--check`` only), 2 = bad input.
"""

from __future__ import annotations

import argparse
import filecmp
import re
import shutil
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS_ROOT = REPO_ROOT / "docs"
USER_DOCS = DOCS_ROOT / "user"
BUNDLE_DIR = REPO_ROOT / "app" / "assets" / "docs"

# Contributor-only authoring conventions doc — deliberately not user-facing.
EXCLUDED_GUIDES = {"style-guide.md"}

# Image directory under docs/user whose screenshots ship with the guides. Only
# PNGs are mirrored: the folder's README.md is contributor-only, and the in-app
# reader decodes raster images, not the SVG diagrams Pages can show.
IMAGES_DIR = USER_DOCS / "images"
BUNDLED_IMAGE_SUFFIX = ".png"

# A guide's reference to a bundled screenshot: ``![alt](images/name.png)``. Only
# PNGs are bundled, so only they are checked (an SVG shows as alt text in the
# app). Mirrors the reference pattern in user_guide_screen_test.dart.
_IMAGE_REFERENCE = re.compile(
    r"!\[[^\]]*\]\(images/([^)\s]+\.png)\)", re.IGNORECASE
)

# Finder can create this metadata file while the checker walks the local bundle.
# It is not documentation and is excluded by app/.gitignore, so it must not make
# a byte-for-byte content check nondeterministic on macOS.
_IGNORED_BUNDLE_FILENAMES = {".DS_Store"}


def _fail(msg: str, code: int = 2) -> None:
    # ``::error::`` renders as an annotation in the GitHub Actions UI.
    print(f"::error::{msg}")
    sys.exit(code)


def discover_guides() -> list[Path]:
    """User-facing guides under ``docs/user`` (sorted), excluding non-user docs."""
    if not USER_DOCS.is_dir():
        _fail(f"missing source docs directory: {USER_DOCS}")
    guides = [
        p
        for p in sorted(USER_DOCS.glob("*.md"))
        if p.name not in EXCLUDED_GUIDES
    ]
    if not guides:
        _fail(f"no user guides found under {USER_DOCS}")
    return guides


def _collect_sources() -> dict[str, Path]:
    """Map of bundle-relative path -> source file for everything to mirror."""
    mapping: dict[str, Path] = {}
    for guide in discover_guides():
        rel = guide.relative_to(DOCS_ROOT).as_posix()
        mapping[rel] = guide
    if IMAGES_DIR.is_dir():
        for image in sorted(IMAGES_DIR.iterdir()):
            if (
                image.is_symlink()
                or not image.is_file()
                or image.suffix.lower() != BUNDLED_IMAGE_SUFFIX
                or image.name in _IGNORED_BUNDLE_FILENAMES
            ):
                continue
            mapping[image.relative_to(DOCS_ROOT).as_posix()] = image
    return mapping


def missing_image_references(mapping: dict[str, Path]) -> list[str]:
    """``guide -> image`` for each bundled-PNG reference with no mirrored file.

    The app suite also checks this, but CI skips that suite for a Markdown-only
    change -- exactly the change that adds a reference -- so a reference whose
    PNG was never committed would otherwise merge and fail an unrelated PR.
    """
    bundled = {rel.lower() for rel in mapping}
    missing: list[str] = []
    for rel, source in sorted(mapping.items()):
        if not rel.endswith(".md"):
            continue
        text = source.read_text(encoding="utf-8")
        for match in _IMAGE_REFERENCE.finditer(text):
            if f"user/images/{match.group(1)}".lower() not in bundled:
                missing.append(f"{rel} -> images/{match.group(1)}")
    return missing


def build_bundle(dest_root: Path) -> dict[str, Path]:
    """Write the mirrored bundle into ``dest_root``; return the source mapping."""
    mapping = _collect_sources()
    if dest_root.exists():
        shutil.rmtree(dest_root)
    for rel, source in mapping.items():
        target = dest_root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    return mapping


def _relative_files(root: Path) -> set[str]:
    if not root.is_dir():
        return set()
    return {
        p.relative_to(root).as_posix()
        for p in root.rglob("*")
        if p.is_file() and p.name not in _IGNORED_BUNDLE_FILENAMES
    }


def _check() -> int:
    unresolved = missing_image_references(_collect_sources())
    for ref in unresolved:
        print(f"::error::guide image reference has no image file: {ref}")
    if unresolved:
        print(
            "::error::Add the PNG under docs/user/images/ (then run "
            "`python3 tools/ci/sync_user_docs.py --write`) or fix the reference."
        )
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        expected_root = Path(tmp) / "docs"
        build_bundle(expected_root)
        expected = _relative_files(expected_root)
        actual = _relative_files(BUNDLE_DIR)

        missing = sorted(expected - actual)
        stale = sorted(actual - expected)
        changed = sorted(
            rel
            for rel in expected & actual
            if not filecmp.cmp(expected_root / rel, BUNDLE_DIR / rel, shallow=False)
        )

        if not (missing or stale or changed):
            print(
                f"OK: in-app user-docs bundle is in sync "
                f"({len(expected)} files under app/assets/docs/)."
            )
            return 0

        for rel in missing:
            print(f"::error::bundled doc missing (needs regeneration): {rel}")
        for rel in changed:
            print(f"::error::bundled doc out of date: {rel}")
        for rel in stale:
            print(f"::error::stale bundled doc (source removed): {rel}")
        print(
            "::error::app/assets/docs/ is out of sync with docs/user/. "
            "Run `python3 tools/ci/sync_user_docs.py --write` and commit the result."
        )
        return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--check",
        action="store_true",
        help="verify the committed bundle matches docs/user (CI); no writes.",
    )
    group.add_argument(
        "--write",
        action="store_true",
        help="(re)generate app/assets/docs/ from docs/user (default).",
    )
    args = parser.parse_args(argv)

    if args.check:
        return _check()

    mapping = build_bundle(BUNDLE_DIR)
    print(
        f"Wrote {len(mapping)} files to "
        f"{BUNDLE_DIR.relative_to(REPO_ROOT)}/ from docs/user."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
