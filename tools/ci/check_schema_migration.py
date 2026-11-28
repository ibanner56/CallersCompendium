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

It also refuses to let a *retired* schema version come back: any per-version
fixture, generator, dump or schema class below ``kMinSupportedSchemaVersion``
fails the gate, whether or not the version changed in the same PR.

And it refuses a change to a *released* version (audit H-07). A drift schema
dump or a generated schema class for a version at or below the newest ``v*``
release tag's ``kCompendiumSchemaVersion`` describes databases users already
have: they are stamped with that number, so ``onUpgrade`` never re-runs its
step, and an "amend vNext" edit made after the tag silently breaks every
upgraded install. Two rules come from the maintainer's decision of 2026-11-28:
such a dump may change only to semantically equal JSON (``json.loads`` equal:
a regeneration that reformats it or reorders object keys; reordering a list,
such as ``entities``, is a change), and with no release tag fetched the gate
exits 2, like ``check_version_bump_policy.py``. A third is this check's own
reading of that decision, not the maintainer's: a released schema *class* may
not change at all, because it is generated from its dump, so a correct
regeneration of a released version leaves it byte-identical (see "Regenerating"
in ``drift_schemas/README.md``). Also this check's own: a tag whose
``database.dart`` yields no schema version exits 2, so an unreadable tag is
never read as "nothing released" (every release tag has the constant).

What it does not see: an edit to the ``if (from < N)`` step in
``database.dart`` itself; and a deleted released dump, which
``schema_verification_test.dart`` (dumps exactly floor..head) catches instead,
since retiring a version deletes its dumps legitimately. A released dump or
schema class *moved* to another path is refused at its new path even when
unchanged: the gate compares each path with the same path at base, not with a
rename's source. Moving released files is rare enough to leave to the
maintainer.

Usage:
    check_schema_migration.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD`` (the checked-out commit; for a PR this is the
merge commit, so the diff is the PR's net effect vs its base).

Exit codes: 0 = OK (no bump, or bump with evidence), 1 = bump without evidence,
a revived retired version or an edit to a released one, 2 = usage / git error,
including a base or head ref that does not resolve to a commit or no release
tag -- which must never be mistaken for "nothing to check".
"""

from __future__ import annotations

import json
import re
import subprocess
import sys

from check_version_bump_policy import latest_release_tag

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


def _released_edits(
    paths: list[str], base: str, head: str, released: int
) -> list[str]:
    """Changed dumps and schema classes of versions at or below [released].

    A dump whose JSON at [head] equals its JSON at [base] is a regeneration
    and is let through; one that is new, or no longer parses, is not.
    """
    refused = []
    for p in sorted(paths):
        m = _VERSIONED_ARTEFACT_RE.search(p)
        if not m or not (m.group("d") or m.group("s")):
            continue  # fixtures and generators are not the released schema
        if int(m.group("d") or m.group("s")) > released:
            continue
        if m.group("d") and _same_json(p, base, head):
            continue
        refused.append(p)
    return refused


def _same_json(path: str, base: str, head: str) -> bool:
    before = _git("show", f"{base}:{path}")
    after = _git("show", f"{head}:{path}")
    if before.returncode != 0 or after.returncode != 0:
        return False
    try:
        return json.loads(before.stdout) == json.loads(after.stdout)
    except ValueError:
        return False


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

    # Released versions are frozen whatever else the PR does (audit H-07).
    tag = latest_release_tag()
    if tag is None:
        _fail(
            "no v* release tag found. Fetch tags (checkout fetch-depth: 0, or "
            "`git fetch --tags`); without one the gate cannot tell a released "
            "schema version from the unreleased vNext.",
        )
    released = _schema_version_at(tag)
    if released is None:
        _fail(
            f"could not read schemaVersion from {DB_PATH} at release tag {tag}; "
            "refusing to treat it as shipping no schema.",
        )
    edited = _released_edits(_changed_paths(base, head), base, head, released)
    if edited:
        _fail(
            f"this PR changes the schema of a released version: release tag "
            f"{tag} ships schema {released}, which these belong to: "
            + ", ".join(edited)
            + ". Databases are already stamped with that number, so onUpgrade "
            "will never re-run its step: bump the schema instead "
            "(CONTRIBUTING.md, \"Adding to an unreleased version\"). If the PR "
            "only moves the file, keep it at its released path. A dump "
            "may change only to semantically equal JSON and a schema class not "
            "at all; a regeneration that changes either is wrong for a "
            "released version, so revert those files (drift_schemas/README.md, "
            "\"Regenerating\").",
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
    evidence = sorted(
        p for p in changed if p == MIGRATION_TEST or p.startswith(EVIDENCE_DIRS)
    )

    if not evidence:
        _fail(
            f"schemaVersion changed ({old} -> {new}) but this PR adds/changes "
            "no migration test, fixture or schema dump. A schema bump must "
            f"ship a migration test ({MIGRATION_TEST}), a fixture under "
            f"{FIXTURES_DIR}, and/or a drift schema dump under "
            f"{DRIFT_SCHEMAS_DIR} (see the schema convention on "
            "CompendiumDatabase and CONTRIBUTING.md).",
            code=1,
        )

    # Say what was checked, not more. This gate asks whether SOME path under
    # the evidence roots changed -- a whitespace edit to an old dump satisfies
    # it -- not whether the change belongs to the new version. The per-version
    # guarantee is the core suite's schema_verification_test.dart ("cover
    # exactly the supported versions, floor to head"), which runs on every
    # bump PR because a bump edits database.dart and so sets core_tests_changed.
    print(
        f"OK: schemaVersion changed ({old} -> {new}) and the PR touches "
        f"{len(evidence)} migration-evidence path(s): {', '.join(evidence)}. "
        f"(Checked: some test/fixture/dump path changed. Not checked here: "
        f"that it belongs to v{new} -- schema_verification_test.dart asserts "
        "the dump range floor..head in the core suite.)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
