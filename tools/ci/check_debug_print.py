#!/usr/bin/env python3
"""CI ratchet: every ``debugPrint`` call must be guarded by ``kDebugMode``.

An unguarded ``debugPrint`` survives into release builds, where it writes to the
system log. This app's debug output carries file paths, import URLs and user
dance content, so an unguarded call is an information-disclosure leak (issue
#617, cleaned up in PR #647). The convention is enforced nowhere in code, so
until now it held purely by habit — this guard makes it mechanical.

The baseline is **clean**: every ``debugPrint`` call site in ``app/lib`` and
``packages/*/lib`` is already guarded, so this hard-fails with no allowlist.
There is deliberately no opt-out: if a call genuinely must run in release, it
should use a real logging sink, not ``debugPrint``.

Scope is production library code only. Tests, tools, and example code may print
freely — they never ship in a release build.

Exit codes: 0 = all guarded, 1 = at least one unguarded call, 2 = bad input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Production library roots only. `app/lib` plus every `packages/*/lib`.
SEARCH_ROOTS = ("app/lib", "packages")

_CALL_RE = re.compile(r"\bdebugPrint\s*\(")
# An `if` whose condition mentions kDebugMode. Covers the bare `if (kDebugMode)`
# and compound forms like `if (kDebugMode && record.error != null)`.
_GUARD_RE = re.compile(r"\bif\s*\(.*\bkDebugMode\b.*\)")
# Same, but requiring the statement to END at the `)` — i.e. the body is on a
# following line (`if (kDebugMode)\n  debugPrint(...);`) or is a block we track
# via brace depth.
_GUARD_OPEN_RE = re.compile(r"\bif\s*\(.*\bkDebugMode\b.*\)\s*\{?\s*$")
# A guard and the call on one line: `if (kDebugMode) debugPrint('...');`
_GUARD_INLINE_RE = re.compile(r"\bif\s*\(.*\bkDebugMode\b.*\)\s*debugPrint\s*\(")

# `import ... show debugPrint` names the symbol without calling it.
_IMPORT_RE = re.compile(r"^\s*import\s")


def _fail(msg: str, code: int = 2) -> None:
    # `::error::` renders as an annotation in the GitHub Actions UI.
    print(f"::error::{msg}")
    sys.exit(code)


def dart_library_files(root: Path) -> list[Path]:
    """Every production `.dart` file: `app/lib/**` and `packages/*/lib/**`."""
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


def strip_line_comment(line: str) -> str:
    """Blank out a trailing `//` comment, ignoring `//` inside a string.

    Only single-quoted and double-quoted Dart strings are tracked; that is
    enough to keep a `'http://…'` literal from being mistaken for a comment.
    """
    out: list[str] = []
    quote: str | None = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                out.append(line[i : i + 2])
                i += 2
                continue
            if c == quote:
                quote = None
            out.append(c)
        else:
            if c in "'\"":
                quote = c
                out.append(c)
            elif c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
            else:
                out.append(c)
        i += 1
    return "".join(out)


def find_unguarded(text: str) -> list[tuple[int, str]]:
    """Return `(line_number, source_line)` for each unguarded `debugPrint(`.

    A call counts as guarded when any of these holds:

    * it sits inside a `{ … }` block opened by an `if (… kDebugMode …)`;
    * the guard and the call share a line (`if (kDebugMode) debugPrint(…)`);
    * the immediately preceding statement is a braceless `if (… kDebugMode …)`.
    """
    unguarded: list[tuple[int, str]] = []
    raw_lines = text.split("\n")
    # One entry per open brace: True when that block was opened by a kDebugMode
    # `if`. Any enclosing guarded block makes the call guarded.
    depth_guarded: list[bool] = []

    for idx, raw in enumerate(raw_lines):
        line = strip_line_comment(raw)
        opens_guard = bool(_GUARD_OPEN_RE.search(line))
        inline_guard = bool(_GUARD_INLINE_RE.search(line))

        for match in _CALL_RE.finditer(line):
            if _IMPORT_RE.match(line):
                # `import 'package:flutter/foundation.dart' show debugPrint;`
                continue
            guarded = any(depth_guarded) or inline_guard
            if not guarded:
                # Braceless single-statement guard on the previous line.
                prev = ""
                for back in range(idx - 1, -1, -1):
                    candidate = strip_line_comment(raw_lines[back]).strip()
                    if candidate:
                        prev = candidate
                        break
                if _GUARD_RE.search(prev) and prev.endswith(")"):
                    guarded = True
            if not guarded:
                unguarded.append((idx + 1, raw.strip()))
            del match

        for char in line:
            if char == "{":
                depth_guarded.append(opens_guard)
            elif char == "}":
                if depth_guarded:
                    depth_guarded.pop()

    return unguarded


def main() -> int:
    root = REPO_ROOT
    files = dart_library_files(root)
    if not files:
        _fail(f"no Dart library files found under {root} ({SEARCH_ROOTS})")

    offenders: list[str] = []
    call_sites = 0
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if "debugPrint" not in text:
            continue
        call_sites += len(_CALL_RE.findall(text))
        for line_no, src in find_unguarded(text):
            rel = path.relative_to(root)
            offenders.append(f"{rel}:{line_no}: {src}")

    if offenders:
        for offender in offenders:
            print(f"::error::unguarded debugPrint: {offender}")
        print(
            f"::error::{len(offenders)} unguarded debugPrint call(s). Wrap each "
            "in `if (kDebugMode) { … }` — an unguarded call writes to the "
            "system log in release builds (issue #617).",
        )
        return 1

    print(
        f"OK: {call_sites} debugPrint call site(s) across {len(files)} library "
        "file(s), all guarded by kDebugMode.",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
