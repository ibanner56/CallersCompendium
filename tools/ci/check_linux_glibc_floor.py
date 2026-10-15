#!/usr/bin/env python3
"""Fail if any binary in a built Linux bundle needs a newer glibc than the floor.

The documented minimum Linux (``docs/user/installation.md``) is glibc 2.35.
``check_linux_build_runner.py`` makes the Linux build legs run in an
``ubuntu:22.04`` container, which bounds what the build can need; this script
checks the result. It reads every ELF file in the bundle (the runner
executable and each ``lib/*.so``), takes every ``GLIBC_`` entry from its
``Version References`` (``objdump -p``: the versions the dynamic loader
insists on at start-up, so a user whose glibc is older gets
"version `GLIBC_2.xx' not found"), and fails if any is above the floor.

Not every requirement is numeric. glibc also defines ABI markers that the
static linker records when a binary uses a newer loader feature, such as
``GLIBC_ABI_DT_RELR`` for packed relative relocations. The loader refuses a
binary that needs one its glibc lacks, exactly as for a numeric version, so
each known marker maps to the glibc that first has it (``ABI_MARKERS``), and an
unknown non-numeric requirement fails rather than being ignored.

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

Version = tuple[int, ...]

# Any glibc version requirement: GLIBC_2.34, GLIBC_ABI_DT_RELR, ... but not
# GLIBCXX_ (libstdc++), which the anchored "GLIBC_" excludes.
_GLIBC_RE = re.compile(r"\bGLIBC_(\S+)\s*$")
_NUMERIC_RE = re.compile(r"^\d+(?:\.\d+)+$")

# Known non-numeric glibc ABI markers: the upstream glibc release that first
# defines each, or None when no upstream release (through 2.42) defines it and
# it exists only as a backport on glibc's stable release branches, which a
# distribution's glibc of the floor version may or may not carry.
# Sources (sourceware glibc, read via the bminor/glibc mirror, 2026-10-06):
#   ABI_DT_RELR: elf/Versions in the glibc-2.36 tag, absent from glibc-2.35;
#     NEWS for 2.36, "Support for DT_RELR relative relocation format".
#   ABI_DT_X86_64_PLT: sysdeps/x86_64/Versions; in no release tag through
#     glibc-2.42, present on master and on release/2.35/master onwards.
#   ABI_GNU2_TLS: sysdeps/x86/Versions; in no release tag through glibc-2.42,
#     present on master and on release/2.38/master onwards.
#   ABI_GNU_TLS: sysdeps/i386/Versions (32-bit x86 only); in no release tag
#     through glibc-2.42, present on master and release/2.38/master onwards.
ABI_MARKERS: dict[str, Version | None] = {
    "ABI_DT_RELR": (2, 36),
    "ABI_DT_X86_64_PLT": None,
    "ABI_GNU2_TLS": None,
    "ABI_GNU_TLS": None,
}


def parse_version(text: str) -> Version:
    return tuple(int(part) for part in text.split("."))


def version_str(version: Version) -> str:
    return ".".join(str(part) for part in version)


def glibc_requirements(objdump_p: str) -> list[str]:
    """The ``GLIBC_`` requirements in the ``Version References`` block of
    ``objdump -p`` output, without the ``GLIBC_`` prefix and in order (e.g.
    ``["2.34", "ABI_DT_RELR"]``). Other blocks (notably ``Version
    definitions``) and other version namespaces (``GLIBCXX_``, ``GCC_``) are
    ignored."""
    reqs: list[str] = []
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
            reqs.append(match.group(1))
    return reqs


def resolve(req: str) -> tuple[Version | None, str | None]:
    """The glibc version a requirement (``GLIBC_`` stripped) implies, or None
    and the reason it cannot be met at any documented floor."""
    if _NUMERIC_RE.match(req):
        return parse_version(req), None
    if req in ABI_MARKERS:
        version = ABI_MARKERS[req]
        if version is not None:
            return version, None
        return None, (
            f"GLIBC_{req} is in no upstream glibc release through 2.42, only a "
            "backport on its stable branches, so a system at the floor may lack it"
        )
    return None, (
        f"GLIBC_{req} is an unknown non-numeric glibc requirement; find the glibc "
        "release that first defines it and add it to ABI_MARKERS"
    )


def read_glibc_requirements(path: Path) -> list[str]:
    out = subprocess.run(
        ["objdump", "-p", str(path)], check=True, capture_output=True, text=True
    ).stdout
    return glibc_requirements(out)


def _is_elf(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def check_bundle(
    bundle: Path, reader: Callable[[Path], list[str]] = read_glibc_requirements
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
        reqs = reader(path)
        if not reqs:
            lines.append(f"  {rel}: no GLIBC_ references")
            continue
        highest: tuple[Version, str] | None = None
        for req in reqs:
            version, problem = resolve(req)
            if problem:
                errors.append(f"{rel} needs {problem}.")
                continue
            if highest is None or version > highest[0]:
                highest = (version, req)
        markers = [r for r in reqs if not _NUMERIC_RE.match(r)]
        suffix = f" (markers: {', '.join('GLIBC_' + m for m in markers)})" if markers else ""
        if highest is None:
            lines.append(f"  {rel}: no numeric GLIBC_ references{suffix}")
            continue
        lines.append(f"  {rel}: GLIBC_{version_str(highest[0])}{suffix}")
        if overall is None or highest[0] > overall[0]:
            overall = (highest[0], rel)
        if highest[0] > GLIBC_FLOOR:
            via = "" if _NUMERIC_RE.match(highest[1]) else f" (through GLIBC_{highest[1]})"
            errors.append(
                f"{rel} needs GLIBC_{version_str(highest[0])}{via}, above the documented "
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
