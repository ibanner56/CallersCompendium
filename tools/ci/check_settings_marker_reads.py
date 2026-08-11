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
adjacent single-quoted and double-quoted literals before matching so the
filter is found even when it is on a continuation line.

## Filter scoping

The filter check is restricted to the SQL string literal that contains the
SELECT, not the surrounding Dart statement. Checking the full statement is
not safe: the phrase "deleted_at IS NULL" can appear as a Dart variable
value or argument in the same statement while the SQL itself is unfiltered.
The enclosing literal is found by detecting the opening quote character
(single or double) and scanning for the matching close. On an unparseable
boundary (e.g. raw or triple-quoted literal), the check fails closed so
an unparseable construct gets a human looking at it.

## Line-number mapping

Adjacent-string joining may merge tokens that are on different source lines
(e.g. ``SELECT … FROM settings`` on line N, ``WHERE key`` on line N+1).
The joined text has a match that has no counterpart in the un-joined text,
so a simple count-based index into ``orig_matches`` would fall off the end
and produce a useless ``:0: (unknown)`` location. Instead, ``join_adjacent_strings``
returns both the joined text and a per-character offset map
(``orig_at[joined_offset] = original_offset``) so every joined-text position
can be translated back to the exact original byte — and therefore to the
correct line number — regardless of how the literals were split.

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
_SELECT_FROM_SETTINGS_RE = re.compile(
    r"\bSELECT\b[^;\n]*\bFROM\s+settings\b[^;\n]*\bWHERE\s+key\b",
    re.IGNORECASE,
)

# The required filter.
_DELETED_AT_FILTER_RE = re.compile(
    r"\bdeleted_at\s+IS\s+NULL\b",
    re.IGNORECASE,
)

# Boundaries between adjacent Dart string literals of the same quote style.
# re.DOTALL so \s matches newlines.
_ADJACENT_SINGLE_RE = re.compile(r"'(\s*)'", re.DOTALL)
_ADJACENT_DOUBLE_RE = re.compile(r'"(\s*)"', re.DOTALL)

# --------------------------------------------------------------------------
# Violation kinds
# --------------------------------------------------------------------------

# Sentinel: violation kinds returned by check_file.
_MISSING_FILTER = "missing_filter"
_BOUNDARY_UNKNOWN = "boundary_unknown"


# --------------------------------------------------------------------------
# String joining with offset map
# --------------------------------------------------------------------------


def join_adjacent_strings(text: str) -> tuple[str, list[int]]:
    """Join adjacent Dart string literals and return an offset map.

    Returns ``(joined, orig_at)`` where:

    * *joined* is the text with adjacent single-quoted and double-quoted
      literal boundaries (``' '``, ``" "``) collapsed to a single space,
      so a multi-line SQL string becomes one logical line.
    * *orig_at* is a list of the same length as *joined* where
      ``orig_at[i]`` is the offset in *text* of the character that ended
      up at position *i* in *joined*.

    The offset map is used by ``check_file`` to translate a match position
    in the joined text back to the correct original source line, even when
    the SELECT and WHERE key tokens were in different source lines before
    joining. A count-based index into ``orig_matches`` would fall off the
    end in that case (the un-joined text has no match spanning two literals)
    and produce a useless ``:0: (unknown)`` location.
    """
    # Work on character lists so we can maintain a parallel orig_at list.
    result: list[str] = list(text)
    orig_at: list[int] = list(range(len(text)))

    changed = True
    while changed:
        changed = False
        joined_str = "".join(result)
        for pat in (_ADJACENT_SINGLE_RE, _ADJACENT_DOUBLE_RE):
            m = pat.search(joined_str)
            if m is None:
                continue
            # Replace the closing-quote / whitespace / opening-quote span
            # with a single space. The space maps to the original position
            # of the closing quote (m.start()).
            result = result[: m.start()] + [" "] + result[m.end() :]
            orig_at = orig_at[: m.start()] + [orig_at[m.start()]] + orig_at[m.end() :]
            changed = True
            break  # restart scan after each substitution

    return "".join(result), orig_at


# --------------------------------------------------------------------------
# Enclosing literal detection
# --------------------------------------------------------------------------


def _enclosing_sql_literal(text: str, match_start: int, match_end: int) -> str | None:
    """Return the content of the Dart string literal enclosing the match.

    Scans backward from *match_start* to find the opening quote (``'`` or
    ``"``), then forward from *match_end* to find the matching closing quote.
    Returns the string content between the quotes, or ``None`` when the
    boundary cannot be determined (triple-quoted, raw-string prefix, or no
    enclosing quote found).

    Returning ``None`` signals the caller to **fail closed** — an
    unrecognised construct is safer to flag for human review than to silently
    pass.
    """
    # Scan backward to find the opening quote character.
    i = match_start - 1
    while i >= 0 and text[i] not in ("'", '"', "\n", ";"):
        i -= 1
    if i < 0 or text[i] not in ("'", '"'):
        return None
    q = text[i]

    # Guard: triple-quoted or raw-string prefix → boundary unparseable.
    if (i >= 2 and text[i - 2 : i + 1] == q * 3) or (
        i >= 1 and text[i - 1] in ("r", "R")
    ):
        return None

    # Find the closing quote (same character) after the match.
    close = text.find(q, match_end)
    if close == -1:
        return None
    return text[i + 1 : close]


