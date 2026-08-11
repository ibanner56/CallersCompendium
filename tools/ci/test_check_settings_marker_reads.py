#!/usr/bin/env python3
"""Offline tests for ``check_settings_marker_reads.py`` — the settings-marker
deleted_at ratchet.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_settings_marker_reads.py

## What is tested and why each case is necessary

1. **Missing filter on a single-line read** — the straightforward case the
   ratchet exists to catch. Tested for both single-quoted and double-quoted
   SQL strings, since Dart style in this repo uses both.

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

5. **Filter in a non-SQL context does not satisfy the check** — if
   ``deleted_at IS NULL`` appears in a Dart variable or argument string in the
   same statement but outside the SQL literal, the ratchet must still fire. The
   check must be restricted to the SQL string itself, not the surrounding Dart
   statement. (Discovered in review: a probe that passes the phrase as a
   variable value produced a false negative in an earlier implementation.)

6. **Double-quoted SQL strings are handled correctly in both directions** —
   both compliant and non-compliant double-quoted reads must be detected and
   reported (or passed) correctly. (Discovered in review: the literal-scoping
   fix for finding 5 introduced a regression where double-quoted compliant reads
   failed to find the closing quote and were incorrectly flagged.)

7. **Correct line numbers when SELECT and WHERE key span different literals** —
   when ``SELECT … FROM settings`` is in one adjacent literal and ``WHERE key``
   is in the next, the un-joined text has no single-line match. An earlier
   implementation fell back to ``:0: (unknown)`` in that case. The
   ``extract_sql_literals`` function preserves the source line of the opening
   literal so every violation has a real file:line location. (Discovered in
   review round 4.)

8. **No fast path on raw text** — the ``settings`` prefilter was removed because
   any substring check on un-joined text is defeatable by splitting the target
   word across adjacent literals (e.g. ``'sett' + 'ings'``). The clean-room
   probe below uses a fixture file that contains no other occurrence of
   ``settings`` so the test proves the fix rather than passing by coincidence.
   (Discovered in review round 7.)
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_settings_marker_reads import (  # noqa: E402
    SqlLiteral,
    _BOUNDARY_UNKNOWN,
    _MISSING_FILTER,
    check_file,
    dart_library_files,
    extract_sql_literals,
)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


# --------------------------------------------------------------------------
# extract_sql_literals
# --------------------------------------------------------------------------


def test_extract_sql_literals() -> None:
    print("extract_sql_literals:")

    # Adjacent literals are joined with empty string (Dart semantics).
    lits = [l for l in extract_sql_literals("'foo''bar'") if l.parseable]
    check(
        "adjacent literals with no whitespace are joined with empty string (Dart semantics)",
        len(lits) == 1 and lits[0].content == "foobar",
        f"got {[l.content for l in lits]}",
    )

    lits = [l for l in extract_sql_literals("'foo '\n'bar'") if l.parseable]
    check(
        "adjacent literals split across a newline are joined",
        len(lits) == 1 and lits[0].content == "foo bar",
        f"got {[l.content for l in lits]}",
    )

    lits = [l for l in extract_sql_literals("'foo '; 'bar'") if l.parseable]
    check(
        "semicolon-separated literals are NOT joined",
        len(lits) == 2,
        f"got {[l.content for l in lits]}",
    )

    lits = [l for l in extract_sql_literals(
        "'SELECT 1 FROM settings WHERE key = ? '\n'AND deleted_at IS NULL'"
    ) if l.parseable]
    check(
        "split SQL literal joins to contain FROM settings",
        len(lits) == 1 and "FROM settings" in lits[0].content,
        f"got {[l.content for l in lits]}",
    )

    lits = [l for l in extract_sql_literals(
        "'SELECT 1 FROM '\n'settings WHERE key = ?'"
    ) if l.parseable]
    check(
        "FROM split across adjacent literals is joined to contain FROM settings",
        len(lits) == 1 and "FROM settings" in lits[0].content,
        f"got {[l.content for l in lits]}",
    )

    lits = [l for l in extract_sql_literals(
        "'SELECT 1 FROM settings WHERE key = ?'\n'AND deleted_at IS NULL'"
    ) if l.parseable]
    check(
        "no-trailing-space join produces ?AND (Dart empty-string concatenation semantics)",
        len(lits) == 1 and "?AND" in lits[0].content,
        f"got {[l.content for l in lits]}",
    )

    lits = [l for l in extract_sql_literals('"foo "\n"bar"') if l.parseable]
    check(
        "double-quoted adjacent literals are joined",
        len(lits) == 1 and lits[0].content == "foo bar",
        f"got {[l.content for l in lits]}",
    )

    # Mixed-quote adjacency: Dart allows 'foo' "bar" (= 'foobar').
    lits = [l for l in extract_sql_literals("'foo ' \"bar\"") if l.parseable]
    check(
        "mixed-quote adjacent literals are joined ('…' + \"…\")",
        len(lits) == 1 and lits[0].content == "foo bar",
        f"got {[l.content for l in lits]}",
    )

    # --- Table-driven adjacency contract ------------------------------------------
    # The rule: a run of adjacent Dart string literals is ONE group. The group is
    # parseable only if every member is a plain (non-raw, non-triple-quoted) literal.
    # Quote style (single vs double) does not break adjacency.
    #
    # Every cell asserts (group count, parseable flag, content membership).
    #
    # Axes enumerated:
    #   Forms:     N = normal quoted  |  R = raw (r'...')  |  T = triple-quoted ('''...''')
    #   Positions: first literal × second literal (both orderings matter)
    #   Quote:     same (=) vs different (≠)  [only meaningful for N+N]
    #   Separator: whitespace | // comment    [tested once each, others implied]
    #
    # Rows dropped as genuinely impossible in Dart:
    #   R+R, T+T, R+T, T+R: Dart does allow these, but they cannot interact with
    #   the ratchet in a way that produces a different outcome from R+N/T+N (both
    #   are unparseable regardless), so they add rows without adding coverage.
    #   If they are ever needed, add them.
    #
    # The contract is symmetric for ordering: r'foo' 'bar' and 'foo' r'bar' both
    # produce one unparseable group. Earlier implementations were NOT symmetric —
    # the look-ahead only ran forward from a parseable-first literal. Rows R+N and
    # T+N below are the ones that were wrong and must be pinned explicitly.
    # --------------------------------------------------------------------------

    # N+N same quote → one parseable group
    g = extract_sql_literals("'ab' 'cd'")
    check("N+N(=): one parseable group, content joined",
          len(g) == 1 and g[0].parseable and g[0].content == "abcd", f"got {g}")

    # N+N different quote → one parseable group
    g = extract_sql_literals("'ab' \"cd\"")
    check("N+N(≠): one parseable group, content joined",
          len(g) == 1 and g[0].parseable and g[0].content == "abcd", f"got {g}")

    # N+R → one unparseable group; content = both fragments
    g = extract_sql_literals("'SELECT ' r'WHERE key = ?'")
    check(
        "N+R: one unparseable group, content includes both fragments",
        len(g) == 1 and not g[0].parseable
        and "SELECT" in g[0].content and "WHERE key" in g[0].content,
        f"got {g}",
    )

    # R+N → one unparseable group; content = both fragments  (symmetric with N+R)
    g = extract_sql_literals("r'SELECT ' 'WHERE key = ?'")
    check(
        "R+N: one unparseable group, content includes both fragments",
        len(g) == 1 and not g[0].parseable
        and "SELECT" in g[0].content and "WHERE key" in g[0].content,
        f"got {g}",
    )

    # N+T → one unparseable group; content = both fragments
    g = extract_sql_literals("'SELECT ' '''WHERE key = ?'''")
    check(
        "N+T: one unparseable group, content includes both fragments",
        len(g) == 1 and not g[0].parseable
        and "SELECT" in g[0].content and "WHERE key" in g[0].content,
        f"got {g}",
    )

    # T+N → one unparseable group; content = both fragments  (symmetric with N+T)
    g = extract_sql_literals("'''SELECT ''' 'WHERE key = ?'")
    check(
        "T+N: one unparseable group, content includes both fragments",
        len(g) == 1 and not g[0].parseable
        and "SELECT" in g[0].content and "WHERE key" in g[0].content,
        f"got {g}",
    )

    # N+N+R → one unparseable group; content = all three fragments
    g = extract_sql_literals("'SELECT ' 'FROM settings ' r'WHERE key = ?'")
    check(
        "N+N+R: one unparseable group, content includes all three fragments",
        len(g) == 1 and not g[0].parseable
        and "SELECT" in g[0].content and "FROM settings" in g[0].content and "WHERE key" in g[0].content,
        f"got {g}",
    )

    # R+N+N → one unparseable group; content = all three fragments  (symmetric)
    g = extract_sql_literals("r'SELECT ' 'FROM settings ' 'WHERE key = ?'")
    check(
        "R+N+N: one unparseable group, content includes all three fragments",
        len(g) == 1 and not g[0].parseable
        and "SELECT" in g[0].content and "FROM settings" in g[0].content and "WHERE key" in g[0].content,
        f"got {g}",
    )

    # // comment between N+N → comment consumed, still one parseable group
    g = extract_sql_literals("'ab' // comment\n'cd'")
    check(
        "N // comment N: comment between literals consumed, still one parseable group",
        len(g) == 1 and g[0].parseable and g[0].content == "abcd",
        f"got {g}",
    )

    # Raw and triple-quoted forms are unparseable.
    raw_lits = extract_sql_literals("r'SELECT 1 FROM settings WHERE key = ?'")
    check(
        "raw-string literal is unparseable",
        any(not l.parseable for l in raw_lits),
        f"got {raw_lits}",
    )

    triple_lits = extract_sql_literals(
        "'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL'"[:0]
        + "'''" + "SELECT 1 FROM settings WHERE key = ?" + "'''"
    )
    check(
        "triple-quoted literal is unparseable",
        any(not l.parseable for l in triple_lits),
        f"got {triple_lits}",
    )

    # Line number of the opening quote.  The two literals must not be adjacent
    # (i.e. they must be separated by a non-whitespace token) so the SELECT is
    # its own literal group with its own line number.
    src = "String x = 'first';\n'SELECT 1 FROM settings WHERE key = ?'"
    lits = [l for l in extract_sql_literals(src) if l.parseable and "SELECT" in l.content]
    check(
        "line number is 2 for SELECT literal on second source line",
        len(lits) == 1 and lits[0].line_no == 2,
        f"got {[(l.line_no, l.content[:40]) for l in lits]}",
    )


# --------------------------------------------------------------------------
# check_file helpers — fake root and path
# --------------------------------------------------------------------------


def _check(
    src: str, filename: str = "packages/fake_pkg/lib/src/fake.dart"
) -> list[tuple[str, str]]:
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


def _kinds(src: str, filename: str = "packages/fake_pkg/lib/src/fake.dart") -> list[str]:
    """Return the violation kind strings for *src* (``_MISSING_FILTER`` or
    ``_BOUNDARY_UNKNOWN``), without the location detail."""
    return [kind for kind, _loc in _check(src, filename)]


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

    check(
        "double-quoted single-line SELECT with deleted_at IS NULL",
        _violation_count(
            'final r = db.customSelect(\n'
            '  "SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL",\n'
            '  variables: [v],\n'
            ').get();\n'
        ) == 0,
        "double-quoted SQL strings are used in this repo and must not be falsely flagged",
    )

    check(
        "double-quoted filter in variable does not satisfy check",
        _violation_count(
            'final r = db.customSelect(\n'
            '  "SELECT 1 FROM settings WHERE key = ?",\n'
            '  variables: ["deleted_at IS NULL"],\n'
            ').get();\n'
        ) == 1,
        "the phrase is in a Dart argument, not the SQL literal — must still fail",
    )

    check(
        "mixed-quote split: single-quoted SELECT, double-quoted filter continuation — compliant",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ? '\n"
            '  "AND deleted_at IS NULL",\n'
            "  variables: [v],\n"
            ").get();\n"
        ) == 0,
        "Dart allows 'foo' \"bar\" adjacency; the joiner must cross quote styles",
    )

    check(
        "mixed-quote split: double-quoted SELECT, single-quoted filter continuation — compliant",
        _violation_count(
            "final r = db.customSelect(\n"
            '  "SELECT 1 FROM settings WHERE key = ? "\n'
            "  'AND deleted_at IS NULL',\n"
            "  variables: [v],\n"
            ").get();\n"
        ) == 0,
        "reverse order: double-quoted opening literal, single-quoted continuation",
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

    check(
        "filter in a Dart variable outside the SQL string is not accepted",
        _violation_count(
            "Future<void> f(dynamic db) async {\n"
            "  await db.customSelect(\n"
            "    'SELECT 1 FROM settings WHERE key = ?',\n"
            "    variables: ['deleted_at IS NULL'],\n"
            "  ).get();\n"
            "}\n"
        ) == 1,
        "the phrase appears as a Dart string argument, not in the SQL literal — "
        "the ratchet must check the SQL string only, not the surrounding statement",
    )

    check(
        "double-quoted SELECT without filter is flagged",
        _violation_count(
            'final r = db.customSelect(\n'
            '  "SELECT 1 FROM settings WHERE key = ?",\n'
            '  variables: [v],\n'
            ').get();\n'
        ) == 1,
        "double-quoted SQL strings must be checked too",
    )

    check(
        "FROM split across adjacent literals is flagged (prefilter bypass closed)",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM '\n"
            "  'settings WHERE key = ?',\n"
            ").get();\n"
        ) == 1,
        "earlier implementation skipped files where 'FROM' and 'settings' were in "
        "different adjacent literals — the prefilter must use the joined content",
    )

    check(
        "no-trailing-space split is flagged (?AND has no preceding space — invalid SQL)",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ?'\n"
            "  'AND deleted_at IS NULL',\n"
            ").get();\n"
        ) == 1,
        "empty-string join produces '...key = ?AND deleted_at IS NULL'; "
        "the filter regex requires \\s+AND so ?AND does not match. "
        "This SQL is also invalid at runtime (SQLite parse error) so flagging is correct.",
    )

    # Clean-room probe: the fixture file contains NO other occurrence of the
    # word 'settings', so a raw-text prefilter on 'settings' would skip the file
    # entirely and the test would pass for the wrong reason. The split 'sett'+'ings'
    # ensures the only occurrence of the word is reconstructed by the joiner.
    _clean_room_src = (
        "// This file deliberately contains no standalone occurrence of the\n"
        "// word 'sett' + 'ings' outside of the literal below, so a raw-text\n"
        "// prefilter would skip it. The ratchet must still catch the read.\n"
        "Future<void> f(dynamic db) async {\n"
        "  await db.customSelect(\n"
        "    'SELECT 1 FROM sett'\n"
        "    'ings WHERE key = ?',\n"
        "  ).get();\n"
        "}\n"
    )
    check(
        "split-word bypass is caught (clean-room: no other occurrence of 'settings' in file)",
        _violation_count(_clean_room_src) == 1,
        "a prefilter on un-joined text would skip this file because 'settings' "
        "does not appear as a whole word; only the joiner reconstructs it",
    )

    check(
        "mixed-quote bypass: unfiltered read using 'SELECT…' + \"WHERE key…\" is flagged",
        _violation_count(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings '\n"
            '  "WHERE key = ?",\n'
            "  variables: [v],\n"
            ").get();\n"
        ) == 1,
        "an earlier implementation only joined same-quote adjacent literals; "
        "this cross-quote split was a complete bypass",
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

    check(
        "raw-string UI prose containing 'settings' is not flagged",
        _violation_count(
            "const helpText = r'Open settings to change your preferences.';\n"
        ) == 0,
        "a raw string that mentions settings but is not a SQL read must not "
        "trigger the fail-closed path — ~85 such strings exist in the corpus today",
    )


# --------------------------------------------------------------------------
# Fail-closed path — raw and triple-quoted literals.
# --------------------------------------------------------------------------


def test_fail_closed() -> None:
    """Unparseable literal boundaries fail closed with a distinct message.

    There are no raw or triple-quoted SQL strings in the real tree today, so
    this branch is unreachable in the baseline scan. That makes it the easiest
    to break silently — a branch that the corpus never exercises and that has
    no test is indistinguishable from one that is broken. These cases pin both
    the exit behaviour (violation reported) and the violation kind
    (``_BOUNDARY_UNKNOWN``, not ``_MISSING_FILTER``), so a later change that
    collapses the two paths goes red here.
    """
    print("fail-closed path (unparseable boundaries):")

    check(
        "raw-string read fails closed with BOUNDARY_UNKNOWN, not MISSING_FILTER",
        _kinds(
            "final r = db.customSelect(\n"
            "  r'SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL',\n"
            ").get();\n"
        ) == [_BOUNDARY_UNKNOWN],
        "the filter is present but the raw-string boundary cannot be parsed — "
        "the error message must say so, not claim the filter is missing",
    )

    check(
        "triple-quoted read fails closed with BOUNDARY_UNKNOWN",
        _kinds(
            "final r = db.customSelect(\n"
            "  '''SELECT 1 FROM settings WHERE key = ? AND deleted_at IS NULL''',\n"
            ").get();\n"
        ) == [_BOUNDARY_UNKNOWN],
        "triple-quoted boundary cannot be determined — must not silently pass",
    )

    check(
        "normal+raw split: unfiltered read is flagged (not silently dropped)",
        _kinds(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings '\n"
            "  r'WHERE key = ?',\n"
            ").get();\n"
        ) == [_BOUNDARY_UNKNOWN],
        "without content accumulation the parseable half has no WHERE key and both "
        "branches miss it — the read disappears entirely instead of failing closed",
    )

    check(
        "normal+raw split: even with filter present, fails closed (boundary unknown)",
        _kinds(
            "final r = db.customSelect(\n"
            "  'SELECT 1 FROM settings WHERE key = ? '\n"
            "  r'AND deleted_at IS NULL',\n"
            ").get();\n"
        ) == [_BOUNDARY_UNKNOWN],
        "filter is in the raw fragment; the whole group is unparseable so we fail closed",
    )

    check(
        "raw+normal split: unfiltered read is flagged (not silently dropped)",
        _kinds(
            "final r = db.customSelect(\n"
            "  r'SELECT 1 FROM settings '\n"
            "  'WHERE key = ?',\n"
            ").get();\n"
        ) == [_BOUNDARY_UNKNOWN],
        "symmetric case: raw-first adjacency must produce one unparseable group, not two separate ones",
    )


# --------------------------------------------------------------------------
# Line-number mapping — SELECT and WHERE key in different adjacent literals.
# --------------------------------------------------------------------------


def test_line_number_mapping() -> None:
    """Violations in split-literal form report a real line number.

    When ``SELECT … FROM settings`` and ``WHERE key`` are in different
    adjacent Dart string literals, the un-joined original text has no
    single-line pattern match. An earlier implementation indexed into
    ``orig_matches`` (computed on the un-joined text) and fell off the end,
    producing ``:0: (unknown)`` — correct detection but useless location.

    The offset map returned by ``join_adjacent_strings`` must translate the
    match position back to the original source line so CI annotations point
    at the actual code.
    """
    print("line-number mapping for split-literal violations:")

    src = (
        "// line 1\n"
        "await db.customSelect(\n"         # line 2
        "  'SELECT 1 FROM settings '\n"    # line 3  ← expected reported line
        "  'WHERE key = ?',\n"             # line 4
        ").get();\n"                        # line 5
    )
    violations = _check(src)
    check(
        "split-literal violation is caught",
        len(violations) == 1,
        f"expected 1 violation, got {len(violations)}",
    )
    if violations:
        _kind, loc = violations[0]
        # Location must be "…:3: …" (the line with SELECT), not "…:0: …"
        parts = loc.split(":")
        reported_line = int(parts[1]) if len(parts) >= 2 and parts[1].isdigit() else 0
        check(
            "split-literal violation reports a real line number (not 0)",
            reported_line != 0,
            f"location was: {loc}",
        )
        check(
            "split-literal violation reports the SELECT line (line 3)",
            reported_line == 3,
            f"expected line 3, got line {reported_line}; location was: {loc}",
        )


# --------------------------------------------------------------------------
# Adjacency matrix — every {first form} × {second form} × {quote style}
# × {separator} combination, enumerated rather than discovered in review.
# --------------------------------------------------------------------------


def test_adjacency_matrix() -> None:
    """Every combination of adjacent-literal forms, enumerated rather than
    discovered one review round at a time.

    The contract being pinned, in one sentence: **a run of adjacent string
    literals is one group, and the group is parseable only if every member is
    a plain quoted literal.** Dart concatenates adjacent literals at compile
    time regardless of quote style, so `'a' "b"` is one string; and a raw or
    triple-quoted member makes the whole group unparseable, because the
    scanner cannot reliably find its boundaries.

    Five separate bugs in this scanner were violations of that one rule in
    different places: the separator (space vs empty), the raw/triple prefixes,
    a raw-text fast path, the quote style of the next literal, and the *order*
    of a raw/normal pair. Each was found in review, one direction at a time —
    twice, a round fixed one direction of a two-directional case and shipped
    the other. Enumerating the space is what stops that.

    Splitting a group is the dangerous failure, not a wrong parseable flag: a
    settings read split across two groups matches neither the SELECT pattern
    (one half lacks `WHERE key`) nor the fail-closed branch (the other lacks
    `SELECT`), so the read disappears silently instead of failing loudly.
    """
    print("adjacency matrix:")

    def make(kind: str, quote: str, text: str) -> str:
        if kind == "normal":
            return f"{quote}{text}{quote}"
        if kind == "raw":
            return f"r{quote}{text}{quote}"
        if kind == "raw-triple":
            return f"r{quote * 3}{text}{quote * 3}"
        return f"{quote * 3}{text}{quote * 3}"

    kinds = ("normal", "raw", "triple", "raw-triple")
    quote_pairs = (("'", "'"), ("'", '"'), ('"', '"'))
    separators = (" ", "\n    ", "  // interposed comment\n    ")

    for first_kind in kinds:
        for second_kind in kinds:
            for q1, q2 in quote_pairs:
                for sep in separators:
                    src = (
                        "var x = "
                        + make(first_kind, q1, "SELECT 1 FROM settings ")
                        + sep
                        + make(second_kind, q2, "WHERE key = ?")
                        + ";"
                    )
                    lits = extract_sql_literals(src)
                    label = (
                        f"{first_kind}+{second_kind} q={q1}{q2} "
                        f"sep={sep.strip() or 'space'!r}"
                    )
                    # One group, always: the run concatenates.
                    check(
                        f"{label}: one group",
                        len(lits) == 1,
                        f"got {len(lits)} groups: {[l.content for l in lits]}",
                    )
                    if len(lits) != 1:
                        continue
                    # Parseable only when every member is a plain literal.
                    expected = first_kind == "normal" and second_kind == "normal"
                    check(
                        f"{label}: parseable={expected}",
                        lits[0].parseable == expected,
                        f"got parseable={lits[0].parseable}",
                    )
                    # The concatenation must be recoverable either way, so the
                    # SELECT pattern can still see the whole read.
                    check(
                        f"{label}: content joined",
                        "SELECT 1 FROM settings WHERE key = ?" in lits[0].content,
                        f"got {lits[0].content!r}",
                    )

    # Three-literal runs: {first} × {middle} × {last}.
    # The two-literal matrix above does not cover the case where a raw/triple
    # member is in the *middle* of a run — that is the position that broke here.
    # A raw middle literal must NOT truncate the run; all three fragments must
    # end up in one group.
    print("adjacency matrix (three-literal runs):")
    thirds = ("normal", "raw", "triple", "raw-triple")
    for first_kind in thirds:
        for mid_kind in thirds:
            for last_kind in thirds:
                src = (
                    "var x = "
                    + make(first_kind, "'", "SELECT 1 ")
                    + " "
                    + make(mid_kind, "'", "FROM settings ")
                    + " "
                    + make(last_kind, "'", "WHERE key = ?")
                    + ";"
                )
                lits = extract_sql_literals(src)
                label = f"{first_kind}+{mid_kind}+{last_kind}"
                check(
                    f"{label}: one group",
                    len(lits) == 1,
                    f"got {len(lits)} groups: {[l.content for l in lits]}",
                )
                if len(lits) != 1:
                    continue
                expected_p = first_kind == "normal" and mid_kind == "normal" and last_kind == "normal"
                check(
                    f"{label}: parseable={expected_p}",
                    lits[0].parseable == expected_p,
                    f"got parseable={lits[0].parseable}",
                )
                check(
                    f"{label}: content joined",
                    "SELECT 1 FROM settings WHERE key = ?" in lits[0].content,
                    f"got {lits[0].content!r}",
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

    # _NOTED_EXCEPTIONS must all exist on disk. If a file is renamed/deleted,
    # main() fails at startup — verify that here too so the test suite catches
    # a stale exception before CI does.
    from check_settings_marker_reads import _NOTED_EXCEPTIONS
    for exc_path in _NOTED_EXCEPTIONS:
        check(
            f"noted exception exists: {exc_path}",
            (root / exc_path).exists(),
            "update _NOTED_EXCEPTIONS if the file was renamed or deleted",
        )

    files = dart_library_files(root)
    check("finds library files", len(files) > 0, f"found {len(files)}")

    offenders: list[tuple[str, str]] = []
    for path in files:
        offenders.extend(check_file(path, root))

    check("baseline is clean", not offenders, "; ".join(loc for _k, loc in offenders))


def main() -> int:
    test_extract_sql_literals()
    test_compliant_reads()
    test_non_compliant_reads()
    test_delete_exception()
    test_non_reads()
    test_fail_closed()
    test_line_number_mapping()
    test_adjacency_matrix()
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
