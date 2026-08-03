#!/usr/bin/env python3
"""Offline tests for ``check_debug_print.py`` — the unguarded-``debugPrint`` ratchet.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_debug_print.py

The ratchet is only worth having if it fails on the shape it exists to catch and
stays quiet on the shapes the codebase legitimately uses, so the cases below are
split into exactly those two groups. Every guard form asserted here is one that
actually appears in ``app/lib`` or ``packages/*/lib`` today — the four-way split
(braced block, same-line, braceless next-line, compound condition) is why the
checker tracks brace depth instead of grepping line by line.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_debug_print import (  # noqa: E402
    dart_library_files,
    find_unguarded,
    is_debug_guard,
    mask_line,
    strip_line_comment,
)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def unguarded_lines(src: str) -> list[int]:
    return [line for line, _ in find_unguarded(src)]


# --------------------------------------------------------------------------
# Guarded shapes — every one of these appears in the real tree and must pass.
# --------------------------------------------------------------------------


def test_guarded_forms() -> None:
    print("guarded forms are accepted:")

    check(
        "braced block",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    debugPrint('hi');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "same-line single statement",
        unguarded_lines(
            "void f() {\n  if (kDebugMode) debugPrint('hi');\n}\n"
        )
        == [],
    )

    check(
        "braceless guard, call on the next line",
        unguarded_lines(
            "void f() {\n  if (kDebugMode)\n    debugPrint('hi');\n}\n"
        )
        == [],
    )

    check(
        "compound condition (kDebugMode && ...)",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode && record.error != null) {\n"
            "    debugPrint('hi');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "nested inside another block",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    for (final x in xs) {\n"
            "      try {\n"
            "        debugPrint('hi');\n"
            "      } catch (_) {}\n"
            "    }\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "several calls in one guarded block",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    debugPrint('a');\n"
            "    debugPrint('b');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "one-line braced guard",
        unguarded_lines(
            "void f() {\n  if (kDebugMode) { debugPrint('hi'); }\n}\n"
        )
        == [],
        "the block opens BEFORE the call on the same line, so the call is "
        "inside it",
    )

    check(
        "one-line braced guard, compound condition",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode && x != null) { debugPrint('hi'); }\n"
            "}\n"
        )
        == [],
    )

    check(
        "guard condition split across lines",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode &&\n"
            "      record.error != null) {\n"
            "    debugPrint('hi');\n"
            "  }\n"
            "}\n"
        )
        == [],
        "`pending` carries across lines, so a wrapped condition is still one "
        "condition",
    )


# --------------------------------------------------------------------------
# Unguarded shapes — the ratchet's whole reason to exist.
# --------------------------------------------------------------------------


def test_unguarded_forms() -> None:
    print("unguarded forms are caught:")

    check(
        "bare call",
        unguarded_lines("void f() {\n  debugPrint('leak');\n}\n") == [2],
    )

    check(
        "call AFTER a guarded block has closed",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    debugPrint('fine');\n"
            "  }\n"
            "  debugPrint('leak');\n"
            "}\n"
        )
        == [5],
        "a closed guard must not keep protecting later calls",
    )

    check(
        "guarded by an unrelated condition",
        unguarded_lines(
            "void f() {\n  if (verbose) {\n    debugPrint('leak');\n  }\n}\n"
        )
        == [3],
    )

    check(
        "kDebugMode mentioned but not as a guard",
        unguarded_lines(
            "void f() {\n"
            "  final mode = kDebugMode ? 'a' : 'b';\n"
            "  debugPrint(mode);\n"
            "}\n"
        )
        == [3],
        "a ternary is not a guard — the call runs either way",
    )

    check(
        "braceless guard only protects the NEXT statement",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode)\n"
            "    debugPrint('fine');\n"
            "  debugPrint('leak');\n"
            "}\n"
        )
        == [4],
    )

    check(
        "sibling else branch is not covered",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    debugPrint('fine');\n"
            "  } else {\n"
            "    debugPrint('leak');\n"
            "  }\n"
            "}\n"
        )
        == [5],
    )

    # --- the intra-line false negative -------------------------------------
    #
    # THE most important case in this file. A guarded block that CLOSES on the
    # same line as a later call: the `}` must be processed before the call, or
    # the closed block's guard is still on the stack and an unguarded call is
    # waved through. That is a false NEGATIVE in a security ratchet — the one
    # direction it exists to prevent, and strictly worse than a false positive,
    # which merely annoys. Line-oriented scanning gets this wrong silently.
    check(
        "block CLOSES before a call on the same line",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    ok();\n"
            "  } debugPrint('leak');\n"
            "}\n"
        )
        == [4],
        "the guard closed at the `}`; the call after it is NOT protected",
    )

    check(
        "block closes and reopens unguarded on one line",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    ok();\n"
            "  } else { debugPrint('leak'); }\n"
            "}\n"
        )
        == [4],
    )

    check(
        "call between a closed guard and a new guarded block",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) { ok(); } debugPrint('leak');\n"
            "  if (kDebugMode) { debugPrint('fine'); }\n"
            "}\n"
        )
        == [2],
    )


# --------------------------------------------------------------------------
# False positives — shapes that name `debugPrint` without calling it.
# --------------------------------------------------------------------------


# --------------------------------------------------------------------------
# Guard SEMANTICS, not guard shape.
#
# The predicate must fail CLOSED: accept only conditions that provably cannot
# hold when `kDebugMode` is false, and report everything else. A false
# positive costs a contributor one restructure; a false negative ships a
# release-build log leak. Earlier revisions matched the shape of a guard
# (`if` … `kDebugMode` … `)`) and so accepted any condition that merely
# MENTIONED the constant — including its own negation.
# --------------------------------------------------------------------------


def test_guard_semantics() -> None:
    print("guard semantics (fail closed):")

    def guarded(cond: str) -> bool:
        return unguarded_lines(
            f"void f() {{\n  if ({cond}) {{\n    debugPrint('x');\n  }}\n}}\n"
        ) == []

    # Accepted: kDebugMode is necessarily true inside the block.
    check("bare kDebugMode", guarded("kDebugMode"))
    check("conjunction, guard first", guarded("kDebugMode && x != null"))
    check("conjunction, guard second", guarded("x != null && kDebugMode"))
    check("conjunction of three", guarded("a && kDebugMode && b"))

    # Rejected: each of these previously passed as a guard.
    check(
        "negated guard runs ONLY in release",
        not guarded("!kDebugMode"),
        "the single worst case: the ratchet would bless a call that runs in "
        "release and nowhere else",
    )
    check(
        "spaced negation",
        not guarded("! kDebugMode"),
    )
    check(
        "disjunction can be satisfied by the other operand",
        not guarded("kDebugMode || verbose"),
        "release logging whenever `verbose` is set",
    )
    check("disjunction, guard second", not guarded("verbose || kDebugMode"))
    check("negated via ==", not guarded("kDebugMode == false"))
    check("negated via !=", not guarded("kDebugMode != true"))
    check(
        "a disjunction anywhere disqualifies the whole condition",
        not guarded("kDebugMode && (a || b)"),
        "conservative by design: rejecting a safe-but-unproven form is the "
        "cheap direction to be wrong in",
    )
    check("ternary is not a guard", not guarded("kDebugMode ? a : b"))
    check("unrelated condition", not guarded("verbose"))

    # The predicate reads the LAST `if (` in the accumulated statement, so a
    # guarded block followed by an unguarded `if` must not inherit the guard.
    check(
        "a later unrelated `if` does not inherit an earlier guard",
        not is_debug_guard("if (kDebugMode) { ok(); } if (verbose)"),
    )


def test_false_positives() -> None:
    print("non-calls are not reported:")

    check(
        "import ... show debugPrint",
        unguarded_lines(
            "import 'package:flutter/foundation.dart'\n"
            "    show debugPrint, kDebugMode;\n"
        )
        == [],
        "this names the symbol, it does not call it",
    )

    check(
        "commented-out call",
        unguarded_lines("void f() {\n  // debugPrint('old');\n}\n") == [],
    )

    check(
        "trailing comment after a guarded call",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    debugPrint('hi'); // debugPrint('not a real call')\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "doc comment mentioning the symbol",
        unguarded_lines("/// Uses debugPrint under kDebugMode.\nvoid f() {}\n")
        == [],
    )

    check(
        "a brace inside a string does not close a block",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    debugPrint('}');\n"
            "    debugPrint('still inside');\n"
            "  }\n"
            "}\n"
        )
        == [],
        "masking string contents is what keeps the brace stack honest",
    )

    # --- multi-line string literals ---------------------------------------
    #
    # Dart triple-quoted literals span lines, so masking has to be whole-file;
    # per-line masking cannot see them. These literals are live in this repo —
    # compendium_core's storage layer holds its schema this way.
    check(
        "a debugPrint token inside a multi-line string is not a call",
        unguarded_lines(
            "void f() {\n"
            "  final sql = '''\n"
            "    -- debugPrint('not code');\n"
            "  ''';\n"
            "  if (kDebugMode) {\n"
            "    debugPrint('real');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "the same for a double-quoted multi-line string",
        unguarded_lines(
            'void f() {\n'
            '  final sql = """\n'
            "    debugPrint('not code');\n"
            '  """;\n'
            '}\n'
        )
        == [],
    )

    # THE serious one. A bare `{` inside a triple-quoted literal pushes a brace
    # frame that then absorbs the `}` closing a real kDebugMode block, leaving
    # the guard on the stack — so a later, genuinely unguarded call is blessed.
    # A false NEGATIVE, which is the direction this ratchet exists to prevent.
    check(
        "a bare brace inside a multi-line string does not corrupt the stack",
        unguarded_lines(
            "void h() {\n"
            "  if (kDebugMode) {\n"
            "    final sql = '''\n"
            "      CREATE TRIGGER t BEGIN {\n"
            "    ''';\n"
            "  }\n"
            "  debugPrint('leak');\n"
            "}\n"
        )
        == [7],
        "the guard block closed at line 6; the call after it is unprotected",
    )

    check(
        "a real call after a multi-line string is still found",
        unguarded_lines(
            "void f() {\n"
            "  final sql = '''\n"
            "    SELECT 1;\n"
            "  ''';\n"
            "  debugPrint('leak');\n"
            "}\n"
        )
        == [5],
    )

    # --- block comments ---------------------------------------------------
    #
    # The third and last construct carrying lexical state across lines. Both
    # directions are tested, and the false-positive case deliberately puts the
    # stray `}` INSIDE a real guard block: at top level it pops the stack in a
    # way that happens to leave the following call correctly unguarded, so the
    # test would pass for the wrong reason and read as coverage it isn't.
    check(
        "a stray } in a block comment does not pop a real guard",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    /* } */\n"
            "    debugPrint('x');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "the same across a multi-line block comment",
        unguarded_lines(
            "void f() {\n"
            "  if (kDebugMode) {\n"
            "    /*\n"
            "      }\n"
            "    */\n"
            "    debugPrint('x');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "guard-opening text inside a block comment is not a guard",
        unguarded_lines(
            "void f() {\n"
            "  /* if (kDebugMode) { */\n"
            "  debugPrint('leak');\n"
            "}\n"
        )
        == [3],
        "commented-out code must not bless the live call beneath it",
    )

    check(
        "a debugPrint token inside a block comment is not a call",
        unguarded_lines("void f() {\n  /* debugPrint('x'); */\n}\n") == [],
    )

    check(
        "block comments nest",
        unguarded_lines(
            "void f() {\n"
            "  /* outer /* inner } */ still comment { */\n"
            "  debugPrint('leak');\n"
            "}\n"
        )
        == [3],
        "Dart nests block comments, so the first */ must not end the outer one",
    )

    check(
        "a raw string is masked like any other",
        unguarded_lines("void f() {\n  final s = r'raw }';\n  debugPrint('x');\n}\n")
        == [3],
    )

    check(
        "`//` inside a string is not a comment",
        unguarded_lines(
            "void f() {\n  final u = 'http://x';\n  debugPrint(u);\n}\n"
        )
        == [3],
        "the URL must not swallow the rest of the line",
    )


def test_masking() -> None:
    print("masking:")
    check(
        "string contents are blanked, length preserved",
        mask_line("f('}{');") == "f('  ');" ,
        repr(mask_line("f('}{');")),
    )
    check(
        "comment is blanked to end of line",
        mask_line("a; // }").rstrip() == "a;",
    )


def test_strip_line_comment() -> None:
    print("comment stripping:")
    check("plain comment", strip_line_comment("a; // b").strip() == "a;")
    check(
        "`//` inside single quotes survives",
        strip_line_comment("f('http://x'); // c").strip() == "f('http://x');",
    )
    check(
        "escaped quote does not end the string",
        strip_line_comment(r"f('a\'// b'); // c").strip() == r"f('a\'// b');",
    )


def test_real_tree_is_clean() -> None:
    """The live baseline: 0 unguarded calls across the production libraries.

    This is the ratchet asserting its own premise. If it ever fails, either a
    new unguarded call landed (fix the call) or the guard forms in use have
    changed (fix the checker) — do not delete this test.
    """
    print("real tree:")
    root = HERE.parents[1]
    files = dart_library_files(root)
    check("finds library files", len(files) > 0, f"found {len(files)}")
    offenders: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if "debugPrint" not in text:
            continue
        for line_no, src in find_unguarded(text):
            offenders.append(f"{path.relative_to(root)}:{line_no}: {src}")
    check("baseline is clean", not offenders, "; ".join(offenders))


def main() -> int:
    test_guarded_forms()
    test_unguarded_forms()
    test_guard_semantics()
    test_false_positives()
    test_masking()
    test_strip_line_comment()
    test_real_tree_is_clean()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all check_debug_print tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
