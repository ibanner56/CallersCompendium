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
# Locates a candidate guard; the ACCEPTANCE decision is made by
# [is_debug_guard], not by this pattern. Matching `if (` is cheap; deciding
# whether the condition actually implies debug-only is not, and must fail
# closed.
_IF_RE = re.compile(r"\bif\s*\(")
_KDEBUG_RE = re.compile(r"\bkDebugMode\b")

# `import ... show debugPrint` names the symbol without calling it.
_IMPORT_RE = re.compile(r"^\s*import\s")


def _last_if_condition(code: str) -> str | None:
    """Text inside the parentheses of the LAST `if (` in [code], or `None`.

    Walks balanced parentheses, so a condition containing its own parentheses
    (`if (kDebugMode && (a || b))`) is returned whole rather than truncated at
    the first `)`.
    """
    starts = [m.end() - 1 for m in _IF_RE.finditer(code)]
    if not starts:
        return None
    open_at = starts[-1]
    depth = 0
    for i in range(open_at, len(code)):
        c = code[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return code[open_at + 1 : i]
    # Unbalanced (condition still being accumulated): not yet a guard.
    return None


def is_debug_guard(code: str) -> bool:
    """Whether the last `if (…)` in [code] guarantees `kDebugMode` is true.

    **Fails closed.** This accepts only conditions it can *prove* cannot hold
    when `kDebugMode` is false, and treats everything else as not a guard. The
    asymmetry is deliberate: a false positive costs a contributor one
    restructure, while a false negative ships a release-build log leak — and
    an unrecognised-but-safe form is far likelier than a novel unsafe one.

    Accepted: a bare `kDebugMode` token, alone or in a conjunction
    (`kDebugMode && x`, `x && kDebugMode`).

    Rejected, and each of these previously passed:

    * `!kDebugMode` — inverted. This is the dangerous one: it runs the call
      **only in release**, the exact outcome the ratchet exists to prevent.
    * `kDebugMode || x` — a disjunction is true whenever `x` is, so the call
      can run in release whenever some other flag is set.
    * `kDebugMode == false`, `kDebugMode != true` — inverted via comparison.
    * anything containing `?`, since a ternary's value is not the token's.

    Earlier revisions matched the *shape* of a guard (`if` … `kDebugMode` …
    `)`), which accepts any condition that merely mentions the constant.
    """
    condition = _last_if_condition(code)
    if condition is None:
        return False
    # A disjunction can be satisfied by its other operand, so the whole
    # condition is unusable regardless of where `kDebugMode` sits in it.
    if "||" in condition or "?" in condition:
        return False
    for match in _KDEBUG_RE.finditer(condition):
        before = condition[: match.start()].rstrip()
        after = condition[match.end() :].lstrip()
        # Negated, directly (`!kDebugMode`) or via a comparison operator.
        if before.endswith("!"):
            continue
        if before.endswith(("==", "!=", ">", "<", ">=", "<=")):
            continue
        if after.startswith(("==", "!=", ">", "<", ">=", "<=")):
            continue
        return True
    return False


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


def mask_source(text: str) -> list[str]:
    """Mask every string literal and comment across the whole file.

    Returns one same-length string per input line, with the inside of every
    string literal and every comment replaced by spaces. Column positions are
    preserved because [find_unguarded] compares the offsets of `debugPrint(`
    matches against the offsets of `{` / `}`.

    Masking has to be whole-file rather than per-line because three Dart
    constructs carry lexical state across line boundaries: the two triple-quoted
    string forms, and block comments. Single-line constructs (ordinary quoted
    strings, raw strings, escapes, `${...}` interpolation, `//`) are already
    handled correctly by a per-line scan; these three are not, and they are the
    whole remaining surface.

    Why it matters in both directions. Given

    ```dart
    if (kDebugMode) {
      final sql = '''
        CREATE TRIGGER t BEGIN {
      ''';
    }
    debugPrint('leak');
    ```

    that `{` is text. Counting it pushes a brace frame that then absorbs the `}`
    closing the real guard, leaving the guard on the stack — so the later,
    genuinely unguarded call is blessed. The mirror case is a stray `}` inside a
    comment or literal, which pops a real guard early and makes a properly
    guarded call be reported.

    Dart block comments nest, so `/*` is tracked with a depth counter rather
    than a boolean.
    """
    out: list[list[str]] = [[] for _ in text.split("\n")]
    line = 0
    i = 0
    n = len(text)
    quote: str | None = None  # active string delimiter: ' " ''' or \"\"\"
    block_depth = 0  # nesting depth of /* */
    while i < n:
        c = text[i]
        if c == "\n":
            out[line].append("\n")
            line += 1
            i += 1
            continue
        if block_depth:
            # Dart block comments nest: `/* /* */ */` closes twice.
            if text.startswith("/*", i):
                block_depth += 1
                out[line].append("  ")
                i += 2
                continue
            if text.startswith("*/", i):
                block_depth -= 1
                out[line].append("  ")
                i += 2
                continue
            out[line].append(" ")
            i += 1
            continue
        if quote:
            if c == "\\":
                out[line].append("  "[: len(text[i : i + 2])])
                i += 2
                continue
            if text.startswith(quote, i):
                out[line].append(quote)
                i += len(quote)
                quote = None
                continue
            out[line].append(" ")
            i += 1
            continue
        if text.startswith("/*", i):
            block_depth = 1
            out[line].append("  ")
            i += 2
            continue
        if text.startswith(("'''", '"""'), i):
            quote = text[i : i + 3]
            out[line].append(quote)
            i += 3
            continue
        if c in "'\"":
            quote = c
            out[line].append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            end = text.find("\n", i)
            if end == -1:
                end = n
            out[line].append(" " * (end - i))
            i = end
            continue
        out[line].append(c)
        i += 1
    return ["".join(parts).rstrip("\n") for parts in out]


def mask_line(line: str) -> str:
    """Single-line convenience wrapper around [mask_source].

    Only correct for input that opens and closes any multi-line construct on
    the same line; [mask_source] is the real entry point and is what
    [find_unguarded] uses.
    """
    return mask_source(line)[0]


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
    # Masked once for the whole file: triple-quoted literals span lines, so
    # per-line masking cannot see them.
    masked_lines = mask_source(text)
    # One entry per open brace: True when that block was opened by a condition
    # mentioning kDebugMode. Any enclosing guarded block guards the call.
    depth_guarded: list[bool] = []
    # Code since the last `;`, `{` or `}` — i.e. the statement being built.
    pending = ""

    for idx, raw in enumerate(raw_lines):
        masked = masked_lines[idx]
        call_starts = {m.start() for m in _CALL_RE.finditer(masked)}
        is_import = bool(_IMPORT_RE.match(masked))

        for pos, char in enumerate(masked):
            if pos in call_starts and not is_import:
                # `import ... show debugPrint;` names the symbol, never calls it.
                if not (any(depth_guarded) or is_debug_guard(pending)):
                    unguarded.append((idx + 1, raw.strip()))
            if char == "{":
                depth_guarded.append(is_debug_guard(pending))
                pending = ""
            elif char == "}":
                if depth_guarded:
                    depth_guarded.pop()
                pending = ""
            elif char == ";":
                pending = ""
            else:
                pending += char
        # A space, not a newline, so a condition wrapped over two lines is
        # still one condition to `is_debug_guard`.
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
