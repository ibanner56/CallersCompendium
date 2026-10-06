#!/usr/bin/env python3
"""Offline tests for ``check_kdf_override_unassigned.py``.

Pure-stdlib, assert-based, like the other ``tools/ci/test_*.py``. Run::

    python3 tools/ci/test_check_kdf_override_unassigned.py
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_kdf_override_unassigned import dart_library_files, scan  # noqa: E402

FAILURES: list[str] = []

DECL = (
    "const _syncIdentityKdfIterations = 600000;\n"
    "@visibleForTesting\n"
    "int syncIdentityKdfIterations = _syncIdentityKdfIterations;\n"
)


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def violations(src: str) -> list[int]:
    return [line for line, _ in scan(src)[1]]


def test_accepted() -> None:
    print("accepted:")
    decls, bad = scan(DECL)
    check("the canonical declaration", decls == [3] and not bad, f"{decls} {bad}")
    check(
        "reads are fine",
        not violations(
            DECL + "void f() { for (var i = 0; i < syncIdentityKdfIterations; i++) {} }\n"
            "final x = syncIdentityKdfIterations;\n"
            "'iterations': syncIdentityKdfIterations,\n"
            "bool b() => a != syncIdentityKdfIterations || syncIdentityKdfIterations == 5;\n"
        ),
    )
    check(
        "prose in comments and strings",
        not violations(
            DECL
            + "// syncIdentityKdfIterations = 1;\n"
            + "/* syncIdentityKdfIterations = 1; /* nested */ still comment = 2; */\n"
            + "/// tests set `syncIdentityKdfIterations = 1000`\n"
            + "final s = 'syncIdentityKdfIterations = 1';\n"
            + "final t = '''\nsyncIdentityKdfIterations = 1;\n''';\n"
        ),
    )
    check(
        "a raw string is not interpolated",
        not violations(DECL + "final r = r'${syncIdentityKdfIterations = 1}';\n"),
    )
    check(
        "a read inside an interpolation is fine",
        not violations(DECL + "final s = 'n=${syncIdentityKdfIterations}';\n"),
    )
    check(
        "an escaped dollar is text, not an interpolation",
        not violations(DECL + "final s = '\\${syncIdentityKdfIterations = 1}';\n"),
    )
    check(
        "a longer identifier is a different symbol",
        not violations(DECL + "var mySyncIdentityKdfIterations = 1;\n"
                       "var syncIdentityKdfIterationsX = 1;\n"),
    )


def test_rejected() -> None:
    print("rejected:")
    for name, stmt in [
        ("plain assignment", "syncIdentityKdfIterations = 1000;"),
        ("assignment without spaces", "syncIdentityKdfIterations=1000;"),
        ("compound +=", "syncIdentityKdfIterations += 1;"),
        ("compound -=", "syncIdentityKdfIterations -= 1;"),
        ("compound *=", "syncIdentityKdfIterations *= 2;"),
        ("compound ~/=", "syncIdentityKdfIterations ~/= 2;"),
        ("null-aware ??=", "syncIdentityKdfIterations ??= 1;"),
        ("postfix ++", "syncIdentityKdfIterations++;"),
        ("prefix --", "--syncIdentityKdfIterations;"),
        ("split across lines", "syncIdentityKdfIterations\n    = 1000;"),
        ("inside a closure", "final f = () => syncIdentityKdfIterations = 1;"),
        ("after a comment on the line", "/* c */ syncIdentityKdfIterations = 1;"),
        ("inside a string interpolation", "print('${syncIdentityKdfIterations = 1}');"),
        ("inside a nested interpolation", "print('a ${'b ${syncIdentityKdfIterations = 1}'}');"),
        ("interpolation after a brace-bearing literal", "print('{x} ${syncIdentityKdfIterations += 1}');"),
        ("interpolation in a triple-quoted string", "print('''\n${syncIdentityKdfIterations = 1}\n''');"),
        ("prefixed by a string interpolation line", "final s = 'a'; syncIdentityKdfIterations = 1;"),
    ]:
        src = DECL + "void f() {\n  " + stmt + "\n}\n"
        check(name, bool(violations(src)), repr(scan(src)))
    # A scratch assignment is reported on its own line, not the declaration's.
    check(
        "reported at the assignment line",
        violations(DECL + "void f() {\n  syncIdentityKdfIterations = 1;\n}\n") == [5],
    )


def test_declaration() -> None:
    print("declaration:")
    check(
        "a lowered default is rejected",
        bool(violations("int syncIdentityKdfIterations = 1000;\n")),
    )
    check(
        "a literal 600000 default is rejected (must be the constant)",
        bool(violations("int syncIdentityKdfIterations = 600000;\n")),
    )
    check(
        "a computed default is rejected",
        bool(violations("int syncIdentityKdfIterations = _syncIdentityKdfIterations ~/ 600;\n")),
    )
    check(
        "a second declaration is a second hit",
        len(scan(DECL + DECL)[0]) == 2,
    )
    check("no declaration is visible to the caller", scan("void f() {}\n")[0] == [])


def test_server_is_production() -> None:
    # guards-3: `server/` depends on compendium_core, so an assignment in its
    # lib/ or bin/ is a production assignment too. Its tests stay out of scope.
    print("server scope:")
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel in ("server/lib/src/a.dart", "server/bin/b.dart", "server/test/c.dart"):
            path = root / rel
            path.parent.mkdir(parents=True)
            path.write_text("void f() { syncIdentityKdfIterations = 1; }\n")
        found = {p.relative_to(root).as_posix() for p in dart_library_files(root)}
    check("server/lib is walked", "server/lib/src/a.dart" in found, str(found))
    check("server/bin is walked", "server/bin/b.dart" in found, str(found))
    check("server/test is not walked", "server/test/c.dart" not in found, str(found))


def test_real_tree() -> None:
    print("real tree:")
    root = HERE.parents[1]
    files = dart_library_files(root)
    check("finds library files", len(files) > 0)
    declared: list[str] = []
    offenders: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if "syncIdentityKdfIterations" not in text:
            continue
        decls, bad = scan(text)
        declared += [f"{path.relative_to(root)}:{d}" for d in decls]
        offenders += [f"{path.relative_to(root)}:{ln}: {why}" for ln, why in bad]
    check("exactly one declaration", len(declared) == 1, str(declared))
    check("no production assignment", not offenders, "; ".join(offenders))


def main() -> int:
    test_accepted()
    test_rejected()
    test_declaration()
    test_server_is_production()
    test_real_tree()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all check_kdf_override_unassigned tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
