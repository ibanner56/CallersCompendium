#!/usr/bin/env python3
"""Ratchet: cap the bytes of instruction text that is resident in every turn.

`AGENTS.md` and every ``.github/instructions/*.instructions.md`` are injected
into an agent's prompt rather than read on demand, so their cost is
``bytes x turns x sessions``. Between 2026-07-22 and 2026-08-14 `AGENTS.md` grew
from 1,181 bytes to 25,589 -- 21.7x, over thirteen commits, every one of them a
net addition and every one individually justified. Nothing was budgeted against,
so the growth was invisible until someone measured the bill.

This gate makes the budget mechanical: a resident file over its cap fails the
build, so a new rule has to *displace* something or move out of residency (a
chapter under ``docs/dev/agents/``, or a path-scoped instruction file whose
``applyTo`` glob keeps it off unrelated sessions).

Path-scoped files get their own, smaller cap and are NOT summed into the root
budget: only the sessions touching their globs pay for them, and summing them
would price a file that most sessions never load as though every session did.

Output is deliberately terse -- one line per file, one line per failure -- so a
red run costs a few hundred tokens to act on rather than a few thousand to read.

Exit codes: 0 = within budget, 1 = over budget, 2 = bad input.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# The always-resident file. 8 KiB is roughly 2k tokens: enough for the rules
# that bind in every session, and small enough that adding one means removing
# one. Raising this number is a decision about every future session's bill, so
# it belongs in a PR that says why.
ROOT_INSTRUCTIONS = Path("AGENTS.md")
ROOT_BUDGET_BYTES = 8 * 1024

# Path-scoped instructions load only for sessions touching their applyTo globs.
# Each is capped on its own; see the module docstring for why they are not summed.
INSTRUCTIONS_DIR = Path(".github/instructions")
SCOPED_GLOB = "*.instructions.md"
SCOPED_BUDGET_BYTES = 6 * 1024

# A scoped file with no applyTo front matter is resident for nothing -- or, worse,
# is silently never loaded while its author believes it is enforced.
FRONT_MATTER_KEY = "applyTo:"


def _measure(path: Path) -> int:
    return len(path.read_bytes())


def _has_apply_to(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return False
    _, _, rest = text.partition("---")
    front_matter, sep, _ = rest.partition("\n---")
    return bool(sep) and FRONT_MATTER_KEY in front_matter


def check(root: Path) -> list[str]:
    """Return a list of failure lines; empty means the tree is within budget."""
    failures: list[str] = []

    root_file = root / ROOT_INSTRUCTIONS
    if not root_file.is_file():
        return [f"{ROOT_INSTRUCTIONS}: missing (the resident agent guide)"]

    size = _measure(root_file)
    print(f"{ROOT_INSTRUCTIONS}: {size} B / {ROOT_BUDGET_BYTES} B resident")
    if size > ROOT_BUDGET_BYTES:
        failures.append(
            f"{ROOT_INSTRUCTIONS}: {size} B exceeds the {ROOT_BUDGET_BYTES} B "
            f"resident budget by {size - ROOT_BUDGET_BYTES} B -- move a rule to "
            f"docs/dev/agents/ or to a path-scoped instruction file"
        )

    scoped_dir = root / INSTRUCTIONS_DIR
    scoped = sorted(scoped_dir.glob(SCOPED_GLOB)) if scoped_dir.is_dir() else []
    for path in scoped:
        rel = path.relative_to(root)
        size = _measure(path)
        print(f"{rel}: {size} B / {SCOPED_BUDGET_BYTES} B path-scoped")
        if size > SCOPED_BUDGET_BYTES:
            failures.append(
                f"{rel}: {size} B exceeds the {SCOPED_BUDGET_BYTES} B "
                f"path-scoped budget by {size - SCOPED_BUDGET_BYTES} B"
            )
        if not _has_apply_to(path):
            failures.append(
                f"{rel}: no `applyTo:` front matter -- it would load for every "
                f"session (or for none) instead of its own paths"
            )

    return failures


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="repository root (default: current directory)",
    )
    args = parser.parse_args(argv)

    root = args.root
    if not (root / "AGENTS.md").exists() and not (root / ".github").exists():
        print(f"::error::{root} does not look like the repository root")
        return 2

    failures = check(root)
    for failure in failures:
        print(f"::error::{failure}")
    if failures:
        print(f"FAIL: {len(failures)} resident-context budget violation(s)")
        return 1
    print("OK: resident agent context is within budget")
    return 0


if __name__ == "__main__":
    sys.exit(main())
