#!/usr/bin/env python3
"""Offline tests for ``check_l10n_unused.py``. Run directly::

    python3 tools/ci/test_check_l10n_unused.py

Pure stdlib, assert-based (matching the rest of ``tools/ci/test_*.py``). Each
case builds a throwaway fixture tree: an ``app_en.arb`` plus Dart files.
"""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_l10n_unused as chk  # noqa: E402

FAILURES: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if not ok:
        FAILURES.append(f"{name}: {detail}" if detail else name)


def fixture(keys: list[str], files: dict[str, str]) -> list[str]:
    """Build a tree, run the checker over it, return the unused keys."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        arb: dict[str, object] = {"@@locale": "en"}
        for k in keys:
            arb[k] = "text"
            arb[f"@{k}"] = {"description": "d"}
        (root / "app/lib/l10n").mkdir(parents=True)
        (root / "app/lib/l10n/app_en.arb").write_text(json.dumps(arb))
        for rel, body in files.items():
            p = root / "app/lib" / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body)
        return chk.unused_keys(root)


def test_used_key_passes() -> None:
    got = fixture(["fooTitle"], {"a.dart": "final s = l10n.fooTitle;\n"})
    check("used key passes", got == [], str(got))
    got = fixture(["fooCount"], {"a.dart": "final s = l10n.fooCount(3);\n"})
    check("used parameterised key passes", got == [], str(got))
    got = fixture(["fooTitle"], {"a.dart": "final s = l10n\n    .fooTitle;\n"})
    check("key after a line break passes", got == [], str(got))
    got = fixture(["fooTitle"], {"a.dart": "final s = '${l10n.fooTitle}!';\n"})
    check("key inside string interpolation passes", got == [], str(got))


def test_unused_key_is_reported() -> None:
    got = fixture(
        ["fooTitle", "barTitle"], {"a.dart": "final s = l10n.fooTitle;\n"}
    )
    check("unused key is reported", got == ["barTitle"], str(got))
    got = fixture(["fooTitle"], {"a.dart": "final s = l10n.fooTitleLonger;\n"})
    check("prefix-sharing identifier is not a use", got == ["fooTitle"], str(got))
    got = fixture(["fooTitle"], {"a.dart": "final fooTitle = 1;\n"})
    check("bare local with the same name is not a use", got == ["fooTitle"], str(got))


def test_comment_only_mention_is_unused() -> None:
    src = (
        "// see l10n.fooTitle\n"
        "/// Uses [l10n.fooTitle] and `fooTitle(`.\n"
        "/* l10n.fooTitle(1) /* nested l10n.fooTitle */ l10n.fooTitle */\n"
        "final x = 1;\n"
    )
    got = fixture(["fooTitle"], {"a.dart": src})
    check("comment-only mention is unused", got == ["fooTitle"], str(got))
    src = (
        "final who = l10n.programsMatrixSectionChipQualifiedTitle(a);\n"
        "// rather than folding into `programsMatrixChipQualifiedTitle`\n"
    )
    got = fixture(
        ["programsMatrixChipQualifiedTitle", "programsMatrixSectionChipQualifiedTitle"],
        {"a.dart": src},
    )
    check(
        "worked example: key named only in a comment",
        got == ["programsMatrixChipQualifiedTitle"],
        str(got),
    )


def test_comment_markers_in_strings() -> None:
    src = "final u = 'http://x'; final s = l10n.fooTitle;\n"
    got = fixture(["fooTitle"], {"a.dart": src})
    check("// inside a string does not hide a later use", got == [], str(got))
    src = "final u = r'//'; final s = l10n.fooTitle;\n"
    got = fixture(["fooTitle"], {"a.dart": src})
    check("raw string with // does not hide a later use", got == [], str(got))
    src = "final u = '''\n// l10n.fooTitle\n'''; final s = l10n.barTitle;\n"
    got = fixture(["fooTitle", "barTitle"], {"a.dart": src})
    check(
        "text inside a string literal is not stripped (conservative: counts as used)",
        got == [],
        str(got),
    )
    src = "final u = 'it\\'s // x'; final s = l10n.fooTitle;\n"
    got = fixture(["fooTitle"], {"a.dart": src})
    check("escaped quote does not desync the scanner", got == [], str(got))


def test_generated_dir_is_ignored() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "app/lib/l10n").mkdir(parents=True)
        (root / "app/lib/l10n/app_en.arb").write_text(json.dumps({"fooTitle": "t"}))
        (root / "app/lib/l10n/app_localizations.dart").write_text(
            "String get x => l10n.fooTitle;\n"
        )
        (root / "app/lib/other.dart").write_text("final x = 1;\n")
        got = chk.unused_keys(root)
    check("generated l10n dir is ignored", got == ["fooTitle"], str(got))


def test_metadata_skipped() -> None:
    got = fixture([], {"a.dart": "final x = 1;\n"})
    check("@-metadata and @@locale are not keys", got == [], str(got))


def test_real_tree_is_clean() -> None:
    got = chk.unused_keys(chk.REPO_ROOT)
    check("real tree has zero unused keys", got == [], ", ".join(got))


def main() -> int:
    test_used_key_passes()
    test_unused_key_is_reported()
    test_comment_only_mention_is_unused()
    test_comment_markers_in_strings()
    test_generated_dir_is_ignored()
    test_metadata_skipped()
    test_real_tree_is_clean()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("all check_l10n_unused tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
