#!/usr/bin/env python3
"""Report: how many bytes a session pays for comments when it reads a file.

Comments are not resident context -- they cost nothing until a file is read.
But once read, a file stays in context and is re-sent every remaining turn, so
its cost has the same ``bytes x turns`` shape as `AGENTS.md`, just with a
narrower blast radius. A 96 KB comment block is twelve times the entire resident
budget, paid by every session that opens that file for any reason.

**This is a report, not a ratchet, and that is deliberate.** A cap on comment
bytes would create pressure to delete exactly the comments worth keeping: this
repository's comments are overwhelmingly *why* rather than *what* (measured at
the time of writing: 1,429 comment lines citing an issue number, 141 citing a
design doc, 286 saying "deliberately" or "intentionally", against 45 `Returns
the ...` restatements and no `// TODO` markers). Deleting a rationale does not save the
money, it defers it to the next session that re-derives the reasoning and gets
it wrong. What is worth acting on is *placement*: a decision that is stable and
cross-cutting can live in `docs/design/` behind a one-line pointer, so a session
reading one method stops paying for rationale about six other decisions.

So this prints a number and always exits 0. Treat a file near the top of the
list as a question -- "does a reader of this file need all of this, here?" --
and not as a defect.

Usage:

    python3 tools/ci/report_comment_weight.py             # summary + top files
    python3 tools/ci/report_comment_weight.py --top 40
    python3 tools/ci/report_comment_weight.py --json      # for scripting
    python3 tools/ci/report_comment_weight.py --paths packages/compendium_core

Generated files are excluded: their comments are written by a tool, so the
number would not be actionable and would swamp the files a human can act on.

Measurement caveats, stated because an unqualified number invites more trust
than this one has earned. Lines are classified by their first non-space
characters, so:

- a trailing comment (``x = 1; // why``) counts as code, making this an
  UNDERCOUNT of true comment bytes;
- a line inside a multi-line string that begins with ``//`` or ``/*`` counts as
  a comment, making it an overcount in the rare files that contain one.

Neither is worth a Dart lexer for a number whose purpose is to rank files
against each other. Do not quote it as an exact figure.

Exit codes: 0 = report produced (always, whatever the numbers), 2 = bad input.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

# Where hand-written Dart lives. Anything outside these roots (build output,
# .dart_tool caches, ephemeral platform scaffolding) is not something a session
# reads to understand the code.
DEFAULT_PATHS = ("app/lib", "app/test", "packages")

# Generated Dart, by filename convention and by directory. `l10n/` holds
# `flutter gen-l10n` output: ~6k comment lines of per-string documentation that
# no one wrote and no one can usefully shorten.
GENERATED_SUFFIXES = (".g.dart", ".freezed.dart", ".gen.dart")
GENERATED_DIRS = ("l10n",)

# A generated file that follows neither convention still announces itself in its
# first lines. Both spellings below are emitted by tools in use here.
GENERATED_MARKERS = (
    "GENERATED CODE - DO NOT MODIFY BY HAND",
    "<!-- generated-by:",
    "generated-by:",
)
GENERATED_MARKER_SCAN_LINES = 5

PRUNED_DIRS = {".dart_tool", "build", ".git", ".symlinks", "ephemeral"}

# The always-resident budget from check_agent_context_budget.py. Used here only
# as a yardstick -- "reading this file costs more than every resident rule
# combined" is a more legible statement than a raw byte count.
RESIDENT_BUDGET_BYTES = 8 * 1024


@dataclass
class Weight:
    """Comment and code bytes for one file, or a total over many."""

    comment_bytes: int = 0
    code_bytes: int = 0

    @property
    def total_bytes(self) -> int:
        return self.comment_bytes + self.code_bytes

    @property
    def share(self) -> float:
        """Comment bytes as a fraction of non-blank bytes; 0.0 for an empty file."""
        return self.comment_bytes / self.total_bytes if self.total_bytes else 0.0

    def add(self, other: "Weight") -> None:
        self.comment_bytes += other.comment_bytes
        self.code_bytes += other.code_bytes


def is_generated(path: Path) -> bool:
    if path.name.endswith(GENERATED_SUFFIXES):
        return True
    if any(part in GENERATED_DIRS for part in path.parts):
        return True
    try:
        with path.open(encoding="utf-8", errors="replace") as handle:
            for _, line in zip(range(GENERATED_MARKER_SCAN_LINES), handle):
                if any(marker in line for marker in GENERATED_MARKERS):
                    return True
    except OSError:
        return False
    return False


def measure(text: str) -> Weight:
    """Classify each non-blank line of Dart source as comment or code.

    See the module docstring for what this deliberately does not do.
    """
    weight = Weight()
    in_block = False
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if in_block:
            weight.comment_bytes += len(line)
            if "*/" in stripped:
                in_block = False
            continue
        if not stripped:
            # Blank lines are neither, and counting them would let reformatting
            # move the share without changing a word.
            continue
        if stripped.startswith("//"):
            weight.comment_bytes += len(line)
        elif stripped.startswith("/*"):
            weight.comment_bytes += len(line)
            # A one-line /* ... */ opens and closes on the same line.
            if "*/" not in stripped[2:]:
                in_block = True
        else:
            weight.code_bytes += len(line)
    return weight


def dart_files(root: Path, paths: Sequence[str]) -> Iterable[Path]:
    for relative in paths:
        base = root / relative
        if not base.exists():
            continue
        if base.is_file():
            if base.suffix == ".dart":
                yield base
            continue
        for path in sorted(base.rglob("*.dart")):
            if PRUNED_DIRS.intersection(path.parts):
                continue
            yield path


def collect(root: Path, paths: Sequence[str]) -> dict[Path, Weight]:
    """Map each hand-written Dart file under `paths` to its comment weight."""
    measured: dict[Path, Weight] = {}
    for path in dart_files(root, paths):
        if is_generated(path):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        measured[path.relative_to(root)] = measure(text)
    return measured


def _kib(value: int) -> str:
    return f"{value / 1024:.1f} KiB"


def report(measured: dict[Path, Weight], top: int) -> list[str]:
    lines: list[str] = []
    total = Weight()
    for weight in measured.values():
        total.add(weight)

    if not measured:
        return ["no hand-written Dart found -- check --paths"]

    lines.append(
        f"hand-written Dart: {len(measured)} files, "
        f"{_kib(total.comment_bytes)} comment / {_kib(total.total_bytes)} "
        f"non-blank ({total.share:.0%})"
    )

    heavy = sorted(
        (
            (weight.comment_bytes, path)
            for path, weight in measured.items()
            if weight.comment_bytes > RESIDENT_BUDGET_BYTES
        ),
        reverse=True,
    )
    if heavy:
        heavy_bytes = sum(size for size, _ in heavy)
        lines.append(
            f"{len(heavy)} file(s) carry more comment bytes than the whole "
            f"{_kib(RESIDENT_BUDGET_BYTES)} resident budget "
            f"({heavy_bytes / RESIDENT_BUDGET_BYTES:.0f}x it in total) -- "
            f"one read of each is what a session pays"
        )

    ranked = sorted(
        measured.items(), key=lambda item: item[1].comment_bytes, reverse=True
    )
    shown = ranked[: max(top, 0)]
    if shown:
        lines.append("")
        lines.append(f"heaviest {len(shown)} by comment bytes:")
        for path, weight in shown:
            lines.append(
                f"  {_kib(weight.comment_bytes):>9} comment  "
                f"{weight.share:>4.0%} of file  {path}"
            )
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="repository root (default: current directory)",
    )
    parser.add_argument(
        "--paths",
        nargs="+",
        default=list(DEFAULT_PATHS),
        metavar="PATH",
        help=f"roots to scan (default: {' '.join(DEFAULT_PATHS)})",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=20,
        help="how many of the heaviest files to list (default: 20)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emit per-file numbers as JSON instead of the summary",
    )
    args = parser.parse_args(argv)

    root = args.root
    if not (root / ".github").exists():
        print(f"::error::{root} does not look like the repository root")
        return 2

    measured = collect(root, args.paths)

    if args.json:
        payload = {
            "resident_budget_bytes": RESIDENT_BUDGET_BYTES,
            "files": {
                str(path): {
                    "comment_bytes": weight.comment_bytes,
                    "code_bytes": weight.code_bytes,
                }
                for path, weight in sorted(measured.items())
            },
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    for line in report(measured, args.top):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
