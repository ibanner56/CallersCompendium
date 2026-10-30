#!/usr/bin/env python3
"""Guard the Windows installer's ``.ccshare`` file association (PLAT-3).

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``). Run directly::

    python3 tools/release/test_windows_file_association.py

**Why this file exists.** Double-clicking a ``.ccshare`` file on Windows opens
it in the app only while the Inno Setup script registers the type: the
extension names a ProgID, the ProgID's ``open`` verb starts the app with the
path quoted as its one argument (``desktopOpenPathFromArgs`` in
``app/lib/src/data/desktop_open_path.dart`` reads it), and
``ChangesAssociations`` tells Explorer to pick the change up. Nothing runs the
installer in CI, so these tests pin the script itself. The portable zip
registers nothing; ``docs/user/installation.md`` says so.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ISS = ROOT / "packaging" / "windows" / "CallersCompendium.iss"
PROG_ID = "CallersCompendium.Share"


def section(name: str) -> list[str]:
    """Non-comment, non-blank lines of the named ``[Section]``."""
    lines: list[str] = []
    inside = False
    for raw in ISS.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            inside = line[1:-1] == name
            continue
        if inside and line and not line.startswith(";"):
            lines.append(line)
    return lines


def registry_entries() -> list[dict[str, str]]:
    """Each ``[Registry]`` line as its ``Key: value`` parameters."""
    entries = []
    for line in section("Registry"):
        params: dict[str, str] = {}
        # Values are quoted with "" as the escaped quote; split on ; outside quotes.
        for part in re.findall(r'(?:[^;"]|"(?:[^"]|"")*")+', line):
            key, _, value = part.strip().partition(":")
            value = value.strip()
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1].replace('""', '"')
            params[key.strip()] = value
        entries.append(params)
    return entries


def entry(subkey: str, value_name: str = "") -> dict[str, str]:
    matches = [
        e
        for e in registry_entries()
        if e.get("Subkey") == subkey and e.get("ValueName", "") == value_name
    ]
    assert len(matches) == 1, (
        f"expected one [Registry] entry for {subkey!r} value {value_name!r}, "
        f"found {len(matches)}"
    )
    return matches[0]


# --------------------------------------------------------------------------


def test_setup_announces_the_association_change() -> None:
    setup = {k.strip(): v.strip() for k, _, v in (l.partition("=") for l in section("Setup"))}
    assert setup.get("ChangesAssociations", "").lower() == "yes", (
        "[Setup] must set ChangesAssociations=yes, or Explorer keeps the old "
        "association until the user signs out"
    )


def test_entries_follow_the_install_scope() -> None:
    for e in registry_entries():
        assert e.get("Root") == "HKA", (
            f"{e.get('Subkey')!r} must use Root: HKA (HKLM for all users, HKCU "
            f"for a per-user install), got {e.get('Root')!r}"
        )


def test_extension_names_the_prog_id() -> None:
    ext = entry(r"Software\Classes\.ccshare")
    assert ext.get("ValueData") == PROG_ID, f"the .ccshare default value must be {PROG_ID!r}"
    assert "uninsdeletevalue" in ext.get("Flags", ""), "uninstall must remove the .ccshare value"
    entry(r"Software\Classes\.ccshare\OpenWithProgids", PROG_ID)


def test_open_verb_passes_the_quoted_path() -> None:
    root = entry(rf"Software\Classes\{PROG_ID}")
    assert "uninsdeletekey" in root.get("Flags", ""), "uninstall must remove the ProgID key"
    command = entry(rf"Software\Classes\{PROG_ID}\shell\open\command")
    assert command.get("ValueData") == '"{app}\\{#MyAppExeName}" "%1"', (
        "the open verb must start the installed exe with the file as one quoted "
        f"argument; got {command.get('ValueData')!r}"
    )


TESTS = [
    test_setup_announces_the_association_change,
    test_entries_follow_the_install_scope,
    test_extension_names_the_prog_id,
    test_open_verb_passes_the_quoted_path,
]


def main() -> int:
    failures = 0
    for test in TESTS:
        try:
            test()
        except AssertionError as error:
            failures += 1
            print(f"FAIL {test.__name__}: {error}")
        else:
            print(f"ok   {test.__name__}")
    if failures:
        print(f"{failures} of {len(TESTS)} Windows file-association test(s) failed")
        return 1
    print(f"OK: {len(TESTS)} Windows file-association tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
