#!/usr/bin/env python3
"""Unit tests for the Linux build-environment (glibc floor) guard."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_linux_build_runner as check  # noqa: E402

_DIGEST = "ubuntu:22.04@sha256:" + "a" * 64

_MATRIX = """\
    strategy:
      matrix:
        include:
          - platform: linux
            arch: x64
            # a comment inside the entry
            os: ubuntu-latest
            container: {linux}
          - platform: macos
            arch: universal
            os: macos-latest
    runs-on: ${{{{ matrix.os }}}}
    container: ${{{{ matrix.container }}}}
"""


def _cases() -> None:
    pinned = _MATRIX.format(linux=_DIGEST)
    assert check.linux_leg_values(pinned, "platform", "container") == [_DIGEST]
    assert check.linux_leg_values(pinned, "platform", "os") == ["ubuntu-latest"]
    assert check.linux_leg_values(pinned, "target", "container") == []

    # The image must be ubuntu:22.04 pinned by an index digest.
    assert check.image_problem(_DIGEST) is None
    assert check.image_problem("ubuntu:22.04") is not None
    assert check.image_problem("ubuntu:24.04@sha256:" + "a" * 64) is not None
    assert check.image_problem("ubuntu:22.04@sha256:" + "a" * 63) is not None
    assert check.image_problem("") is not None

    # An entry without its own `container` must not borrow the next entry's.
    missing = """\
        include:
          - platform: linux
            os: ubuntu-latest
          - platform: macos
            container: ubuntu:22.04
"""
    assert check.linux_leg_values(missing, "platform", "container") == [""]

    # Job-level keys of the job holding the Linux entry; a key of the same
    # name inside a step or in another job is never read.
    job = (
        "jobs:\n"
        "  build:\n"
        "    strategy:\n"
        "      matrix:\n"
        "        include:\n"
        "          - platform: linux\n"
        "            os: ubuntu-latest\n"
        "    runs-on: {runs_on}\n"
        "{container}"
        "    steps:\n"
        "      - container: decoy\n"
        "        run: python3 tools/ci/check_linux_glibc_floor.py bundle\n"
        "  other:\n"
        "    runs-on: windows-latest\n"
        "    container: decoy\n"
    )
    full = job.format(
        runs_on="${{ matrix.os }}", container="    container: ${{ matrix.container }}\n"
    )
    assert check.linux_leg_job_values(full, "platform", "runs-on") == ["${{ matrix.os }}"]
    assert check.linux_leg_job_values(full, "platform", "container") == [
        "${{ matrix.container }}"
    ]
    assert check.linux_leg_job_runs_glibc_check(full, "platform") == [True]
    no_container = job.format(runs_on="${{ matrix.os }}", container="")
    assert check.linux_leg_job_values(no_container, "platform", "container") == [""]

    # Quoted values are read the same as bare ones.
    quoted = f"""\
          - target: 'linux'
            container: "{_DIGEST}"
"""
    assert check.linux_leg_values(quoted, "target", "container") == [_DIGEST]


def _copy_workflows(root: Path) -> None:
    for rel, _ in check.LEGS:
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text((check.REPO_ROOT / rel).read_text(encoding="utf-8"), encoding="utf-8")


def _mutation_caught(rel: Path, needle: str, replacement: str, why: str) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _copy_workflows(root)
        target = root / rel
        text = target.read_text(encoding="utf-8")
        assert text.count(needle) == 1, f"{rel}: expected exactly one {needle!r}"
        target.write_text(text.replace(needle, replacement), encoding="utf-8")
        errors = check.check(root)
        assert any(str(rel) in e for e in errors), (
            f"{rel}: {why}, but the guard passed: {errors}"
        )


def _mutations() -> None:
    # Each mutation is a way the Linux leg could stop building inside
    # ubuntu:22.04 while the rest of the file still looks right. The guard
    # must fail for each one, in each workflow it guards.
    for rel, key in check.LEGS:
        _mutation_caught(
            rel,
            "    container: ${{ matrix.container }}\n",
            "",
            "the job no longer runs in the matrix container",
        )
        _mutation_caught(
            rel,
            "    runs-on: ${{ matrix.os }}\n",
            "    runs-on: ubuntu-latest\n",
            "runs-on no longer uses matrix.os",
        )
        text = (check.REPO_ROOT / rel).read_text(encoding="utf-8")
        images = check.linux_leg_values(text, key, "container")
        assert len(images) == 1 and images[0], f"{rel}: no Linux container to mutate"
        _mutation_caught(
            rel,
            images[0],
            "ubuntu:24.04",
            "the Linux container is no longer ubuntu:22.04 pinned by digest",
        )
        _mutation_caught(
            rel,
            "python3 tools/ci/check_linux_glibc_floor.py",
            "echo skipped",
            "the glibc floor check no longer runs on the Linux bundle",
        )


def _repo() -> None:
    # The real workflows: this is the assertion that fails if a Linux leg
    # drifts out of the ubuntu:22.04 container.
    errors = check.check()
    assert errors == [], "\n".join(errors)


def main() -> int:
    _cases()
    _mutations()
    _repo()
    print("OK: all Linux build-environment guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
