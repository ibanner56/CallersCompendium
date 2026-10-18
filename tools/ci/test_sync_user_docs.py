#!/usr/bin/env python3
"""Regression tests for the in-app user-documentation sync checker."""

from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("sync_user_docs.py")
SPEC = importlib.util.spec_from_file_location("sync_user_docs", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
sync_user_docs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_user_docs)


def _cases() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        (root / "user").mkdir()
        (root / "user" / "settings.md").write_text(
            "# Settings\n", encoding="utf-8"
        )
        (root / "user" / ".DS_Store").write_bytes(b"finder metadata")

        assert sync_user_docs._relative_files(root) == {"user/settings.md"}


def _image_cases() -> None:
    original = (
        sync_user_docs.DOCS_ROOT,
        sync_user_docs.USER_DOCS,
        sync_user_docs.IMAGES_DIR,
    )
    try:
        with tempfile.TemporaryDirectory() as temp:
            docs = Path(temp) / "docs"
            images = docs / "user" / "images"
            images.mkdir(parents=True)
            (docs / "user" / "settings.md").write_text("# S\n", encoding="utf-8")
            (images / "shot.png").write_bytes(b"png")
            (images / "Upper.PNG").write_bytes(b"png")
            (images / "README.md").write_text("contributor doc", encoding="utf-8")
            (images / ".DS_Store").write_bytes(b"finder metadata")
            (images / "diagram.svg").write_text("<svg/>", encoding="utf-8")
            (images / "shot.jpg").write_bytes(b"jpg")
            sync_user_docs.DOCS_ROOT = docs
            sync_user_docs.USER_DOCS = docs / "user"
            sync_user_docs.IMAGES_DIR = images

            assert set(sync_user_docs._collect_sources()) == {
                "user/settings.md",
                "user/images/shot.png",
                "user/images/Upper.PNG",
            }

            def write_guide(body: str) -> dict:
                (docs / "user" / "settings.md").write_text(body, encoding="utf-8")
                return sync_user_docs._collect_sources()

            # A present PNG (incl. an uppercase suffix, matched exactly), an
            # SVG, and a remote image are fine.
            assert not sync_user_docs.missing_image_references(
                write_guide(
                    "![a](images/shot.png) ![b](images/Upper.PNG) "
                    "![c](images/diagram.svg) ![d](https://x.test/y.png)\n"
                )
            )
            # A name differing only in case is reported: the app's asset
            # lookup is exact, so it would show the caption, not the image.
            assert sync_user_docs.missing_image_references(
                write_guide("![a](images/SHOT.PNG)\n")
            ) == ["user/settings.md -> images/SHOT.PNG"]
            # A PNG reference with no file is reported with its guide.
            assert sync_user_docs.missing_image_references(
                write_guide("![a](images/shot.png)\n![b](images/gone.png)\n")
            ) == ["user/settings.md -> images/gone.png"]
    finally:
        (
            sync_user_docs.DOCS_ROOT,
            sync_user_docs.USER_DOCS,
            sync_user_docs.IMAGES_DIR,
        ) = original


def main() -> int:
    _cases()
    _image_cases()
    print("OK: all user-doc sync checker tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
