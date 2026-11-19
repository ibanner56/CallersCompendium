#!/usr/bin/env python3
"""Codemod: put layout literals in ``app/lib`` onto the design tokens.

Re-runnable and idempotent. After merging ``main`` into a branch that touched
the same files, re-run it over the conflicted files instead of hand-merging:

    python3 tools/codemod/spacing_tokens.py            # every file in app/lib
    python3 tools/codemod/spacing_tokens.py FILE...    # only these files
    python3 tools/codemod/spacing_tokens.py --check    # exit 1 if it would change

What it rewrites (UI code only; ``pw.EdgeInsets`` in PDF export is in PDF
points, not logical pixels, and is left alone):

* A bare number that is a whole argument of ``EdgeInsets``/``EdgeInsetsDirectional``
  (``EdgeInsets.all(16)``, ``EdgeInsets.only(left: 8)``, ``fromLTRB(a, b, c, d)``)
  becomes an ``AppSpacing`` token. Off-scale values snap *up* to the next step
  (6 -> 8, 10 -> 12, 20 -> 24): a gap that grows cannot crowd a tap target
  under large text.
* ``BorderRadius.circular(N)`` / ``Radius.circular(N)`` with a literal ``N``
  becomes the matching ``AppShapes`` radius (off-scale values snap to the
  nearest named radius, ties up: 5/6 -> 8, 10 -> 12, 14 and 20 -> 16).

Values it has no token for (1, 7, 56, 72, 80 ...) are left alone: write them
as a sum of tokens (``AppSpacing.xxl + AppSpacing.xs``) by hand. ``0`` is never
rewritten. ``app/test/theme/spacing_literals_test.dart`` and
``radius_tokens_test.dart`` fail on any literal left behind.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "app" / "lib"

SPACING = {
    "2": "xxxs", "4": "xxs", "8": "xs", "12": "sm", "16": "md",
    "24": "lg", "32": "xl", "48": "xxl",
    # Off-scale: snap up.
    "6": "xs", "10": "sm", "20": "lg",
}
RADIUS = {
    "8": "radiusSmall", "12": "radiusMedium", "16": "radiusLarge",
    "28": "radiusDialog",
    # Off-scale: snap to the nearest named radius (ties go up).
    "5": "radiusSmall", "6": "radiusSmall", "10": "radiusMedium",
    "14": "radiusLarge", "20": "radiusLarge",
}
NUM = re.compile(r"^\d+(?:\.0+)?$")


def _balanced(s: str, i: int) -> int:
    """Index just past the ``)`` matching the ``(`` that precedes ``i``."""
    depth = 1
    while depth and i < len(s):
        c = s[i]
        if c in "'\"":  # skip string literals
            q = c
            i += 1
            while i < len(s) and s[i] != q:
                i += 2 if s[i] == "\\" else 1
        depth += (c in "([{") - (c in ")]}")
        i += 1
    return i


def _split_top(args: str) -> list[tuple[int, int]]:
    spans, depth, start, i = [], 0, 0, 0
    while i < len(args):
        c = args[i]
        if c in "'\"":
            q = c
            i += 1
            while i < len(args) and args[i] != q:
                i += 2 if args[i] == "\\" else 1
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            spans.append((start, i))
            start = i + 1
        i += 1
    spans.append((start, len(args)))
    return spans


def _norm(n: str) -> str:
    return re.sub(r"\.0+$", "", n)


def _rewrite_args(args: str, table: dict[str, str], prefix: str) -> str:
    out, last = [], 0
    for a, b in _split_top(args):
        seg = args[a:b]
        m = re.fullmatch(r"(\s*(?:\w+:\s*)?)(\d+(?:\.\d+)?)(\s*)", seg)
        if m and NUM.match(m.group(2)) and _norm(m.group(2)) in table:
            seg = f"{m.group(1)}{prefix}.{table[_norm(m.group(2))]}{m.group(3)}"
        out.append(args[last:a])
        out.append(seg)
        last = b
    out.append(args[last:])
    return "".join(out)


INSETS = re.compile(r"(?<![\w.])(EdgeInsets(?:Directional)?)\.(\w+)\(")
RADII = re.compile(r"(?<![\w.])((?:Border)?Radius)\.circular\(")


def transform(src: str) -> str:
    def sweep(text: str, pat: re.Pattern[str], table, prefix) -> str:
        pos, res = 0, []
        for m in pat.finditer(text):
            if m.start() < pos:
                continue
            end = _balanced(text, m.end())
            inner = text[m.end() : end - 1]
            new = _rewrite_args(inner, table, prefix)
            res.append(text[pos : m.end()])
            res.append(new)
            pos = end - 1
        res.append(text[pos:])
        return "".join(res)

    out = sweep(src, INSETS, SPACING, "AppSpacing")
    out = sweep(out, RADII, RADIUS, "AppShapes")
    # `const` before a call whose arguments are now tokens stays valid
    # (the tokens are compile-time constants), so nothing to strip.
    return out


def _ensure_import(path: Path, text: str, needs: str, module: str) -> str:
    if f"{needs}." not in text or re.search(rf"import\s+'[^']*{module}\.dart';", text):
        return text
    if path.name == f"{module}.dart":
        return text
    rel = Path(
        __import__("os").path.relpath(LIB / "src" / "theme" / f"{module}.dart", path.parent)
    ).as_posix()
    imports = list(re.finditer(r"^import\s+'[^']+';\s*$", text, re.M))
    line = f"import '{rel}';"
    if not imports:
        return line + "\n" + text
    # Keep the relative imports sorted the way dart format / the linter want.
    rels = [m for m in imports if not m.group(0).startswith(("import 'dart:", "import 'package:"))]
    for m in rels:
        if m.group(0) > line:
            return text[: m.start()] + line + "\n" + text[m.start() :]
    anchor = (rels or imports)[-1]
    return text[: anchor.end()] + "\n" + line + text[anchor.end() :]


def process(path: Path) -> bool:
    src = path.read_text()
    out = transform(src)
    out = _ensure_import(path, out, "AppSpacing", "app_spacing")
    out = _ensure_import(path, out, "AppShapes", "app_shapes")
    if out != src:
        path.write_text(out)
        return True
    return False


def main(argv: list[str]) -> int:
    check = "--check" in argv
    files = [Path(a) for a in argv if not a.startswith("--")] or sorted(LIB.rglob("*.dart"))
    changed = []
    for f in files:
        f = f.resolve()
        if "generated" in f.parts or f.name.endswith((".g.dart", ".freezed.dart")):
            continue
        if check:
            if transform(f.read_text()) != f.read_text():
                changed.append(f)
        elif process(f):
            changed.append(f)
    for f in changed:
        print(("would change " if check else "changed ") + str(f.relative_to(ROOT)))
    return 1 if (check and changed) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
