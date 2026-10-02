#!/usr/bin/env python3
"""Offline tests for ``check_join_use_columns.py``.

Pure-stdlib, assert-based. Run directly::

    python3 tools/ci/test_check_join_use_columns.py
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_join_use_columns import (  # noqa: E402
    EMPTY_REASON,
    MISSING,
    check_text,
    check_tree,
    main,
)


def _body(join: str, above: str = "") -> str:
    return f"""
Future<void> f() async {{
  final rows = await (_db.select(_db.danceTags).join([
    {above}
    {join}
  ])).get();
}}
"""


def test_flags_join_without_use_columns() -> None:
    src = _body("innerJoin(_db.dances, _db.dances.id.equalsExp(x),)")
    (v,) = check_text(src, "a.dart")
    assert v.kind == MISSING and v.line == 5, v


def test_flags_left_outer_join() -> None:
    src = _body("leftOuterJoin(_db.dances, _db.dances.id.equalsExp(x),)")
    assert [v.kind for v in check_text(src, "a.dart")] == [MISSING]


def test_flags_multiline_call_at_innerjoin_line() -> None:
    src = """
final q = s.join([
  innerJoin(
    _db.dances,
    _db.dances.id.equalsExp(x),
  ),
]);
"""
    (v,) = check_text(src, "a.dart")
    assert v.line == 3, v


def test_use_columns_false_passes() -> None:
    src = _body(
        "innerJoin(_db.dances, _db.dances.id.equalsExp(x), useColumns: false,)"
    )
    assert check_text(src, "a.dart") == []


def test_use_columns_on_next_join_does_not_leak() -> None:
    src = """
final q = s.join([
  innerJoin(_db.dances, _db.dances.id.equalsExp(x)),
  innerJoin(_db.danceTags, y, useColumns: false),
]);
"""
    (v,) = check_text(src, "a.dart")
    assert v.line == 3, v


def test_marker_above_passes() -> None:
    src = _body(
        "innerJoin(_db.dances, _db.dances.id.equalsExp(x),)",
        above="// join-columns: needed — reads readTable(_db.dances)",
    )
    assert check_text(src, "a.dart") == []


def test_marker_on_call_line_passes() -> None:
    src = _body(
        "innerJoin(_db.dances, x) // join-columns: needed — CS-14b guard"
    )
    assert check_text(src, "a.dart") == []


def test_marker_above_enclosing_statement_passes() -> None:
    # `dart format` re-lays-out an expression with a comment inside it, so the
    # marker may sit above `final x = await (...)`.
    src = """
Future<void> f() async {
  if (permanent) {
    // join-columns: needed — replaced by liveDanceCitationCount in CS-14b
    final liveUses =
        await (_db.select(_db.danceTags).join([
              innerJoin(_db.dances, x),
            ])).get();
  }
}
"""
    assert check_text(src, "a.dart") == []


def test_marker_without_reason_is_flagged() -> None:
    src = _body(
        "innerJoin(_db.dances, x)",
        above="// join-columns: needed —",
    )
    assert [v.kind for v in check_text(src, "a.dart")] == [EMPTY_REASON]


def test_marker_separated_by_code_does_not_count() -> None:
    src = """
// join-columns: needed — stale, belongs to the join above
final a = 1;
final q = s.join([innerJoin(_db.dances, x)]);
"""
    assert [v.kind for v in check_text(src, "a.dart")] == [MISSING]


def test_other_tables_ignored() -> None:
    src = _body("innerJoin(_db.danceTags, _db.danceTags.id.equalsExp(x),)")
    assert check_text(src, "a.dart") == []
    src = _body("innerJoin(_db.dancesFoo, x)")
    assert check_text(src, "a.dart") == []


def test_comments_and_strings_ignored() -> None:
    src = """
/// Joins with `innerJoin(_db.dances, x)` and no columns.
// innerJoin(_db.dances, x)
/* innerJoin(_db.dances, x) */
final s = 'innerJoin(_db.dances, x)';
"""
    assert check_text(src, "a.dart") == []


def test_use_columns_in_comment_or_string_does_not_count() -> None:
    src = """
final q = s.join([
  innerJoin(_db.dances, x /* useColumns: false */, 'useColumns: false'),
]);
"""
    assert [v.kind for v in check_text(src, "a.dart")] == [MISSING]


def test_tree_and_exit_codes() -> None:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "ok.dart").write_text(
            _body("innerJoin(_db.dances, x, useColumns: false)")
        )
        assert check_tree(root) == []
        assert main(["x", str(root)]) == 0
        (root / "bad.dart").write_text(_body("innerJoin(_db.dances, x)"))
        assert len(check_tree(root)) == 1
        assert main(["x", str(root)]) == 1
        assert main(["x", str(root / "missing")]) == 2


def test_real_tree_is_compliant() -> None:
    assert main(["x"]) == 0


if __name__ == "__main__":
    tests = [(k, v) for k, v in sorted(globals().items()) if k.startswith("test_")]
    for name, fn in tests:
        fn()
        print(f"ok  {name}")
    print(f"{len(tests)} passed")
