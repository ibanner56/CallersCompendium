#!/usr/bin/env python3
"""CI ratchet: no ``RegExp(`` compiled per call in the import hot paths.

``RegExp(...)`` compiles its pattern every time it runs. In the import matching
and figure-parsing code that cost is paid once per record (a 20,000-dance
``.USR`` is 20,000 times, and dedupe ran five of them per *pair* before CS-25a
hoisted them): the pattern must be a top-level or ``static`` declaration, built
once, not a ``RegExp(`` sitting in a function body.

Files checked (under ``packages/compendium_core/lib/src/imports/``):
``dedupe.dart``, ``figure_parser.dart`` and every ``*_figure_dialect.dart``.

A ``RegExp(`` is **per-call** when, in the comment/string-masked source, any of
these holds:

* it sits inside a function body (a ``{`` block whose header ends in a
  parameter list, optionally followed by ``async``/``sync*``/``async*``, or in a
  getter name: methods, constructors' bodies, local functions, closures and
  block getters);
* its statement has an arrow body before it (``f() => RegExp(...)``,
  ``get re => RegExp(...)``, ``() => RegExp(...)``), including one that
  returns a collection literal (``f() => {'x': RegExp('x')}``);
* it initialises an *instance* field of a class (no ``static``): that compiles
  once per object, and these objects are created per call.

Top-level declarations and ``static`` class members (including collection
literals and ``const`` maps of them) are fine. Strings and comments are
masked first, so a ``RegExp(`` in a comment never counts, but ``${...}``
interpolation inside a string is real code and is kept.

Each offender prints as ``path:line`` (relative to the repo root) with its
enclosing symbol. Offenders are matched against ``ALLOWED`` by
``(path, symbol)``: an entry names how many per-call ``RegExp(`` that symbol is
allowed to keep, and why. The count is a ceiling — a new one in an allowed
symbol still fails. An entry whose symbol now has *fewer* is reported as a
``::warning::`` (lower or delete it) rather than a failure, so the lane that
fixes one is never blocked by this file.

Known, documented gaps (not silent): a ``RegExp(`` inside a *constructor
initialiser list* is not recognised as function scope; ``RegExp`` tear-offs
(``RegExp.new``) and ``RegExp`` built by a differently named factory are not
seen. The symbol for a closure is its nearest enclosing named function.

Exit codes: 0 = clean, 1 = at least one un-allowed per-call ``RegExp(``,
2 = bad input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
IMPORTS_DIR = "packages/compendium_core/lib/src/imports"
CHECKED_FILES = ("dedupe.dart", "figure_parser.dart")
CHECKED_GLOBS = ("*_figure_dialect.dart",)

# (repo-relative path, symbol) -> (max per-call RegExp( count, reason).
# These belong to the figure-entry lane (CS-45a-d); they are listed so the
# ratchet is green today and a *new* one anywhere fails.
ALLOWED: dict[tuple[str, str], tuple[int, str]] = {}


def _blank(text: str) -> str:
    return re.sub(r"[^\n]", " ", text)


def mask_source(text: str) -> str:
    """Blank comments and string contents to spaces, keeping offsets and newlines.

    Interpolated code (``${...}``) inside a non-raw string is preserved, since
    it is real code; the ``${`` / ``}`` delimiters and the string text around it
    are blanked. Raw strings (``r'...'``) have no escapes and no interpolation.
    """
    out: list[str] = []
    n = len(text)
    i = 0
    # Stack of open string/interpolation contexts. A string context is
    # ("str", quote, raw); an interpolation is ("interp", brace_depth).
    stack: list[list] = []
    block_depth = 0
    while i < n:
        c = text[i]
        if block_depth:
            if text.startswith("/*", i):
                block_depth += 1
                out.append("  ")
                i += 2
            elif text.startswith("*/", i):
                block_depth -= 1
                out.append("  ")
                i += 2
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
            continue
        top = stack[-1] if stack else None
        if top is not None and top[0] == "str":
            _, quote, raw = top
            if c == "\\" and not raw:
                chunk = text[i : i + 2]
                out.append(_blank(chunk))
                i += len(chunk)
            elif text.startswith(quote, i):
                out.append(" " * len(quote))
                i += len(quote)
                stack.pop()
            elif c == "$" and not raw and text.startswith("${", i):
                out.append("  ")
                i += 2
                stack.append(["interp", 0])
            else:
                out.append("\n" if c == "\n" else " ")
                i += 1
            continue
        # Code (top level, or inside an interpolation).
        if top is not None and top[0] == "interp":
            if c == "{":
                top[1] += 1
            elif c == "}":
                if top[1] == 0:
                    stack.pop()
                    out.append(" ")
                    i += 1
                    continue
                top[1] -= 1
        if text.startswith("/*", i):
            block_depth = 1
            out.append("  ")
            i += 2
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end == -1 else end
            out.append(" " * (end - i))
            i = end
            continue
        raw = False
        j = i
        if c == "r" and i + 1 < n and text[i + 1] in "'\"":
            prev = text[i - 1] if i else " "
            if not (prev.isalnum() or prev == "_"):
                raw = True
                j = i + 1
        if text[j : j + 1] in ("'", '"'):
            quote = text[j : j + 3] if text.startswith(text[j] * 3, j) else text[j]
            out.append(" " * (j - i + len(quote)))
            i = j + len(quote)
            stack.append(["str", quote, raw])
            continue
        out.append(c)
        i += 1
    return "".join(out)


_CLASS_HEADER_RE = re.compile(r"\b(class|mixin|extension|enum)\b")
_FUNC_TAIL_RE = re.compile(r"\)\s*(?:async\s*\*?|sync\s*\*)?\s*$")
_REGEXP_RE = re.compile(r"(?<![\w.])RegExp\s*\(")


def _header(masked: str, pos: int) -> tuple[int, str]:
    """The text between the previous `;`, `{` or `}` and [pos]."""
    start = max(masked.rfind(ch, 0, pos) for ch in ";{}") + 1
    return start, masked[start:pos]


_CONTROL_KEYWORDS = frozenset({"if", "for", "while", "switch", "catch"})
_GETTER_RE = re.compile(r"\bget\s+(\w+)\s*$")
# What can precede a function's `=>`: a parameter list (optionally `async`) or a
# getter name. A switch-expression case (`1 => RegExp(...)`) is neither.
_ARROW_FN_RE = re.compile(r"(?:\)\s*(?:async\s*)?|\bget\s+\w+\s*)=>")


def _has_arrow_fn(header: str) -> bool:
    """Whether [header] contains a function's `=>` (an expression-bodied
    function, getter or closure), as opposed to a switch-case arrow."""
    return _ARROW_FN_RE.search(header) is not None


def _block_kind(header: str) -> str:
    if _CLASS_HEADER_RE.search(header):
        return "class"
    # A block getter (`get re {`) has no parameter list; an arrow-bodied
    # function returning a collection literal (`=> {'x': RegExp('x')}`) opens a
    # `{` that is a literal but still runs on every call.
    if _name_before_params(header) in _CONTROL_KEYWORDS:
        # `switch (x) {` / `if (c) {`: a block, not a callable. Inside a real
        # function the enclosing function still marks it per-call; a top-level
        # switch expression runs once.
        return "block"
    if (
        _FUNC_TAIL_RE.search(header)
        or _GETTER_RE.search(header)
        or _has_arrow_fn(header)
    ):
        return "function"
    return "literal"


def _name_before_params(header: str) -> str | None:
    """Identifier before the parameter list that ends [header], if any."""
    header = header.rstrip()
    stripped = re.sub(r"\)\s*(?:async\s*\*?|sync\s*\*)?\s*$", ")", header)
    if not stripped.endswith(")"):
        return None
    depth = 0
    for k in range(len(stripped) - 1, -1, -1):
        if stripped[k] == ")":
            depth += 1
        elif stripped[k] == "(":
            depth -= 1
            if depth == 0:
                m = re.search(r"([A-Za-z_]\w*)\s*(?:<[^()]*>)?\s*$", stripped[:k])
                return m.group(1) if m else None
    return None


def _callable_name(header: str) -> str | None:
    """Name of the function whose body block [header] opens, if it has one."""
    getter = _GETTER_RE.search(header.strip())
    if getter:
        return getter.group(1)
    if _has_arrow_fn(header):
        return _arrow_name(header)
    return _name_before_params(header)


def _arrow_name(header: str) -> str | None:
    """Name of the declaration whose arrow body follows [header]."""
    before = header.rsplit("=>", 1)[0]
    m = re.search(r"\bget\s+(\w+)\s*$", before.strip())
    if m:
        return m.group(1)
    return _name_before_params(before)


def find_per_call(masked: str) -> list[tuple[int, str]]:
    """Per-call ``RegExp(`` sites as ``(offset, symbol)`` pairs."""
    # Block stack: (kind, name or None) for every open `{`.
    results: list[tuple[int, str]] = []
    stack: list[tuple[str, str | None]] = []
    pos = 0
    matches = list(_REGEXP_RE.finditer(masked))
    mi = 0
    n = len(masked)
    while pos < n:
        c = masked[pos]
        if mi < len(matches) and pos == matches[mi].start():
            site = _classify(masked, pos, stack)
            if site is not None:
                results.append(site)
            mi += 1
        if c == "{":
            _, header = _header(masked, pos)
            kind = _block_kind(header)
            name = _callable_name(header) if kind == "function" else None
            stack.append((kind, name))
        elif c == "}":
            if stack:
                stack.pop()
        pos += 1
    return results


def _classify(
    masked: str, pos: int, stack: list[tuple[str, str | None]]
) -> tuple[int, str] | None:
    """`(pos, symbol)` when the `RegExp(` at [pos] is per-call, else `None`."""
    start, header = _header(masked, pos)
    symbol = "<top-level>"
    for kind, name in reversed(stack):
        if kind == "function" and name:
            symbol = name
            break
    if _has_arrow_fn(header):
        return pos, _arrow_name(header) or symbol
    if any(kind == "function" for kind, _ in stack):
        return pos, symbol
    # Directly in a class body (ignoring collection literals between): instance
    # fields compile once per object, so only `static` members are hoisted.
    if stack and any(kind == "class" for kind, _ in stack):
        innermost_class = max(
            i for i, (kind, _) in enumerate(stack) if kind == "class"
        )
        member_start = start
        if not re.search(r"\bstatic\b", masked[member_start:pos]):
            # Walk back to the start of the member through any enclosing
            # literals, so `static final m = {'a': RegExp(...)}` stays static.
            if any(
                kind in ("literal", "block")
                for kind, _ in stack[innermost_class + 1 :]
            ):
                depth = 0
                k = pos
                while k > 0:
                    k -= 1
                    ch = masked[k]
                    if ch == "}":
                        depth += 1
                    elif ch == "{":
                        if depth == 0:
                            _, h = _header(masked, k)
                            if re.search(r"\bstatic\b", h):
                                return None
                            if _block_kind(h) not in ("literal", "block"):
                                break
                        else:
                            depth -= 1
            return pos, "<instance field>"
    return None


def find_offenders(src: str) -> list[tuple[int, str]]:
    """``(line, symbol)`` for every per-call ``RegExp(`` in [src]."""
    masked = mask_source(src)
    return [
        (src.count("\n", 0, off) + 1, symbol)
        for off, symbol in find_per_call(masked)
    ]


def checked_files(root: Path) -> list[Path]:
    base = root / IMPORTS_DIR
    files = [base / name for name in CHECKED_FILES]
    for pattern in CHECKED_GLOBS:
        files.extend(sorted(base.glob(pattern)))
    return [f for f in files if f.is_file()]


def evaluate(
    found: dict[str, list[tuple[int, str]]],
    allowed: dict[tuple[str, str], tuple[int, str]],
) -> tuple[list[str], list[str]]:
    """Return `(failures, warnings)` for `{path: [(line, symbol)]}`."""
    failures: list[str] = []
    warnings: list[str] = []
    used: dict[tuple[str, str], int] = {}
    for path, sites in sorted(found.items()):
        seen: dict[str, int] = {}
        for line, symbol in sites:
            key = (path, symbol)
            seen[symbol] = seen.get(symbol, 0) + 1
            limit = allowed.get(key, (0, ""))[0]
            if seen[symbol] > limit:
                failures.append(
                    f"{path}:{line}: per-call RegExp( in `{symbol}` "
                    "(hoist it to a top-level or static final)"
                )
        for symbol, count in seen.items():
            used[(path, symbol)] = count
    for key, (limit, _reason) in sorted(allowed.items()):
        actual = used.get(key, 0)
        if actual < limit:
            warnings.append(
                f"allow-list entry {key[0]}:{key[1]} permits {limit} but only "
                f"{actual} remain; lower or delete it"
            )
    return failures, warnings


def main() -> int:
    files = checked_files(REPO_ROOT)
    if not files:
        print(f"::error::no files to check under {IMPORTS_DIR}")
        return 2
    found: dict[str, list[tuple[int, str]]] = {}
    for f in files:
        rel = f.relative_to(REPO_ROOT).as_posix()
        found[rel] = find_offenders(f.read_text(encoding="utf-8"))
    failures, warnings = evaluate(found, ALLOWED)
    for w in warnings:
        print(f"::warning::{w}")
    for msg in failures:
        print(f"::error::{msg}")
    if failures:
        print(
            f"\n{len(failures)} per-call RegExp( site(s). Build the pattern once "
            "as a top-level or `static final`, or (figure-entry lane only) add "
            "an ALLOWED entry in tools/ci/check_hot_path_regexp.py with a reason."
        )
        return 1
    print(f"ok: no un-allowed per-call RegExp( in {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
