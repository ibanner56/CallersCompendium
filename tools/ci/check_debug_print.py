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


def mask_line(line: str) -> str:
    """Blank out comments and string *contents*, preserving column positions.

    Returns a same-length string in which a trailing `//` comment and the
    inside of every string literal are replaced by spaces. Positions are
    preserved because [find_unguarded] compares the offsets of `debugPrint(`
    matches against the offsets of `{` / `}`, so the two must agree on columns.

    Masking is what keeps a brace or a `debugPrint(` *inside a string* from
    being read as code — `debugPrint('}')` must not close a block.
    """
    out: list[str] = []
    quote: str | None = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                out.append("  "[: len(line[i : i + 2])])
                i += 2
                continue
            if c == quote:
                quote = None
                out.append(c)
            else:
                out.append(" ")
        else:
            if c in "'\"":
                quote = c
                out.append(c)
            elif c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                out.append(" " * (len(line) - i))
                break
            else:
                out.append(c)
        i += 1
    return "".join(out)


def strip_line_comment(line: str) -> str:
    """Blank out a trailing `//` comment, ignoring `//` inside a string.

    Kept as the narrow, readable form of [mask_line] for the cases that only
    care about comments.
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

    Walks the file as a character stream rather than line by line, because
    guardedness is a **position** property, not a line property. Braces and
    calls are interleaved within a single line in both directions:

    ```dart
    if (kDebugMode) { debugPrint('a'); }   // opens BEFORE the call: guarded
    } debugPrint('b');                     // closes BEFORE the call: NOT
    ```

    Scanning a line's calls before its braces gets the first wrong (a false
    positive) and the second wrong (a false *negative* — an unguarded call
    waved through, which is the direction this ratchet exists to prevent).
    Processing each `{`, `}` and call in offset order is what makes both fall
    out of one rule.

    A call is guarded when either:

    * it is inside a `{ … }` block whose `{` was preceded by a condition
      mentioning `kDebugMode` — this covers the braced form at any nesting
      depth, including a block opened earlier on the same line; or
    * the statement it belongs to is introduced by such a condition — this
      covers `if (kDebugMode) debugPrint(…)` and the braceless two-line form,
      and requires no special case for either.

    `pending` accumulates the code since the last statement boundary (`;`, `{`
    or `}`) and carries across lines, so a condition split over several lines
    is still seen as one.
    """
    unguarded: list[tuple[int, str]] = []
    raw_lines = text.split("\n")
    # One entry per open brace: True when that block was opened by a condition
    # mentioning kDebugMode. Any enclosing guarded block guards the call.
    depth_guarded: list[bool] = []
    # Code since the last `;`, `{` or `}` — i.e. the statement being built.
    pending = ""

    for idx, raw in enumerate(raw_lines):
        masked = mask_line(raw)
        call_starts = {m.start() for m in _CALL_RE.finditer(masked)}
        is_import = bool(_IMPORT_RE.match(masked))

        for pos, char in enumerate(masked):
            if pos in call_starts and not is_import:
                # `import ... show debugPrint;` names the symbol, never calls it.
                if not (any(depth_guarded) or _GUARD_RE.search(pending)):
                    unguarded.append((idx + 1, raw.strip()))
            if char == "{":
                depth_guarded.append(bool(_GUARD_RE.search(pending)))
                pending = ""
            elif char == "}":
                if depth_guarded:
                    depth_guarded.pop()
                pending = ""
            elif char == ";":
                pending = ""
            else:
                pending += char
        # A space, not a newline: `_GUARD_RE`'s `.*` does not cross newlines,
        # and a condition wrapped over two lines is still one condition.
        pending += " "

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
