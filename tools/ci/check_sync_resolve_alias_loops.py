#!/usr/bin/env python3
"""CI ratchet: no ``await <store>.resolveAlias(...)`` inside a loop under
``app/lib/src/sync/`` (audit finding P7, CS-16).

``resolveAlias`` on the sync store is one database transaction per call. The
coordinator's five normalisation helpers used to call it once per item, so a
pass over a 20k-record library issued ~20k SQL statements per helper (464 ms
for 20k calls against 0.33 ms for a single ``listAliases()``). They now load
``store.aliasMap()`` once per helper call and resolve synchronously. This
ratchet keeps a per-item store round trip from creeping back into a loop.

A finding is an ``await`` expression containing ``.resolveAlias(`` that sits
inside the body of a ``for`` / ``while`` / ``do`` loop, braced or not, or a collection-``for``
element. Matching ``await`` plus a *method call* is deliberate: the
coordinator also passes local ``resolveAlias: (address) => ...`` lambdas over
already-resolved maps (no ``await``, no store), and those are not store calls.

Opt out of one site with a comment on the call's line, the line above it, or
the loop header's line (or the line above that)::

    // alias-loop: allowed — <reason>

Only the marker's presence is checked; the reason is a code-review concern.

Known gap, stated rather than hidden: the walk is lexical. A per-item call
hidden in a ``forEach`` / ``map`` closure, or behind a helper function that
the loop calls, is not seen. Nor is a per-item `aliasMap()` load, which would
be the same mistake under another name; `normalisation resolves aliases from
one aliasMap per step` in `sync_coordinator_test.dart` covers that one.

Exit codes: 0 = clean, 1 = at least one unmarked site, 2 = bad input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_caught_error_logged import (  # noqa: E402
    _line_of,
    _match_brace,
    _match_paren,
    mask_source,
)

REPO_ROOT = HERE.parents[1]

SEARCH_ROOT = "app/lib/src/sync"

_LOOP_RE = re.compile(r"\b(for|while)\s*\(")
_DO_RE = re.compile(r"\bdo\b")
_WORD_RE = re.compile(r"[A-Za-z_]\w*")
# `await` followed, within the same statement, by a `.resolveAlias(` call.
_AWAITED_RESOLVE_RE = re.compile(r"\bawait\b[^;{}]*?\.resolveAlias\s*\(")
_MARKER_RE = re.compile(r"alias-loop:\s*allowed\b")


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}")
    sys.exit(code)


def dart_sync_files(root: Path) -> list[Path]:
    sync_dir = root / SEARCH_ROOT
    if not sync_dir.is_dir():
        return []
    return sorted(sync_dir.rglob("*.dart"))


def _skip_ws(masked: str, i: int) -> int:
    while i < len(masked) and masked[i] in " \t\r\n":
        i += 1
    return i


def _expression_end(masked: str, start: int) -> int:
    """End of an expression statement or collection-for element: the first
    unnested `;`, `,` or closing bracket at or after [start]."""
    depth = 0
    for i in range(start, len(masked)):
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif c in ";," and depth == 0:
            return i
    return len(masked)


def _word_at(masked: str, i: int) -> str:
    m = _WORD_RE.match(masked, i)
    return m.group(0) if m else ""


def _statement_end(masked: str, start: int) -> int:
    """Offset just past the statement beginning at [start].

    A braced block, `if`/`else`, `for`, `while` and `do` end where their own
    last sub-statement ends, so a following statement is never swallowed (a
    nested `{ ... }` body must not be read through to the next `;`). Anything
    else is an expression statement, which ends at its `;`. `switch` and `try`
    are not modelled and fall back to the expression walk."""
    n = len(masked)
    i = _skip_ws(masked, start)
    if i >= n:
        return n
    if masked[i] == "{":
        close = _match_brace(masked, i)
        return n if close is None else close + 1
    word = _word_at(masked, i)
    if word in ("if", "for", "while"):
        j = _skip_ws(masked, i + len(word))
        if j < n and masked[j] == "(":
            close = _match_paren(masked, j)
            if close is not None:
                end = _statement_end(masked, close + 1)
                if word == "if":
                    k = _skip_ws(masked, end)
                    if _word_at(masked, k) == "else":
                        return _statement_end(masked, k + len("else"))
                return end
    elif word == "do":
        end = _statement_end(masked, i + len("do"))
        k = _skip_ws(masked, end)
        if _word_at(masked, k) == "while":
            j = _skip_ws(masked, k + len("while"))
            close = _match_paren(masked, j) if j < n and masked[j] == "(" else None
            if close is not None:
                return _expression_end(masked, close + 1) + 1
        return end
    return _expression_end(masked, i) + 1


def _loop_bodies(masked: str) -> list[tuple[int, int, int]]:
    """`(loop_keyword_offset, body_start, body_end)` for every loop."""
    bodies: list[tuple[int, int, int]] = []
    for m in _LOOP_RE.finditer(masked):
        close = _match_paren(masked, m.end() - 1)
        if close is None:
            continue
        i = _skip_ws(masked, close + 1)
        if i >= len(masked) or masked[i] == ";":
            continue  # `while (...);` closing a do-while, or an empty body
        bodies.append((m.start(), i, _statement_end(masked, i)))
    for m in _DO_RE.finditer(masked):
        i = _skip_ws(masked, m.end())
        bodies.append((m.start(), i, _statement_end(masked, i)))
    return bodies


def _marked(text: str, lines: set[int]) -> bool:
    """A marker counts on the site's own line, or alone on the line above it.

    The line-above form must be comment-only: a trailing marker on the previous
    statement belongs to that statement, not this one."""
    src = text.split("\n")
    for line in lines:
        if 1 <= line <= len(src) and _MARKER_RE.search(src[line - 1]):
            return True
        above = src[line - 2].lstrip() if 2 <= line <= len(src) + 1 else ""
        if above.startswith("//") and _MARKER_RE.search(above):
            return True
    return False


def find_loop_resolves(text: str) -> list[tuple[int, str]]:
    """`(line_no, source_line)` for each unmarked awaited `.resolveAlias(` call
    inside a loop body in [text]. One finding per call, however deeply nested."""
    masked = mask_source(text)
    found: dict[int, set[int]] = {}  # call offset -> loop header lines
    for loop_start, body_start, body_end in _loop_bodies(masked):
        for m in _AWAITED_RESOLVE_RE.finditer(masked, body_start, body_end):
            found.setdefault(m.start(), set()).add(_line_of(text, loop_start))
    src = text.split("\n")
    findings: list[tuple[int, str]] = []
    for offset in sorted(found):
        line = _line_of(text, offset)
        if _marked(text, {line} | found[offset]):
            continue
        findings.append((line, src[line - 1].strip()))
    return findings


def main() -> int:
    files = dart_sync_files(REPO_ROOT)
    if not files:
        _fail(f"no Dart files found under {REPO_ROOT / SEARCH_ROOT}")
    offenders = 0
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if "resolveAlias" not in text:
            continue
        rel = path.relative_to(REPO_ROOT).as_posix()
        for line, snippet in find_loop_resolves(text):
            offenders += 1
            print(
                f"::error file={rel},line={line}::`await ….resolveAlias(` inside a "
                f"loop is one transaction per item: {snippet}"
            )
    if offenders:
        print(
            f"\n{offenders} per-item resolveAlias call(s) in a loop. Load "
            "`await store.aliasMap()` once before the loop and resolve "
            "synchronously, or mark a justified site with "
            "`// alias-loop: allowed — <reason>`."
        )
        return 1
    print(f"ok: no awaited resolveAlias inside a loop under {SEARCH_ROOT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
