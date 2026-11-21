#!/usr/bin/env python3
"""Guard: the Linux build legs run in the image that sets the glibc floor.

The Linux tar.gz and AppImage are not self-contained: glibc, GTK 3 and the
rest of the desktop stack come from the user's system, and every binary
compiled in CI (the runner executable and the plugin ``.so`` files) may require
any glibc up to the one on the machine that built it. Which one it needs moves
with the code and the toolchain headers: a trivial ``strtol`` call compiled on
Ubuntu 24.04 (glibc 2.39) already needs ``GLIBC_2.38``. Only the build
environment bounds it (post-audit finding platform-3).

So the Linux build legs run inside an ``ubuntu:22.04`` container (glibc 2.35),
and that is the minimum the user guide states (``docs/user/installation.md``).
The glibc comes from the container, not from the runner it is scheduled on, so
the runner can be any current GitHub-hosted Ubuntu: GitHub retiring the
``ubuntu-22.04`` runner image (on 2027-04-17) no longer moves or breaks the
floor. ``ci.yml``'s Linux build leg uses the same image so main's push build
proves the release toolchain still builds before a tag does.

The image is pinned by its multi-arch index digest, like every action in these
workflows is pinned by commit: the ``ubuntu:22.04`` tag is rebuilt in place
(point releases, security rebuilds), and a pinned digest means a release is
built from exactly the base image that CI last built and checked. Bump the
digest in both workflows together; the check below requires them to match.

This walks each workflow's build matrix: it finds the ``include`` entry for
the Linux leg and reads that entry's own ``os`` and ``container`` keys,
stopping at the next entry, so a key belonging to a neighbouring leg is never
read as Linux's. It then checks that the job holding that matrix has
``runs-on: ${{ matrix.os }}`` and ``container: ${{ matrix.container }}`` at
job level (a fixed value there would make the matrix entry decorative), and
that the job runs ``tools/ci/check_linux_glibc_floor.py``, which reads the
built bundle and fails if any binary needs a newer glibc than the floor.

Usage: ``check_linux_build_runner.py`` (no arguments). Exit 0 when every leg
matches, 1 otherwise.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# The container whose glibc is the documented Linux floor, pinned by digest.
# Changing the tag is a support decision: update docs/user/installation.md and
# GLIBC_FLOOR in check_linux_glibc_floor.py in the same PR.
LINUX_BUILD_IMAGE_TAG = "ubuntu:22.04"
_IMAGE_RE = re.compile(r"^" + re.escape(LINUX_BUILD_IMAGE_TAG) + r"@sha256:[0-9a-f]{64}$")

# (workflow path, matrix key naming the leg)
LEGS = (
    (Path(".github/workflows/release.yml"), "platform"),
    (Path(".github/workflows/ci.yml"), "target"),
)

# The step every Linux build job must run on its bundle.
GLIBC_CHECK = "python3 tools/ci/check_linux_glibc_floor.py"

# The only job-level values that put a job on its matrix entry's runner and
# container.
MATRIX_RUNS_ON = "${{ matrix.os }}"
MATRIX_CONTAINER = "${{ matrix.container }}"

_ENTRY_RE = re.compile(r"^(?P<indent>\s*)-\s+(?P<key>[\w-]+):\s*(?P<value>\S+)\s*$")
_JOB_RE = re.compile(r"^  (?P<job>[\w-]+):\s*(?:#.*)?$")


def image_problem(image: str) -> str | None:
    """Why ``image`` is not an acceptable Linux build container, or None."""
    if _IMAGE_RE.match(image):
        return None
    return (
        f"'{image or '(none)'}' is not {LINUX_BUILD_IMAGE_TAG} pinned by digest "
        f"('{LINUX_BUILD_IMAGE_TAG}@sha256:<64 hex>')"
    )


def _linux_entries(lines: list[str], key: str) -> list[tuple[int, int]]:
    """(line index, dash indentation) of every ``- key: linux`` entry."""
    found = []
    for i, line in enumerate(lines):
        entry = _ENTRY_RE.match(line)
        if not entry or entry.group("key") != key:
            continue
        if entry.group("value").strip("'\"") != "linux":
            continue
        found.append((i, len(entry.group("indent"))))
    return found


def linux_leg_values(text: str, key: str, field: str) -> list[str]:
    """Returns ``field`` of every matrix entry whose first key is
    ``key: linux``, in file order. An entry without that field yields ``""``."""
    lines = text.splitlines()
    field_re = re.compile(r"^\s*" + re.escape(field) + r":\s*(?P<value>\S+)\s*$")
    values: list[str] = []
    for i, dash_indent in _linux_entries(lines, key):
        # The entry's own keys sit deeper than its "- "; it ends at the first
        # non-blank, non-comment line at or above the dash's indentation.
        found = ""
        for follow in lines[i + 1 :]:
            stripped = follow.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if len(follow) - len(follow.lstrip()) <= dash_indent:
                break
            match = field_re.match(follow)
            if match:
                found = match.group("value").strip("'\"")
                break
        values.append(found)
    return values


def _job_bodies(text: str, key: str) -> list[list[str]]:
    """For every ``key: linux`` matrix entry, the lines of the job holding it.

    The job is the nearest line above the entry at the two-space indentation
    of a key under ``jobs:``; its body runs until the next non-blank,
    non-comment line at that indentation or shallower."""
    lines = text.splitlines()
    bodies: list[list[str]] = []
    for i, _ in _linux_entries(lines, key):
        body: list[str] = []
        start = next((j for j in range(i - 1, -1, -1) if _JOB_RE.match(lines[j])), None)
        if start is not None:
            for follow in lines[start + 1 :]:
                stripped = follow.strip()
                if stripped and not stripped.startswith("#"):
                    if len(follow) - len(follow.lstrip()) <= 2:
                        break
                body.append(follow)
        bodies.append(body)
    return bodies


def linux_leg_job_values(text: str, key: str, field: str) -> list[str]:
    """For every ``key: linux`` entry, the job-level ``field`` (e.g.
    ``runs-on``, ``container``) of the job holding it, ``""`` when absent.

    Only a key at the job's own level (four spaces) counts, so one inside a
    step or a nested map is never read."""
    field_re = re.compile(r"^    " + re.escape(field) + r":\s*(?P<value>.+?)\s*$")
    values: list[str] = []
    for body in _job_bodies(text, key):
        found = ""
        for line in body:
            match = field_re.match(line)
            if match:
                found = match.group("value").strip("'\"")
                break
        values.append(found)
    return values


def linux_leg_job_runs_glibc_check(text: str, key: str) -> list[bool]:
    """For every ``key: linux`` entry, whether its job runs the glibc check
    (on a line that is not a comment)."""
    return [
        any(GLIBC_CHECK in line and not line.strip().startswith("#") for line in body)
        for body in _job_bodies(text, key)
    ]


def check(root: Path = REPO_ROOT) -> list[str]:
    errors: list[str] = []
    images: dict[str, list[Path]] = {}
    for rel, key in LEGS:
        path = root / rel
        if not path.is_file():
            errors.append(f"{rel}: missing.")
            continue
        text = path.read_text(encoding="utf-8")
        containers = linux_leg_values(text, key, "container")
        if not containers:
            errors.append(f"{rel}: no build matrix entry '- {key}: linux' found.")
        for image in containers:
            problem = image_problem(image)
            if problem:
                errors.append(
                    f"{rel}: the Linux build leg's matrix container is {problem}. "
                    "Its glibc is the minimum the shipped Linux binaries need; "
                    "see docs/user/installation.md before changing it."
                )
            else:
                images.setdefault(image, []).append(rel)
        for runner in linux_leg_values(text, key, "os"):
            if not runner.startswith("ubuntu-"):
                errors.append(
                    f"{rel}: the Linux build leg's os is '{runner or '(none)'}'; "
                    "a container job needs a GitHub-hosted Ubuntu runner."
                )
        for runs_on in linux_leg_job_values(text, key, "runs-on"):
            if runs_on != MATRIX_RUNS_ON:
                errors.append(
                    f"{rel}: the job holding the Linux build leg has "
                    f"runs-on '{runs_on or '(none)'}', not '{MATRIX_RUNS_ON}', "
                    "so the matrix os does not decide where it runs."
                )
        for container in linux_leg_job_values(text, key, "container"):
            if container != MATRIX_CONTAINER:
                errors.append(
                    f"{rel}: the job holding the Linux build leg has "
                    f"container '{container or '(none)'}', not '{MATRIX_CONTAINER}', "
                    f"so the Linux leg does not build inside {LINUX_BUILD_IMAGE_TAG} "
                    "and its glibc floor is the runner's."
                )
        for runs_check in linux_leg_job_runs_glibc_check(text, key):
            if not runs_check:
                errors.append(
                    f"{rel}: the job holding the Linux build leg never runs "
                    f"'{GLIBC_CHECK}', so nothing checks the built bundle "
                    "against the glibc floor."
                )
    if len(images) > 1:
        errors.append(
            "the Linux build legs use different images: "
            + "; ".join(f"{', '.join(map(str, rels))}: {img}" for img, rels in images.items())
            + ". Bump the digest in every workflow together."
        )
    return errors


def main() -> int:
    errors = check()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print(f"OK: Linux build legs run in {LINUX_BUILD_IMAGE_TAG}, pinned by digest")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