# --------------------------------------------------------------------------
# File discovery
# --------------------------------------------------------------------------


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


# --------------------------------------------------------------------------
# Per-file check
# --------------------------------------------------------------------------


def check_file(path: Path, root: Path) -> list[tuple[str, str]]:
    """Return ``(kind, location)`` pairs for every violation in *path*.

    *kind* is one of ``_MISSING_FILTER`` or ``_BOUNDARY_UNKNOWN``:

    * ``_MISSING_FILTER``: the SQL string was parsed and the filter is absent.
    * ``_BOUNDARY_UNKNOWN``: the enclosing literal boundary could not be
      determined (raw or triple-quoted string). The check **fails closed** so
      the read gets human review; the error message names the cause rather than
      claiming the filter is missing (it may be present — we simply cannot
      verify the boundary).

    Returns an empty list when all reads comply or the file has no relevant
    content.

    Line numbers are recovered via the offset map returned by
    ``join_adjacent_strings``, so a SELECT that spans two adjacent literals
    (e.g. ``'SELECT … FROM settings '`` on one line, ``'WHERE key'`` on the
    next) still produces a real file:line location rather than ``:0: (unknown)``.

    The deliberate hard DELETE in repositories.dart is inherently excluded
    because ``_SELECT_FROM_SETTINGS_RE`` requires SELECT. ``_NOTED_EXCEPTIONS``
    documents this by name.
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    if "FROM SETTINGS" not in text.upper():
        return []

    rel = str(path.relative_to(root))
    joined, orig_at = join_adjacent_strings(text)
    orig_lines = text.splitlines()

    violations: list[tuple[str, str]] = []
    for m in _SELECT_FROM_SETTINGS_RE.finditer(joined):
        # Translate the match's start position in the joined text back to the
        # original source offset via the offset map, then derive the line number.
        orig_offset = orig_at[m.start()] if m.start() < len(orig_at) else 0
        line_no = text[:orig_offset].count("\n") + 1
        orig_line = orig_lines[line_no - 1].strip() if line_no <= len(orig_lines) else "(unknown)"

        # Before checking the joined text, detect raw (r'…') and triple-quoted
        # ('''…''' or """…""") forms in the *original* source. join_adjacent_strings
        # collapses '''…''' into a plain single-quoted literal, so
        # _enclosing_sql_literal would not see the triple-quote prefix.
        orig_m_start = orig_offset
        orig_m_end = orig_at[m.end() - 1] + 1 if (m.end() - 1) < len(orig_at) else orig_offset + 1
        orig_boundary = _enclosing_sql_literal(text, orig_m_start, orig_m_end)
        if orig_boundary is None:
            violations.append((_BOUNDARY_UNKNOWN, f"{rel}:{line_no}: {orig_line}"))
            continue

        sql_literal = _enclosing_sql_literal(joined, m.start(), m.end())
        if sql_literal is not None and _DELETED_AT_FILTER_RE.search(sql_literal):
            continue
        kind = _BOUNDARY_UNKNOWN if sql_literal is None else _MISSING_FILTER
        violations.append((kind, f"{rel}:{line_no}: {orig_line}"))
    return violations


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------


def main() -> int:
    root = REPO_ROOT
    files = dart_library_files(root)
    if not files:
        _fail(f"no Dart library files found under {root}")

    offenders: list[tuple[str, str]] = []
    for path in files:
        offenders.extend(check_file(path, root))

    if offenders:
        for kind, loc in offenders:
            if kind == _BOUNDARY_UNKNOWN:
                print(
                    f"::error::cannot verify deleted_at IS NULL filter — "
                    f"string-literal boundary is unparseable (raw or "
                    f"triple-quoted literal). Rewrite as a plain quoted "
                    f"literal, or extend the ratchet to handle this form. "
                    f"{loc}"
                )
            else:
                print(f"::error::missing deleted_at IS NULL filter: {loc}")
        print(
            f"::error::{len(offenders)} raw settings read(s) require attention. "
            "Every SELECT from settings WHERE key must filter deleted rows — "
            "the hard-delete in repositories.dart is justified in prose by "
            "this invariant (issue #907).",
        )
        return 1

    print(
        f"OK: all raw FROM settings WHERE key reads filter deleted_at IS NULL "
        f"across {len(files)} library file(s).",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
