#!/usr/bin/env python3
"""Guard: the Windows ``CompanyName`` resource stays ``org.callerscompendium``.

``path_provider_windows`` builds every per-app folder from the version
resource in ``app/windows/runner/Runner.rc``: ``%LOCALAPPDATA%\\<CompanyName>\\
<ProductName>`` (the database, via ``getApplicationCacheDirectory``) and
``%APPDATA%\\<CompanyName>\\<ProductName>`` (the legacy Roaming location, the
crash log, shared_preferences). Releases through v0.8.1-beta shipped
``org.callerscompendium``, so changing the string makes the next release open
an empty library for every existing Windows user: the database resolver does
not know any other folder name. ``LegalCopyright`` and the other strings are
free to change; this one is not.

Usage: ``check_windows_company_name.py`` (no arguments). Exit 0 when the pinned
value is present, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER_RC = Path("app/windows/runner/Runner.rc")
PINNED = "org.callerscompendium"

_VALUE = re.compile(r'^\s*VALUE\s+"CompanyName"\s*,\s*"([^"]*)"', re.MULTILINE)


def company_names(text: str) -> list[str]:
    """Every ``CompanyName`` value declared in ``text``, in order."""
    return _VALUE.findall(text)


def check(root: Path = REPO_ROOT) -> list[str]:
    path = root / RUNNER_RC
    if not path.is_file():
        return [f"{RUNNER_RC}: file not found."]
    names = company_names(path.read_text(encoding="utf-8"))
    if names != [PINNED]:
        return [
            f"{RUNNER_RC}: CompanyName is {names!r}, expected [{PINNED!r}]. "
            "path_provider derives %LOCALAPPDATA% and %APPDATA% folders from "
            "it, so changing it moves every Windows data folder and existing "
            "users would open an empty library. Restore the value, or ship a "
            "migration before changing it."
        ]
    return []


def main() -> int:
    errors = check()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print(f"OK: Windows CompanyName is {PINNED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
