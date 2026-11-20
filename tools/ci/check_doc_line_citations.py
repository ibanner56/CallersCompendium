#!/usr/bin/env python3
"""CI ratchet: ``file.dart:N`` line citations in Markdown docs must still land on code.

Docs cite Dart code by line number (`` `appearance_section.dart:137` ``). Nothing
moves the citation when lines are added above it, so it goes stale silently and a
reader (or an agent) lands on a blank line, a comment, or past the end of the
file. This is a **count ceiling**: it fails when the number of stale citations
differs from ``doc_line_citations_ceiling.json`` -- above it, a new stale
citation; below it, a cleanup that did not lower the ceiling and so left slack
for the next one. It catches the cheap cases only, not every semantic drift;
prefer citing a stable anchor (a symbol or widget key) where one exists.

Scope. ``docs/**/*.md`` except ``docs/dev/audits/`` (dated historical records).

A citation is a backticked ``path.dart:N`` or ``path.dart:N-M``. The path is
resolved as a repo-relative path first; otherwise as a basename that is unique
among the tracked ``.dart`` files (``git ls-files``; a directory walk when the
root is not a git checkout). It is **stale** when

* the path is missing, or the basename is ambiguous;
* the line is past the end of the file; or
* the cited line (the first line of a range) is blank or comment-only
  (``//``, ``///``, ``/*``, ``*``).

``count`` = the number of stale (doc, line, citation) occurrences.
``--ceiling N`` overrides the checked-in ceiling
(``tools/ci/doc_line_citations_ceiling.json``).

Exit codes: 0 = count equals the ceiling, 1 = over or under it, 2 = bad input.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CEILING_PATH = Path(__file__).resolve().parent / "doc_line_citations_ceiling.json"
DOCS_DIR = "docs"
EXCLUDED_PREFIXES = ("docs/dev/audits/",)

_CITATION_RE = re.compile(r"`([A-Za-z0-9_./\-]+\.dart):(\d+)(?:[-–](\d+))?`")
_COMMENT_PREFIXES = ("//", "/*", "*")


@dataclass(frozen=True)
class Finding:
    doc: str
    line: int
    citation: str
    reason: str

    def render(self) -> str:
        return f"{self.doc}:{self.line}: stale citation `{self.citation}` ({self.reason})"


def markdown_files(root: Path) -> list[Path]:
    base = root / DOCS_DIR
    if not base.is_dir():
        return []
    return [
        p
        for p in sorted(base.rglob("*.md"))
        if not p.relative_to(root).as_posix().startswith(EXCLUDED_PREFIXES)
    ]


def dart_files(root: Path) -> list[str]:
    """Repo-relative posix paths of tracked ``.dart`` files."""
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--", "*.dart"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        files = [f for f in out.split("\0") if f]
        if files:
            return sorted(files)
    except (OSError, subprocess.CalledProcessError):
        pass
    return sorted(p.relative_to(root).as_posix() for p in root.rglob("*.dart"))


def resolve(path: str, files: set[str], by_name: dict[str, list[str]]) -> tuple[str | None, str]:
    """Return (resolved repo path, "") or (None, reason)."""
    if path in files:
        return path, ""
    if "/" not in path:
        matches = by_name.get(path, [])
        if len(matches) == 1:
            return matches[0], ""
        if len(matches) > 1:
            return None, f"ambiguous basename, {len(matches)} files"
    return None, "file not found"


def check_line(root: Path, rel: str, line: int, cache: dict[str, list[str]]) -> str:
    """Return "" when [line] of [rel] is code, else the reason it is stale."""
    if rel not in cache:
        text = (root / rel).read_text(encoding="utf-8", errors="replace")
        cache[rel] = text.splitlines()
    lines = cache[rel]
    if line < 1 or line > len(lines):
        return f"line {line} is past the end of {rel} ({len(lines)} lines)"
    stripped = lines[line - 1].strip()
    if not stripped:
        return f"line {line} of {rel} is blank"
    if stripped.startswith(_COMMENT_PREFIXES):
        return f"line {line} of {rel} is only a comment"
    return ""


def scan(root: Path) -> tuple[list[Finding], int, int]:
    """Return (stale findings, markdown files scanned, citations seen)."""
    files = dart_files(root)
    file_set = set(files)
    by_name: dict[str, list[str]] = {}
    for f in files:
        by_name.setdefault(f.rsplit("/", 1)[-1], []).append(f)
    cache: dict[str, list[str]] = {}
    findings: list[Finding] = []
    docs = markdown_files(root)
    seen = 0
    for doc in docs:
        rel_doc = doc.relative_to(root).as_posix()
        for n, text in enumerate(doc.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for m in _CITATION_RE.finditer(text):
                seen += 1
                path, start = m.group(1), int(m.group(2))
                shown = m.group(0).strip("`")
                resolved, reason = resolve(path, file_set, by_name)
                if resolved is not None:
                    reason = check_line(root, resolved, start, cache)
                if reason:
                    findings.append(Finding(rel_doc, n, shown, reason))
    return findings, len(docs), seen


def read_ceiling(path: Path = CEILING_PATH) -> int:
    ceiling = json.loads(path.read_text(encoding="utf-8"))["ceiling"]
    if not isinstance(ceiling, int) or isinstance(ceiling, bool) or ceiling < 0:
        raise ValueError(f"{path}: 'ceiling' must be a non-negative integer")
    return ceiling


def _fail(msg: str, code: int = 2) -> int:
    print(f"::error::{msg}")
    return code


def run(root: Path, ceiling: int | None, quiet: bool = False) -> int:
    if not markdown_files(root):
        return _fail(f"no Markdown files found under {root / DOCS_DIR}")
    if ceiling is None:
        try:
            ceiling = read_ceiling()
        except (OSError, ValueError, KeyError) as e:
            return _fail(f"cannot read the ceiling ({CEILING_PATH.name}): {e}")
    findings, doc_count, seen = scan(root)
    count = len(findings)
    if not quiet:
        for finding in findings:
            print(finding.render())
    if count > ceiling:
        print(
            f"::error::{count} stale doc line citation(s) exceeds the ceiling of "
            f"{ceiling}. Update the citation you broke (or cite a symbol instead "
            "of a line); do not raise the ceiling."
        )
        return 1
    if count < ceiling:
        print(
            f"::error::{count} stale doc line citation(s) is below the ceiling of "
            f"{ceiling}. Lower {CEILING_PATH.name} to {count} in this change, so "
            "the cleanup sticks and leaves no slack for a new stale citation."
        )
        return 1
    print(
        f"OK: {count} stale doc line citation(s) of {seen} across {doc_count} "
        f"doc(s), ceiling {ceiling}."
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
