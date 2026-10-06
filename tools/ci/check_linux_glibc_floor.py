#!/usr/bin/env python3
"""Fail if any binary in a built Linux bundle needs a newer glibc than the floor.

The documented minimum Linux (``docs/user/installation.md``) is glibc 2.35.
``check_linux_build_runner.py`` makes the Linux build legs run in an
``ubuntu:22.04`` container, which bounds what the build can need; this script
checks the result. It reads every ELF file in the bundle (the runner
executable and each ``lib/*.so``), takes the ``GLIBC_x.y[.z]`` entries from its
``Version References`` (``objdump -p``: the versions the dynamic loader
insists on at start-up, so a user whose glibc is older gets
"version `GLIBC_2.xx' not found"), and fails if any is above the floor.

It prints the highest version each file needs and the highest overall, so the
build log says where the bundle actually stands, not only that it passed.

Usage: ``check_linux_glibc_floor.py <bundle dir>`` (e.g.
``app/build/linux/x64/release/bundle``). Needs ``objdump`` (binutils). Exit 0
when every file is at or below the floor, 1 otherwise.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

# glibc of the ubuntu:22.04 build container, and the minimum the user guide
# states. Changing it is a support decision: see check_linux_build_runner.py.
GLIBC_FLOOR = (2, 35)

# The runner executable a Flutter Linux bundle must contain (BINARY_NAME in
# app/linux/CMakeLists.txt). Its absence means the path is wrong or the build
# is empty, and the check must not pass vacuously.
EXECUTABLE = "compendium_app"

_GLIBC_RE = re.compile(r"\bGLIBC_(\d+(?:\.\d+)+)\s*$")

Version = tuple[int, ...]


def parse_version(text: str) -> Version:
    return tuple(int(part) for part in text.split("."))


def version_str(version: Version) -> str:
    return ".".join(str(part) for part in version)


def glibc_refs(objdump_p: str) -> list[Version]:
    """The ``GLIBC_`` versions in the ``Version References`` block of
    ``objdump -p`` output, in order. Other blocks (notably ``Version
    definitions``) and other version namespaces (``GLIBCXX_``, ``GCC_``) are
    ignored."""
    refs: list[Version] = []
    in_refs = False
    for line in objdump_p.splitlines():
        if line.startswith("Version References:"):
            in_refs = True
            continue
        if in_refs and line and not line.startswith(" "):
            in_refs = False
        if not in_refs:
            continue
        match = _GLIBC_RE.search(line)
        if match:
            refs.append(parse_version(match.group(1)))
    return refs


def read_glibc_refs(path: Path) -> list[Version]:
    out = subprocess.run(
        ["objdump", "-p", str(path)], check=True, capture_output=True, text=True
    ).stdout
    return glibc_refs(out)


def _is_elf(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def check_bundle(
    bundle: Path, reader: Callable[[Path], list[Version]] = read_glibc_refs
) -> tuple[list[str], str]:
    """Returns (errors, report) for the bundle at ``bundle``."""
    if not bundle.is_dir():
        return [f"{bundle}: not a directory."], ""
    errors: list[str] = []
    if not (bundle / EXECUTABLE).is_file():
        errors.append(f"{bundle}: no {EXECUTABLE} executable; is this a release bundle?")
    lines: list[str] = []
    overall: tuple[Version, str] | None = None
    for path in sorted(p for p in bundle.rglob("*") if p.is_file() and not p.is_symlink()):
        if not _is_elf(path):
            continue
        rel = path.relative_to(bundle).as_posix()
        refs = reader(path)
        if not refs:
            lines.append(f"  {rel}: no GLIBC_ references")
            continue
        highest = max(refs)
        lines.append(f"  {rel}: GLIBC_{version_str(highest)}")
        if overall is None or highest > overall[0]:
            overall = (highest, rel)
        if highest > GLIBC_FLOOR:
            errors.append(
                f"{rel} needs GLIBC_{version_str(highest)}, above the documented "
                f"floor of {version_str(GLIBC_FLOOR)} (docs/user/installation.md). "
                "Was it built outside the ubuntu:22.04 container?"
            )
    if overall is None and not errors:
        errors.append(f"{bundle}: no ELF file references glibc; nothing was checked.")
    summary = (
        f"Highest glibc symbol version in the bundle: GLIBC_{version_str(overall[0])} "
        f"(in {overall[1]}); floor {version_str(GLIBC_FLOOR)}"
        if overall
        else "No glibc references found"
    )
    return errors, "\n".join(lines + [summary])


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: check_linux_glibc_floor.py <bundle dir>", file=sys.stderr)
        return 2
    errors, report = check_bundle(Path(argv[0]))
    if report:
        print(report)
    for error in errors:
        print(f"::error::{error}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
