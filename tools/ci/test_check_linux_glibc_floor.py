#!/usr/bin/env python3
"""Unit tests for the Linux bundle glibc-floor check."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_linux_glibc_floor as floor  # noqa: E402

# Trimmed `objdump -p` output of a real Flutter runner binary. Only the
# "Version References" block is what the dynamic loader checks; the
# "Version definitions" block and symbol names elsewhere must be ignored.
_OBJDUMP = """\
compendium_app:     file format elf64-x86-64

Dynamic Section:
  NEEDED               libc.so.6
  RUNPATH              $ORIGIN/lib

Version definitions:
1 0x01 0x0e1b0f5f  libfake.so
2 0x00 0x0d696918  GLIBC_9.99

Version References:
  required from libgcc_s.so.1:
    0x0b792650 0x00 09 GCC_3.0
  required from libstdc++.so.6:
    0x0297f870 0x00 08 GLIBCXX_3.4.30
  required from libc.so.6:
    0x09691a75 0x00 07 GLIBC_2.2.5
    0x069691b4 0x00 05 GLIBC_2.34
    0x09691974 0x00 03 GLIBC_2.4
"""


def _cases() -> None:
    reqs = floor.glibc_requirements(_OBJDUMP)
    # GLIBCXX and GCC are not glibc; the definitions block is not a reference.
    assert reqs == ["2.2.5", "2.34", "2.4"], reqs
    # Numeric, not lexical: 2.4 < 2.34 < 2.35, and 2.2.5 is the oldest.
    assert floor.resolve("2.34") == ((2, 34), None)
    assert floor.resolve("2.4")[0] < floor.resolve("2.34")[0]
    assert floor.parse_version("2.35") == (2, 35)
    assert (2, 36) > floor.GLIBC_FLOOR >= (2, 35)
    assert floor.version_str((2, 2, 5)) == "2.2.5"

    # Non-numeric ABI markers are loader-enforced requirements too. A binary
    # linked with packed relative relocations needs GLIBC_ABI_DT_RELR, which
    # glibc first provides in 2.36: that is above the floor even when every
    # numeric version is 2.34 or lower.
    assert floor.glibc_requirements(_OBJDUMP_RELR) == ["ABI_DT_RELR", "2.2.5", "2.34"]
    assert floor.resolve("ABI_DT_RELR") == ((2, 36), None)
    errors, report = _check_text(_OBJDUMP_RELR)
    assert len(errors) == 1 and "GLIBC_ABI_DT_RELR" in errors[0] and "2.36" in errors[0], errors
    assert "GLIBC_2.36" in report, report

    # Markers glibc has only as stable-branch backports (no upstream release
    # through 2.42 defines them) cannot be counted on at the floor.
    for marker in ("ABI_DT_X86_64_PLT", "ABI_GNU2_TLS", "ABI_GNU_TLS"):
        version, problem = floor.resolve(marker)
        assert version is None and problem and "backport" in problem, (marker, problem)

    # Anything else non-numeric fails closed, by name, instead of being ignored.
    version, problem = floor.resolve("FOO")
    assert version is None and problem and "GLIBC_FOO" in problem, problem
    errors, _ = _check_text(_OBJDUMP_RELR.replace("GLIBC_ABI_DT_RELR", "GLIBC_FOO"))
    assert len(errors) == 1 and "GLIBC_FOO" in errors[0] and "unknown" in errors[0], errors


_OBJDUMP_RELR = """\
relr:     file format elf64-x86-64

Version References:
  required from libc.so.6:
    0x00fd0e42 0x00 04 GLIBC_ABI_DT_RELR
    0x09691a75 0x00 03 GLIBC_2.2.5
    0x069691b4 0x00 02 GLIBC_2.34
