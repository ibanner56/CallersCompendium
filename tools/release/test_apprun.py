#!/usr/bin/env python3
"""Offline tests for ``packaging/linux/AppRun``, the AppImage entrypoint.

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``). Run directly::

    python3 tools/release/test_apprun.py

**Why this file exists.** ``AppRun`` prepends the bundle's ``lib/`` to
``LD_LIBRARY_PATH``. Written as ``"${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"``
it leaves a trailing ``:`` whenever the variable was unset, which is the normal
case. glibc reads an empty element as the current directory, so a library
planted wherever the user launched the AppImage from (typically
``~/Downloads``) is loaded ahead of the system's copy (CWE-427). Each case
runs the real script against a stub app that prints its environment.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APPRUN = ROOT / "packaging" / "linux" / "AppRun"


def run_apprun(extra_env: dict[str, str], unset: tuple[str, ...] = ()) -> dict[str, str]:
    """Runs AppRun in a scratch AppDir whose app prints its environment."""
    with tempfile.TemporaryDirectory() as tmp:
        appdir = Path(tmp) / "AppDir"
        bindir = appdir / "usr" / "bin"
        (bindir / "lib").mkdir(parents=True)
        shutil.copy(APPRUN, appdir / "AppRun")
        (appdir / "AppRun").chmod(0o755)
        app = bindir / "compendium_app"
        app.write_text("#!/bin/sh\nenv\n", encoding="utf-8")
        app.chmod(0o755)
        env = {k: v for k, v in os.environ.items() if k not in unset}
        env.update(extra_env)
        out = subprocess.run(
            ["/bin/sh", str(appdir / "AppRun")],
            env=env,
            cwd=tmp,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        seen = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
        seen["__APPDIR__"] = str(appdir.resolve())
        return seen


def assert_no_relative_entries(value: str) -> None:
    entries = value.split(":")
    assert all(entries), f"empty (current-directory) entry in {value!r}"
    assert all(e.startswith("/") for e in entries), f"relative entry in {value!r}"


def test_unset_library_path_gets_only_the_bundle_lib() -> None:
    env = run_apprun({}, unset=("LD_LIBRARY_PATH",))
    value = env["LD_LIBRARY_PATH"]
    assert_no_relative_entries(value)
    assert value == f"{env['__APPDIR__']}/usr/bin/lib", value


def test_empty_library_path_gets_only_the_bundle_lib() -> None:
    env = run_apprun({"LD_LIBRARY_PATH": ""})
    assert_no_relative_entries(env["LD_LIBRARY_PATH"])


def test_existing_library_path_is_kept_after_the_bundle_lib() -> None:
    env = run_apprun({"LD_LIBRARY_PATH": "/opt/a:/opt/b"})
    value = env["LD_LIBRARY_PATH"]
    assert_no_relative_entries(value)
    assert value == f"{env['__APPDIR__']}/usr/bin/lib:/opt/a:/opt/b", value


def main() -> int:
    if not Path("/bin/sh").exists():
        print("skip: no /bin/sh")
        return 0
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for test in tests:
        test()
        print(f"ok   {test.__name__}")
    print(f"OK: {len(tests)} test(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
