#!/usr/bin/env python3
"""Offline tests for ``check_flutter_version.py`` -- the .fvmrc-vs-toolchain guard.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_flutter_version.py

The guard is one regex and one comparison, and neither had a test. What is
worth pinning is the parse of the ``flutter --version`` banner -- the input CI
actually feeds it, since ``_checks.yml`` runs the guard with no argument right
after ``subosito/flutter-action`` -- plus the bare-string form the optional
argument accepts, and the three exit codes (match, mismatch, unparseable).
Nothing here runs ``flutter``: every case supplies the version text itself.
"""

from __future__ import annotations

import contextlib
import io
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_flutter_version as guard  # noqa: E402

FAILURES: list[str] = []

# A real `flutter --version` banner (stable channel). The Dart and DevTools
# versions on the last line are the decoys: a parse that takes the LAST
# dotted triple, or any triple, would report Dart's version as Flutter's.
BANNER = (
    "Flutter 3.47.0 • channel stable • https://github.com/flutter/flutter.git\n"
    "Framework • revision 0123456789 (3 weeks ago) • 2026-09-01 10:00:00 -0700\n"
    "Engine • revision abcdef0123 (3 weeks ago) • 2026-09-01 08:00:00 -0700\n"
    "Tools • Dart 3.11.0 • DevTools 2.50.1\n"
)


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def parsed(raw: str) -> str | None:
    match = guard._FLUTTER_VERSION_RE.search(raw)
    return match.group("v") if match else None


def exit_code(argv: list[str]) -> int:
    """Run ``main`` and return its exit code, whether returned or raised.

    ``_fail`` prints a ``::error::`` annotation and calls ``sys.exit``; the
    output is captured so a red case does not read as a real annotation.
    """
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            return guard.main(argv)
        except SystemExit as stop:
            return int(stop.code or 0)


def test_banner_parsing() -> None:
    print("version parsing:")
    check("the flutter --version banner yields the Flutter version", parsed(BANNER) == "3.47.0", repr(parsed(BANNER)))
    check(
        "not the Dart or DevTools version further down the banner",
        parsed(BANNER) not in ("3.11.0", "2.50.1"),
    )
    check("a bare version string parses", parsed("3.47.0") == "3.47.0")
    check("surrounding whitespace is tolerated", parsed("  3.47.0\n") == "3.47.0")
    check(
        "a pre-release build reports its semver core",
        parsed("Flutter 3.48.0-0.1.pre • channel beta") == "3.48.0",
        "pinned so a change here is deliberate: .fvmrc pins the core triple",
    )
    check("no version at all is a non-match", parsed("Flutter (unknown)") is None)
    check(
        "a two-part number is not a version",
        parsed("Flutter 3.47 • channel stable") is None,
    )


def test_installed_version_argument() -> None:
    print("the optional argument:")
    check(
        "an explicit argument is used verbatim (trimmed) and flutter is not run",
        guard._installed_version(["check", " 3.47.0 "]) == "3.47.0",
    )
    check(
        "an explicit banner argument is parsed like flutter's own output",
        guard._installed_version(["check", BANNER]) == "3.47.0",
    )
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            guard._installed_version(["check", "not a version"])
    except SystemExit as stop:
        check("an unparseable argument exits 2", stop.code == 2, repr(stop.code))
    else:
        check("an unparseable argument exits 2", False, "returned instead of exiting")


def test_verdict_exit_codes() -> None:
    print("exit codes against the real .fvmrc:")
    pinned = guard._pinned_version()
    check("the pin itself is a full version", parsed(pinned) == pinned, repr(pinned))
    check("matching toolchain exits 0", exit_code(["check", pinned]) == 0)
    check(
        "matching banner exits 0",
        exit_code(["check", f"Flutter {pinned} • channel stable\nTools • Dart 3.11.0"]) == 0,
    )
    major, minor, patch = pinned.split(".")
    other = f"{major}.{minor}.{int(patch) + 1}"
    check("a different patch version exits 1", exit_code(["check", other]) == 1)
    check("an unparseable toolchain string exits 2", exit_code(["check", "garbage"]) == 2)


def main() -> int:
    test_banner_parsing()
    test_installed_version_argument()
    test_verdict_exit_codes()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all check_flutter_version tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
