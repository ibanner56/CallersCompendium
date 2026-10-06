#!/usr/bin/env python3
"""Unit tests for the Android JVM unit-test CI step guard."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_android_unit_tests as check  # noqa: E402

_GOOD = """\
jobs:
  build:
    strategy:
      matrix:
        include:
          - target: linux
            os: ubuntu-22.04
          - target: android
            os: ubuntu-latest
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v7
      - name: Build
        working-directory: app
        run: flutter build ${{ matrix.build_args }}
      - name: Android unit tests
        if: matrix.target == 'android'
        working-directory: app/android
        run: ./gradlew :app:testDebugUnitTest
  other:
    runs-on: ubuntu-latest
    steps:
      - run: ./gradlew :app:testDebugUnitTest
"""


def _errors(text: str) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        dest = root / check.WORKFLOW
        dest.parent.mkdir(parents=True)
        dest.write_text(text, encoding="utf-8")
        return check.check(root)


def _cases() -> None:
    assert _errors(_GOOD) == [], _errors(_GOOD)

    # Block-scalar run with the command on a later line still counts.
    block = _GOOD.replace(
        "        run: ./gradlew :app:testDebugUnitTest\n  other:",
        "        run: |\n          ./gradlew --version\n"
        "          ./gradlew :app:testDebugUnitTest\n  other:",
    )
    assert _errors(block) == [], _errors(block)

    # Step missing from build: the copy in another job must not satisfy it.
    missing = _GOOD.replace(
        "      - name: Android unit tests\n"
        "        if: matrix.target == 'android'\n"
        "        working-directory: app/android\n"
        "        run: ./gradlew :app:testDebugUnitTest\n",
        "",
    )
    errors = _errors(missing)
    assert any("never run in CI" in e for e in errors), errors

    # Not conditioned on the Android leg.
    unconditioned = _GOOD.replace("        if: matrix.target == 'android'\n", "")
    assert any("not conditioned" in e for e in _errors(unconditioned))

    # Wrong directory.
    wrong_dir = _GOOD.replace("working-directory: app/android", "working-directory: app")
    assert any("does not run in" in e for e in _errors(wrong_dir))

    # Before the build: no wrapper yet.
    build = (
        "      - name: Build\n"
        "        working-directory: app\n"
        "        run: flutter build ${{ matrix.build_args }}\n"
    )
    gradle = (
        "      - name: Android unit tests\n"
        "        if: matrix.target == 'android'\n"
        "        working-directory: app/android\n"
        "        run: ./gradlew :app:testDebugUnitTest\n"
    )
    assert build + gradle in _GOOD
    reordered = _GOOD.replace(build + gradle, gradle + build)
    assert any("runs before" in e for e in _errors(reordered)), _errors(reordered)

    # No android leg in the matrix.
    no_leg = _GOOD.replace("          - target: android\n            os: ubuntu-latest\n", "")
    assert any("no '- target: android' leg" in e for e in _errors(no_leg))

    # A command mentioned only in a comment does not count.
    commented = missing.replace(
        "    steps:\n", "    steps:\n      # ./gradlew :app:testDebugUnitTest\n", 1
    )
    assert any("never run in CI" in e for e in _errors(commented))


def _repo() -> None:
    # The real workflow: this fails if the step is removed from ci.yml.
    errors = check.check()
    assert errors == [], "\n".join(errors)


def main() -> int:
    _cases()
    _repo()
    print("OK: all Android unit-test CI step guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
