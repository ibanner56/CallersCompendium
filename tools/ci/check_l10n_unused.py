#!/usr/bin/env python3
"""CI ratchet: every ``app_en.arb`` key must be referenced by app code.

A key that no Dart code under ``app/lib`` reads is dead weight: translators
maintain text nobody sees and ``gen-l10n`` emits an unused getter per locale.
At the commit that introduced this check sixteen such keys existed in all six
ARB files (96 translated strings); nothing stopped the number growing.

The baseline is **clean**, so this hard-fails at zero with no allowlist (same
shape as ``check_debug_print.py``). If a string is only used from a test, it is
still unused by the app: delete it, or use it.

## What counts as a reference

``app/lib/**/*.dart`` **excluding** ``app/lib/l10n/`` (the generated getters
would reference every key), with comments stripped *before* matching, then
``.<key>`` or ``<key>(``. Stripped: ``// ...`` to end of line (this includes
``///`` dartdoc) and ``/* ... */`` (which nests in Dart). ``//`` inside a string
literal is not a comment and is left alone.

Worked example: ``program_matrix_table.dart`` once carried the comment
``// ... rather than folding into `programsMatrixChipQualifiedTitle` ...`` while
the code called ``programsMatrixSectionChipQualifiedTitle``. A plain grep counted
the comment as a use and hid a dead key; with comments stripped the key is
reported.

Pure stdlib and Flutter-free: it reads the ARB as JSON and never runs
``gen-l10n``.

Exit codes: 0 = every key referenced, 1 = at least one unused key, 2 = bad input.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ARB_PATH = Path("app/lib/l10n/app_en.arb")
SCAN_ROOT = Path("app/lib")
GENERATED_DIR = Path("app/lib/l10n")


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(code)


def arb_keys(arb_text: str) -> list[str]:
    """Message keys of an ARB document, in file order, skipping ``@`` metadata."""
    data = json.loads(arb_text)
    if not isinstance(data, dict):
        raise ValueError("ARB root is not an object")
    return [k for k in data if not k.startswith("@")]


def strip_comments(src: str) -> str:
    """Dart source with comments removed and string literals left intact.

    A small state machine rather than a regex so that ``'http://x'`` is not
    truncated at ``//`` and ``/* */`` nests as Dart's do. Newlines inside
    comments are kept so line structure survives.
    """
    out: list[str] = []
    i, n = 0, len(src)
    # Stack of string contexts: (quote, raw, brace_depth_of_interpolation).
    # Empty stack = ordinary code. A string on top with depth None is being
    # read as string text; with an int it is inside a ``${ ... }`` expression.
    strings: list[list] = []  # each: [quote, raw, interp_depth or None]
    while i < n:
        c = src[i]
        top = strings[-1] if strings else None
        in_text = top is not None and top[2] is None
        if in_text:
            quote, raw = top[0], top[1]
            if c == "\\" and not raw:
                out.append(src[i : i + 2])
                i += 2
                continue
            if src.startswith(quote, i):
                out.append(quote)
                i += len(quote)
                strings.pop()
                continue
            if c == "$" and not raw and src.startswith("{", i + 1):
                out.append("${")
                i += 2
                top[2] = 0
                continue
            out.append(c)
            i += 1
            continue
        # Code context (top-level, or inside a ``${ ... }``).
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j == -1 else j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif src.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    if src[j] == "\n":
                        out.append("\n")
                    j += 1
            i = j
            continue
        if top is not None:  # inside ``${ ... }``
            if c == "{":
                top[2] += 1
            elif c == "}":
                if top[2] == 0:
                    top[2] = None
                else:
                    top[2] -= 1
        if c in "'\"":
            raw = i > 0 and src[i - 1] == "r" and (i < 2 or not src[i - 2].isalnum())
            quote = c * 3 if src.startswith(c * 3, i) else c
            strings.append([quote, raw, None])
            out.append(quote)
            i += len(quote)
            continue
        out.append(c)
        i += 1
    return "".join(out)


def referenced(keys: list[str], code: str) -> set[str]:
    """The subset of [keys] read in comment-stripped [code]: ``.key`` or ``key(``."""
    found: set[str] = set()
    for key in keys:
        k = re.escape(key)
        if re.search(rf"\.\s*{k}(?![\w$])|(?<![\w$.]){k}\s*\(", code):
            found.add(key)
    return found


def dart_files(root: Path) -> list[Path]:
    """``app/lib/**/*.dart`` excluding the generated ``app/lib/l10n/`` tree."""
    gen = (root / GENERATED_DIR).resolve()
    return sorted(
        p
        for p in (root / SCAN_ROOT).rglob("*.dart")
        if gen not in p.resolve().parents
    )


def unused_keys(root: Path) -> list[str]:
    arb = root / ARB_PATH
    try:
        keys = arb_keys(arb.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        _fail(f"cannot read {ARB_PATH}: {e}")
    files = dart_files(root)
    if not files:
        _fail(f"no Dart files found under {root / SCAN_ROOT}")
    remaining = set(keys)
    for path in files:
        if not remaining:
            break
        code = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        remaining -= referenced(sorted(remaining), code)
    return [k for k in keys if k in remaining]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    unused = unused_keys(args.root)
    if unused:
        for key in unused:
            print(f"::error::unused ARB key: {key}")
        print(
            f"::error::{len(unused)} ARB key(s) in {ARB_PATH} are never referenced "
            "by app/lib (comments do not count). Delete each key and its @key "
            "block from all six ARB files, or use it. See "
            "tools/ci/check_l10n_unused.py."
        )
        return 1
    print(f"OK: every {ARB_PATH} key is referenced by app code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
