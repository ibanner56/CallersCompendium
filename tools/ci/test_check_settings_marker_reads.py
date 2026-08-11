#!/usr/bin/env python3
"""Offline tests for ``check_settings_marker_reads.py`` — the settings-marker
deleted_at ratchet.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_settings_marker_reads.py

## What is tested and why each case is necessary

The ratchet has three independent failure modes, each caught by a specific
subset of cases:

1. **Missing filter on a single-line read** — the straightforward case the
   ratchet exists to catch.

2. **Missing filter on a split-across-lines read** — two of the five compliant
   reads in the real codebase put ``AND deleted_at IS NULL`` on the *next*
   source line. A line-oriented grep would report the first line without the
   filter and fail on correct code. The fix (joining adjacent string literals)
   must be verified explicitly; this is the single most important case because
   it is the easiest to ship incorrectly — a checker that "mostly works" and
   has never been tested against the split form will silently flag correct code
   in the real tree (false positive) or pass incorrect code (false negative if
   the logic happens to be wrong in that direction).

3. **Deliberate DELETE exception** — ``repositories.dart`` does a hard DELETE
   with no ``deleted_at IS NULL``, which is intentionally correct. The DELETE
   must not be flagged regardless of whether the checker uses a SELECT-requiring
   pattern or an explicit exclusion.

4. **Widened scope** — a non-compliant read in a file other than
   ``repositories.dart`` must be caught. The scope is all of ``app/lib`` and
   ``packages/*/lib``, not just one file.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_settings_marker_reads import (  # noqa: E402
    check_file,
    dart_library_files,
    join_adjacent_strings,
)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


# --------------------------------------------------------------------------
# join_adjacent_strings
# --------------------------------------------------------------------------


def test_join_adjacent_strings() -> None:
    print("join_adjacent_strings:")

    check(
        "single-line adjacent literals are joined",
        join_adjacent_strings("'foo' 'bar'") == "'foo bar'",
    )

    check(
        "split across a newline",
        "\n" not in join_adjacent_strings("'foo '\n'bar'")
        and "FROM settings" in join_adjacent_strings(
            "'SELECT 1 FROM settings WHERE key = ? '\n'AND deleted_at IS NULL'"
        ),
        "the newline is removed so the two halves appear on one logical line",
    )

    check(
        "three adjacent literals are fully joined",
        "SELECT" in join_adjacent_strings(
            "'SELECT 1 FROM settings WHERE key = ? '\n"
            "'AND value_json = ? '\n"
            "'AND deleted_at IS NULL'"
        ),
    )

    check(
        "non-adjacent literals are not joined",
        join_adjacent_strings("'a'; 'b'") == "'a'; 'b'",
    )


# --------------------------------------------------------------------------
# check_file helpers — fake root and path
# --------------------------------------------------------------------------


def _check(src: str, filename: str = "packages/fake_pkg/lib/src/fake.dart") -> list[str]:
    """Write *src* to a temp file and run check_file against it."""
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        # Build the directory structure so the file is at the expected path.
        full = root / filename
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(src, encoding="utf-8")
        return check_file(full, root)


def _violation_count(src: str, filename: str = "packages/fake_pkg/lib/src/fake.dart") -> int:
    return len(_check(src, filename))


# --------------------------------------------------------------------------
# Compliant reads — ratchet must stay silent.
# --------------------------------------------------------------------------


def test_compliant_reads() -> None:
    print("compliant reads are not flagged:")

    check(
        "single-line SELECT with deleted_at IS NULL",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',\n"
            "  variables: [v],\n"
            ").get();\n"
        ) == 0,
    )

    check(
        "split-across-lines SELECT with deleted_at IS NULL on the next line",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ? '\n"
            "  'AND deleted_at IS NULL',\n"
            "  variables: [v],\n"
            ").get();\n"
        ) == 0,
        "this is the form that a line-oriented grep gets wrong",
    )

    check(
        "split SELECT with extra condition between key and filter",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ? AND value_json = ? '\n"
            "  'AND deleted_at IS NULL',\n"
            "  variables: [v, w],\n"
            ").get();\n"
        ) == 0,
    )

    check(
        "three-part split with filter on the third line",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT value_json FROM settings '\n"
            "  'WHERE key = ? '\n"
            "  'AND deleted_at IS NULL',\n"
            ").get();\n"
        ) == 0,
    )


# --------------------------------------------------------------------------
# Non-compliant reads — ratchet must fire.
# --------------------------------------------------------------------------


def test_non_compliant_reads() -> None:
    print("non-compliant reads are caught:")

    check(
        "SELECT without any filter is flagged",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ?',\n"
            "  variables: [v],\n"
            ").get();\n"
        ) == 1,
    )

    check(
        "split SELECT where the second part has no filter is flagged",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ? '\n"
            "  'AND value_json = ?',\n"
            "  variables: [v, w],\n"
            ").get();\n"
        ) == 1,
        "the filter is missing even though the read is split — "
        "a ratchet that only checks the first line would miss this",
    )

    check(
        "violation in a different file than repositories.dart is caught",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ?',\n"
            ").get();\n",
            filename="app/lib/src/some_other_file.dart",
        ) == 1,
        "the ratchet covers app/lib and packages/*/lib, not just repositories.dart",
    )


# --------------------------------------------------------------------------
# Deliberate DELETE exception — must not be flagged.
# --------------------------------------------------------------------------


def test_delete_exception() -> None:
    print("deliberate DELETE exception is not flagged:")

    check(
        "hard DELETE without deleted_at IS NULL is not flagged",
        _violation_count(
            "await db.customStatement(\n"
            "  'DELETE FROM settings WHERE key = ?',\n"
            "  [markerKey],\n"
            ");\n"
        ) == 0,
        "a DELETE is not a SELECT; the ratchet only enforces the filter on reads",
    )

    check(
        "DELETE coexisting with a compliant SELECT in the same file",
        _violation_count(
            "// compliant read\n"
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',\n"
            "  variables: [v],\n"
            ").get();\n"
            "// hard delete (no filter needed — not a SELECT)\n"
            "await db.customStatement(\n"
            "  'DELETE FROM settings WHERE key = ?',\n"
            "  [markerKey],\n"
            ");\n"
        ) == 0,
    )


# --------------------------------------------------------------------------
# Negative cases — things that look like reads but must not be flagged.
# --------------------------------------------------------------------------


def test_non_reads() -> None:
    print("non-read statements are not flagged:")

    check(
        "INSERT OR REPLACE INTO settings is not flagged",
        _violation_count(
            "await db.customStatement(\n"
            "  'INSERT OR REPLACE INTO settings (key, value_json) VALUES (?, ?)',\n"
            "  [k, v],\n"
            ");\n"
        ) == 0,
    )

    check(
        "SELECT from a different table is not flagged",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM dances WHERE key = ?',\n"
            ").get();\n"
        ) == 0,
    )

    check(
        "source file with no FROM settings at all is not flagged",
        _violation_count("void f() => 42;\n") == 0,
    )


# --------------------------------------------------------------------------
# Real-tree baseline — the production libraries must be clean.
# --------------------------------------------------------------------------


def test_real_tree_is_clean() -> None:
    """The live baseline: 0 violations across the production libraries.

    This is the ratchet asserting its own premise. If it ever fails, either a
    new non-compliant read landed (add the filter) or the compliant forms in
    use have changed (fix the checker) — do not delete this test.
    """
    print("real tree:")
    root = HERE.parents[1]
    files = dart_library_files(root)
    check("finds library files", len(files) > 0, f"found {len(files)}")

    offenders: list[str] = []
    for path in files:
        offenders.extend(check_file(path, root))

    check("baseline is clean", not offenders, "; ".join(offenders))


def main() -> int:
    test_join_adjacent_strings()
    test_compliant_reads()
    test_non_compliant_reads()
    test_delete_exception()
    test_non_reads()
    test_real_tree_is_clean()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all check_settings_marker_reads tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
