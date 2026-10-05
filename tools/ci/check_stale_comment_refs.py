#!/usr/bin/env python3
"""CI ratchet: comment citations of Dart symbols must resolve to code (count ceiling).

Dartdoc and ordinary comments cite symbols -- ``[Type.member]`` references and
backticked identifiers -- that later get renamed or deleted. A reader following
a dead citation lands nowhere, and an agent "fixing" the cited code edits the
wrong thing (AGENTS.md calls documentation drift the repository's most
persistent defect class). The analyzer's ``comment_references`` lint is off
(hundreds of unresolved references) and cannot see backtick citations at all,
so this check does both, as a **count ceiling**: it fails only when the number
of unresolved citations *rises above* ``stale_comment_refs_ceiling.json``. The
backlog is cleaned up one directory per PR (each claim judged in its own
context, never swept); lowering the ceiling is what makes a cleanup stick.

Scope. Comments (``///``, ``//``, ``/* */``) in ``app/lib``, ``app/test/support``
and ``packages/compendium_core/lib``. Generated files (``*.g.dart``,
``app_localizations*.dart``) are indexed but their comments are not scanned.

What counts as a citation (one finding per distinct name per comment line):

* ``[Name]`` / ``[Type.member]`` -- a dartdoc reference. Not a citation: a
  markdown link (``[text](url)``), an index expression (``foo[0]``, a ``[``
  preceded by a word character, ``)`` or ``]``), or anything that is not a
  dotted identifier (``[a, b]``, ``[1]``).
* `` `name` `` -- a backticked span that *looks like* a Dart identifier: it has
  a lower-to-upper camel boundary (``resolveFoo``, ``DanceLink``), or a leading
  underscore (``_private``), or is ``Type.member`` with a Capitalised first
  segment. A trailing ``()`` is ignored. Plain lowercase words (``main``,
  ``null``), snake_case, file names (``foo.dart``) and code snippets
  (anything with spaces or punctuation) are prose, not citations.
* Text inside a fenced code block in a comment is never scanned.

Resolution. A citation resolves when **every dot-separated segment** is an
identifier token somewhere in the symbol index: the non-comment text of every
``.dart`` file under the three scan roots (string-literal text included, so a
settings or JSON key named in a comment resolves to the literal that defines
it), plus the key set of ``app/lib/l10n/app_en.arb``. Tokens, not
declarations: a member cited as ``Type.member`` is not checked to belong to
``Type`` -- that costs some recall and keeps false positives out of the
ceiling. A tiny stop-list (``this``, ``null``, ``true``, ``false``, ``new``,
``super``, ``void``) is exempt. An ARB key cited only in comments *is* reported
if the key no longer exists in the ARB.

The counting rule is therefore: ``count`` = the number of unresolved
(file, line, name) citations. ``--ceiling N`` overrides the checked-in
ceiling (``tools/ci/stale_comment_refs_ceiling.json``).

Exit codes: 0 = count at or under the ceiling, 1 = over it, 2 = bad input.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Roots whose comments are scanned AND whose code feeds the symbol index.
SCAN_ROOTS = (
    "app/lib",
    "app/test/support",
    "packages/compendium_core/lib",
)
ARB_PATH = "app/lib/l10n/app_en.arb"
CEILING_PATH = Path(__file__).resolve().parent / "stale_comment_refs_ceiling.json"

STOP_LIST = frozenset({"this", "null", "true", "false", "new", "super", "void"})
# `Type.dart` / `README.md`-style file names are not Type.member citations.
_FILE_EXTENSIONS = frozenset(
    {"dart", "md", "json", "arb", "yaml", "yml", "py", "sql", "txt", "html", "png"}
)

_IDENT = r"[A-Za-z_$][A-Za-z0-9_$]*"
_DOTTED_RE = re.compile(rf"^{_IDENT}(?:\.{_IDENT})*$")
_TOKEN_RE = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
_BRACKET_RE = re.compile(r"\[([^\[\]\n]+)\]")
_BACKTICK_RE = re.compile(r"`([^`\n]+)`")
_CAMEL_RE = re.compile(r"[a-z0-9][A-Z]")
_PASCAL_HEAD_RE = re.compile(r"^[A-Z]")
_FENCE_RE = re.compile(r"^\s*```")


@dataclass(frozen=True)
class Comment:
    """One comment line: 1-based [line] and its [text] without the marker."""

    line: int
    text: str


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    name: str
    kind: str  # "dartdoc" | "backtick"

    def render(self) -> str:
        shown = f"[{self.name}]" if self.kind == "dartdoc" else f"`{self.name}`"
        return f"{self.path}:{self.line}: unresolved {self.kind} citation {shown}"


def split_source(text: str) -> tuple[str, list[Comment]]:
    """Split Dart [text] into (code with comments blanked, comment lines).

    The returned code keeps every string literal (their words feed the symbol
    index) and replaces each comment character with a space. A character-stream
    scan, not a per-line regex: ``//`` inside a string (``'https://x'``), nested
    block comments, raw strings, triple-quoted strings and ``${...}``
    interpolations containing their own quotes all change what is a comment.
    """
    code: list[str] = []
    comments: list[Comment] = []
    n = len(text)
    i = 0
    line = 1
    # Stack of lexical states. ("str", quote, raw) | ("interp", brace_depth).
    stack: list[tuple] = []

    def emit_comment(start: int, end: int, first_line: int) -> None:
        body = text[start:end]
        for offset, piece in enumerate(body.split("\n")):
            comments.append(Comment(first_line + offset, piece))

    while i < n:
        c = text[i]
        top = stack[-1] if stack else None
        if c == "\n":
            code.append("\n")
            line += 1
            i += 1
            continue
        if top and top[0] == "str":
            _, quote, raw = top
            if c == "\\" and not raw:
                # Skip the escaped character; an escaped newline is left for the
                # newline branch so line counting stays right.
                code.append(" ")
                i += 1
                if i < n and text[i] != "\n":
                    code.append(text[i])
                    i += 1
                continue
            if text.startswith(quote, i):
                code.append(quote)
                i += len(quote)
                stack.pop()
                continue
            if not raw and text.startswith("${", i):
                code.append("${")
                stack.append(("interp", 1))
                i += 2
                continue
            code.append(c)
            i += 1
            continue
        # Code state (top level or inside an interpolation).
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end == -1 else end
            marker = 3 if text.startswith("///", i) else 2
            emit_comment(i + marker, end, line)
            code.append(" " * (end - i))
            i = end
            continue
        if text.startswith("/*", i):
            depth = 1
            j = i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth += 1
                    j += 2
                elif text.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            body_end = j - 2 if depth == 0 else j
            emit_comment(i + 2, body_end, line)
            span = text[i:j]
            code.append(re.sub(r"[^\n]", " ", span))
            line += span.count("\n")
            i = j
            continue
        if c in "'\"":
            raw = i > 0 and text[i - 1] == "r" and (i < 2 or not _is_word(text[i - 2]))
            quote = text[i : i + 3] if text.startswith(c * 3, i) else c
            stack.append(("str", quote, raw))
            code.append(quote)
            i += len(quote)
            continue
        if top and top[0] == "interp":
            if c == "{":
                stack[-1] = ("interp", top[1] + 1)
            elif c == "}":
                if top[1] == 1:
                    stack.pop()
                else:
                    stack[-1] = ("interp", top[1] - 1)
        code.append(c)
        i += 1
    return "".join(code), comments


def _is_word(ch: str) -> bool:
    return ch.isalnum() or ch in "_$"


def _blocks(comments: list[Comment]) -> list[list[Comment]]:
    """Group consecutive-line comments, so a backtick span wrapped over two
    lines is still one span."""
    blocks: list[list[Comment]] = []
    for comment in comments:
        if blocks and blocks[-1][-1].line + 1 == comment.line:
            blocks[-1].append(comment)
        else:
            blocks.append([comment])
    return blocks


def _looks_like_identifier(name: str) -> bool:
    if not _DOTTED_RE.match(name):
        return False
    segments = name.split(".")
    if len(segments) > 1:
        if segments[-1] in _FILE_EXTENSIONS:
            return False
        return bool(_PASCAL_HEAD_RE.match(segments[0])) or any(
            _is_camel_or_private(s) for s in segments
        )
    return _is_camel_or_private(name)


def _is_camel_or_private(segment: str) -> bool:
    if segment.startswith("_") and len(segment) > 1:
        return True
    return bool(_CAMEL_RE.search(segment))


def citations(comments: list[Comment]) -> list[tuple[int, str, str]]:
    """Every `(line, name, kind)` citation in [comments], deduplicated per line."""
    found: dict[tuple[int, str, str], None] = {}
    for block in _blocks(comments):
        # Drop fenced code (``` toggles within the block); keep line numbers.
        lines: list[Comment] = []
        in_fence = False
        for comment in block:
            if _FENCE_RE.match(comment.text):
                in_fence = not in_fence
                continue
            if not in_fence:
                lines.append(comment)

        for comment in lines:
            text = comment.text
            for m in _BRACKET_RE.finditer(text):
                name = m.group(1).strip()
                before = text[m.start() - 1] if m.start() else ""
                after = text[m.end() : m.end() + 1]
                if after in ("(", "[") or (before and (_is_word(before) or before in ")]")):
                    continue
                if _DOTTED_RE.match(name):
                    found[(comment.line, name, "dartdoc")] = None

        # Backticks: pair spans across the whole block unless a stray backtick
        # makes the count odd, in which case fall back to per-line pairing.
        joined = "\n".join(c.text for c in lines)
        starts = []
        offset = 0
        for c in lines:
            starts.append(offset)
            offset += len(c.text) + 1

        def line_at(pos: int) -> int:
            idx = 0
            for k, s in enumerate(starts):
                if s <= pos:
                    idx = k
            return lines[idx].line

        spans: list[tuple[int, str]] = []
        if joined.count("`") % 2 == 0:
            spans = [(m.start(), m.group(1)) for m in re.finditer(r"`([^`]+)`", joined)]
        else:
            for k, c in enumerate(lines):
                spans += [
                    (starts[k] + m.start(), m.group(1)) for m in _BACKTICK_RE.finditer(c.text)
                ]
        for pos, raw in spans:
            name = raw.strip()
            if name.endswith("()"):
                name = name[:-2]
            if _looks_like_identifier(name):
                found[(line_at(pos), name, "backtick")] = None
    return list(found)


def source_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for rel in SCAN_ROOTS:
        base = root / rel
        if base.is_dir():
            files.extend(sorted(base.rglob("*.dart")))
    return files


def _is_generated(path: Path) -> bool:
    name = path.name
    return name.endswith(".g.dart") or name.startswith("app_localizations")


def arb_keys(root: Path) -> set[str]:
    path = root / ARB_PATH
    if not path.is_file():
        return set()
    data = json.loads(path.read_text(encoding="utf-8"))
    return {k for k in data if not k.startswith("@")}


def scan(root: Path) -> tuple[list[Finding], int]:
    """Return (unresolved findings, number of files scanned)."""
    files = source_files(root)
    parsed: list[tuple[Path, list[Comment]]] = []
    index: set[str] = set(arb_keys(root))
    for path in files:
        code, comments = split_source(path.read_text(encoding="utf-8", errors="replace"))
        index.update(_TOKEN_RE.findall(code))
        if not _is_generated(path):
            parsed.append((path, comments))

    findings: list[Finding] = []
    for path, comments in parsed:
        rel = path.relative_to(root).as_posix()
        for line, name, kind in citations(comments):
            if all(seg in index or seg in STOP_LIST for seg in name.split(".")):
                continue
            findings.append(Finding(rel, line, name, kind))
    findings.sort(key=lambda f: (f.path, f.line, f.name))
    return findings, len(files)


def read_ceiling(path: Path = CEILING_PATH) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    ceiling = data["ceiling"]
    if not isinstance(ceiling, int) or isinstance(ceiling, bool) or ceiling < 0:
        raise ValueError(f"{path}: 'ceiling' must be a non-negative integer")
    return ceiling


def _fail(msg: str, code: int = 2) -> int:
    print(f"::error::{msg}")
    return code


def run(root: Path, ceiling: int | None, quiet: bool = False) -> int:
    if not source_files(root):
        return _fail(f"no Dart files found under {root} ({SCAN_ROOTS})")
    if ceiling is None:
        try:
            ceiling = read_ceiling()
        except (OSError, ValueError, KeyError) as e:
            return _fail(f"cannot read the ceiling ({CEILING_PATH.name}): {e}")
    findings, file_count = scan(root)
    count = len(findings)
    if not quiet:
        for finding in findings:
            print(finding.render())
    if count > ceiling:
        print(
            f"::error::{count} unresolved comment citation(s) exceeds the ceiling of "
            f"{ceiling}. Fix or delete the citation you added (the cited name no "
            "longer exists in code); do not raise the ceiling."
        )
        return 1
    note = ""
    if count < ceiling:
        note = f" Ceiling is {ceiling}: lower {CEILING_PATH.name} to {count}."
    print(
        f"OK: {count} unresolved comment citation(s) across {file_count} file(s), "
        f"ceiling {ceiling}.{note}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--ceiling", type=int, help="override the checked-in ceiling")
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--quiet", action="store_true", help="print only the summary")
    args = parser.parse_args(argv)
    return run(args.root, args.ceiling, args.quiet)


if __name__ == "__main__":
    sys.exit(main())
