#!/usr/bin/env python3
"""Offline tests for ``check_sync_resolve_alias_loops.py``.

Pure-stdlib, assert-based. Run directly::

    python3 tools/ci/test_check_sync_resolve_alias_loops.py
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_sync_resolve_alias_loops import (  # noqa: E402
    dart_sync_files,
    find_loop_resolves,
)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def lines(src: str) -> list[int]:
    return [line for line, _ in find_loop_resolves(src)]


# --- shapes that must be flagged -------------------------------------------

check(
    "for-in loop with braces",
    lines("void f() async {\n  for (final a in xs) {\n    n.add(await store.resolveAlias(a));\n  }\n}\n")
    == [3],
)
check(
    "assignment form inside a nested loop",
    lines(
        "void f() async {\n  for (final a in xs) {\n    for (final b in a) {\n"
        "      final r = await store.resolveAlias(b);\n    }\n  }\n}\n"
    )
    == [4],
    "nested loops report the call once",
)
check(
    "while loop",
    lines("void f() async {\n  while (go()) {\n    await store.resolveAlias(a);\n  }\n}\n")
    == [3],
)
check(
    "do-while loop",
    lines("void f() async {\n  do {\n    await store.resolveAlias(a);\n  } while (go());\n}\n")
    == [3],
)
check(
    "unbraced loop body",
    lines("void f() async {\n  for (final a in xs)\n    await store.resolveAlias(a);\n}\n")
    == [3],
)
check(
    "collection-for element",
    lines("Future<void> f() async {\n  final r = [for (final a in xs) await store.resolveAlias(a)];\n}\n")
    == [2],
)
check(
    "call on a longer receiver chain",
    lines("void f() async {\n  for (final a in xs) {\n    await this.store.resolveAlias(a);\n  }\n}\n")
    == [3],
)
check(
    "multi-line await expression",
    lines(
        "void f() async {\n  for (final a in xs) {\n    final r = await\n"
        "        store.resolveAlias(a);\n  }\n}\n"
    )
    == [3],
    "reported at the `await`",
)
check(
    "marker for a different reason does not exempt another site",
    lines(
        "void f() async {\n  for (final a in xs) {\n"
        "    await store.resolveAlias(a); // alias-loop: allowed — one-off\n"
        "    await store.resolveAlias(b);\n  }\n}\n"
    )
    == [4],
)

check(
    "unbraced do-while body",
    lines("void f() async {\n  do await store.resolveAlias(a); while (go());\n}\n")
    == [2],
)
check(
    "unbraced loop over an unbraced if",
    lines("void f() async {\n  for (final a in xs)\n    if (keep(a)) await store.resolveAlias(a);\n}\n")
    == [3],
)
check(
    "unbraced loop over an if/else with the call in the else",
    lines(
        "void f() async {\n  for (final a in xs)\n    if (keep(a)) use(a); else await store.resolveAlias(a);\n}\n"
    )
    == [3],
)
check(
    "unbraced loop over a braced if holding the call",
    lines(
        "void f() async {\n  for (final a in xs)\n    if (keep(a)) {\n      await store.resolveAlias(a);\n    }\n}\n"
    )
    == [4],
)

# --- shapes that must stay quiet -------------------------------------------

check(
    "call outside any loop",
    lines("void f() async {\n  final r = await store.resolveAlias(a);\n}\n") == [],
)
check(
    "local resolveAlias lambda argument",
    lines(
        "void f() {\n  for (final a in xs) {\n    g(resolveAlias: (x) => map[x] ?? x);\n  }\n}\n"
    )
    == [],
    "no await, no method call",
)
check(
    "synchronous resolve from a loaded map",
    lines(
        "void f() async {\n  final aliases = await store.aliasMap();\n"
        "  for (final a in xs) {\n    n.add(aliases.resolve(a));\n  }\n}\n"
    )
    == [],
)
check(
    "await after the loop closes",
    lines("void f() async {\n  for (final a in xs) {\n    g(a);\n  }\n  await store.resolveAlias(a);\n}\n")
    == [],
)
check(
    "call in a comment or string",
    lines(
        "void f() {\n  for (final a in xs) {\n    // await store.resolveAlias(a)\n"
        "    g('await store.resolveAlias(a)');\n  }\n}\n"
    )
    == [],
)
check(
    "while closing a do-while is not a body",
    lines("void f() async {\n  do {\n    g();\n  } while (go());\n  await store.resolveAlias(a);\n}\n")
    == [],
)
check(
    "await after an unbraced loop over a braced if",
    lines(
        "void f() async {\n  for (final a in xs)\n    if (keep(a)) { use(a); }\n"
        "  await store.resolveAlias(a);\n}\n"
    )
    == [],
    "the nested block must end the loop body",
)
check(
    "await after an unbraced loop over an if/else of blocks",
    lines(
        "void f() async {\n  for (final a in xs)\n    if (keep(a)) { use(a); } else { skip(a); }\n"
        "  await store.resolveAlias(a);\n}\n"
    )
    == [],
)
check(
    "await after an unbraced do-while",
    lines("void f() async {\n  do g(); while (go());\n  await store.resolveAlias(a);\n}\n")
    == [],
)
check(
    "await after nested unbraced loops",
    lines(
        "void f() async {\n  for (final a in xs)\n    for (final b in a) use(b);\n"
        "  await store.resolveAlias(a);\n}\n"
    )
    == [],
)
check(
    "marker on the call's line",
    lines(
        "void f() async {\n  for (final a in xs) {\n"
        "    await store.resolveAlias(a); // alias-loop: allowed — bounded to 3\n  }\n}\n"
    )
    == [],
)
check(
    "marker on the line above the call",
    lines(
        "void f() async {\n  for (final a in xs) {\n"
        "    // alias-loop: allowed — bounded to 3\n    await store.resolveAlias(a);\n  }\n}\n"
    )
    == [],
)
check(
    "marker above the loop header",
    lines(
        "void f() async {\n  // alias-loop: allowed — bounded to 3\n  for (final a in xs) {\n"
        "    await store.resolveAlias(a);\n  }\n}\n"
    )
    == [],
)

# --- the real tree ----------------------------------------------------------

REPO_ROOT = HERE.parents[1]
check(
    "the sync directory is found",
    bool(dart_sync_files(REPO_ROOT)),
    "app/lib/src/sync has no Dart files — SEARCH_ROOT is stale",
)

if FAILURES:
    print(f"\n{len(FAILURES)} failure(s):")
    for failure in FAILURES:
        print(f"  - {failure}")
    sys.exit(1)
print("\nall ok")
