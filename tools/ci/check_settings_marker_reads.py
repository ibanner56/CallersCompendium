#!/usr/bin/env python3
"""CI ratchet: every raw FROM settings WHERE key read must filter
deleted_at IS NULL.

See CONTRIBUTING.md "Raw SQL reads from the settings table" and issue #907.

Design
------
Earlier revisions interleaved string-literal parsing with the filter check,
producing a series of bugs in the literal-boundary logic that each needed a
separate round to find: the semicolon-scan false negative, the double-quote
false positive, the ':0: (unknown)' line number, the prefilter bypass (FROM
split across adjacent literals), and the wrong join separator (space instead
of empty string, masking broken SQL that would fail at runtime).

The current design solves the parsing problem once, separately, in
extract_sql_literals, which returns a flat list of SqlLiteral objects.
The filter check consumes that list and contains no string-parsing logic of
its own. This makes the two concerns independently testable and keeps the
outer check_file logic to a simple two-condition branch.

Multi-line SQL and join semantics
---------------------------------
Adjacent Dart string literals concatenate at compile time with NO separator.
extract_sql_literals joins them with the empty string to match Dart semantics.
A read split as:

    'SELECT 1 FROM settings WHERE key = ?'
    'AND deleted_at IS NULL'

produces "SELECT 1 FROM settings WHERE key = ?AND deleted_at IS NULL" which
is invalid SQL (missing space before AND). The ratchet correctly flags this
because the filter regex requires a word boundary. The compliant form uses a
trailing space inside the first literal:

    'SELECT 1 FROM settings WHERE key = ? '
    'AND deleted_at IS NULL'

Filter scoping
--------------
The filter check is restricted to the joined content of the SQL literal
group, not the surrounding Dart statement. A probe that passes
'deleted_at IS NULL' as a Dart variable value does not satisfy the check
because the variable string is a separate literal group.

Fail-closed on unparseable boundaries
--------------------------------------
Raw (r'...') and triple-quoted forms are not parsed. They are detected and
flagged as _BOUNDARY_UNKNOWN with a message explaining why and naming the
way out, rather than silently passing or claiming the filter is missing.

Deliberate exception
--------------------
repositories.dart performs a hard DELETE FROM settings WHERE key = ? to
clear the rebuild marker. That is intentionally a DELETE, not a SELECT.
_SELECT_FROM_SETTINGS_RE requires SELECT, so the DELETE never matches.
_NOTED_EXCEPTIONS documents this by name per the kUpdateManifestPublicKey
precedent in AGENTS.md: name exceptions rather than narrowing patterns.

Exit codes: 0 = all compliant, 1 = at least one violation, 2 = bad input.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# --------------------------------------------------------------------------
# Deliberate exceptions
# --------------------------------------------------------------------------

# repositories.dart contains a hard DELETE of the rebuild marker with no
# deleted_at IS NULL filter — correct for a DELETE statement. Because
# _SELECT_FROM_SETTINGS_RE requires SELECT, the DELETE never matches.
# This dict names the exception explicitly (per the kUpdateManifestPublicKey
# precedent in AGENTS.md: name exceptions rather than narrowing patterns)
# and is validated at startup: if the file no longer exists, main() fails
# loudly so a rename cannot silently orphan this documentation.
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

_SELECT_FROM_SETTINGS_RE = re.compile(
    r"\bSELECT\b[^;]*\bFROM\s+settings\b[^;]*\bWHERE\s+key\b",
    re.IGNORECASE,
)

_DELETED_AT_FILTER_RE = re.compile(
    # The leading \s+AND is required, not cosmetic. Dart adjacent string literals
    # concatenate with nothing (empty string), so a read split as:
    #   'SELECT … WHERE key = ?'
    #   'AND deleted_at IS NULL'
    # joins to '…WHERE key = ?AND deleted_at IS NULL' — invalid SQL that SQLite
    # rejects at runtime. \bdeleted_at or \bAND both match after '?' (non-word
    # char → word boundary before A), so only requiring actual whitespace before
    # AND correctly rejects that form. Widening this pattern reopens that bypass.
    #
    # A parenthesised form 'AND (deleted_at IS NULL)' is not matched and fails
    # closed; no read in the tree uses that form today.
    r"\s+AND\s+deleted_at\s+IS\s+NULL\b",
    re.IGNORECASE,
)

# --------------------------------------------------------------------------
# Violation kinds
# --------------------------------------------------------------------------

_MISSING_FILTER = "missing_filter"
_BOUNDARY_UNKNOWN = "boundary_unknown"


# --------------------------------------------------------------------------
# Literal extraction
# --------------------------------------------------------------------------


@dataclass
class SqlLiteral:
    """A Dart string literal (or run of adjacent literals) from source."""

    content: str
    line_no: int
    source_line: str
    parseable: bool


def extract_sql_literals(text: str) -> list[SqlLiteral]:
    """Parse all Dart string literals from *text* and return them.

    Adjacent literals of the same quote style are joined with the empty
    string (Dart compile-time concatenation semantics). Triple-quoted and
    raw literals are returned with parseable=False; their content field
    holds the raw literal text (between the quotes) so callers can scan it
    without re-parsing.

    This is the single place that decides what constitutes a string literal
    and where its boundaries are. All other logic consumes SqlLiteral objects
    and contains no string-parsing of its own.

    We walk the text character by character:
    - Skip // line comments.
    - Handle escape sequences inside literals.
    - Detect raw (r'...') and triple-quoted forms and mark unparseable.
    - Join adjacent same-style literals with empty string.
    """
    lines = text.splitlines(keepends=True)
    cum: list[int] = [0]
    for line in lines:
        cum.append(cum[-1] + len(line))

    def offset_to_lineno(off: int) -> int:
        lo, hi = 0, len(cum) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if cum[mid] <= off:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    def source_line_at(off: int) -> str:
        return lines[offset_to_lineno(off) - 1].rstrip()

    result: list[SqlLiteral] = []
    i = 0
    n = len(text)

    while i < n:
        c = text[i]

        # Skip line comments.
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue

        if c not in ("'", '"'): 
            i += 1
            continue

        q = c
        lit_start = i
        raw = i > 0 and text[i - 1] in ("r", "R")
        triple = i + 2 < n and text[i + 1] == q and text[i + 2] == q

        if raw or triple:
            if triple:
                close_seq = q * 3
                end = text.find(close_seq, i + 3)
                lit_end = (end + 3) if end != -1 else n
                raw_content = text[i + 3 : end] if end != -1 else text[i + 3 :]
                i = lit_end
            else:
                j = i + 1
                while j < n and text[j] != q:
                    j += 1
                raw_content = text[i + 1 : j]
                i = j + 1
            line_no = offset_to_lineno(lit_start)
            src_line = source_line_at(lit_start).strip()
            # Store raw_content so the fail-closed check in check_file can scan
            # the full literal text, not just the first source line. A triple-
            # quoted literal whose 'settings' appears on line 2+ would be
            # silently skipped if we only checked source_line.
            result.append(SqlLiteral(raw_content, line_no, src_line, parseable=False))
            continue

        # Normal literal.
        content_chars: list[str] = []
        j = i + 1
        while j < n:
            ch = text[j]
            if ch == "\\":
                j += 1
                if j < n:
                    content_chars.append(text[j])
                j += 1
                continue
            if ch == q:
                j += 1
                break
            content_chars.append(ch)
            j += 1

        lit_content = "".join(content_chars)
        line_no = offset_to_lineno(lit_start)
        src_line = source_line_at(lit_start).strip()
        i = j

        # Look ahead for adjacent same-style literals (Dart concatenation).
        while i < n:
            k = i
            while k < n and text[k] in (" ", "\t", "\n", "\r"):
                k += 1
            if k >= n:
                break
            if text[k] == "/" and k + 1 < n and text[k + 1] == "/":
                while k < n and text[k] != "\n":
                    k += 1
                i = k  # advance past the comment before the next iteration
                continue
            if text[k] != q:
                break
            if k + 2 < n and text[k + 1] == q and text[k + 2] == q:
                break
            j2 = k + 1
            adj_chars: list[str] = []
            while j2 < n:
                ch = text[j2]
                if ch == "\\":
                    j2 += 1
                    if j2 < n:
                        adj_chars.append(text[j2])
                    j2 += 1
                    continue
                if ch == q:
                    j2 += 1
                    break
                adj_chars.append(ch)
                j2 += 1
            lit_content += "".join(adj_chars)
            i = j2

        result.append(SqlLiteral(lit_content, line_no, src_line, parseable=True))

    return result


# --------------------------------------------------------------------------
# File discovery
# --------------------------------------------------------------------------


def dart_library_files(root: Path) -> list[Path]:
    """Every production .dart file: app/lib/** and packages/*/lib/**."""
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
    print(f"::error::{msg}")
    sys.exit(code)


# --------------------------------------------------------------------------
# Per-file check
# --------------------------------------------------------------------------


def check_file(path: Path, root: Path) -> list[tuple[str, str]]:
    """Return (kind, location) pairs for every violation in *path*.

    kind is _MISSING_FILTER or _BOUNDARY_UNKNOWN.

    Delegates all literal parsing to extract_sql_literals; this function
    contains no quote-scanning logic of its own.

    No fast path on raw text. Any substring check on un-joined text is
    defeatable by splitting the target word across adjacent literals (e.g.
    'sett' + 'ings'), which the joiner reconstructs but the raw check misses.
    Every bypass found in review so far has been in a raw-text heuristic that
    ran before the joiner. The cost of extract_sql_literals over the full
    corpus (~340 files) is under one second; correctness outweighs it.
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    rel = str(path.relative_to(root))
    violations: list[tuple[str, str]] = []

    for lit in extract_sql_literals(text):
        if not lit.parseable:
            # Fail closed only on unparseable literals that look like a settings
            # SELECT — i.e. the SELECT pattern matches the raw content. This avoids
            # false positives on raw strings used for UI prose that happen to contain
            # the word "settings" (e.g. r'Open settings to change your preferences.')
            # There are ~85 such strings in the corpus today; flagging them would
            # block correct work and teach contributors to delete the ratchet.
            if _SELECT_FROM_SETTINGS_RE.search(lit.content):
                violations.append((
                    _BOUNDARY_UNKNOWN,
                    f"{rel}:{lit.line_no}: {lit.source_line}",
                ))
            continue

        if not _SELECT_FROM_SETTINGS_RE.search(lit.content):
            continue

        if _DELETED_AT_FILTER_RE.search(lit.content):
            continue

        violations.append((_MISSING_FILTER, f"{rel}:{lit.line_no}: {lit.source_line}"))

    return violations


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------


def main() -> int:
    root = REPO_ROOT
    # Validate that every noted exception still exists on disk. If a file is
    # renamed or deleted, this fails loudly rather than leaving stale documentation.
    for exc_path, reason in _NOTED_EXCEPTIONS.items():
        if not (root / exc_path).exists():
            _fail(
                f"noted exception no longer exists: {exc_path} ({reason}). "
                "Update _NOTED_EXCEPTIONS in check_settings_marker_reads.py."
            )

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
