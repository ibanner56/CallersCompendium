#!/usr/bin/env python3
"""Report: a core library change with no ``core`` changelog record in the PR.

``packages/compendium_core`` bumps its version if and only if pending
``changelog.d`` fragments carry ``core`` entries, and release prep compiles those
fragments -- it does not diff the tree. A change under
``packages/compendium_core/lib/`` that ships no ``core`` record is therefore lost
permanently, and it also suppresses the core version bump. Fragment *structure*
is gated (``compile_changelog_fragments.py --check``); fragment *presence* is not.

**This is a report, not a gate, and that is the maintainer's decision** (#2230):
a pure refactor, a test-only change or a docs-only change owes no record, and
telling those apart takes judgement the code reviewer already supplies. A hard
gate would need an exemption mechanism that review already is. So this prints an
advisory and always exits 0. The prose rule in
``.github/skills/code-review/SKILL.md`` stays, because an advisory enforces
nothing.

What it looks at, in the whole PR (``<base>...<head>``, against the merge base):

- Files **added, modified or type-changed** under ``packages/compendium_core/lib/``. Deleted
  files, tests, docs and tooling never trigger it. A *deleted-only* change is
  silent because there is no behaviour left to describe.
- Fragments directly under ``changelog.d/`` that the PR **adds or modifies**. One
  with a non-empty ``core`` record (``user_visible: false`` included) satisfies
  the report; one with only an ``app`` record does not.

If it cannot tell -- an unresolvable ref, a git failure, a fragment that is not
valid JSON -- it prints ``unavailable`` and says why, rather than guessing in
either direction. It still exits 0.

Usage:
    report_missing_core_changelog.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD``. Exit code: always 0.
"""

from __future__ import annotations

import json
import subprocess
import sys

CORE_LIB = "packages/compendium_core/lib/"
FRAGMENT_DIR = "changelog.d/"
# An annotation prefix so a report that cannot answer is visible on the run, not
# only in the step log. A notice, never an error: a report must not look like a failure.
NOTICE = "::notice title=Core changelog advisory::"
# How many files an advisory lists before summarising the rest.
LISTED = 15


class Unavailable(Exception):
    """The report cannot answer; the message says why."""


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], capture_output=True, text=True)


def changed_files(base: str, head: str) -> list[tuple[str, str]]:
    """``(status, path)`` for the whole PR, renames split into delete + add."""
    res = subprocess.run(
        ["git", "diff", "--name-status", "-z", "--no-renames", f"{base}...{head}"],
        capture_output=True,
    )
    if res.returncode != 0:
        detail = res.stderr.decode("utf-8", "replace").strip() or "git diff failed"
        raise Unavailable(f"cannot diff {base}...{head}: {detail}")
    parts = res.stdout.decode("utf-8", "surrogateescape").split("\0")
    entries: list[tuple[str, str]] = []
    # -z output is `STATUS\0path\0STATUS\0path\0...` with a trailing empty field.
    for i in range(0, len(parts) - 1, 2):
        status, path = parts[i], parts[i + 1]
        if status:
            entries.append((status[0], path))
    return entries


def is_fragment(path: str) -> bool:
    """A fragment lives directly in ``changelog.d/``; README.md and subfolders do not count."""
    name = path[len(FRAGMENT_DIR) :] if path.startswith(FRAGMENT_DIR) else ""
    return bool(name) and "/" not in name and name.endswith(".json")


def has_core_record(text: str, path: str) -> bool:
    """Whether a fragment carries a non-empty ``core`` record."""
    try:
        data = json.loads(text)
    except ValueError as error:
        raise Unavailable(f"{path} is not valid JSON ({error})") from error
    if not isinstance(data, dict):
        raise Unavailable(f"{path} is not a JSON object")
    core = data.get("core")
    if not isinstance(core, dict):
        return False
    # A record is a non-blank string in some category, the same floor the
    # compiler holds entries to; an empty list or a blank entry records nothing.
    return any(
        isinstance(items, list) and any(isinstance(item, str) and item.strip() for item in items)
        for items in core.values()
    )


def advise(base: str, head: str) -> list[str]:
    """The lines to print: the advisory, or nothing when none is owed."""
    changes = changed_files(base, head)
    core_files = sorted(
        path for status, path in changes if status != "D" and path.startswith(CORE_LIB)
    )
    if not core_files:
        return []
    for status, path in changes:
        if status != "D" and is_fragment(path):
            shown = _git("show", f"{head}:{path}")
            if shown.returncode != 0:
                raise Unavailable(f"cannot read {path} at {head}")
            if has_core_record(shown.stdout, path):
                return []
    listed = "\n".join(f"  {path}" for path in core_files[:LISTED])
    more = len(core_files) - LISTED
    if more > 0:
        listed += f"\n  ... and {more} more"
    return [
        f"::notice title=Core changelog advisory::{len(core_files)} file(s) under "
        f"{CORE_LIB} changed and no changelog.d fragment in this PR has a `core` "
        "record. Advisory only; it never fails the build.",
        f"Advisory: {len(core_files)} file(s) under {CORE_LIB} changed, and no "
        "fragment this PR adds or modifies carries a `core` record:",
        listed,
        "A pure refactor, a test-only or a docs-only change owes none; say which "
        "it is in the PR. Otherwise add a `core` entry to a changelog.d fragment: "
        "release prep compiles fragments and does not diff the tree, so a missing "
        "entry is lost, and core's version bumps only when core entries exist.",
    ]


def main(argv: list[str]) -> int:
    args = argv[1:]
    try:
        if not 1 <= len(args) <= 2 or not all(a.strip() for a in args):
            raise Unavailable("usage: report_missing_core_changelog.py <base_ref> [head_ref]")
        base = args[0].strip()
        head = args[1].strip() if len(args) == 2 else "HEAD"
        for line in advise(base, head):
            print(line)
    except Unavailable as error:
        print(f"{NOTICE}Core changelog advisory unavailable: {error}")
    except Exception as error:  # noqa: BLE001 -- a report must never fail a build
        print(f"{NOTICE}Core changelog advisory unavailable: unexpected {type(error).__name__}: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
