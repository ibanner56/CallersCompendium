#!/usr/bin/env python3
"""Guard that the pdfium the Linux and Windows builds ship is pinned and verified.

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``). Run directly::

    python3 tools/release/test_pdfium_pin.py

**Why this file exists** (audit finding platform-5). The ``printing`` plugin
downloads a prebuilt pdfium from ``bblanchon/pdfium-binaries`` while CMake
configures the Linux and Windows builds. Its ``download_project`` call passes no
``URL_HASH``, and its only knob is the ``PDFIUM_VERSION`` cache variable (which
also accepts ``latest``). The release pipeline SHA-pins every other tool it
downloads (appimagetool, the AppImage runtime, the Inno Setup packages); pdfium
ships inside the product and was the exception.

``packaging/pdfium/pdfium.cmake`` holds the pin. The two app CMake files force
``PDFIUM_VERSION`` to it before the plugins are added and, once the plugin has
downloaded its archive, check the archive's and the bundled library's SHA-256,
failing the configure step on any mismatch. These tests check that wiring and
run the verifier under ``cmake -P`` against fake archives, so a verifier that
cannot fail is caught as well as a missing pin.
"""

from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import pdfium_pin  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PIN_FILE = ROOT / "packaging" / "pdfium" / "pdfium.cmake"
LOCKFILE = ROOT / "pubspec.lock"
LICENSE_ASSET = ROOT / "app" / "assets" / "licenses" / "pdfium-LICENSE.txt"
APP_CMAKE = {
    "linux": ROOT / "app" / "linux" / "CMakeLists.txt",
    "win": ROOT / "app" / "windows" / "CMakeLists.txt",
}
HEX64 = re.compile(r"^[0-9a-f]{64}$")

# Every target a developer or the release can build. The release ships x64
# only; arm64 is pinned too so a local arm64 build is verified, not refused.
TARGETS = ("linux-x64", "linux-arm64", "win-x64", "win-arm64")


def pin() -> pdfium_pin.PdfiumPin:
    assert PIN_FILE.is_file(), f"missing pin file {PIN_FILE.relative_to(ROOT)}"
    return pdfium_pin.read(PIN_FILE)


def test_pin_names_an_explicit_release() -> None:
    p = pin()
    assert re.fullmatch(r"\d+", p.version), (
        f"PDFIUM_VERSION must be an explicit chromium/<n> build, not {p.version!r}"
    )
    assert p.version != "latest"
    assert re.fullmatch(r"\d+\.\d+\.\d+\.\d+", p.full_version), p.full_version
    assert p.full_version.split(".")[2] == p.version, (
        "the full PDFium version's build number must be the pinned chromium build"
    )


def test_every_target_has_archive_and_library_hashes() -> None:
    p = pin()
    for target in TARGETS:
        assert target in p.targets, f"no pinned hashes for pdfium-{target}"
        entry = p.targets[target]
        assert HEX64.match(entry.archive_sha256), f"{target}: bad archive SHA-256"
        assert HEX64.match(entry.library_sha256), f"{target}: bad library SHA-256"
    archives = [p.targets[t].archive_sha256 for t in TARGETS]
    assert len(set(archives)) == len(archives), "each archive must have its own hash"


def test_pin_matches_the_locked_printing_plugin() -> None:
    # The verifier relies on where printing's download_project puts the
    # archive, and on its PDFIUM_VERSION/PDFIUM_ARCH variables. A plugin
    # upgrade must re-review that, so the pin names the version it was
    # written against.
    lock = LOCKFILE.read_text(encoding="utf-8")
    match = re.search(
        r'^  printing:\n(?:    .*\n)*?    version: "([^"]+)"', lock, re.MULTILINE
    )
    assert match is not None, "printing is not in pubspec.lock"
    assert match.group(1) == pin().printing_version, (
        f"pubspec.lock has printing {match.group(1)} but packaging/pdfium/pdfium.cmake "
        f"was written for {pin().printing_version}; re-check the plugin's "
        "CMakeLists.txt and update the pin"
    )


