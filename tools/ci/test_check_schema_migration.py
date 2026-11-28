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


def build_repo(repo: Path, *, tag: bool = True) -> Path:
    """A base commit at schema 9, after a release tagged at schema 8 unless
    [tag] is false. The gate refuses to run without a release tag, so every
    scenario that is not about tags has one. The tag ships 8, below every
    retired (v9) artefact below, so the released-version check never refuses
    those first and the floor cases still test the floor check."""
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "gate@example.invalid")
    git(repo, "config", "user.name", "gate")
    write(repo, DB_PATH, database_source(8))
    write(repo, MIGRATION_TEST, "// migration tests\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "release")
    if tag:
        git(repo, "tag", "-a", "v0.1.0-beta", "-m", "release")
    write(repo, DB_PATH, database_source(9))
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    return repo


def scenario(
    changes: dict[str, str], *, tag: bool = True
) -> subprocess.CompletedProcess:
    """Commits `changes` on top of a fresh base repo and runs the gate."""
    with tempfile.TemporaryDirectory() as tmp_name:
        repo = build_repo(Path(tmp_name), tag=tag)
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


# --------------------------------------------------------------------------
# A released version's dump and schema class are frozen (audit H-07).
# --------------------------------------------------------------------------

RELEASED = 12
RELEASED_DUMP = (
    "packages/compendium_core/drift_schemas/generated/drift_schema_v12.json"
)
RELEASED_SCHEMA = "packages/compendium_core/test/storage/generated/schema_v12.dart"
VNEXT_DUMP = (
    "packages/compendium_core/drift_schemas/generated/drift_schema_v13.json"
)
DUMP = '{"version": "1.2.0", "entities": [{"id": 0, "name": "dances"}]}\n'


def test_released_versions() -> None:
    print("released schema versions:")
    # The tag ships schema 12 and main is already at vNext 13, so v12's dump
    # and schema class are what users' databases were stamped with.
    vnext = {RELEASED_DUMP: DUMP, RELEASED_SCHEMA: "// v12\n", VNEXT_DUMP: DUMP}

    def released_at_12(changes: dict[str, str]) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp_name:
            repo = Path(tmp_name)
            git(repo, "init", "-q", "-b", "main")
            git(repo, "config", "user.email", "gate@example.invalid")
            git(repo, "config", "user.name", "gate")
            write(repo, DB_PATH, database_source(RELEASED))
            write(repo, MIGRATION_TEST, "// migration tests\n")
            git(repo, "add", "-A")
            git(repo, "commit", "-q", "-m", "release")
            git(repo, "tag", "-a", "v0.1.0-beta", "-m", "release")
            write(repo, DB_PATH, database_source(13))
            for relative, contents in vnext.items():
                write(repo, relative, contents)
            git(repo, "add", "-A")
            git(repo, "commit", "-q", "-m", "vNext")
            for relative, contents in changes.items():
                write(repo, relative, contents)
            git(repo, "add", "-A")
            git(repo, "commit", "-q", "-m", "change")
            return run_gate(repo)

    result = released_at_12(
        {RELEASED_DUMP: DUMP.replace('"dances"', '"dances", "x": 1')}
    )
    check(
        "an edit to a released dump fails",
        result.returncode == 1,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )
    check(
        "the failure names the released path and the tag",
        "drift_schema_v12.json" in result.stdout and "v0.1.0-beta" in result.stdout,
        result.stdout + result.stderr,
    )

    result = released_at_12({RELEASED_SCHEMA: "// v12, edited\n"})
    check(
        "an edit to a released schema class fails",
        result.returncode == 1,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )

    regenerated = (
        '{\n  "entities": [\n    {"name": "dances", "id": 0}\n  ],\n'
        '  "version": "1.2.0"\n}\n'
    )
    result = released_at_12({RELEASED_DUMP: regenerated})
    check(
        "a released dump regenerated to equal JSON passes",
        result.returncode == 0,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )

    result = released_at_12(
        {VNEXT_DUMP: DUMP.replace('"dances"', '"dances", "x": 1')}
    )
    check(
        "an edit to the unreleased vNext dump passes",
        result.returncode == 0,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )

    result = released_at_12(
        {"packages/compendium_core/drift_schemas/generated/drift_schema_v11.json": DUMP}
    )
    check(
        "a new dump for a released version fails",
        result.returncode == 1,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )

    result = released_at_12({RELEASED_DUMP: "not json\n"})
    check(
        "a released dump that no longer parses fails",
        result.returncode == 1,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )


def test_release_tag_required() -> None:
    print("release tag:")
    result = scenario({MIGRATION_TEST: "// edited\n"}, tag=False)
    check(
        "no release tag exits 2",
        result.returncode == 2,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )
    check(
        "the failure says to fetch tags",
        "fetch" in (result.stdout + result.stderr).lower(),
        result.stdout + result.stderr,
    )

    # A tag whose database.dart yields no schema version must not read as
    # "nothing released", which would let every released dump change.
    with tempfile.TemporaryDirectory() as tmp_name:
        repo = Path(tmp_name)
        git(repo, "init", "-q", "-b", "main")
        git(repo, "config", "user.email", "gate@example.invalid")
        git(repo, "config", "user.name", "gate")
        write(repo, DB_PATH, "// no schemaVersion here\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "release")
        git(repo, "tag", "-a", "v0.1.0-beta", "-m", "release")
        write(repo, DB_PATH, database_source(13))
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "base")
        write(repo, MIGRATION_TEST, "// edited\n")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "change")
        result = run_gate(repo)
    check(
        "an unreadable release tag exits 2",
        result.returncode == 2,
        f"exit={result.returncode}: {result.stdout + result.stderr}",
    )


def main() -> int:
    test_accepted()
    test_rejected()
    test_floor()
    test_unknown_refs()
    test_released_versions()
    test_release_tag_required()
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
