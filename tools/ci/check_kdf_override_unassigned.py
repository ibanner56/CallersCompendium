#!/usr/bin/env python3
"""CI ratchet: no production file may assign ``syncIdentityKdfIterations``.

``syncIdentityKdfIterations`` (``packages/compendium_core/lib/src/sync/
sync_storage.dart``) is a ``@visibleForTesting`` override of the PBKDF2
iteration count behind sync identity verifiers, so the sync-heavy test suites
can avoid ~2 s per derivation at the production 600,000 iterations. It is a
mutable global in ``lib/``, so the safety argument is that nothing in
production ever assigns it: its default is the private production constant, and
a marker written at any other count is skipped on decode.

This fails if any file under ``app/lib``, ``packages/*/lib``, ``server/lib``
or ``server/bin``

* assigns it (``=``, ``+=``, ``-=``, ``*=``, ``/=``, ``~/=``, ``??=``, ``++``,
  ``--``) other than at its single declaration, or
* declares it with any default other than ``_syncIdentityKdfIterations``, or
* no longer declares it exactly once (the check would otherwise pass vacuously).

Comments and string literals are masked first, so prose that mentions an
assignment does not trip it. The server counts as production: it depends on
``compendium_core``, so an assignment there lowers the same global. Tests,
tools and examples are out of scope.

Exit codes: 0 = clean, 1 = violation, 2 = bad input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

NAME = "syncIdentityKdfIterations"
DEFAULT = "_syncIdentityKdfIterations"

# The single permitted declaration: `int syncIdentityKdfIterations = <default>;`
# (optionally `var`/`final`-less, with `int`), where <default> must be DEFAULT.
_DECL_RE = re.compile(
    r"(?<![\w$])int\s+" + NAME + r"\s*=\s*(?P<value>[^;]*);"
)
# Any write: plain or compound assignment, or a prefix/postfix increment.
# `==` is a comparison, not a write, so `=` must not be followed by `=`.
_ASSIGN_RE = re.compile(
    r"(?<![\w$])" + NAME + r"\s*(?:[-+*/%&|^]|~/|<<|>>>?|\?\?)?=(?!=)"
    r"|(?<![\w$])" + NAME + r"\s*(?:\+\+|--)"
    r"|(?:\+\+|--)\s*" + NAME + r"(?![\w$])"
)


def mask_source(text: str) -> str:
    """[text] with comments and string-literal text blanked to spaces.

    Same length and newlines preserved, so offsets and line numbers survive.
    Handles `//`, nesting `/* */`, and ordinary, raw and triple-quoted strings.
    Code inside a `${ ... }` interpolation is *executable* Dart, so it is kept
    (and scanned recursively, nested strings included); only the surrounding
    string text is blanked. A raw string has no interpolation and is blanked
    whole.
    """
    res = list(text)
    n = len(text)

    def blank(start: int, end: int) -> None:
        for k in range(start, min(end, n)):
            if res[k] != "\n":
                res[k] = " "

    def string(i: int, raw: bool) -> int:
        """[i] is at the opening quote; returns the index after the closer."""
        quote = text[i : i + 3] if text.startswith(("'''", '"""'), i) else text[i]
        j = i + len(quote)
        while j < n:
            if text.startswith(quote, j):
                return j + len(quote)
            if text[j] == "\\" and not raw:
                blank(j, j + 2)
                j += 2
            elif text.startswith("${", j) and not raw:
                blank(j, j + 2)
                j = code(j + 2, True)
                if j < n:  # the closing `}` of the interpolation
                    blank(j, j + 1)
                    j += 1
            else:
                blank(j, j + 1)
                j += 1
        return j

    def code(i: int, in_interpolation: bool) -> int:
        """Scan code from [i]; inside an interpolation, stop at its `}`."""
        depth = 0
        while i < n:
            c = text[i]
            if text.startswith("/*", i):
                level, j = 1, i + 2
                while j < n and level:
                    if text.startswith("/*", j):
                        level += 1
                        j += 2
                    elif text.startswith("*/", j):
                        level -= 1
                        j += 2
                    else:
                        j += 1
                blank(i, j)
                i = j
            elif text.startswith("//", i):
                end = text.find("\n", i)
                end = n if end == -1 else end
                blank(i, end)
                i = end
            elif c in "'\"":
                i = string(i, i > 0 and text[i - 1] == "r")
            elif in_interpolation and c == "{":
                depth += 1
                i += 1
            elif in_interpolation and c == "}":
                if depth == 0:
                    return i
                depth -= 1
                i += 1
            else:
                i += 1
        return i

    code(0, False)
    return "".join(res)


def _line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def scan(text: str) -> tuple[list[int], list[tuple[int, str]]]:
    """Return `(declaration_lines, violations)` for one file's [text].

    Each violation is `(line, reason)`. A declaration's own `=` is not reported
    as an assignment, but a declaration with a wrong default is.
    """
    masked = mask_source(text)
    declarations: list[int] = []
    violations: list[tuple[int, str]] = []
    declaration_spans: list[tuple[int, int]] = []
    for m in _DECL_RE.finditer(masked):
        line = _line_of(masked, m.start())
        declarations.append(line)
        declaration_spans.append((m.start(), m.end()))
        if m.group("value").strip() != DEFAULT:
            violations.append(
                (line, f"declaration default must be exactly {DEFAULT}")
            )
    for m in _ASSIGN_RE.finditer(masked):
        if any(start <= m.start() < end for start, end in declaration_spans):
            continue
        violations.append(
            (_line_of(masked, m.start()), f"assigns {NAME} in production code")
        )
    return declarations, violations


def dart_library_files(root: Path) -> list[Path]:
    """Every production `.dart` file: `app/lib/**`, `packages/*/lib/**`,
    `server/lib/**` and `server/bin/**`."""
    files: list[Path] = []
    for production in (("app", "lib"), ("server", "lib"), ("server", "bin")):
        directory = root.joinpath(*production)
        if directory.is_dir():
            files.extend(sorted(directory.rglob("*.dart")))
    packages = root / "packages"
    if packages.is_dir():
        for pkg in sorted(p for p in packages.iterdir() if p.is_dir()):
            lib = pkg / "lib"
            if lib.is_dir():
                files.extend(sorted(lib.rglob("*.dart")))
    return files


def main() -> int:
    root = REPO_ROOT
    files = dart_library_files(root)
    if not files:
        print(f"::error::no Dart library files found under {root}")
        return 2

    offenders: list[str] = []
    declared: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if NAME not in text:
            continue
        rel = path.relative_to(root)
        declarations, violations = scan(text)
        declared.extend(f"{rel}:{line}" for line in declarations)
        offenders.extend(f"{rel}:{line}: {why}" for line, why in violations)

    if len(declared) != 1:
        offenders.append(
            f"expected exactly one declaration of {NAME}, found "
            f"{len(declared)} ({', '.join(declared) or 'none'})"
        )

    if offenders:
        for offender in offenders:
            print(f"::error::{offender}")
        print(
            f"::error::{len(offenders)} problem(s) with {NAME}. It is a "
            "test-only override: only tests may assign it, and its default "
            f"must stay {DEFAULT} (600,000 iterations)."
        )
        return 1

    print(
        f"OK: {NAME} is declared once ({declared[0]}) with default {DEFAULT} "
        f"and assigned nowhere in {len(files)} library file(s)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
