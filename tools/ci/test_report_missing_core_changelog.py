#!/usr/bin/env python3
"""Offline tests for ``report_missing_core_changelog.py`` -- the core-changelog advisory.

Pure-stdlib, assert-based, run directly::

    python3 tools/ci/test_report_missing_core_changelog.py

Each case builds a throwaway git repository with a base commit and a head
commit, and drives the real script. Two groups: the advisory must print for a
core library change that ships no ``core`` record, and must stay silent for every
exempt diff shape. A third group pins the property that makes it a report and
not a gate: it exits 0 no matter what, and says ``unavailable`` when it cannot
tell instead of guessing.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "report_missing_core_changelog.py"

CORE_FILE = "packages/compendium_core/lib/src/codec.dart"
OTHER_CORE_FILE = "packages/compendium_core/lib/src/other.dart"
# The advisory's own line; the "unavailable" notice shares the annotation prefix, so
# that prefix alone cannot tell the two apart.
ADVISORY = "Advisory: "

FAILURES: list[str] = []
TEMP_DIRS: list[tempfile.TemporaryDirectory] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


class Repo:
    def __init__(self, root: Path) -> None:
        self.root = root
        self._git("init", "-q", ".")
        self._git("config", "user.email", "t@example.invalid")
        self._git("config", "user.name", "test")
        self.write(CORE_FILE, "// v1\n")
        self.write(OTHER_CORE_FILE, "// v1\n")
        self.write("app/lib/src/screen.dart", "// v1\n")
        self.write("changelog.d/README.md", "# fragments\n")
        self.commit("base")

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True, text=True, check=False)

    def write(self, path: str, text: str) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def remove(self, path: str) -> None:
        (self.root / path).unlink()

    def commit(self, message: str) -> None:
        self._git("add", "-A")
        self._git("commit", "-q", "--allow-empty", "-m", message)

    def run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            cwd=self.root, capture_output=True, text=True, check=False,
        )


def fragment(**records: object) -> str:
    return json.dumps({"id": "1-x", "user_visible": True, **records})


def scenario(name: str, change) -> tuple[subprocess.CompletedProcess, Repo]:
    """Build a base, apply ``change`` and commit it as head; run the report over HEAD~1..HEAD."""
    tmp = tempfile.TemporaryDirectory()
    TEMP_DIRS.append(tmp)  # keep the directory alive for the caller, cleaned up in main()
    repo = Repo(Path(tmp.name))
    change(repo)
    repo.commit("head")
    print(f"{name}:")
    return repo.run("HEAD~1", "HEAD"), repo




def advises(res: subprocess.CompletedProcess) -> bool:
    return ADVISORY in res.stdout


def main() -> int:
    # ---- the advisory must PRINT -------------------------------------------

    res, _ = scenario("core lib change, no fragment", lambda r: r.write(CORE_FILE, "// v2\n"))
    check("prints the advisory", advises(res), res.stdout)
    check("exits 0", res.returncode == 0, f"exit={res.returncode}")
    check("names the changed file", CORE_FILE in res.stdout, res.stdout)
    check("does not name an untouched core file", OTHER_CORE_FILE not in res.stdout, res.stdout)

    def two_files(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write(OTHER_CORE_FILE, "// v2\n")
        r.write("packages/compendium_core/lib/src/new.dart", "// new\n")

    res, _ = scenario("several core lib files changed", two_files)
    check("names every changed file, added ones included", all(
        p in res.stdout for p in (CORE_FILE, OTHER_CORE_FILE, "packages/compendium_core/lib/src/new.dart")
    ), res.stdout)
    check("counts them", "3 file(s)" in res.stdout, res.stdout)

    def many(r: Repo) -> None:
        for i in range(20):
            r.write(f"packages/compendium_core/lib/src/gen{i:02}.dart", "// x\n")

    res, _ = scenario("more files than are listed", many)
    check("summarises the rest", "... and 5 more" in res.stdout and "20 file(s)" in res.stdout, res.stdout)

    def app_record_only(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", fragment(app={"fixed": ["A bug is fixed."]}))

    res, _ = scenario("core lib change with an app-only fragment", app_record_only)
    check("still advises: an app record is not a core record", advises(res), res.stdout)

    def empty_core(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", fragment(app={"fixed": ["x"]}, core={"fixed": []}))

    res, _ = scenario("core lib change with an empty core record", empty_core)
    check("still advises: an empty core record records nothing", advises(res), res.stdout)

    # A fragment that existed at base and is not touched by the PR is not "in the diff".
    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.write("changelog.d/1-x.json", fragment(core={"fixed": ["x"]}))
        repo.commit("a fragment already pending on main")
        repo.write(CORE_FILE, "// v2\n")
        repo.commit("head")
        print("core lib change; the core fragment was already on the base:")
        res = repo.run("HEAD~1", "HEAD")
        check("advises: only fragments the PR adds or modifies count", advises(res), res.stdout)

    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        repo.write("changelog.d/1-x.json", fragment(core={"fixed": ["x"]}))
        repo.commit("a fragment already pending on main")
        repo.write(CORE_FILE, "// v2\n")
        repo.remove("changelog.d/1-x.json")
        repo.commit("head")
        print("core lib change that deletes the only core fragment:")
        res = repo.run("HEAD~1", "HEAD")
        check("advises: a deleted fragment is no record", advises(res), res.stdout)

    # ---- more shapes that must PRINT ---------------------------------------

    res, _ = scenario(
        "core lib path with spaces and non-ASCII characters",
        lambda r: r.write("packages/compendium_core/lib/src/odd name é.dart", "// x\n"),
    )
    check("names the path intact", "odd name é.dart" in res.stdout and advises(res), res.stdout)

    def blank_core_entry(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", fragment(core={"fixed": ["  "]}))

    res, _ = scenario("core lib change with a blank core entry", blank_core_entry)
    check("still advises: a blank entry records nothing", advises(res), res.stdout)

    def type_change(r: Repo) -> None:
        r.remove(CORE_FILE)
        (r.root / CORE_FILE).symlink_to("other.dart")

    try:
        res, _ = scenario("core lib file replaced by a symlink (git status T)", type_change)
    except OSError:
        print("  skip symlinks unavailable here")
    else:
        check("advises: a type change is a change", advises(res), res.stdout)

    # ---- the advisory must stay SILENT -------------------------------------

    def with_core_record(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", fragment(core={"fixed": ["Fix the codec."]}))

    res, _ = scenario("core lib change with a core fragment", with_core_record)
    check("silent", not advises(res) and res.stdout == "", res.stdout)
    check("exits 0", res.returncode == 0)

    def internal_core_record(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", fragment(user_visible=False, core={"changed": ["Rework internals."]}))

    res, _ = scenario("core lib change with a user_visible:false core fragment", internal_core_record)
    check("silent: user_visible false still counts as a core record", res.stdout == "", res.stdout)

    def both_records(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", fragment(app={"fixed": ["x"]}, core={"fixed": ["y"]}))

    res, _ = scenario("core lib change with app and core records", both_records)
    check("silent", res.stdout == "", res.stdout)

    def fragment_modified(r: Repo) -> None:
        r.write("changelog.d/1-x.json", fragment(core={"fixed": ["x"]}))
        r.commit("fragment on main")
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", fragment(core={"fixed": ["x", "more"]}))

    res, _ = scenario("core lib change that modifies an existing core fragment", fragment_modified)
    check("silent: a modified fragment is in the diff", res.stdout == "", res.stdout)

    res, _ = scenario(
        "core test-only change",
        lambda r: r.write("packages/compendium_core/test/codec_test.dart", "// test\n"),
    )
    check("silent", res.stdout == "", res.stdout)

    res, _ = scenario("docs-only change", lambda r: r.write("docs/design/sync-spec.md", "# doc\n"))
    check("silent", res.stdout == "", res.stdout)

    def tooling_only(r: Repo) -> None:
        r.write("tools/ci/check_x.py", "# tool\n")
        r.write(".github/workflows/ci.yml", "name: x\n")

    res, _ = scenario("CI/tooling-only change", tooling_only)
    check("silent", res.stdout == "", res.stdout)

    res, _ = scenario("app library change only", lambda r: r.write("app/lib/src/screen.dart", "// v2\n"))
    check("silent: scoped to the core library", res.stdout == "", res.stdout)

    res, _ = scenario("core pubspec change only", lambda r: r.write("packages/compendium_core/pubspec.yaml", "name: x\n"))
    check("silent: not under lib/", res.stdout == "", res.stdout)

    res, _ = scenario("deleted-only core lib change", lambda r: r.remove(CORE_FILE))
    check("silent", res.stdout == "", res.stdout)

    def rename_out(r: Repo) -> None:
        r.write("packages/compendium_core/test/moved.dart", "// v1\n")
        r.remove(CORE_FILE)

    res, _ = scenario("core lib file moved out of lib/", rename_out)
    check("silent", res.stdout == "", res.stdout)

    res, _ = scenario("a non-fragment json in changelog.d does not count", lambda r: (
        r.write(CORE_FILE, "// v2\n"),
        r.write("changelog.d/sub/1-x.json", fragment(core={"fixed": ["x"]})),
    ))
    check("advises: only fragments directly in changelog.d count", advises(res), res.stdout)

    # ---- it is a report: it never fails and never guesses -------------------

    def malformed(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", "{ not json")

    res, _ = scenario("a malformed fragment in the diff", malformed)
    check("exits 0", res.returncode == 0, f"exit={res.returncode}")
    check("says unavailable and names the file", "unavailable" in res.stdout and "1-x.json" in res.stdout, res.stdout)
    check("does not advise on a guess", not advises(res), res.stdout)

    def not_object(r: Repo) -> None:
        r.write(CORE_FILE, "// v2\n")
        r.write("changelog.d/1-x.json", "[1, 2]")

    res, _ = scenario("a fragment that is not a JSON object", not_object)
    check("exits 0 and says unavailable", res.returncode == 0 and "unavailable" in res.stdout, res.stdout)

    # A malformed fragment is irrelevant when no core lib file changed: nothing to report.
    res, _ = scenario("a malformed fragment but no core lib change", lambda r: r.write("changelog.d/1-x.json", "{ not json"))
    check("silent, exits 0", res.returncode == 0 and res.stdout == "", res.stdout)

    with tempfile.TemporaryDirectory() as tmp:
        repo = Repo(Path(tmp))
        print("unresolvable base ref:")
        res = repo.run("no-such-ref", "HEAD")
        check("exits 0", res.returncode == 0, f"exit={res.returncode}")
        check("says unavailable", "unavailable" in res.stdout, res.stdout)
        print("usage errors:")
        for args in ((), ("HEAD", ""), ("", "HEAD"), ("a", "b", "c")):
            res = repo.run(*args)
            check(f"{args!r} exits 0 and says unavailable", res.returncode == 0 and "unavailable" in res.stdout, f"exit={res.returncode} {res.stdout}")

    with tempfile.TemporaryDirectory() as tmp:
        print("not a git repository:")
        res = subprocess.run([sys.executable, str(SCRIPT), "main"], cwd=tmp, capture_output=True, text=True, check=False)
        check("exits 0 and says unavailable", res.returncode == 0 and "unavailable" in res.stdout, f"exit={res.returncode} {res.stdout}{res.stderr}")

    for tmp in TEMP_DIRS:
        tmp.cleanup()
    if FAILURES:
        print(f"\n{len(FAILURES)} FAILED:")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
