#!/usr/bin/env python3
"""Guard that the Linux window matches its launcher and both downloads carry it.

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``). Run directly::

    python3 tools/release/test_linux_desktop_integration.py

**Why this file exists** (post-audit finding platform-8). The runner registers
the GtkApplication id ``APPLICATION_ID`` from ``app/linux/CMakeLists.txt`` and
sets it as the program name, so the running window's Wayland ``app_id`` and its
X11 ``WM_CLASS`` instance are that id. A desktop shell pairs a window with its
launcher by that value: the ``.desktop`` file's own name on Wayland, its
``StartupWMClass`` on X11. The launcher used to be ``compendium_app.desktop``
with no ``StartupWMClass``, so on GNOME the running app showed a generic icon
in a dock entry of its own. The window also had no icon of its own, and the
tar.gz carried neither the ``.desktop`` file nor the icon.

These tests cannot run a desktop session. They pin the *contract* between the
files that have to agree: the CMake id, the ``.desktop`` file's name and
``StartupWMClass``, the icon the runner loads and the icon CMake installs, and
the release step that copies the launcher and icon into both Linux downloads.
"""

from __future__ import annotations

import configparser
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CMAKE = ROOT / "app" / "linux" / "CMakeLists.txt"
RUNNER = ROOT / "app" / "linux" / "runner" / "my_application.cc"
PACKAGING = ROOT / "packaging" / "linux"
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
PACKAGE_STEP = "Package Linux (tar.gz + AppImage)"


def cmake_set(name: str) -> str:
    text = CMAKE.read_text(encoding="utf-8")
    match = re.search(rf'^\s*set\(\s*{name}\s+"([^"]+)"\s*\)', text, re.MULTILINE)
    assert match, f"{CMAKE.relative_to(ROOT)} has no set({name} \"...\")"
    return match.group(1)


def desktop_files() -> list[Path]:
    return sorted(PACKAGING.glob("*.desktop"))


def desktop_entry() -> configparser.SectionProxy:
    files = desktop_files()
    assert len(files) == 1, f"expected one .desktop file in packaging/linux, found {files}"
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str  # keys are case-sensitive
    parser.read(files[0], encoding="utf-8")
    assert parser.has_section("Desktop Entry"), f"{files[0].name} has no [Desktop Entry]"
    return parser["Desktop Entry"]


def step_run(name: str) -> str:
    """The ``run:`` body of the named release.yml step, up to the next step."""
    text = WORKFLOW.read_text(encoding="utf-8")
    start = text.find(f"- name: {name}\n")
    assert start >= 0, f"release.yml has no step named {name!r}"
    end = text.find("\n      - ", start + 1)
    return text[start : end if end >= 0 else len(text)]


def strip_cxx_comments(src: str) -> str:
    src = re.sub(r"/\*[\s\S]*?\*/", "", src)
    return re.sub(r"//[^\n]*", "", src)


def strip_cmake_comments(src: str) -> str:
    return re.sub(r"#[^\n]*", "", src)


# --------------------------------------------------------------------------


def test_launcher_matches_application_id() -> None:
    app_id = cmake_set("APPLICATION_ID")
    files = desktop_files()
    assert [f.name for f in files] == [f"{app_id}.desktop"], (
        f"the .desktop file must be named after APPLICATION_ID ({app_id}.desktop) so "
        f"Wayland shells match the window's app_id to it; found {[f.name for f in files]}"
    )
    entry = desktop_entry()
    assert entry.get("StartupWMClass") == app_id, (
        f"StartupWMClass must equal APPLICATION_ID {app_id!r} so X11 shells match the "
        f"window's WM_CLASS to the launcher; got {entry.get('StartupWMClass')!r}"
    )


def test_runner_uses_the_cmake_id_as_program_name() -> None:
    # The match above holds only while the runner names itself after the id.
    src = strip_cxx_comments(RUNNER.read_text(encoding="utf-8"))
    assert re.search(r"\bg_set_prgname\s*\(\s*APPLICATION_ID\s*\)", src), (
        "my_application.cc must call g_set_prgname(APPLICATION_ID): WM_CLASS and the "
        "Wayland app_id come from it"
    )
    assert re.search(r'"application-id"\s*,\s*APPLICATION_ID', src), (
        "my_application.cc must register the GtkApplication with APPLICATION_ID"
    )


def test_no_file_association_is_declared() -> None:
    # Opening files from the launcher needs the single-instance raise channel to
    # carry a path, which it deliberately does not (no payload). Not approved.
    entry = desktop_entry()
    assert "MimeType" not in entry, "MimeType= would register a file association"
    exec_line = entry.get("Exec", "")
    assert not re.search(r"%[fFuU]", exec_line), (
        f"Exec={exec_line!r} passes files or URLs to the app, which it cannot accept"
    )


