#!/usr/bin/env python3
"""Offline tests for ``_bash.find_bash`` — the bash the release-tooling tests
drive their shell scripts with.

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``) and fully OFFLINE.  Run directly::

    python3 tools/release/test_bash.py

**Why this file exists.** Every other test in this directory stubs an external
command — ``gh``, ``curl`` — by writing a shim into a temporary directory and
prepending that directory to ``PATH``.  That technique is only as good as the
shell it hands the script to.  Git for Windows ships two: ``Git/usr/bin/bash``
(MSYS, which honours the ``PATH`` it is given) and ``Git/bin/bash`` (a launcher
that rebuilds ``PATH``, putting ``/mingw64/bin`` first and discarding whatever
the caller prepended).  Under the launcher the stubs are silently bypassed and
the real binaries run, so a test that believes it is recording calls instead
makes live network requests — and reports whatever the outside world returned
as if it were a defect in the code under test.

Case 2 is the **primary red run**: it asserts the selected bash actually
resolves a stub off the caller's ``PATH``.  Against the launcher it goes red.

Case 1 is what gives Linux CI any signal at all: CI has no launcher to pick
wrongly, so only a fabricated install tree can exercise the preference there.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _bash import _PROGRAM_DIR_VARS, _git_bash, bash_environ, find_bash  # noqa: E402


def _case_1_prefers_msys_over_the_launcher() -> None:
    """A Git install holding both bashes resolves to the MSYS one."""
    with tempfile.TemporaryDirectory() as directory:
        base = Path(directory)
        launcher = base / "Git" / "bin" / "bash.exe"
        msys = base / "Git" / "usr" / "bin" / "bash.exe"
        for path in (launcher, msys):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("", encoding="utf-8")

        previous = {var: os.environ.get(var) for var in _PROGRAM_DIR_VARS}
        try:
            for var in _PROGRAM_DIR_VARS:
                os.environ.pop(var, None)
            os.environ["ProgramFiles"] = str(base)
            found = _git_bash()
        finally:
            for var, value in previous.items():
                if value is None:
                    os.environ.pop(var, None)
                else:
                    os.environ[var] = value

        assert found == str(msys), (
            f"case 1 expected the MSYS bash at {msys}, got {found!r}. The "
            f"launcher at {launcher} rebuilds PATH for the shell it starts, "
            f"which drops the stub directories every other test in this "
            f"directory prepends."
        )


def _case_2_honours_a_prepended_path_entry() -> None:
    """The selected bash runs a stub the caller put first on ``PATH``.

    This is the property the stubbing in ``test_release_workflow_recovery.py``
    and the ``publish_pages_*`` suites depends on, asserted directly instead of
    as a side effect of those tests passing.
    """
    with tempfile.TemporaryDirectory() as directory:
        stub_dir = Path(directory) / "bin"
        stub_dir.mkdir()
        # Named after a command that really exists, because that is the case
        # that matters: shadowing something absent proves nothing.
        stub = stub_dir / "curl"
        stub.write_text(
            "#!/usr/bin/env bash\nprintf 'stub-ran\n'\n", encoding="utf-8"
        )
        stub.chmod(0o755)

        environment = bash_environ(stub_dir=stub_dir)
        result = subprocess.run(
            [find_bash(), "-c", "curl --stub-probe"],
            cwd=directory,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

        assert result.returncode == 0 and "stub-ran" in result.stdout, (
            f"case 2: {find_bash()!r} did not resolve the stub at {stub}; it "
            f"ran something else, so PATH-based stubbing does not hold. "
            f"rc={result.returncode} out={result.stdout!r} err={result.stderr!r}"
        )


def _case_3_path_wins_off_windows() -> None:
    """Away from Windows, a bash deliberately put on ``PATH`` is still used."""
    if os.name == "nt":
        return
    on_path = shutil.which("bash")
    assert on_path is not None, "case 3 needs bash on PATH"
    assert find_bash() == on_path, (
        f"case 3 expected the PATH bash {on_path!r}, got {find_bash()!r}: the "
        f"Windows-only Git lookup must not take precedence here."
    )


def _case_4_path_order() -> None:
    """`bash_environ` orders PATH stub / bash / caller, and keeps the caller's.

    The behavioural consequences of getting this wrong are Windows-only
    (System32's `find.exe` shadowing GNU find, a shebang that cannot find
    bash), so this asserts the order itself — the only part of the contract a
    Linux CI run can see.
    """
    bash_dir = str(Path(find_bash()).parent)
    environment = bash_environ({"PATH": "/caller/one" + os.pathsep + "/caller/two"},
                               stub_dir="/stubs")
    entries = environment["PATH"].split(os.pathsep)
    assert entries[0] == "/stubs", (
        f"case 4: the stub directory must come first or it shadows nothing; "
        f"got {entries!r}"
    )
    assert entries[1] == bash_dir, (
        f"case 4: bash's own directory must precede the caller's PATH, or "
        f"Windows homographs such as System32's find.exe win; got {entries!r}"
    )
    assert entries[2:] == ["/caller/one", "/caller/two"], (
        f"case 4: the caller's PATH must survive intact, in order; "
        f"got {entries!r}"
    )

    without_stub = bash_environ({"PATH": "/caller/one"})
    assert without_stub["PATH"].split(os.pathsep) == [bash_dir, "/caller/one"], (
        f"case 4: with no stub directory the rest must keep its order; "
        f"got {without_stub['PATH']!r}"
    )


def main() -> int:
    _case_1_prefers_msys_over_the_launcher()
    _case_2_honours_a_prepended_path_entry()
    _case_3_path_wins_off_windows()
    _case_4_path_order()
    print("OK: all find_bash tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
