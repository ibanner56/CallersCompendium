#!/usr/bin/env python3
"""CI ratchet: Markdown docs must not cite Dart code by ``file.dart:N`` line number.

A line citation (`` `appearance_section.dart:137` ``) goes stale whenever lines
are added above it, and nothing moves it. It used to be counted only when it
slid onto a blank line, a comment or past the end of the file, so one that slid
onto a *different* line of code passed, and that is the ordinary way they drift
(audit H-05: eight of the 31 left were wrong and the gate read 0). A line number
cannot be checked for meaning, so every one now counts: cite a symbol
(`` `_tagsForMany` in `dance_repository.dart` ``) or the file instead.

This is a **count ceiling**: it fails when the number of line citations differs
from ``doc_line_citations_ceiling.json`` -- above it, a new citation; below it,
a cleanup that did not lower the ceiling and so left slack for the next one.

Scope. ``docs/**/*.md`` except ``docs/dev/audits/`` (dated historical records).

A citation is a backticked ``path.dart:N`` or ``path.dart:N-M``. Each one is a
finding. Its reason says what a reader following it would hit: the path is
resolved as a repo-relative path first, otherwise as a basename or partial path
(``model/x.dart``) that is a path suffix of exactly one of the tracked ``.dart``
files (``git ls-files``; a directory walk when the root is not a git checkout),
and the reason names a missing or ambiguous path, a line past the end of the
file, a blank or comment-only line, or otherwise that the number will drift.

``count`` = the number of (doc, line, citation) occurrences.
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
DRIFTS = "a line number drifts when lines are added above it; cite a symbol or the file"


@dataclass(frozen=True)
class Finding:
    doc: str
    line: int
    citation: str
    reason: str

    def render(self) -> str:
        return f"{self.doc}:{self.line}: line citation `{self.citation}` ({self.reason})"


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
    """Return (resolved repo path, "") or (None, reason).

    An exact repo path wins. Otherwise [path] (a bare basename or a partial
    path such as ``model/x.dart``) must be a path suffix of exactly one tracked
    file.
    """
    if path in files:
        return path, ""
    base = path.rsplit("/", 1)[-1]
    matches = [f for f in by_name.get(base, []) if f == path or f.endswith("/" + path)]
    if len(matches) == 1:
        return matches[0], ""
    if len(matches) > 1:
        return None, f"ambiguous path, {len(matches)} files"
    return None, "file not found"


def check_line(root: Path, rel: str, line: int, cache: dict[str, list[str]]) -> str:
    """Return why a citation of [line] of [rel] fails: what it now lands on, or
    [DRIFTS] when it still lands on code (which may not be the code meant)."""
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
    return DRIFTS


def scan(root: Path) -> tuple[list[Finding], int, int]:
    """Return (findings, markdown files scanned, citations seen).

    Every citation is a finding, so ``seen`` equals ``len(findings)``."""
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
    findings, doc_count, _ = scan(root)
    count = len(findings)
    if not quiet:
        for finding in findings:
            print(finding.render())
    if count > ceiling:
        print(
            f"::error::{count} doc line citation(s) exceeds the ceiling of "
            f"{ceiling}. Cite a symbol or the file instead of a line number; do "
            "not raise the ceiling."
        )
        return 1
    if count < ceiling:
        print(
            f"::error::{count} doc line citation(s) is below the ceiling of "
            f"{ceiling}. Lower {CEILING_PATH.name} to {count} in this change, so "
            "the cleanup sticks and leaves no slack for a new citation."
        )
        return 1
    print(
        f"OK: {count} doc line citation(s) across {doc_count} doc(s), "
        f"ceiling {ceiling}."
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
