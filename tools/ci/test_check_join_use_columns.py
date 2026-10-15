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


def test_one_marker_does_not_exempt_two_joins() -> None:
    src = """
final q = s.join([
  // join-columns: needed — first join reads dances
  innerJoin(_db.dances, a),
  innerJoin(_db.dances, b),
]);
"""
    (v,) = check_text(src, "a.dart")
    assert v.kind == MISSING and v.line == 5, v


def test_each_join_with_its_own_marker_passes() -> None:
    src = """
final q = s.join([
  // join-columns: needed — first
  innerJoin(_db.dances, a),
  // join-columns: needed — second
  leftOuterJoin(_db.dances, b),
]);
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


def test_flags_aliased_dances_in_first_argument() -> None:
    # guards-6: `_db.dances` anywhere in the first argument is the same join.
    for join in (
        "innerJoin(_db.dances.createAlias('d'), x,)",
        "leftOuterJoin(this._db.dances.createAlias('d'), x,)",
        "innerJoin(alias(_db.dances, 'd'), x,)",
    ):
        assert [v.kind for v in check_text(_body(join), "a.dart")] == [MISSING], join


def test_flags_local_alias_of_dances() -> None:
    # guards-6: a name bound to `_db.dances` (or an alias of it) is the same join.
    for decl in (
        "final d = _db.dances.createAlias('d');",
        "final d = alias(_db.dances, 'd');",
        "late final $DancesTable d = _db.dances;",
    ):
        src = f"""
Future<void> f() async {{
  {decl}
  final rows = await (_db.select(_db.danceTags).join([
    innerJoin(d, d.id.equalsExp(x)),
  ])).get();
}}
"""
        assert [v.kind for v in check_text(src, "a.dart")] == [MISSING], decl


def test_flags_generic_call_wrapping_dances() -> None:
    # Review of #1701: a comma inside `<...>` type arguments must not end the
    # first argument early.
    for join in (
        "innerJoin(alias<Table, Row>(_db.dances, 'd'), x,)",
        "innerJoin(wrap<Map<String, int>, Row>(_db.dances), x,)",
    ):
        assert [v.kind for v in check_text(_body(join), "a.dart")] == [MISSING], join


def test_comparison_in_first_argument_does_not_hide_dances() -> None:
    # `a < b` is not a generic; unbalanced brackets fall back to the whole call.
    join = "innerJoin(pick(a<b, _db.dances), x,)"
    assert [v.kind for v in check_text(_body(join), "a.dart")] == [MISSING], join


def test_flags_field_alias_used_through_this_or_bare() -> None:
    # Review of #1701: a field alias used as `this.d` (or bare) is the same join.
    for use in ("this.d", "d"):
        src = f"""
class R {{
  late final d = _db.dances.createAlias('d');
  Future<void> f() async {{
    final rows = await (_db.select(_db.danceTags).join([
      innerJoin({use}, x),
    ])).get();
  }}
}}
"""
        assert [v.kind for v in check_text(src, "a.dart")] == [MISSING], use


def test_other_member_with_alias_name_is_not_an_alias() -> None:
    src = """
final d = _db.dances.createAlias('d');
Future<void> f() async {
  final rows = await (_db.select(_db.danceTags).join([
    innerJoin(other.d, x),
  ])).get();
}
"""
    assert check_text(src, "a.dart") == []


def test_dances_only_in_second_argument_is_not_a_dances_join() -> None:
    src = _body("innerJoin(_db.tags, _db.tags.id.equalsExp(_db.dances.id),)")
    assert check_text(src, "a.dart") == []


def test_real_tree_is_compliant() -> None:
    assert main(["x"]) == 0


if __name__ == "__main__":
    tests = [(k, v) for k, v in sorted(globals().items()) if k.startswith("test_")]
    for name, fn in tests:
        fn()
        print(f"ok  {name}")
    print(f"{len(tests)} passed")