def _code_lines(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def test_app_cmake_pins_before_and_verifies_after_the_plugins() -> None:
    for os_name, path in APP_CMAKE.items():
        lines = _code_lines(path)
        include = [
            i for i, l in enumerate(lines)
            if l.startswith("include(") and "packaging/pdfium/pdfium.cmake" in l
        ]
        pin_calls = [i for i, l in enumerate(lines) if l == "compendium_pin_pdfium()"]
        plugins = [
            i for i, l in enumerate(lines) if l == "include(flutter/generated_plugins.cmake)"
        ]
        verify = [
            i for i, l in enumerate(lines) if l == f"compendium_verify_pdfium({os_name})"
        ]
        rel = path.relative_to(ROOT)
        assert len(include) == 1, f"{rel} must include packaging/pdfium/pdfium.cmake once"
        assert len(pin_calls) == 1, f"{rel} must call compendium_pin_pdfium() once"
        assert len(plugins) == 1, f"{rel} must include generated_plugins.cmake once"
        assert len(verify) == 1, f"{rel} must call compendium_verify_pdfium({os_name}) once"
        assert include[0] < pin_calls[0] < plugins[0] < verify[0], (
            f"{rel}: pin before the plugins are added, verify straight after"
        )


def test_pin_macro_forces_the_cache_variable() -> None:
    text = PIN_FILE.read_text(encoding="utf-8")
    assert re.search(
        r'set\(PDFIUM_VERSION\s+"\$\{COMPENDIUM_PDFIUM_VERSION\}"\s+CACHE\s+STRING\s+"[^"]*"\s+FORCE\)',
        text,
    ), (
        "PDFIUM_VERSION must be set as a FORCEd cache entry: the plugin's own "
        "set(... CACHE ...) then leaves it alone, and -DPDFIUM_VERSION=latest "
        "cannot override the pin"
    )


# --- the verifier itself, run under `cmake -P` ------------------------------


def _have_cmake() -> bool:
    return shutil.which("cmake") is not None


def _fake_build(tmp: Path, os_name: str, arch: str, payload: bytes) -> tuple[str, str]:
    """Lay out what printing's download_project leaves in the build dir."""
    src = tmp / "pdfium-download" / "pdfium-download-prefix" / "src"
    src.mkdir(parents=True)
    archive = src / f"pdfium-{os_name}-{arch}.tgz"
    archive.write_bytes(b"archive:" + payload)
    lib = (
        tmp / "pdfium-src" / "bin" / "pdfium.dll"
        if os_name == "win"
        else tmp / "pdfium-src" / "lib" / "libpdfium.so"
    )
    lib.parent.mkdir(parents=True)
    lib.write_bytes(b"library:" + payload)
    return (
        hashlib.sha256(archive.read_bytes()).hexdigest(),
        hashlib.sha256(lib.read_bytes()).hexdigest(),
    )


def _run_verifier(tmp: Path, os_name: str, prelude: str) -> subprocess.CompletedProcess:
    driver = tmp / "driver.cmake"
    driver.write_text(
        f'include("{PIN_FILE.as_posix()}")\n'
        f'set(COMPENDIUM_PDFIUM_BUILD_DIR "{tmp.as_posix()}")\n'
        f"{prelude}\n"
        f"compendium_verify_pdfium({os_name})\n",
        encoding="utf-8",
    )
    return subprocess.run(
        ["cmake", "-P", str(driver)], cwd=tmp, capture_output=True, text=True
    )


def _expect(result: subprocess.CompletedProcess, ok: bool, needle: str) -> None:
    out = result.stdout + result.stderr
    if ok:
        assert result.returncode == 0, f"verifier refused a matching pdfium:\n{out}"
    else:
        assert result.returncode != 0, f"verifier accepted a bad pdfium:\n{out}"
    assert needle in out, f"expected {needle!r} in verifier output:\n{out}"


def test_verifier_accepts_matching_hashes() -> None:
    if not _have_cmake():
        raise AssertionError("cmake is required to run the pdfium verifier tests")
    p = pin()
    for os_name in ("linux", "win"):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            archive, lib = _fake_build(tmp, os_name, "x64", b"good")
            key = f"{os_name}_x64"
            result = _run_verifier(
                tmp,
                os_name,
                f'set(PDFIUM_VERSION "{p.version}")\nset(PDFIUM_ARCH "x64")\n'
                f'set(COMPENDIUM_PDFIUM_ARCHIVE_SHA256_{key} "{archive}")\n'
                f'set(COMPENDIUM_PDFIUM_LIBRARY_SHA256_{key} "{lib}")',
            )
            _expect(result, True, "verified")


def test_verifier_rejects_a_different_archive() -> None:
    # The real pinned archive hash against a fake archive: what a swapped
    # release asset looks like. The library hash is made to match, so only the
    # archive check can stop it (otherwise a disabled archive check would still
    # fail on the library and pass this test).
    p = pin()
    for os_name in ("linux", "win"):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            _, lib = _fake_build(tmp, os_name, "x64", b"tampered")
            result = _run_verifier(
                tmp,
                os_name,
                f'set(PDFIUM_VERSION "{p.version}")\nset(PDFIUM_ARCH "x64")\n'
                f'set(COMPENDIUM_PDFIUM_LIBRARY_SHA256_{os_name}_x64 "{lib}")',
            )
            _expect(result, False, "SHA-256 mismatch")
            _expect(result, False, f"pdfium-{os_name}-x64.tgz")


def test_verifier_rejects_a_different_library() -> None:
    p = pin()
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        archive, _ = _fake_build(tmp, "linux", "x64", b"stale")
        result = _run_verifier(
            tmp,
            "linux",
            f'set(PDFIUM_VERSION "{p.version}")\nset(PDFIUM_ARCH "x64")\n'
            f'set(COMPENDIUM_PDFIUM_ARCHIVE_SHA256_linux_x64 "{archive}")',
        )
        _expect(result, False, "libpdfium.so")


def test_verifier_rejects_an_unpinned_version_or_arch_or_missing_archive() -> None:
    p = pin()
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        archive, lib = _fake_build(tmp, "linux", "x64", b"x")
        # Hashes made to match, so only the version check can refuse it.
        _expect(
            _run_verifier(
                tmp,
                "linux",
                'set(PDFIUM_VERSION "latest")\nset(PDFIUM_ARCH "x64")\n'
                f'set(COMPENDIUM_PDFIUM_ARCHIVE_SHA256_linux_x64 "{archive}")\n'
                f'set(COMPENDIUM_PDFIUM_LIBRARY_SHA256_linux_x64 "{lib}")',
            ),
            False,
            "PDFIUM_VERSION is 'latest'",
        )
        _expect(
            _run_verifier(
                tmp, "linux", f'set(PDFIUM_VERSION "{p.version}")\nset(PDFIUM_ARCH "riscv64")'
            ),
            False,
            "no pinned SHA-256",
        )
    with tempfile.TemporaryDirectory() as td:
        _expect(
            _run_verifier(
                Path(td), "linux", f'set(PDFIUM_VERSION "{p.version}")\nset(PDFIUM_ARCH "x64")'
            ),
            False,
            "not found",
        )


# --- the licence text that ships in the app ---------------------------------


def test_bundled_licence_is_the_pinned_release_licence() -> None:
    assert LICENSE_ASSET.is_file(), f"missing {LICENSE_ASSET.relative_to(ROOT)}"
    shipped = LICENSE_ASSET.read_bytes()
    shipped.decode("utf-8")  # rootBundle.loadString decodes UTF-8 strictly
    original = pdfium_pin.license_bytes_as_released(shipped)
    assert hashlib.sha256(original).hexdigest() == pin().license_sha256, (
        "app/assets/licenses/pdfium-LICENSE.txt is not the LICENSE from the pinned "
        "pdfium-binaries release (after the documented one-byte UTF-8 fix)"
    )
    text = shipped.decode("utf-8")
    for heading in (
        "# BEGIN PDFium license",
        "# BEGIN FreeType license",
        "# BEGIN libjpeg-turbo license file",
        "# BEGIN lcms license note",
        "# BEGIN openjpeg license note",
        "# BEGIN zlib license",
    ):
        assert heading in text, f"bundled pdfium licence lacks {heading!r}"


def main() -> int:
    tests = [(name, fn) for name, fn in globals().items() if name.startswith("test_")]
    failures = 0
    for name, fn in tests:
        try:
            fn()
        except Exception as error:  # noqa: BLE001 - report every failing case
            failures += 1
            print(f"FAIL {name}: {type(error).__name__}: {error}")
        else:
            print(f"ok   {name}")
    if failures:
        print(f"{failures} of {len(tests)} failed")
        return 1
    print(f"all {len(tests)} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