"""


def _check_text(objdump_p: str) -> tuple[list[str], str]:
    """check_bundle over a one-file bundle whose objdump output is given."""
    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp)
        (bundle / "compendium_app").write_bytes(b"\x7fELF" + b"\0" * 60)
        return floor.check_bundle(bundle, lambda p: floor.glibc_requirements(objdump_p))


def _bundle_checks() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp)
        elf = b"\x7fELF" + b"\0" * 60
        (bundle / "lib").mkdir()
        (bundle / "compendium_app").write_bytes(elf)
        (bundle / "lib" / "libok.so").write_bytes(elf)
        (bundle / "lib" / "libnoglibc.so").write_bytes(elf)
        (bundle / "data").mkdir()
        (bundle / "data" / "icudtl.dat").write_bytes(b"not an elf")

        table = {
            "compendium_app": ["2.34", "2.2.5"],
            "libok.so": ["2.14"],
            "libnoglibc.so": [],
        }

        def reader(path: Path) -> list[str]:
            return table[path.name]

        errors, report = floor.check_bundle(bundle, reader)
        assert errors == [], errors
        assert "GLIBC_2.34" in report and "compendium_app" in report, report

        # A single library above the floor fails the whole bundle, by name.
        table["libok.so"] = ["2.38"]
        errors, _ = floor.check_bundle(bundle, reader)
        assert len(errors) == 1 and "libok.so" in errors[0] and "2.38" in errors[0], errors

        # Exactly at the floor passes.
        table["libok.so"] = [floor.version_str(floor.GLIBC_FLOOR)]
        errors, _ = floor.check_bundle(bundle, reader)
        assert errors == [], errors

        # A bundle without the runner executable is not a bundle: a wrong path
        # or an empty build must fail, never pass vacuously.
        (bundle / "compendium_app").unlink()
        errors, _ = floor.check_bundle(bundle, reader)
        assert any("compendium_app" in e for e in errors), errors

    with tempfile.TemporaryDirectory() as tmp:
        errors, _ = floor.check_bundle(Path(tmp) / "missing", lambda p: [])
        assert errors, "a missing bundle directory must fail"


def _live_relr() -> None:
    # A real ELF linked with packed relative relocations: its numeric glibc
    # versions are all at or below the floor, but the GLIBC_ABI_DT_RELR it
    # needs is not. The check must fail it, reading it with the real objdump.
    cc = shutil.which("cc") or shutil.which("gcc") or shutil.which("clang")
    if cc is None or shutil.which("objdump") is None:
        print("SKIP live DT_RELR check: no C compiler or objdump")
        return
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "relr.c"
        src.write_text("static int x; int *p = &x; int main(void) { return *p; }\n")
        bundle = Path(tmp) / "bundle"
        bundle.mkdir()
        exe = bundle / "compendium_app"
        built = subprocess.run(
            [cc, "-O2", "-fPIE", "-pie", "-Wl,-z,pack-relative-relocs", "-o", str(exe), str(src)],
            capture_output=True,
            text=True,
        )
        if built.returncode != 0:
            print("SKIP live DT_RELR check: the linker does not support -z pack-relative-relocs")
            return
        dump = subprocess.run(
            ["objdump", "-p", str(exe)], check=True, capture_output=True, text=True
        ).stdout
        if "GLIBC_ABI_DT_RELR" not in dump:
            print("SKIP live DT_RELR check: this glibc does not version DT_RELR (< 2.36)")
            return
        errors, report = floor.check_bundle(bundle)
        assert any("GLIBC_ABI_DT_RELR" in e for e in errors), (
            f"a binary needing GLIBC_ABI_DT_RELR (glibc 2.36) passed the "
            f"{floor.version_str(floor.GLIBC_FLOOR)} floor:\n{report}"
        )


def _live() -> None:
    # Read a real ELF with the real objdump, so the parser is checked against
    # the tool's actual output format and not only the sample above.
    if shutil.which("objdump") is None:
        print("SKIP live objdump check: objdump is not installed")
        return
    exe = Path(sys.executable).resolve()
    reqs = floor.read_glibc_requirements(exe)
    assert reqs, f"objdump -p {exe} yielded no GLIBC_ version references"


def main() -> int:
    _live_relr()
    _cases()
    _bundle_checks()
    _live()
    print("OK: all Linux glibc-floor check tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
