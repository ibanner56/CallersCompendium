#!/usr/bin/env python3
"""Offline tests for ``check_archive_key_versions.py``.

Pure-stdlib, assert-based. Run directly::

    python3 tools/ci/test_check_archive_key_versions.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_archive_key_versions import (  # noqa: E402
    CODEC,
    MANIFEST,
    REPO_ROOT,
    STAMPERS,
    check,
    declared_constants,
    entity_keys,
    main,
    stamper_constants,
)

FAILURES: list[str] = []


def expect(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def test_key_extraction() -> None:
    print("key extraction")
    src = (
        "Map<String, Object?> archiveThingToJson(\n"
        "  Thing t, {\n"
        "  bool includeOptionalFields = false,\n"
        "}) => {\n"
        "  'id': t.id,\n"
        "  // 'commented': out,\n"
        "  // the app's own note: no key here,\n"
        "  'url': 'https://example.com//not-a-comment',\n"
        "  /* 'blocked': out, */\n"
        "  if (includeOptionalFields || t.a != null) 'a': t.a,\n"
        "  if (t.b case Some(:final v)) 'b': v else 'c': null,\n"
        "  'nested': switch (t.kind) {\n"
        "    Kind.x => {'inner': 1},\n"
        "    Kind.y => const <Object?>[],\n"
        "  },\n"
        "  'ternary': t.flag ? 'yes' : 'no',\n"
        "  'call': helper(t, {'arg': 1}),\n"
        "  'text': 'not: a key',\n"
        "};\n"
        "\n"
        "Map<String, Object?> archiveBlockToJson(Block b) {\n"
        "  if (b.bad) throw StateError('x: y');\n"
        "  return {'k1': b.k1, 'k2': b.k2};\n"
        "}\n"
        "\n"
        "String archiveIso(DateTime dt) => 'x';\n"
    )
    keys = entity_keys(src)
    expect(
        "expression body: own keys only, in order",
        keys.get("archiveThingToJson")
        == ["id", "url", "a", "b", "c", "nested", "ternary", "call", "text"],
        str(keys.get("archiveThingToJson")),
    )
    expect(
        "block body: the returned literal",
        keys.get("archiveBlockToJson") == ["k1", "k2"],
        str(keys.get("archiveBlockToJson")),
    )
    expect("non-map function ignored", "archiveIso" not in keys, str(keys))


def test_check_rules() -> None:
    print("check rules")
    keys = {"archiveFooToJson": ["id", "newKey", "gated"]}
    stamped = {"requiredSchemaVersion": {"archiveSchemaVersionGated"}}
    declared = {"archiveSchemaVersionGated", "archiveSchemaVersionUnused"}

    ok = {"archiveFooToJson": {
        "id": "baseline", "newKey": "archiveSchemaVersionGated",
        "gated": "archiveSchemaVersionGated",
    }}
    expect("fully classified passes", check(keys, ok, stamped, declared) == [])

    missing = {"archiveFooToJson": {
        "id": "baseline", "gated": "archiveSchemaVersionGated",
    }}
    problems = check(keys, missing, stamped, declared)
    expect(
        "unclassified key flagged",
        len(problems) == 1 and "'newKey'" in problems[0],
        str(problems),
    )

    stale = {"archiveFooToJson": {**ok["archiveFooToJson"], "gone": "baseline"}}
    problems = check(keys, stale, stamped, declared)
    expect(
        "stale entry flagged",
        len(problems) == 1 and "'gone'" in problems[0],
        str(problems),
    )

    extra_fn = {**ok, "archiveGoneToJson": {"id": "baseline"}}
    problems = check(keys, extra_fn, stamped, declared)
    expect(
        "unknown function flagged",
        len(problems) == 1 and "archiveGoneToJson" in problems[0],
        str(problems),
    )

    undeclared = {"archiveFooToJson": {
        **ok["archiveFooToJson"], "newKey": "archiveSchemaVersionTypo",
    }}
    problems = check(keys, undeclared, stamped, declared)
    expect(
        "undeclared constant flagged",
        len(problems) == 1 and "not a declared" in problems[0],
        str(problems),
    )

    unstamped = {"archiveFooToJson": {
        **ok["archiveFooToJson"], "newKey": "archiveSchemaVersionUnused",
    }}
    problems = check(keys, unstamped, stamped, declared)
    expect(
        "declared but unstamped constant flagged",
        len(problems) == 1 and "nothing stamps it" in problems[0],
        str(problems),
    )


def test_stamper_parsing() -> None:
    print("stamper parsing")
    src = (
        "const int vBase = 1;\n"
        "const int vNew = 2;\n"
        "/// Mentions vDoc only in a comment.\n"
        "int requiredThing(Doc d, {bool flag = true}) {\n"
        "  // vComment is not used\n"
        "  if (d.x) return vNew;\n"
        "  return vBase;\n"
        "}\n"
        "int other() => vOther;\n"
    )
    used = stamper_constants(src, "requiredThing")
    expect("body constants found", {"vNew", "vBase"} <= used, str(used))
    expect(
        "comments and other functions excluded",
        not ({"vDoc", "vComment", "vOther"} & used),
        str(used),
    )
    expect("declarations found", declared_constants(src) == {"vBase", "vNew"})


def _real_inputs() -> tuple[str, dict, dict, set]:
    codec = (REPO_ROOT / CODEC).read_text(encoding="utf-8")
    manifest = json.loads((REPO_ROOT / MANIFEST).read_text(encoding="utf-8"))
    stamped: dict[str, set[str]] = {}
    declared: set[str] = set()
    for path, function in STAMPERS:
        source = (REPO_ROOT / path).read_text(encoding="utf-8")
        stamped[function] = stamper_constants(source, function)
        declared |= declared_constants(source)
    return codec, manifest, stamped, declared


def test_real_tree() -> None:
    print("the real tree")
    codec, manifest, stamped, declared = _real_inputs()
    keys = entity_keys(codec)
    expect(
        "dance and program are both covered",
        {"archiveDanceToJson", "archiveProgramToJson"} <= keys.keys(),
        str(sorted(keys)),
    )
    expect(
        "pay and dialect are stamped by the backup envelope",
        all(
            manifest["archiveProgramToJson"][k] == "backupSchemaVersionProgramPay"
            for k in ("dialectName", "payMinorUnits", "payCurrency")
        ),
    )
    expect("main() passes on the tree", main() == 0)

    # The hazard itself: a program key written only when set, with no case.
    anchor = "  if (p.dialectName != null) 'dialectName': p.dialectName,\n"
    expect("anchor present in the codec", anchor in codec)
    mutated = codec.replace(
        anchor, anchor + "  if (p.newThing != null) 'newThing': p.newThing,\n"
    )
    problems = check(entity_keys(mutated), manifest, stamped, declared)
    expect(
        "a new unversioned program key fails",
        len(problems) == 1 and "'newThing'" in problems[0],
        str(problems),
    )

    # Dropping the backup case leaves pay naming a constant nothing stamps.
    unstamped = {k: v - {"backupSchemaVersionProgramPay"} for k, v in stamped.items()}
    problems = check(entity_keys(codec), manifest, unstamped, declared)
    expect(
        "pay without its stamping case fails",
        len(problems) == 3 and all("nothing stamps it" in p for p in problems),
        str(problems),
    )


def run() -> int:
    test_key_extraction()
    test_check_rules()
    test_stamper_parsing()
    test_real_tree()
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s)")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(run())
