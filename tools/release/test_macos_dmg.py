#!/usr/bin/env python3
"""Guard the macOS installer disk image's layout contract.

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``). Run directly::

    python3 tools/release/test_macos_dmg.py

The ``.dmg`` window is assembled from files that have to agree:
``packaging/macos/dmg_settings.py`` (window size, icon positions, what goes in
the image), the committed background art drawn for that geometry by
``tools/brand/generate_dmg_background.py``, ``packaging/macos/build_dmg.sh``,
the hash-pinned ``requirements-dmg.txt``, and the two macOS packaging steps of
``.github/workflows/release.yml``. Building the image needs ``hdiutil`` and
only happens on a tag, so a drift between them would otherwise surface at
release time as a mis-drawn window — or not at all. These tests run the
settings file the way dmgbuild does and pin the rest by inspection.
"""

from __future__ import annotations

import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGING = ROOT / "packaging" / "macos"
SETTINGS = PACKAGING / "dmg_settings.py"
BUILD = PACKAGING / "build_dmg.sh"
REQUIREMENTS = PACKAGING / "requirements-dmg.txt"
BACKGROUND_1X = PACKAGING / "dmg-background.png"
BACKGROUND_2X = PACKAGING / "dmg-background@2x.png"
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
INSTALL_STEP = "Install DMG layout tool (dmgbuild, hash-pinned)"
PACKAGE_STEPS = (
    "Package macOS (zip + dmg)",
    "Sign, notarize & package macOS (Developer ID)",
)
APP = "/build/Products/Release/Caller’s Compendium.app"


def load_settings(app: str = APP) -> dict:
    """Execute the settings file as dmgbuild 1.6's ``load_settings`` does."""
    namespace: dict = {"defines": {"app": app, "background": str(BACKGROUND_1X)}}
    exec(compile(SETTINGS.read_text(encoding="utf-8"), str(SETTINGS), "exec"),
         namespace, namespace)
    return namespace


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()[:24]
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path.name} is not a PNG"
    assert data[12:16] == b"IHDR", f"{path.name} has no leading IHDR chunk"
    return struct.unpack(">II", data[16:24])


def workflow_step(name: str) -> str:
    text = WORKFLOW.read_text(encoding="utf-8")
    start = text.find(f"      - name: {name}\n")
    assert start >= 0, f"release.yml has no step named {name!r}"
    end = text.find("\n      - name: ", start + 1)
    return text[start:end if end >= 0 else len(text)]


def test_settings_put_the_app_and_applications_shortcut_in_the_image() -> None:
    s = load_settings()
    assert s["files"] == [APP], s["files"]
    assert s["symlinks"] == {"Applications": "/Applications"}, s["symlinks"]
    assert s["icon"] == f"{APP}/Contents/Resources/AppIcon.icns", s["icon"]
    assert s["background"] == str(BACKGROUND_1X), s["background"]
    # The previous hdiutil recipe's format and filesystem, kept on purpose.
    assert s["format"] == "UDZO", s["format"]
    assert s["filesystem"] == "HFS+", s["filesystem"]


def test_trailing_slash_on_the_app_path_does_not_lose_the_icon_name() -> None:
    s = load_settings(APP + "/")
    assert set(s["icon_locations"]) == {"Caller’s Compendium.app", "Applications"}


def test_window_is_bare_icon_view() -> None:
    s = load_settings()
    for key in ("show_status_bar", "show_tab_view", "show_toolbar",
                "show_pathbar", "show_sidebar"):
        assert s[key] is False, f"{key} should be False"
    assert s["default_view"] == "icon-view"
    assert s["window_rect"][1] == s["WINDOW_SIZE"], "window size must match the art"
    assert s["icon_size"] == s["ICON_SIZE"]


def test_both_icons_are_placed_and_fully_inside_the_window() -> None:
    s = load_settings()
    width, height = s["WINDOW_SIZE"]
    half = s["ICON_SIZE"] / 2
    app_name = Path(APP).name
    assert s["icon_locations"] == {
        app_name: s["APP_POS"],
        "Applications": s["APPLICATIONS_POS"],
    }, s["icon_locations"]
    for name, (x, y) in s["icon_locations"].items():
        assert half <= x <= width - half, f"{name} icon is clipped horizontally"
        # Room below for the label (~2 text lines).
        assert half <= y <= height - half - 2 * s["text_size"] - 8, \
            f"{name} icon or label is clipped vertically"
    assert s["APP_POS"][0] < s["APPLICATIONS_POS"][0], \
        "the art's arrow points left-to-right, from the app to Applications"


def test_background_art_matches_the_window_geometry() -> None:
    width, height = load_settings()["WINDOW_SIZE"]
    assert png_size(BACKGROUND_1X) == (width, height), \
        f"{BACKGROUND_1X.name}: re-run tools/brand/generate_dmg_background.py"
    assert png_size(BACKGROUND_2X) == (2 * width, 2 * height), \
        f"{BACKGROUND_2X.name}: re-run tools/brand/generate_dmg_background.py"


def test_requirements_are_exact_and_hash_pinned() -> None:
    text = REQUIREMENTS.read_text(encoding="utf-8")
    entries = re.split(r"(?<!\\)\n", re.sub(r"(?m)^#.*\n", "", text))
    entries = [e for e in entries if e.strip()]
    names = set()
    for entry in entries:
        match = re.match(r"([A-Za-z0-9_.-]+)==\S+", entry.strip())
        assert match, f"not an exact pin: {entry!r}"
        assert re.search(r"--hash=sha256:[0-9a-f]{64}", entry), f"no hash: {entry!r}"
        names.add(match.group(1).lower().replace("-", "_"))
    # --require-hashes needs every transitive dependency listed.
    assert names == {"dmgbuild", "ds_store", "mac_alias"}, names


def test_build_script_wires_settings_and_background() -> None:
    text = BUILD.read_text(encoding="utf-8")
    assert '-s "$here/dmg_settings.py"' in text
    assert '-D app="$app_path"' in text
    assert '-D background="$here/dmg-background.png"' in text
    assert subprocess.run(["bash", "-n", str(BUILD)]).returncode == 0
    assert BUILD.stat().st_mode & 0o111, "build_dmg.sh must be executable"


def test_both_packaging_steps_use_the_build_script() -> None:
    install = workflow_step(INSTALL_STEP)
    assert "--require-hashes -r packaging/macos/requirements-dmg.txt" in install
    assert "DMGBUILD_PYTHON=" in install
    text = WORKFLOW.read_text(encoding="utf-8")
    for name in PACKAGE_STEPS:
        step = workflow_step(name)
        assert "packaging/macos/build_dmg.sh" in step, f"{name} bypasses build_dmg.sh"
        assert "hdiutil create" not in step, f"{name} still builds a bare dmg"
        assert text.index(INSTALL_STEP) < text.index(f"- name: {name}\n"), \
            f"{name} runs before dmgbuild is installed"


def main() -> int:
    tests = [(n, f) for n, f in sorted(globals().items())
             if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn()
        except AssertionError as exc:
            failed += 1
            print(f"FAIL {name}: {exc}")
        else:
            print(f"ok   {name}")
    print(f"{len(tests) - failed}/{len(tests)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
