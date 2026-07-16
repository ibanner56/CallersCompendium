#!/usr/bin/env python3
"""Single-source guard: pinned Flutter version (.fvmrc) vs the running toolchain.

``.fvmrc`` is the **single source of truth** for the Flutter version. FVM reads
it locally and CI installs from it via ``subosito/flutter-action``'s
``flutter-version-file: .fvmrc`` — so there is deliberately no second version
string to keep in sync. This guard closes the last gap: it asserts the Flutter
SDK actually resolved onto the runner matches the pin, catching a channel
override or an action that silently resolved a different build.

Usage:
    check_flutter_version.py [installed_version]

If ``installed_version`` is omitted, the script runs ``flutter --version`` and
parses it. In CI we pass the version explicitly so the check does not depend on
``flutter`` being on PATH at that step.

Exit codes: 0 = match, 1 = mismatch, 2 = could not parse an input.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FVMRC = REPO_ROOT / ".fvmrc"

# Matches the `flutter --version` banner ("Flutter 3.44.6 • ...") and also a
# bare "3.44.6" string (so CI can pass the version directly).
_FLUTTER_VERSION_RE = re.compile(
    r"(?:Flutter\s+)?\b(?P<v>\d+\.\d+\.\d+)\b"
)


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}")
    sys.exit(code)


def _pinned_version() -> str:
    if not FVMRC.is_file():
        _fail(f"missing file: {FVMRC}")
    try:
        data = json.loads(FVMRC.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _fail(f"{FVMRC} is not valid JSON: {exc}")
    version = data.get("flutter")
    if not isinstance(version, str) or not version.strip():
        _fail(f'{FVMRC} has no string "flutter" field')
    return version.strip()


def _installed_version(argv: list[str]) -> str:
    if len(argv) > 1 and argv[1].strip():
        raw = argv[1].strip()
    else:
        try:
            raw = subprocess.run(
                ["flutter", "--version"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        except (OSError, subprocess.CalledProcessError) as exc:
            _fail(f"could not run `flutter --version`: {exc}")
            raise  # unreachable; keeps type checkers happy
    m = _FLUTTER_VERSION_RE.search(raw)
    if not m:
        _fail(f"could not parse a Flutter version from: {raw!r}")
    return m.group("v")


def main(argv: list[str]) -> int:
    pinned = _pinned_version()
    installed = _installed_version(argv)
    if installed != pinned:
        _fail(
            f"Flutter version mismatch: installed '{installed}' != "
            f"'{pinned}' pinned in .fvmrc (the single source of truth). "
            "The toolchain must match .fvmrc.",
            code=1,
        )
    print(f"OK: Flutter toolchain matches .fvmrc ('{pinned}').")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
