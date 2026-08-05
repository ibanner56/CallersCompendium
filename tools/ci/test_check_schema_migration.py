#!/usr/bin/env python3
"""Offline tests for ``check_schema_migration.py`` — the schema-bump gate.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_schema_migration.py

The gate is only worth having if it fails when a ``schemaVersion`` bump ships no
migration evidence and stays quiet otherwise, so the cases below are split into
exactly those two groups. Each builds a throwaway git repository and drives the
real script end to end, because the parts most likely to break — resolving a
getter that defers to a named constant, and reading ``git diff --name-status``
including renames — only exist in that integration.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_schema_migration.py"

DB_PATH = "packages/compendium_core/lib/src/storage/database.dart"
MIGRATION_TEST = "packages/compendium_core/test/storage/migration_test.dart"
FIXTURE = "packages/compendium_core/test/storage/fixtures/v9.sqlite"
SCHEMA_DUMP = "packages/compendium_core/drift_schemas/drift_schema_v9.json"

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def database_source(version: int) -> str:
    """A minimal `database.dart` in the repo's single-source shape."""
    return (
        f"const int kCompendiumSchemaVersion = {version};\n"
        "\n"
        "class CompendiumDatabase {\n"
        "  int get schemaVersion => kCompendiumSchemaVersion;\n"
        "}\n"
    )


def git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )


def write(repo: Path, relative: str, contents: str) -> None:
    target = repo / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(contents, encoding="utf-8")


def run_gate(repo: Path, base: str = "HEAD~1") -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), base],
        cwd=repo,
        capture_output=True,
        text=True,
    )


def build_repo(repo: Path) -> Path:
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "gate@example.invalid")
    git(repo, "config", "user.name", "gate")
    write(repo, DB_PATH, database_source(9))
    write(repo, MIGRATION_TEST, "// migration tests\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    return repo


def scenario(changes: dict[str, str]) -> subprocess.CompletedProcess:
    """Commits `changes` on top of a fresh base repo and runs the gate."""
    with tempfile.TemporaryDirectory() as tmp_name:
        repo = build_repo(Path(tmp_name))
        for relative, contents in changes.items():
            write(repo, relative, contents)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "change")
        return run_gate(repo)


# --------------------------------------------------------------------------
# Accepted: no bump, or a bump carrying evidence.
# --------------------------------------------------------------------------


def test_accepted() -> None:
    print("accepted changes:")

    result = scenario({MIGRATION_TEST: "// edited, no bump\n"})
    check(
        "no schemaVersion change passes",
        result.returncode == 0,
        result.stdout + result.stderr,
    )

    result = scenario(
        {DB_PATH: database_source(10), MIGRATION_TEST: "// covers v10\n"}
    )
    check(
        "bump with a migration test passes",
        result.returncode == 0,
        result.stdout + result.stderr,
    )

    result = scenario({DB_PATH: database_source(10), FIXTURE: "fake sqlite\n"})
    check(
        "bump with a fixture passes",
        result.returncode == 0,
        result.stdout + result.stderr,
    )

    result = scenario({DB_PATH: database_source(10), SCHEMA_DUMP: "{}\n"})
    check(
        "bump with a drift schema dump passes (#828)",
        result.returncode == 0,
        result.stdout + result.stderr,
    )


# --------------------------------------------------------------------------
# Rejected: a bump with nothing that counts as migration evidence.
# --------------------------------------------------------------------------


def test_rejected() -> None:
    print("rejected changes:")

    result = scenario({DB_PATH: database_source(10)})
    check(
        "bump with no evidence fails",
        result.returncode == 1,
        f"exit={result.returncode}",
    )
    check(
        "the failure names the schema dump directory too",
        "drift_schemas" in (result.stdout + result.stderr),
        result.stdout + result.stderr,
    )

    # Editing database.dart alone is deliberately not evidence: the point of the
    # gate is a migration *test*, not a migration.
    result = scenario(
        {
            DB_PATH: database_source(10) + "// plus an onUpgrade step\n",
        }
    )
    check(
        "editing database.dart alone is not evidence",
        result.returncode == 1,
        f"exit={result.returncode}",
    )


def main() -> int:
    test_accepted()
    test_rejected()
    print()
    if FAILURES:
        for failure in FAILURES:
            print(f"::error::{failure}")
        print(f"{len(FAILURES)} check(s) failed")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
