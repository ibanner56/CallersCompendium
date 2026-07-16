#!/usr/bin/env python3
"""Schema-change gate: a schemaVersion bump must ship a migration test/fixture.

``CompendiumDatabase.schemaVersion`` (in
``packages/compendium_core/lib/src/storage/database.dart``) is the on-disk
schema version. The project convention (documented on that class and in
CONTRIBUTING.md) is: every bump ships a ``MigrationStrategy`` step **and** a
test that opens a fixture DB captured at the previous version.

This gate enforces the test/fixture half automatically. Given a base ref, it
compares ``schemaVersion`` at base vs head; if it changed, it requires that the
same diff also added or changed migration evidence:

  * ``packages/compendium_core/test/storage/migration_test.dart``, or
  * any file under ``packages/compendium_core/test/storage/fixtures/``.

If the version changed with no such evidence, CI fails. (It intentionally does
NOT accept a mere edit to database.dart itself as evidence — the point is a
migration *test*.)

Usage:
    check_schema_migration.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD`` (the checked-out commit; for a PR this is the
merge commit, so the diff is the PR's net effect vs its base).

Exit codes: 0 = OK (no bump, or bump with evidence), 1 = bump without evidence,
2 = usage / git error.
"""

from __future__ import annotations

import re
import subprocess
import sys

DB_PATH = "packages/compendium_core/lib/src/storage/database.dart"
MIGRATION_TEST = "packages/compendium_core/test/storage/migration_test.dart"
FIXTURES_DIR = "packages/compendium_core/test/storage/fixtures/"

_SCHEMA_RE = re.compile(r"int\s+get\s+schemaVersion\s*=>\s*(?P<v>\d+)\s*;")


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}")
    sys.exit(code)


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], capture_output=True, text=True
    )


def _schema_version_at(ref: str) -> int | None:
    """Return schemaVersion in DB_PATH at ``ref``, or None if unreadable there."""
    res = _git("show", f"{ref}:{DB_PATH}")
    if res.returncode != 0:
        # File absent at that ref (e.g. brand-new file) — treat as "no prior".
        return None
    m = _SCHEMA_RE.search(res.stdout)
    if not m:
        return None
    return int(m.group("v"))


def _changed_paths(base: str, head: str) -> list[str]:
    """Added/modified/renamed/copied paths in the base..head diff.

    Includes renames/copies (R/C) so that moving a migration test/fixture still
    counts as evidence. For R/C, ``git diff --name-status`` emits three
    tab-separated columns (``R100\told\tnew``); the destination path is always
    the last column, so taking ``parts[-1]`` yields the new path for R/C and the
    sole path for A/M.
    """
    res = _git("diff", "--name-status", "--diff-filter=AMRC", base, head)
    if res.returncode != 0:
        _fail(
            f"git diff {base}..{head} failed: {res.stderr.strip()}. "
            "Ensure full history is fetched (checkout fetch-depth: 0)."
        )
    paths = []
    for line in res.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            paths.append(parts[-1].strip())
    return paths


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        _fail("usage: check_schema_migration.py <base_ref> [head_ref]")
    base = argv[1].strip()
    head = argv[2].strip() if len(argv) > 2 and argv[2].strip() else "HEAD"

    old = _schema_version_at(base)
    new = _schema_version_at(head)

    if new is None:
        _fail(f"could not read schemaVersion from {DB_PATH} at {head}")

    if old is None:
        print(
            f"OK: no schemaVersion at base {base} to compare against "
            f"(new={new}); schema gate not applicable."
        )
        return 0

    if old == new:
        print(f"OK: schemaVersion unchanged ({new}); no migration required.")
        return 0

    changed = _changed_paths(base, head)
    has_evidence = any(
        p == MIGRATION_TEST or p.startswith(FIXTURES_DIR) for p in changed
    )

    if not has_evidence:
        _fail(
            f"schemaVersion changed ({old} -> {new}) but this PR adds/changes "
            "no migration test or fixture. A schema bump must ship a migration "
            f"test ({MIGRATION_TEST}) and/or a fixture under {FIXTURES_DIR} "
            "(see the schema convention on CompendiumDatabase and CONTRIBUTING.md).",
            code=1,
        )

    print(
        f"OK: schemaVersion changed ({old} -> {new}) with migration "
        "test/fixture evidence in the same PR."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
