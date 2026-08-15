#!/usr/bin/env python3
"""Version-history gate: a version bump must append its entry to the design doc.

``contraTaxonomyVersion`` and ``kCompendiumSchemaVersion`` each carry an
append-only per-version log. Those logs used to live as doc comments on the
declarations themselves, where they had grown to 40.7 KiB and 19.4 KiB -- read
in full by every session that opened either file, to reach a one-line constant.
They now live in ``docs/design/figure-taxonomy.md`` and
``docs/design/storage.md``, which is where the code already pointed for both
subjects.

Relocating a log creates exactly one new failure mode: a future bump appends its
entry nowhere, and the history silently stops recording. A rule an agent must
remember costs prompt tokens every turn and fails silently when forgotten, so
this is a gate instead: if a constant moved between base and head, the matching
doc must gain an entry *for that specific version*.

Checking that the doc merely changed would not do. The realistic mistake is not
"forgot the doc" but "bumped to v29 while editing the v28 entry", which a
file-level check passes and this one fails: the entry must name the new value.

Usage:
    check_version_history.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD``. Exit codes: 0 = OK (no bump, or bump with a
matching entry), 1 = bump without an entry, 2 = usage / git error, including a
base or head ref that does not resolve to a commit -- which must never be
mistaken for "nothing to check".
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass

TAXONOMY_SOURCE = "packages/compendium_core/lib/src/taxonomy/contra_taxonomy.dart"
TAXONOMY_DOC = "docs/design/figure-taxonomy.md"
TAXONOMY_HEADING = "## Taxonomy version history"

SCHEMA_SOURCE = "packages/compendium_core/lib/src/storage/database.dart"
SCHEMA_DOC = "docs/design/storage.md"
SCHEMA_HEADING = "## Schema version history"


@dataclass(frozen=True)
class Ledger:
    """One constant and the document section that must log its versions."""

    constant: str
    source: str
    doc: str
    heading: str


LEDGERS = (
    Ledger("contraTaxonomyVersion", TAXONOMY_SOURCE, TAXONOMY_DOC, TAXONOMY_HEADING),
    Ledger("kCompendiumSchemaVersion", SCHEMA_SOURCE, SCHEMA_DOC, SCHEMA_HEADING),
)


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}")
    sys.exit(code)


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], capture_output=True, text=True)


def _require_commit(ref: str) -> None:
    """Exit non-zero unless ``ref`` resolves to a commit.

    ``git show <ref>:<path>`` fails identically for "bad ref" and "file absent
    at that ref", and the second is a legitimate no-op for this gate. Without
    this check a typo or a shallow fetch would make the gate report success
    without having examined anything, which is worse than not running it.
    """
    res = _git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if res.returncode != 0 or not res.stdout.strip():
        _fail(
            f"ref {ref!r} does not resolve to a commit. Ensure full history is "
            "fetched (checkout fetch-depth: 0) and that the ref is correct; "
            "refusing to run the version-history gate against an unknown ref."
        )


def _const_int(source: str, name: str) -> int | None:
    """Resolve a top-level ``const int <name> = <digits>;`` in ``source``."""
    match = re.search(
        r"const\s+int\s+" + re.escape(name) + r"\s*=\s*(?P<value>\d+)\s*;", source
    )
    return int(match.group("value")) if match else None


def _version_at(ref: str, path: str, constant: str) -> int | None:
    """The constant's value at ``ref``, or None if the file is absent there."""
    res = _git("show", f"{ref}:{path}")
    if res.returncode != 0:
        return None
    return _const_int(res.stdout, constant)


def _section(text: str, heading: str) -> str | None:
    """The body under ``heading``, up to the next heading of the same level.

    Sub-headings are part of the section: the schema log splits its entries into
    retired and supported subsections, and an entry under either one counts.
    """
    level = len(heading) - len(heading.lstrip("#"))
    lines = text.splitlines()
    for start, line in enumerate(lines):
        if line.strip() != heading:
            continue
        body: list[str] = []
        for candidate in lines[start + 1 :]:
            if re.match(rf"^#{{1,{level}}} \S", candidate):
                break
            body.append(candidate)
        return "\n".join(body)
    return None


def _has_entry(section: str, version: int) -> bool:
    """Whether the section carries a list entry for exactly ``version``.

    Anchored on the bullet so that a mention inside another entry's prose ("see
    v24") is not mistaken for the entry itself, and bounded on the right by a
    non-digit so that v2 does not match v20.
    """
    return re.search(rf"^\s*[-*] v{version}(?!\d)", section, re.MULTILINE) is not None


def _check(ledger: Ledger, base: str, head: str) -> int:
    old = _version_at(base, ledger.source, ledger.constant)
    new = _version_at(head, ledger.source, ledger.constant)

    if new is None:
        _fail(f"could not read {ledger.constant} from {ledger.source} at {head}")
    if old is None:
        print(
            f"OK: no {ledger.constant} at base {base} to compare against "
            f"(new={new}); not applicable."
        )
        return 0
    if old == new:
        print(f"OK: {ledger.constant} unchanged ({new}).")
        return 0

    doc = _git("show", f"{head}:{ledger.doc}")
    if doc.returncode != 0:
        _fail(
            f"{ledger.constant} changed ({old} -> {new}) but {ledger.doc}, "
            "which holds its version history, does not exist at "
            f"{head}.",
            code=1,
        )
    section = _section(doc.stdout, ledger.heading)
    if section is None:
        _fail(
            f"{ledger.constant} changed ({old} -> {new}) but {ledger.doc} has "
            f"no {ledger.heading!r} section to record it in. That section is "
            "where the per-version log lives; restore it rather than logging "
            "the bump somewhere else.",
            code=1,
        )
    if not _has_entry(section, new):
        _fail(
            f"{ledger.constant} changed ({old} -> {new}) but "
            f"{ledger.doc} has no '- v{new}' entry under {ledger.heading!r}. "
            "Every bump appends its entry in the same PR, saying what changed "
            "and whether anything must be rebuilt or migrated.",
            code=1,
        )
    print(f"OK: {ledger.constant} {old} -> {new}, logged in {ledger.doc}.")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2 or not argv[1].strip():
        _fail("usage: check_version_history.py <base_ref> [head_ref]")
    base = argv[1].strip()
    head = argv[2].strip() if len(argv) > 2 and argv[2].strip() else "HEAD"

    _require_commit(base)
    _require_commit(head)

    for ledger in LEDGERS:
        _check(ledger, base, head)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
