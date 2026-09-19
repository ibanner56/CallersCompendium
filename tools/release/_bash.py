"""Locate bash for the release-tooling tests that drive shell scripts."""

import os
import shutil
from pathlib import Path

_GIT_BASH_RELATIVE = (
    "Git/bin/bash.exe",
    "Git/usr/bin/bash.exe",
    "Programs/Git/bin/bash.exe",
)


def find_bash() -> str:
    """Returns a bash executable, including Git for Windows' copy.

    Windows shells such as PowerShell often don't have Git's `usr\bin` on PATH,
    so a bare "bash" fails with FileNotFoundError even though Git is installed.
    """
    found = shutil.which("bash")
    if found:
        return found
    for var in ("ProgramFiles", "ProgramFiles(x86)", "LocalAppData"):
        base = os.environ.get(var)
        if not base:
            continue
        for relative in _GIT_BASH_RELATIVE:
            candidate = Path(base) / relative
            if candidate.exists():
                return str(candidate)
    raise FileNotFoundError(
        "bash not found; install Git for Windows or add bash to PATH"
    )
