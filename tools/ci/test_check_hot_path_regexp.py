#!/usr/bin/env python3
"""Offline tests for ``check_hot_path_regexp.py`` — the hot-path RegExp ratchet.

Pure-stdlib, assert-based (matching the rest of ``tools/*/test_*.py``). Run
directly::

    python3 tools/ci/test_check_hot_path_regexp.py

A ratchet is only worth having if it is shown to fail on the shape it exists to
catch (the pre-CS-25a ``normalizeTitle``) and stay quiet on the shapes the
codebase legitimately uses (top-level and ``static`` finals).
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_hot_path_regexp import (  # noqa: E402
    ALLOWED,
    REPO_ROOT,
    checked_files,
    evaluate,
    find_offenders,
    mask_source,
)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def lines(src: str) -> list[int]:
    return [line for line, _symbol in find_offenders(src)]


def symbols(src: str) -> list[str]:
    return [symbol for _line, symbol in find_offenders(src)]


def test_flagged_shapes() -> None:
    print("per-call shapes are flagged:")

    # The shape dedupe.dart had before CS-25a hoisted it (lines 390-392).
    pre_cs25a = (
        "String normalizeTitle(String title) {\n"
        "  var s = title.toLowerCase();\n"
        "  s = s.replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ');\n"
        "  s = s.replaceAll(RegExp(r'\\s+'), ' ').trim();\n"
        "  s = s.replaceFirst(RegExp(r'^(the|a|an)\\s+'), '');\n"
        "  return s;\n"
        "}\n"
    )
    check("pre-CS-25a normalizeTitle", lines(pre_cs25a) == [3, 4, 5], str(lines(pre_cs25a)))
    check("names the function", set(symbols(pre_cs25a)) == {"normalizeTitle"})

    check(
        "method in a class",
        lines("class P {\n  bool f(String s) {\n    return RegExp('a').hasMatch(s);\n  }\n}\n")
        == [3],
    )
    check(
        "local variable in a function",
        lines("void f() {\n  final re = RegExp(r'x');\n}\n") == [2],
    )
    check(
        "inside a nested closure",
        symbols("void outer(List<String> xs) {\n  xs.where((x) {\n    return RegExp('a').hasMatch(x);\n  });\n}\n")
        == ["outer"],
    )
    check(
        "arrow-bodied function",
        symbols("RegExp make() => RegExp(r'x');\n") == ["make"],
    )
    check(
        "arrow-bodied getter",
        symbols("class A {\n  static RegExp get re => RegExp('x');\n}\n") == ["re"],
    )
    check(
        "arrow closure assigned at top level",
        lines("final f = (String s) => RegExp(s);\n") == [1],
    )
    check(
        "async function body",
        lines("Future<void> f() async {\n  RegExp('x');\n}\n") == [2],
    )
    check(
        "instance field (compiled per object)",
        symbols("class A {\n  final _re = RegExp('x');\n}\n") == ["<instance field>"],
    )
    check(
        "instance field inside a collection literal",
        symbols("class A {\n  final _m = {'a': RegExp('x')};\n}\n") == ["<instance field>"],
    )
    check(
        "constructor body",
        lines("class A {\n  A() {\n    final r = RegExp('x');\n  }\n}\n") == [3],
    )
    check(
        "string interpolation is real code",
        lines("void f() {\n  g('${RegExp('x')}');\n}\n") == [2],
    )
    check(
        "RegExp after a comment-looking string is still seen",
        lines("void f() {\n  g('// not a comment');\n  RegExp('x');\n}\n") == [3],
    )
    check(
        "multi-line call",
        lines("void f() {\n  final re = RegExp(\n    r'x',\n  );\n}\n") == [2],
    )


def test_accepted_shapes() -> None:
    print("hoisted shapes are accepted:")

    check("top-level final", lines("final RegExp _a = RegExp(r'\\s+');\n") == [])
    check("top-level final, multi-line", lines("final RegExp _a = RegExp(\n  r'x',\n  caseSensitive: false,\n);\n") == [])
    check("top-level const map of finals", lines("final _m = <String, RegExp>{'a': RegExp('x')};\n") == [])
    check("static final in a class", lines("class A {\n  static final RegExp _a = RegExp('x');\n}\n") == [])
    check(
        "static final map literal in a class",
        lines("class A {\n  static final _m = {'a': RegExp('x'), 'b': RegExp('y')};\n}\n") == [],
    )
    check(
        "static final list literal in a class, multi-line",
        lines("class A {\n  static final _l = [\n    RegExp('x'),\n    RegExp('y'),\n  ];\n}\n") == [],
    )
    check("in a line comment", lines("void f() {\n  // RegExp('x')\n}\n") == [])
    check("in a block comment", lines("/* RegExp('x') */\nvoid f() {}\n") == [])
    check("nested block comment", lines("/* a /* b */ RegExp('x') */\nvoid f() {}\n") == [])
    check("in a string", lines("void f() {\n  g(\"RegExp('x')\");\n}\n") == [])
    check("in a raw string", lines("void f() {\n  g(r'RegExp(\\');\n}\n") == [])
    check("in a triple-quoted string", lines("void f() {\n  g('''\nRegExp('x')\n''');\n}\n") == [])
    check("a different identifier", lines("void f() {\n  MyRegExp('x');\n  a.RegExp('y');\n}\n") == [])
    check("using a hoisted pattern", lines("final _a = RegExp('x');\nbool f(String s) {\n  return _a.hasMatch(s);\n}\n") == [])


def test_masking() -> None:
    print("masking:")
    src = "a // c\n'''x\ny''' /* z\nw */ b\n"
    masked = mask_source(src)
    check("length preserved", len(masked) == len(src))
    check("newlines preserved", masked.count("\n") == src.count("\n"))
    check("code survives", "a" in masked and "b" in masked)
    check(
        "interpolated code survives",
        "RegExp" in mask_source("g('x ${RegExp('y')} z');\n"),
    )
    check(
        "brace inside a string does not open a block",
        lines("void f() {\n  g('{');\n}\nfinal _a = RegExp('x');\n") == [],
    )


def test_allow_list() -> None:
    print("allow-list:")
    found = {"p/a.dart": [(10, "f"), (20, "f"), (30, "g")]}

    failures, warnings = evaluate(found, {})
    check("everything fails without an allow-list", len(failures) == 3 and not warnings)
    check("offenders print as path:line", failures[0].startswith("p/a.dart:10:"), failures[0])

    failures, warnings = evaluate(found, {("p/a.dart", "f"): (2, "reason")})
    check("an allowed symbol is accepted up to its count", len(failures) == 1 and "p/a.dart:30:" in failures[0])

    failures, _ = evaluate(found, {("p/a.dart", "f"): (1, "r"), ("p/a.dart", "g"): (1, "r")})
    check("a new one in an allowed symbol still fails", len(failures) == 1 and "p/a.dart:20:" in failures[0])

    failures, warnings = evaluate(found, {("p/a.dart", "f"): (2, "r"), ("p/a.dart", "g"): (3, "r")})
    check("a stale ceiling is a warning, not a failure", not failures and len(warnings) == 1, str(warnings))

    failures, warnings = evaluate({"p/a.dart": []}, {("p/a.dart", "gone"): (1, "r")})
    check("an allow-list entry for a vanished symbol warns", not failures and len(warnings) == 1)


def test_real_tree() -> None:
    print("real tree:")
    files = checked_files(REPO_ROOT)
    names = {f.name for f in files}
    check("checks dedupe.dart", "dedupe.dart" in names)
    check("checks figure_parser.dart", "figure_parser.dart" in names)
    check("checks the dialect files", {"callersbox_figure_dialect.dart", "contradb_figure_dialect.dart"} <= names)
    found = {
        f.relative_to(REPO_ROOT).as_posix(): find_offenders(f.read_text(encoding="utf-8"))
        for f in files
    }
    failures, _ = evaluate(found, ALLOWED)
    check("the tree is clean", not failures, "; ".join(failures))
    # The scanner must actually see the hoisted declarations to be trusted:
    # a scanner that finds no RegExp at all would also report a clean tree.
    total = sum(f.read_text(encoding="utf-8").count("RegExp(") for f in files)
    check("the checked files do contain RegExp( declarations", total > 10, str(total))


def main() -> int:
    test_flagged_shapes()
    test_accepted_shapes()
    test_masking()
    test_allow_list()
    test_real_tree()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all check_hot_path_regexp tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
