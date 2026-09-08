#!/usr/bin/env python3
"""Offline tests for ``compile_changelog_fragments.py``."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compile_changelog_fragments as compiler  # noqa: E402

APP = """\
<!-- release-managed-by: tools/release/compile_changelog_fragments.py -->
# Changelog

## [Unreleased]

_Nothing yet._

## [0.1.0] - 2026-01-01

### Added

- Previous app feature.
"""

CORE = """\
<!-- release-managed-by: tools/release/compile_changelog_fragments.py -->
# Changelog

## [Unreleased]

_Nothing yet._

## [0.1.0] - 2026-01-01

### Fixed

- Previous core fix.
"""


def write_fragment(directory: Path, identifier: str, contents: object) -> None:
    (directory / f"{identifier}.json").write_text(
        json.dumps(contents), encoding="utf-8"
    )


def fixture_repo() -> tuple[tempfile.TemporaryDirectory[str], Path]:
    temporary = tempfile.TemporaryDirectory()
    root = Path(temporary.name)
    (root / "changelog.d").mkdir()
    (root / "app").mkdir()
    (root / "packages/compendium_core").mkdir(parents=True)
    (root / "app/CHANGELOG.md").write_text(APP, encoding="utf-8")
    (root / "app/pubspec.yaml").write_text(
        "name: compendium_app\nversion: 0.2.0\n", encoding="utf-8"
    )
    (root / "packages/compendium_core/CHANGELOG.md").write_text(CORE, encoding="utf-8")
    (root / "packages/compendium_core/pubspec.yaml").write_text(
        "name: compendium_core\nversion: 0.2.0\n", encoding="utf-8"
    )
    return temporary, root


def cases() -> None:
    temporary, root = fixture_repo()
    try:
        fragments = root / "changelog.d"
        write_fragment(
            fragments,
            "100-feature",
            {
                "id": "100-feature",
                "user_visible": True,
                "app": {"added": ["You can export a dance."]},
                "core": {"added": ["Add export encoding."]},
            },
        )
        write_fragment(
            fragments,
            "101-fix",
            {
                "id": "101-fix",
                "user_visible": True,
                "app": {"fixed": ["Export no longer drops titles."]},
            },
        )

        entries = compiler.load_fragments(fragments)
        assert [entry.identifier for entry in entries] == ["100-feature", "101-fix"]
        app, core = compiler.compile_changelogs(
            app_changelog=(root / "app/CHANGELOG.md").read_text(encoding="utf-8"),
            core_changelog=(root / "packages/compendium_core/CHANGELOG.md").read_text(
                encoding="utf-8"
            ),
            fragments=entries,
            app_version="0.2.0",
            core_version="0.2.0",
            release_date="2026-02-02",
        )
        assert "## [0.2.0] - 2026-02-02" in app
        assert "### Added\n\n- You can export a dance." in app
        assert "### Fixed\n\n- Export no longer drops titles." in app
        assert "## [0.2.0] - 2026-02-02" in core
        assert "Add export encoding." in core

        result = compiler.apply_release(
            root=root,
            fragments=entries,
            app_version="0.2.0",
            core_version="0.2.0",
            release_date="2026-02-02",
        )
        assert result.app_entries == 2 and result.core_entries == 1
        assert not list(fragments.glob("*.json"))
        assert "You can export a dance." in (root / "app/CHANGELOG.md").read_text(
            encoding="utf-8"
        )

        write_fragment(
            fragments,
            "102-beta-fix",
            {
                "id": "102-beta-fix",
                "user_visible": True,
                "app": {"fixed": ["A beta regression is fixed."]},
            },
        )
        beta, _ = compiler.compile_changelogs(
            app_changelog=(root / "app/CHANGELOG.md").read_text(encoding="utf-8"),
            core_changelog=(root / "packages/compendium_core/CHANGELOG.md").read_text(
                encoding="utf-8"
            ),
            fragments=compiler.load_fragments(fragments),
            app_version="0.2.0",
            core_version=None,
            release_date="2026-02-03",
        )
        assert beta.count("## [0.2.0]") == 1
        assert "A beta regression is fixed." in beta

        (root / "app/CHANGELOG.md").write_text(
            APP.replace("_Nothing yet._", "- A direct edit."), encoding="utf-8"
        )
        try:
            compiler.check_pending_state(root)
        except compiler.FragmentError as error:
            assert "changelog.d fragment" in str(error)
        else:
            raise AssertionError("direct Unreleased edit passed")

        for direct_content in ("Unexpected prose.", "### Unexpected heading"):
            (root / "app/CHANGELOG.md").write_text(
                APP.replace("_Nothing yet._", direct_content), encoding="utf-8"
            )
            try:
                compiler.check_pending_state(root)
            except compiler.FragmentError:
                pass
            else:
                raise AssertionError(f"direct content passed: {direct_content}")

        (root / "app/CHANGELOG.md").write_text(
            APP.replace("_Nothing yet._", "- A direct edit."), encoding="utf-8"
        )
        write_fragment(
            fragments,
            "103-write-guard",
            {
                "id": "103-write-guard",
                "user_visible": True,
                "app": {"fixed": ["A write guard is present."]},
            },
        )
        before = (root / "app/CHANGELOG.md").read_text(encoding="utf-8")
        try:
            compiler.apply_release(
                root=root,
                fragments=compiler.load_fragments(fragments),
                app_version="0.2.0",
                core_version=None,
                release_date="2026-02-03",
            )
        except compiler.FragmentError:
            pass
        else:
            raise AssertionError("write accepted a direct Unreleased edit")
        assert (root / "app/CHANGELOG.md").read_text(encoding="utf-8") == before
        assert (fragments / "103-write-guard.json").exists()
        (root / "app/CHANGELOG.md").write_text(APP, encoding="utf-8")
        before = (root / "app/CHANGELOG.md").read_text(encoding="utf-8")
        try:
            compiler.apply_release(
                root=root,
                fragments=compiler.load_fragments(fragments),
                app_version="0.2.1",
                core_version=None,
                release_date="2026-02-03",
            )
        except compiler.FragmentError as error:
            assert "app version" in str(error)
        else:
            raise AssertionError("write accepted a stale app version")
        assert (root / "app/CHANGELOG.md").read_text(encoding="utf-8") == before
        assert (fragments / "103-write-guard.json").exists()
    finally:
        temporary.cleanup()

    for name, create in (
        ("unexpected-extension", lambda directory: (directory / "note.txt").write_text("x")),
        ("nested-fragment", lambda directory: (directory / "nested").mkdir()),
        ("readme-directory", lambda directory: (directory / "README.md").mkdir()),
    ):
        temporary, root = fixture_repo()
        try:
            create(root / "changelog.d")
            try:
                compiler.load_fragments(root / "changelog.d")
            except compiler.FragmentError as error:
                assert "unexpected entries" in str(error)
            else:
                raise AssertionError(f"{name} passed")
        finally:
            temporary.cleanup()

    for name, contents in (
        ("mismatch", {"id": "other", "user_visible": True, "app": {"added": ["x"]}}),
        ("empty", {"id": "empty"}),
        ("unknown", {"id": "unknown", "user_visible": True, "app": {"security": ["x"]}}),
        ("blank-entry", {"id": "blank-entry", "user_visible": True, "app": {"added": [" "]}}),
        (
            "invisible-app",
            {
                "id": "invisible-app",
                "user_visible": False,
                "app": {"added": ["This must be user-visible."]},
            },
        ),
        (
            "multiline-entry",
            {
                "id": "multiline-entry",
                "user_visible": True,
                "app": {"added": ["A note\n\n### Injected heading"]},
            },
        ),
    ):
        temporary, root = fixture_repo()
        try:
            write_fragment(root / "changelog.d", name, contents)
            try:
                compiler.load_fragments(root / "changelog.d")
            except compiler.FragmentError:
                pass
            else:
                raise AssertionError(f"{name} fragment passed")
        finally:
            temporary.cleanup()

    temporary, root = fixture_repo()
    try:
        write_fragment(
            root / "changelog.d",
            "core-only",
            {
                "id": "core-only",
                "user_visible": False,
                "core": {"fixed": ["Fix parser state."]},
            },
        )
        entries = compiler.load_fragments(root / "changelog.d")
        try:
            compiler.compile_changelogs(
                app_changelog=APP,
                core_changelog=CORE,
                fragments=entries,
                app_version="0.2.0",
                core_version=None,
                release_date="2026-02-02",
            )
        except compiler.FragmentError as error:
            assert "core version" in str(error)
        else:
            raise AssertionError("core entries accepted without a core version")
    finally:
        temporary.cleanup()


if __name__ == "__main__":
    cases()
    print("OK: changelog fragment compiler tests passed")
