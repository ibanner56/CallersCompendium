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

It also refuses to let a *retired* schema version come back: any per-version
fixture, generator, dump or schema class below ``kMinSupportedSchemaVersion``
fails the gate, whether or not the version changed in the same PR.

  * ``packages/compendium_core/test/storage/migration_test.dart``,
  * any file under ``packages/compendium_core/test/storage/fixtures/``, or
  * any file under ``packages/compendium_core/drift_schemas/`` — the generated
    drift schema dumps behind ``schema_verification_test.dart`` (issue #828).
    A bump ships a dump for the new version, and that is migration evidence in
    its own right: the verification suite asserts that migrating from every
    recorded version reproduces the freshly created head schema.

If the version changed with no such evidence, CI fails. (It intentionally does
NOT accept a mere edit to database.dart itself as evidence — the point is a
migration *test*.)

Usage:
    check_schema_migration.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD`` (the checked-out commit; for a PR this is the
merge commit, so the diff is the PR's net effect vs its base).

Exit codes: 0 = OK (no bump, or bump with evidence), 1 = bump without evidence,
2 = usage / git error, including a base or head ref that does not resolve to a
commit -- which must never be mistaken for "nothing to check".
"""

from __future__ import annotations

import re
import subprocess
import sys

DB_PATH = "packages/compendium_core/lib/src/storage/database.dart"
MIGRATION_TEST = "packages/compendium_core/test/storage/migration_test.dart"
FIXTURES_DIR = "packages/compendium_core/test/storage/fixtures/"
DRIFT_SCHEMAS_DIR = "packages/compendium_core/drift_schemas/"

EVIDENCE_DIRS = (FIXTURES_DIR, DRIFT_SCHEMAS_DIR)

_GETTER_RE = re.compile(
    r"int\s+get\s+schemaVersion\s*=>\s*(?P<rhs>[A-Za-z_$][\w$]*|\d+)\s*;"
)

# Retired schema versions (issue #828). Anything below the floor has had its
# migration steps, fixture and schema dump deleted, so re-adding one is either a
# mistake or an unnoticed revert -- and a sub-floor fixture is worse than
# useless, because there is no `onUpgrade` path from it to head.
_VERSIONED_ARTEFACT_RE = re.compile(
    r"(?:^|/)(?:generate_)?v(?P<v>\d+)(?:_fixture\.dart|\.sqlite)$"
    r"|(?:^|/)drift_schema_v(?P<d>\d+)\.json$"
    r"|(?:^|/)schema_v(?P<s>\d+)\.dart$"
)


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}")
    sys.exit(code)


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], capture_output=True, text=True
    )


def _require_commit(ref: str) -> None:
    """Exit non-zero unless ``ref`` resolves to a commit.

    Without this, a base ref that does not exist -- a typo, or a shallow fetch
    that never pulled the PR base -- makes ``git show <ref>:<path>`` fail, which
    :func:`_schema_version_at` cannot distinguish from "the file did not exist
    at that ref". The gate would then report "schema gate not applicable" and
    exit 0, silently passing a PR it never examined. A gate that passes because
    it could not look is worse than no gate, so an unresolvable ref is a hard
    usage error.
    """
    res = _git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if res.returncode != 0 or not res.stdout.strip():
        _fail(
            f"ref {ref!r} does not resolve to a commit. Ensure full history is "
            "fetched (checkout fetch-depth: 0) and that the ref is correct; "
            "refusing to run the schema gate against an unknown ref.",
        )


def _artefact_version(path: str) -> int | None:
    """Schema version a per-version artefact path belongs to, if any."""
    m = _VERSIONED_ARTEFACT_RE.search(path)
    if not m:
        return None
    raw = m.group("v") or m.group("d") or m.group("s")
    return int(raw) if raw else None


def _below_floor(paths: list[str], floor: int) -> list[str]:
    """Added/changed per-version artefacts for retired schema versions."""
    return sorted(
        p for p in paths
        if (v := _artefact_version(p)) is not None and v < floor
    )


def _const_int(source: str, name: str) -> int | None:
    """Resolve a top-level ``const int <name> = <digits>;`` in ``source``."""
    m = re.search(
        r"const\s+int\s+" + re.escape(name) + r"\s*=\s*(?P<v>\d+)\s*;", source
    )
    return int(m.group("v")) if m else None


def _schema_version_at(ref: str) -> int | None:
    """Return schemaVersion in DB_PATH at ``ref``, or None if unreadable there."""
    res = _git("show", f"{ref}:{DB_PATH}")
    if res.returncode != 0:
        # File absent at that ref (e.g. brand-new file) — treat as "no prior".
        return None
    m = _GETTER_RE.search(res.stdout)
    if not m:
        return None
    rhs = m.group("rhs")
    if rhs.isdigit():
        # Getter returns a numeric literal directly: `=> 9;`.
        return int(rhs)
    # Single-source pattern: the getter defers to a named constant
    # (`=> kCompendiumSchemaVersion;`), so resolve that constant's value from
    # the same file (`const int kCompendiumSchemaVersion = 9;`).
    return _const_int(res.stdout, rhs)


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

    # Both refs must resolve before anything reads from them; see
    # _require_commit for why an unresolvable ref cannot be allowed to look
    # like an absent file.
    _require_commit(base)
    _require_commit(head)

    old = _schema_version_at(base)
    new = _schema_version_at(head)

    # Floor check runs regardless of whether schemaVersion changed: a sub-floor
    # fixture or dump can be reintroduced by a PR that touches no version at all
    # (a bad merge, a revert, a copied file), and it would be dead weight at
    # best and a misleading migration start point at worst.
    head_source = _git("show", f"{head}:{DB_PATH}").stdout
    floor = _const_int(head_source, "kMinSupportedSchemaVersion")
    if floor is not None:
        changed_now = _changed_paths(base, head)
        revived = _below_floor(changed_now, floor)
        if revived:
            _fail(
                "this PR adds or changes per-version artefacts for retired "
                f"schema versions (below kMinSupportedSchemaVersion={floor}): "
                + ", ".join(revived)
                + ". Versions below the floor have no migration path to head "
                "(see the schema floor on CompendiumDatabase); delete them or "
                "raise the floor deliberately.",
                code=1,
            )

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
        p == MIGRATION_TEST or p.startswith(EVIDENCE_DIRS) for p in changed
    )

    if not has_evidence:
        _fail(
            f"schemaVersion changed ({old} -> {new}) but this PR adds/changes "
            "no migration test, fixture or schema dump. A schema bump must "
            f"ship a migration test ({MIGRATION_TEST}), a fixture under "
            f"{FIXTURES_DIR}, and/or a drift schema dump under "
            f"{DRIFT_SCHEMAS_DIR} (see the schema convention on "
            "CompendiumDatabase and CONTRIBUTING.md).",
            code=1,
        )

    print(
        f"OK: schemaVersion changed ({old} -> {new}) with migration "
        "test/fixture/schema-dump evidence in the same PR."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
