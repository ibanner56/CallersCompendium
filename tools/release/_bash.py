"""Locate bash for the release-tooling tests that drive shell scripts."""

import os
import shutil
from collections.abc import Mapping
from pathlib import Path

# Ordered by preference, and the order is load-bearing: MSYS bash
# (`Git/usr/bin/bash.exe`) must win over the Git launcher (`Git/bin/bash.exe`).
#
# The launcher rebuilds PATH for the shell it starts, putting `/mingw64/bin`
# first and dropping any directory the caller prepended. The tests in this
# directory stub `gh` and `curl` by writing shims into a temp directory and
# prepending it to PATH, so under the launcher those stubs are silently
# bypassed and the real binaries run — a test that believes it is asserting on
# recorded calls instead makes live network requests and fails on whatever the
# outside world happens to return.
_GIT_BASH_RELATIVE = (
    "Git/usr/bin/bash.exe",
    "Programs/Git/usr/bin/bash.exe",
    "Git/bin/bash.exe",
    "Programs/Git/bin/bash.exe",
)

_PROGRAM_DIR_VARS = ("ProgramFiles", "ProgramFiles(x86)", "LocalAppData")


def _git_bash() -> str | None:
    """The most preferred bash inside a Git for Windows install, if any."""
    for relative in _GIT_BASH_RELATIVE:
        for var in _PROGRAM_DIR_VARS:
            base = os.environ.get(var)
            if not base:
                continue
            candidate = Path(base) / relative
            if candidate.exists():
                return str(candidate)
    return None


def find_bash() -> str:
    """Returns a bash executable, including Git for Windows' copy.

    Windows shells such as PowerShell often don't have Git's `usr\bin` on PATH,
    so a bare "bash" fails with FileNotFoundError even though Git is installed.

    On Windows the Git install is searched *before* PATH. PATH is not a
    reliable signal there: the Git installer's "use Git from the command line"
    option puts the `Git/bin` launcher on it, and `C:/Windows/System32/bash.exe`
    is the WSL entry point, which runs in a different filesystem namespace
    entirely. Either one is found by `which` and neither can see the temp
    directories these tests hand it. Elsewhere PATH is authoritative and is
    consulted first, so a deliberately chosen bash still wins.
    """
    searches = (_git_bash, lambda: shutil.which("bash"))
    if os.name != "nt":
        searches = tuple(reversed(searches))
    for search in searches:
        found = search()
        if found:
            return found
    raise FileNotFoundError(
        "bash not found; install Git for Windows or add bash to PATH"
    )


def bash_environ(
    environment: Mapping[str, str] | None = None,
    stub_dir: "str | os.PathLike[str] | None" = None,
) -> dict[str, str]:
    """A child environment for [find_bash] whose PATH actually works.

    PATH becomes `stub_dir` (when given), then the selected bash's own
    directory, then the caller's PATH. Each position is load-bearing:

    - `stub_dir` is **first** so a test's shim shadows the real command. That
      is the whole point of the stub, so nothing may come before it.
    - The bash directory comes **next**, ahead of the caller's PATH, for two
      reasons. The shells' own utilities have to be reachable at all: the
      scripts call `dirname`, `basename` and `find`, and the shims start with
      `#!/usr/bin/env bash`, every one of them resolved against the PATH the
      shell is *given* rather than against the shell's own location. On
      Windows the parent is often PowerShell, whose PATH holds no Git
      `usr/bin`, so omitting it fails with `dirname: command not found` or
      `env: 'bash': No such file or directory`. And it has to beat the
      caller's PATH, because Windows ships unrelated programs under the same
      names — `C:/Windows/System32/find.exe` is not GNU find, and with
      System32 first `publish_pages_site.sh`'s prune silently does nothing
      and leaves stale assets behind.
    - The caller's PATH comes last, still intact, for `git` and anything else
      the environment legitimately provides.

    The launcher at `Git/bin/bash.exe` papers over all of this by rebuilding
    PATH itself — and takes the stub directory with it, which is exactly why
    it must not be used. See _GIT_BASH_RELATIVE.
    """
    result = dict(os.environ if environment is None else environment)
    entries = [
        str(stub_dir) if stub_dir is not None else "",
        str(Path(find_bash()).parent),
        result.get("PATH", ""),
    ]
    result["PATH"] = os.pathsep.join(entry for entry in entries if entry)
    return result
