#!/usr/bin/env python3
"""CI ratchet: a join onto `_db.dances` in a repository must say whether it
needs the joined columns.

Why
---
`select(x).join([innerJoin(_db.dances, ...)])` makes drift materialise **every**
`dances` column (figures JSON, notes, ...) for every joined row unless the join
passes `useColumns: false`. The tag facet read paid ~445 ms of a 2.08 s
Collection reload at 20k dances for exactly that, while reading only `tags`
columns (CS-14a). A join that only filters or counts rows must say so with
`useColumns: false`.

Rule
----
Under `packages/compendium_core/lib/src/storage/repositories/`, every
`innerJoin(` / `leftOuterJoin(` whose first argument mentions `_db.dances`
(the table itself, `_db.dances.createAlias(...)`, `alias(_db.dances, ...)`)
must either

  * carry `useColumns:` in the same call, or
  * carry the marker `// join-columns: needed — <reason>` on the line(s)
    directly above the call, on the call's own line, or inside the call.

The reason is mandatory. Use the marker when the loop genuinely reads
`row.readTable(_db.dances)`; note that with `useColumns: false` that call
throws, so a join that reads `dances` columns must NOT drop them.

Comments and string literals are blanked before matching, so dartdoc or prose
that mentions `innerJoin(_db.dances` is neither flagged nor accepted.

Exit codes: 0 = all compliant, 1 = at least one violation, 2 = bad input.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
REPOSITORIES_DIR = (
    REPO_ROOT / "packages/compendium_core/lib/src/storage/repositories"
)

_JOIN_RE = re.compile(r"\b(?:innerJoin|leftOuterJoin)\s*\(")
_DANCES_RE = re.compile(r"\b_db\s*\.\s*dances\b")
_USE_COLUMNS_RE = re.compile(r"\buseColumns\s*:")
_MARKER_RE = re.compile(r"join-columns:\s*needed\s*[—–-]+\s*(\S.*)")
_MARKER_WORD_RE = re.compile(r"join-columns:")

MISSING = "missing_use_columns"
EMPTY_REASON = "marker_without_reason"


@dataclass(frozen=True)
class Violation:
    path: str
    line: int
    kind: str
    source: str

    def render(self) -> str:
        if self.kind == EMPTY_REASON:
            why = (
                "`join-columns:` marker needs the form "
                "`// join-columns: needed — <reason>`"
            )
        else:
            why = (
                "join onto _db.dances without `useColumns:` materialises "
                "every dances column; add `useColumns: false`, or mark it "
                "`// join-columns: needed — <reason>` if the loop reads "
                "readTable(_db.dances)"
            )
        return f"{self.path}:{self.line}: {why}\n    {self.source}"


def split_code_and_comments(text: str) -> tuple[str, list[tuple[int, str]]]:
    """Return (code, comments).

    *code* is *text* with comments and string-literal contents replaced by
    spaces (newlines kept, so offsets and line numbers are unchanged).
    *comments* is a list of (offset, comment text) for every `//` and
    `/* */` comment. Triple-quoted and raw literals are handled like plain
    ones; a repository file with SQL in them is not this check's concern.
    """
    out = list(text)
    comments: list[tuple[int, str]] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            j = text.find("\n", i)
            j = n if j == -1 else j
            comments.append((i, text[i:j]))
            for k in range(i, j):
                out[k] = " "
            i = j
        elif c == "/" and nxt == "*":
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            comments.append((i, text[i:j]))
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        elif c in ("'", '"'):
            triple = text[i : i + 3] == c * 3
            close = c * 3 if triple else c
            j = i + (3 if triple else 1)
            while j < n:
                if text[j] == "\\" and not (i > 0 and text[i - 1] in "rR"):
                    j += 2
                    continue
                if text.startswith(close, j):
                    break
                if text[j] == "\n" and not triple:
                    break
                j += 1
            end = min(j + len(close), n)
            for k in range(i + len(close), min(j, n)):
                if out[k] != "\n":
                    out[k] = " "
            i = end
        else:
            i += 1
    return "".join(out), comments


def _call_end(code: str, open_paren: int) -> int:
    depth = 0
    for k in range(open_paren, len(code)):
        if code[k] == "(":
            depth += 1
        elif code[k] == ")":
            depth -= 1
            if depth == 0:
                return k
    return len(code)


def _first_argument_end(code: str, after_paren: int) -> int:
    """Offset of the `,` or `)` that ends the call argument starting at
    [after_paren], skipping nested brackets."""
    depth = 0
    for k in range(after_paren, len(code)):
        c = code[k]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return k
            depth -= 1
        elif c == "," and depth == 0:
            return k
    return len(code)


def check_text(text: str, path: str) -> list[Violation]:
    code, comments = split_code_and_comments(text)
    lines = text.splitlines()

    def lineno(off: int) -> int:
        return text.count("\n", 0, off) + 1

    violations: list[Violation] = []
    prev_join_end = -1
    for m in _JOIN_RE.finditer(code):
        start = m.start()
        end = _call_end(code, code.index("(", start))
        if not _DANCES_RE.search(code[m.end() : _first_argument_end(code, m.end())]):
            continue
        line = lineno(start)
        span = code[start : end + 1]
        floor, prev_join_end = prev_join_end, end
        if _USE_COLUMNS_RE.search(span):
            continue

        # Marker: any comment between the end of the previous statement and
        # the end of this call. That covers the line(s) directly above the
        # call, its own lines, and a comment above `final x = await (...)` --
        # `dart format` re-lays-out a whole expression when a comment sits
        # inside it, so the marker may live on the enclosing statement.
        # A marker belongs to one join: the search starts after the previous
        # dance join in the same statement, so one marker cannot exempt two.
        stmt_start = max(
            max(code.rfind(ch, 0, start) for ch in ";{}") + 1,
            floor + 1,
        )
        line_end = text.find("\n", end)
        line_end = len(text) if line_end == -1 else line_end
        candidates = [
            body for off, body in comments if stmt_start <= off <= line_end
        ]
        marked = [c for c in candidates if _MARKER_WORD_RE.search(c)]
        if any(_MARKER_RE.search(c) for c in marked):
            continue
        kind = EMPTY_REASON if marked else MISSING
        violations.append(
            Violation(path, line, kind, lines[line - 1].strip())
        )
    return violations


def check_tree(root: Path) -> list[Violation]:
    violations: list[Violation] = []
    for path in sorted(root.rglob("*.dart")):
        try:
            rel = path.relative_to(REPO_ROOT).as_posix()
        except ValueError:
            rel = path.as_posix()
        violations.extend(check_text(path.read_text(encoding="utf-8"), rel))
    return violations


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else REPOSITORIES_DIR
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2
    violations = check_tree(root)
    for v in violations:
        print(v.render())
    if violations:
        print(
            f"\n{len(violations)} join(s) onto _db.dances without "
            "`useColumns:` or a `join-columns: needed` marker.",
            file=sys.stderr,
        )
        return 1
    print("join-columns: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