def test_icon_is_installed_into_the_bundle_and_set_on_the_window() -> None:
    icon_name = desktop_entry().get("Icon")
    assert icon_name and "/" not in icon_name, f"Icon= must be a bare icon name, got {icon_name!r}"
    cmake = strip_cmake_comments(CMAKE.read_text(encoding="utf-8"))
    install = re.search(
        r"install\(\s*FILES\s+\"[^\"]*packaging/linux/icon\.png\"\s+"
        r"DESTINATION\s+\"\$\{INSTALL_BUNDLE_DATA_DIR\}\"[^)]*\)",
        cmake,
    )
    assert install, (
        "app/linux/CMakeLists.txt must install packaging/linux/icon.png into the "
        "bundle's data directory"
    )
    renamed = re.search(r'RENAME\s+"?([^")\s]+)"?', install.group(0))
    installed_as = renamed.group(1) if renamed else "icon.png"
    assert installed_as == f"{icon_name}.png", (
        f"the bundled icon is installed as {installed_as!r}; it should be "
        f"{icon_name}.png to match the launcher's Icon={icon_name}"
    )

    src = strip_cxx_comments(RUNNER.read_text(encoding="utf-8"))
    assert re.search(r"\bgtk_window_set_icon(_from_file)?\s*\(\s*window\b", src), (
        "my_application.cc never sets the window icon"
    )
    assert f'"{installed_as}"' in src and '"data"' in src, (
        f"my_application.cc must load data/{installed_as}, the file CMake installs"
    )


def test_tarball_ships_the_launcher_and_icon() -> None:
    app_id = cmake_set("APPLICATION_ID")
    icon_name = desktop_entry().get("Icon")
    run = step_run(PACKAGE_STEP)
    tar_at = run.find('tar -czf "dist/${stage}.tar.gz" "$stage"')
    assert tar_at >= 0, "the package step no longer builds the tar.gz from $stage"
    before_tar = run[:tar_at]
    assert re.search(
        rf'cp\s+packaging/linux/{re.escape(app_id)}\.desktop\s+"\$stage/{re.escape(app_id)}\.desktop"',
        before_tar,
    ), f"the tar.gz stage must get packaging/linux/{app_id}.desktop before it is archived"
    assert re.search(
        rf'cp\s+packaging/linux/icon\.png\s+"\$stage/{re.escape(icon_name)}\.png"', before_tar
    ), f"the tar.gz stage must get the icon as {icon_name}.png before it is archived"

    verify = run[tar_at:]
    for member in (f"{app_id}.desktop", f"{icon_name}.png", f"data/{icon_name}.png"):
        assert member in verify, f"the package step does not check that the tar.gz holds {member}"


def test_appimage_uses_the_same_launcher_and_icon() -> None:
    app_id = cmake_set("APPLICATION_ID")
    icon_name = desktop_entry().get("Icon")
    run = step_run(PACKAGE_STEP)
    assert re.search(
        rf'cp\s+packaging/linux/{re.escape(app_id)}\.desktop\s+"\$appdir/{re.escape(app_id)}\.desktop"',
        run,
    ), "the AppDir must get the renamed .desktop file"
    # appimagetool resolves Icon= to <name>.png at the AppDir root.
    assert re.search(
        rf'cp\s+packaging/linux/icon\.png\s+"\$appdir/{re.escape(icon_name)}\.png"', run
    ), f"the AppDir root must hold {icon_name}.png for Icon={icon_name}"
    assert "compendium_app.desktop" not in run.replace(f"{app_id}.desktop", ""), (
        "the package step still refers to the old compendium_app.desktop"
    )


TESTS = [
    test_launcher_matches_application_id,
    test_runner_uses_the_cmake_id_as_program_name,
    test_no_file_association_is_declared,
    test_icon_is_installed_into_the_bundle_and_set_on_the_window,
    test_tarball_ships_the_launcher_and_icon,
    test_appimage_uses_the_same_launcher_and_icon,
]


def main() -> int:
    failures = 0
    for test in TESTS:
        try:
            test()
        except AssertionError as error:
            failures += 1
            print(f"FAIL {test.__name__}: {error}")
        else:
            print(f"ok   {test.__name__}")
    if failures:
        print(f"{failures} of {len(TESTS)} Linux desktop-integration test(s) failed")
        return 1
    print(f"OK: {len(TESTS)} Linux desktop-integration tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
