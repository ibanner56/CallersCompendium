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
FIXTURE = "packages/compendium_core/test/storage/fixtures/v12.sqlite"
SCHEMA_DUMP = (
    "packages/compendium_core/drift_schemas/generated/drift_schema_v12.json"
)
FLOOR = 11
RETIRED_FIXTURE = "packages/compendium_core/test/storage/fixtures/v9.sqlite"
RETIRED_GENERATOR = (
    "packages/compendium_core/test/storage/fixtures/generate_v9_fixture.dart"
)
RETIRED_DUMP = (
    "packages/compendium_core/drift_schemas/generated/drift_schema_v9.json"
)
# Deliberately the pre-move flat path: the gate's evidence prefix and its
# version regex are both depth-agnostic, and a stray dump at the old location
# must still be rejected rather than slipping through unrecognised.
RETIRED_DUMP_FLAT = (
    "packages/compendium_core/drift_schemas/drift_schema_v9.json"
)
RETIRED_SCHEMA = "packages/compendium_core/test/storage/generated/schema_v9.dart"

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
        f"const int kMinSupportedSchemaVersion = {FLOOR};\n"
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
        {DB_PATH: database_source(24), MIGRATION_TEST: "// covers v24\n"}
    )
    check(
        "bump with a migration test passes",
        result.returncode == 0,
        result.stdout + result.stderr,
    )

    result = scenario({DB_PATH: database_source(24), FIXTURE: "fake sqlite\n"})
    check(
        "bump with a fixture passes",
        result.returncode == 0,
        result.stdout + result.stderr,
    )

    result = scenario({DB_PATH: database_source(24), SCHEMA_DUMP: "{}\n"})
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

    result = scenario({DB_PATH: database_source(24)})
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
            DB_PATH: database_source(24) + "// plus an onUpgrade step\n",
        }
    )
    check(
        "editing database.dart alone is not evidence",
        result.returncode == 1,
        f"exit={result.returncode}",
    )


# --------------------------------------------------------------------------
# Retired versions must not come back (#828 schema floor).
# --------------------------------------------------------------------------


def test_floor() -> None:
    print("retired schema versions:")

    for label, path in (
        ("fixture", RETIRED_FIXTURE),
        ("generator", RETIRED_GENERATOR),
        ("schema dump", RETIRED_DUMP),
        ("schema dump at the pre-move flat path", RETIRED_DUMP_FLAT),
        ("generated schema class", RETIRED_SCHEMA),
    ):
        result = scenario({path: "revived\n"})
        check(
            f"a below-floor {label} is rejected",
            result.returncode == 1,
            f"exit={result.returncode}: {result.stdout + result.stderr}",
        )

    # The floor check must not depend on schemaVersion changing: reviving a
    # retired artefact is a defect on its own.
    result = scenario({RETIRED_FIXTURE: "revived\n"})
    check(
        "the floor is enforced even with no schemaVersion change",
        result.returncode == 1,
        f"exit={result.returncode}",
    )
    check(
        "the failure names the offending path",
        "v9.sqlite" in (result.stdout + result.stderr),
        result.stdout + result.stderr,
    )

    # At-floor and above-floor artefacts are exactly what a normal PR touches.
    result = scenario(
        {"packages/compendium_core/test/storage/fixtures/v11.sqlite": "ok\n"}
    )
    check(
        "an at-floor fixture is accepted",
        result.returncode == 0,
        result.stdout + result.stderr,
    )
    result = scenario({FIXTURE: "ok\n"})
    check(
        "an above-floor fixture is accepted",
        result.returncode == 0,
        result.stdout + result.stderr,
    )


# --------------------------------------------------------------------------
# An unresolvable ref must be a hard error, never a silent pass.
# --------------------------------------------------------------------------


def test_unknown_refs() -> None:
    print("unresolvable refs:")

    with tempfile.TemporaryDirectory() as tmp_name:
        repo = build_repo(Path(tmp_name))
        write(repo, DB_PATH, database_source(24))
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "bump with no evidence")

        # A bad base ref must not be mistaken for "the file did not exist
        # there", which would report the gate as not applicable and exit 0 --
        # passing a PR the gate never examined.
        result = run_gate(repo, base="refs/heads/no-such-ref")
        check(
            "an unknown base ref exits 2",
            result.returncode == 2,
            f"exit={result.returncode}: {result.stdout + result.stderr}",
        )
        check(
            "the failure says the ref did not resolve",
            "does not resolve to a commit" in (result.stdout + result.stderr),
            result.stdout + result.stderr,
        )
        check(
            "an unknown base ref is NOT reported as 'not applicable'",
            "not applicable" not in (result.stdout + result.stderr),
            result.stdout + result.stderr,
        )

    # The case the guard actually protects. When no floor constant is present
    # the below-floor check is skipped, so nothing else touches the refs and a
    # bad base ref reaches `_schema_version_at`, which cannot tell "unreadable
    # ref" from "file absent at that ref" -- and the gate reports itself not
    # applicable and exits 0. With a floor present the failure happens to be
    # caught earlier by the below-floor check, which is why this case is tested
    # separately rather than assumed to be covered.
    with tempfile.TemporaryDirectory() as tmp_name:
        repo = build_repo(Path(tmp_name))
        # Same shape as database_source(), minus the floor constant only --
        # the schemaVersion getter must still be present, or the gate would
        # fail earlier for an unrelated reason and the case would pass without
        # exercising the ref guard at all.
        unfloored = (
            "const int kCompendiumSchemaVersion = 24;\n"
            "\n"
            "class CompendiumDatabase {\n"
            "  int get schemaVersion => kCompendiumSchemaVersion;\n"
            "}\n"
        )
        write(repo, DB_PATH, unfloored)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "bump, no floor constant")

        result = run_gate(repo, base="refs/heads/no-such-ref")
        check(
            "with no floor constant, an unknown base ref still exits 2",
            result.returncode == 2,
            f"exit={result.returncode}: {result.stdout + result.stderr}",
        )
        check(
            "with no floor constant, it is not reported as 'not applicable'",
            "not applicable" not in (result.stdout + result.stderr),
            result.stdout + result.stderr,
        )

    with tempfile.TemporaryDirectory() as tmp_name:
        repo = build_repo(Path(tmp_name))
        write(repo, DB_PATH, database_source(24))
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "bump with no evidence")

        # The valid-ref path still works, so the guard is not simply refusing
        # everything.
        result = run_gate(repo)
        check(
            "a valid base ref still reaches the evidence check",
            result.returncode == 1,
            f"exit={result.returncode}: {result.stdout + result.stderr}",
        )


def main() -> int:
    test_accepted()
    test_rejected()
    test_floor()
    test_unknown_refs()
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
