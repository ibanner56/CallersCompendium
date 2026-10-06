#!/usr/bin/env python3
"""Unit tests for the Linux build-runner (glibc floor) guard."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_linux_build_runner as check  # noqa: E402

_MATRIX = """\
    strategy:
      matrix:
        include:
          - platform: linux
            arch: x64
            # a comment inside the entry
            os: {linux}
          - platform: macos
            arch: universal
            os: macos-latest
    runs-on: ${{{{ matrix.os }}}}
"""


def _cases() -> None:
    pinned = _MATRIX.format(linux="ubuntu-22.04")
    assert check.linux_leg_runners(pinned, "platform") == ["ubuntu-22.04"]
    assert check.linux_leg_runners(pinned, "target") == []

    floating = _MATRIX.format(linux="ubuntu-latest")
    assert check.linux_leg_runners(floating, "platform") == ["ubuntu-latest"]

    # An entry without its own `os` must not borrow the next entry's.
    missing = """\
        include:
          - platform: linux
            arch: x64
          - platform: macos
            os: ubuntu-22.04
"""
    assert check.linux_leg_runners(missing, "platform") == [""]

    # Quoted values are read the same as bare ones.
    quoted = """\
          - target: 'linux'
            os: "ubuntu-22.04"
"""
    assert check.linux_leg_runners(quoted, "target") == ["ubuntu-22.04"]


def _mutated_runs_on() -> None:
    # The matrix entry alone proves nothing if the build job does not run on
    # it: with `runs-on` swapped to a fixed label and the entry left intact,
    # the guard must still fail, for each workflow it guards.
    import tempfile

    for rel, _key in check.LEGS:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for other, _ in check.LEGS:
                dest = root / other
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(
                    (check.REPO_ROOT / other).read_text(encoding="utf-8"),
                    encoding="utf-8",
                )
            target = root / rel
            text = target.read_text(encoding="utf-8")
            needle = "    runs-on: ${{ matrix.os }}\n"
            assert text.count(needle) == 1, f"{rel}: expected one matrix runs-on"
            target.write_text(
                text.replace(needle, "    runs-on: ubuntu-latest\n"),
                encoding="utf-8",
            )
            errors = check.check(root)
            assert any(str(rel) in e for e in errors), (
                f"{rel}: runs-on no longer uses matrix.os, but the guard "
                f"passed: {errors}"
            )


def _repo() -> None:
    # The real workflows: this is the assertion that fails if a Linux leg
    # drifts off the floor runner (e.g. back to ubuntu-latest).
    errors = check.check()
    assert errors == [], "\n".join(errors)


def main() -> int:
    _cases()
    _mutated_runs_on()
    _repo()
    print("OK: all Linux build-runner guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
