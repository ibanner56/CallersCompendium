#!/usr/bin/env python3
"""CI ratchet: every raw ``FROM settings WHERE key`` read must filter
``deleted_at IS NULL``.

## Why this invariant matters

``repositories.dart`` performs a deliberate hard DELETE of
``__derived_rebuild_required__`` and justifies that choice in a comment:

    "Every one of those reads does filter ``deleted_at IS NULL`` anyway,
    so a marker can neither be read back as still-set after this clears it
    nor be resurrected by a stale row."

That justification is load-bearing: it is the stated premise of a different
design decision elsewhere in the same file. A future raw read without the
filter would silently falsify it too — the connection exists only in a
comment, ninety lines away. This ratchet makes the invariant mechanical.

Background: issue #885 shipped an unfiltered read. The consequence is a
permanently-skipped repair for a corruption that takes down the Programs and
Collection listings entirely (#429, #466) — and the failure mode presents as
the original corruption bug, not as a missing migration.

## Scope

``app/lib`` and ``packages/*/lib`` (production library code only). Tests,
tools, and example code are excluded.

## Deliberate exception

``repositories.dart`` performs a hard ``DELETE FROM settings WHERE key = ?``
to clear the rebuild marker. That is intentionally a DELETE, not a SELECT.
The detection pattern already requires SELECT, so the DELETE line will not
match. ``_NOTED_EXCEPTIONS`` documents this by name following the
``kUpdateManifestPublicKey`` precedent in AGENTS.md: do not narrow the
detection pattern to suppress a false positive; name the exception instead.

## Multi-line SQL

Two of the five compliant reads put ``AND deleted_at IS NULL`` on the next
source line (Dart adjacent-string concatenation). This script joins
adjacent single-quoted literals before matching so the filter is found
even when it is on a continuation line.

Exit codes: 0 = all compliant, 1 = at least one non-compliant read, 2 = bad
input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# --------------------------------------------------------------------------
# Deliberate exceptions — documented by path, not by narrowing the pattern.
# --------------------------------------------------------------------------

# ``repositories.dart`` contains a hard DELETE of the rebuild marker with no
# ``deleted_at IS NULL`` filter — correct for a DELETE statement. Because
# ``_SELECT_FROM_SETTINGS_RE`` requires SELECT, the DELETE line will not
# match regardless. This entry makes the exception explicit and auditable;
# it does not change behaviour. See AGENTS.md (kUpdateManifestPublicKey
# precedent): name exceptions rather than narrowing detection patterns.
_NOTED_EXCEPTIONS: dict[str, str] = {
    "packages/compendium_core/lib/src/storage/repositories/repositories.dart": (
        "deliberate hard DELETE of the rebuild marker — "
        "absence of deleted_at IS NULL is correct for a DELETE; "
        "SELECT reads in the same file all comply"
    ),
}

# --------------------------------------------------------------------------
# Patterns
# --------------------------------------------------------------------------

# A raw SELECT from the settings table keyed by WHERE key.
# Used against the joined text (which has no newlines within SQL strings)
# so re.DOTALL is not needed and would cause cross-line false positives.
_SELECT_FROM_SETTINGS_RE = re.compile(
    r"\bSELECT\b[^;\n]*\bFROM\s+settings\b[^;\n]*\bWHERE\s+key\b",
    re.IGNORECASE,
)

# The required filter.
_DELETED_AT_FILTER_RE = re.compile(
    r"\bdeleted_at\s+IS\s+NULL\b",
    re.IGNORECASE,
)

# Boundary between adjacent Dart single-quoted string literals:
# closing quote, optional whitespace (including newlines), opening quote.
# re.DOTALL so \s matches newlines.
_ADJACENT_STRINGS_RE = re.compile(r"'(\s*)'", re.DOTALL)


def join_adjacent_strings(text: str) -> str:
    """Join adjacent Dart single-quoted string literals into one logical unit.

    Replaces each ``'<whitespace>'`` boundary (including newlines) with
    ``' '`` so a multi-line SQL string becomes one logical line. Iterates
    until stable to handle three or more consecutive literals.

    The result may have fewer lines than the input (newlines between
    adjacent literals are collapsed). The caller should not assume
    line-count parity with the original text.
    """
    prev = None
    while prev != text:
        prev = text
        text = _ADJACENT_STRINGS_RE.sub(" ", text)
    return text


def dart_library_files(root: Path) -> list[Path]:
    """Every production ``.dart`` file: ``app/lib/**`` and ``packages/*/lib/**``."""
    files: list[Path] = []
    app_lib = root / "app" / "lib"
    if app_lib.is_dir():
        files.extend(sorted(app_lib.rglob("*.dart")))
    packages = root / "packages"
    if packages.is_dir():
        for pkg in sorted(p for p in packages.iterdir() if p.is_dir()):
            lib = pkg / "lib"
            if lib.is_dir():
                files.extend(sorted(lib.rglob("*.dart")))
    return files


def _fail(msg: str, code: int = 2) -> None:
    # ``::error::`` renders as an annotation in the GitHub Actions UI.
    print(f"::error::{msg}")
    sys.exit(code)


def check_file(path: Path, root: Path) -> list[str]:
    """Return violation strings for *path* (empty when all reads are compliant).

    Strategy: join adjacent string literals to handle multi-line SQL, then
    search the joined text for SELECT-FROM-settings-WHERE-key matches. For
    each match, check whether ``AND deleted_at IS NULL`` appears in the same
    SQL statement (before the next ``;``). Line numbers are recovered from the
    original text by finding the matching SELECT occurrence there.

    The deliberate hard DELETE in repositories.dart is inherently excluded
    because ``_SELECT_FROM_SETTINGS_RE`` requires SELECT. ``_NOTED_EXCEPTIONS``
    documents this by name.
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    if "FROM SETTINGS" not in text.upper():
        return []

    rel = str(path.relative_to(root))
    joined = join_adjacent_strings(text)

    # Pre-compute all SELECT positions in the ORIGINAL text so violations can
    # be mapped back to source line numbers. The Nth match in joined corresponds
    # to the Nth match in the original (joining does not reorder or create
    # SELECT tokens).
    orig_matches = list(_SELECT_FROM_SETTINGS_RE.finditer(text))
    orig_lines = text.splitlines()

    violations: list[str] = []
    for idx, m in enumerate(_SELECT_FROM_SETTINGS_RE.finditer(joined)):
        # Restrict the filter check to the string literal that contains the
        # SELECT. Scanning to the next ; is not safe: the phrase
        # "deleted_at IS NULL" can appear in a variable name or argument
        # string in the same Dart statement, causing a false negative (the
        # ratchet says OK when the SQL itself is missing the filter).
        #
        # After join_adjacent_strings the SQL is fully on one logical line
        # within its enclosing quotes. Find the opening quote before the
        # match and the closing quote after it.
        open_q = joined.rfind("'", 0, m.start())
        close_q = joined.find("'", m.end())
        if open_q == -1 or close_q == -1:
            # Cannot determine the string boundary — fail closed so an
            # unparseable construct gets a human looking at it.
            sql_literal = None
        else:
            sql_literal = joined[open_q + 1 : close_q]
        if sql_literal is not None and _DELETED_AT_FILTER_RE.search(sql_literal):
            continue
        # Violation (or unparseable boundary) — find the original line number.
        if idx < len(orig_matches):
            orig_m = orig_matches[idx]
            line_no = text[: orig_m.start()].count("\n") + 1
            orig_line = orig_lines[line_no - 1].strip()
        else:
            line_no = 0
            orig_line = "(unknown)"
        violations.append(f"{rel}:{line_no}: {orig_line}")
    return violations


def main() -> int:
    root = REPO_ROOT
    files = dart_library_files(root)
    if not files:
        _fail(f"no Dart library files found under {root}")

    offenders: list[str] = []
    for path in files:
        offenders.extend(check_file(path, root))

    if offenders:
        for o in offenders:
            print(f"::error::missing deleted_at IS NULL filter: {o}")
        print(
            f"::error::{len(offenders)} raw settings read(s) missing "
            "`AND deleted_at IS NULL`. Every SELECT from settings WHERE key "
            "must filter deleted rows — the hard-delete in repositories.dart "
            "is justified in prose by this invariant (issue #907).",
        )
        return 1

    print(
        f"OK: all raw FROM settings WHERE key reads filter deleted_at IS NULL "
        f"across {len(files)} library file(s).",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
