#!/usr/bin/env python3
"""Unit tests for the Linux bundle glibc-floor check."""

from __future__ import annotations

import shutil
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
    refs = floor.glibc_refs(_OBJDUMP)
    # GLIBCXX and GCC are not glibc; the definitions block is not a reference.
    assert refs == [(2, 2, 5), (2, 34), (2, 4)], refs
    # Numeric, not lexical: 2.4 < 2.34 < 2.35, and 2.2.5 is the oldest.
    assert max(refs) == (2, 34)
    assert floor.parse_version("2.35") == (2, 35)
    assert (2, 36) > floor.GLIBC_FLOOR >= (2, 35)
    assert floor.version_str((2, 2, 5)) == "2.2.5"


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
            "compendium_app": [(2, 34), (2, 2, 5)],
            "libok.so": [(2, 14)],
            "libnoglibc.so": [],
        }

        def reader(path: Path) -> list[tuple[int, ...]]:
            return table[path.name]

        errors, report = floor.check_bundle(bundle, reader)
        assert errors == [], errors
        assert "GLIBC_2.34" in report and "compendium_app" in report, report

        # A single library above the floor fails the whole bundle, by name.
        table["libok.so"] = [(2, 38)]
        errors, _ = floor.check_bundle(bundle, reader)
        assert len(errors) == 1 and "libok.so" in errors[0] and "2.38" in errors[0], errors

        # Exactly at the floor passes.
        table["libok.so"] = [floor.GLIBC_FLOOR]
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


def _live() -> None:
    # Read a real ELF with the real objdump, so the parser is checked against
    # the tool's actual output format and not only the sample above.
    if shutil.which("objdump") is None:
        print("SKIP live objdump check: objdump is not installed")
        return
    exe = Path(sys.executable).resolve()
    refs = floor.read_glibc_refs(exe)
    assert refs, f"objdump -p {exe} yielded no GLIBC_ version references"


def main() -> int:
    _cases()
    _bundle_checks()
    _live()
    print("OK: all Linux glibc-floor check tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
