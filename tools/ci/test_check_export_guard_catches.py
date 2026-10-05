#!/usr/bin/env python3
"""Offline tests for ``check_export_guard_catches.py``.

Pure-stdlib, assert-based. Run directly::

    python3 tools/ci/test_check_export_guard_catches.py
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_export_guard_catches import find_offenders, is_export_file  # noqa: E402
from check_caught_error_logged import dart_app_files, mask_source  # noqa: E402
from check_export_guard_catches import REPO_ROOT  # noqa: E402

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def lines(src: str) -> list[int]:
    return [n for n, _ in find_offenders(src)]


def test_flagged() -> None:
    print("flagged shapes")
    call = (
        "Future<void> f() async {\n"
        "  try {\n"
        "    await SharePlus.instance.share(x);\n"
        "  } on Exception catch (e, st) {\n"
        "    log(e, st);\n"
        "  }\n"
        "}\n"
    )
    check("share call + on Exception", lines(call) == [4], str(lines(call)))
    tearoff = (
        "final saver = widget.backupSaver ?? saveBackupToFile;\n"
        "try { await saver(); }\n"
        "on Exception catch (e) {}\n"
    )
    check("tear-off of saveBackupToFile", lines(tearoff) == [3], str(lines(tearoff)))
    for token in ("Printing.layoutPdf", "pickBackupFile"):
        src = "final f = x ?? " + token + ";\n} on Exception catch (e) {\n"
        check(f"tear-off of {token}", lines(src) == [2], str(lines(src)))
    bare = "final f = Printing.layoutPdf;\n} on Exception {\n"
    check("`on Exception {` without catch", lines(bare) == [2], str(lines(bare)))


def test_passed() -> None:
    print("passing shapes")
    marked = (
        "final f = x ?? saveBackupToFile;\n"
        "} on Exception catch (_) { // export-guard: exempt — not an export\n"
    )
    check("marker on the clause line", lines(marked) == [], str(lines(marked)))
    body = (
        "final f = x ?? saveBackupToFile;\n"
        "} on Exception catch (_) {\n"
        "  // export-guard: exempt — not an export\n"
        "}\n"
    )
    check("marker as first body line", lines(body) == [], str(lines(body)))
    other = (
        "final f = x ?? saveBackupToFile;\n"
        "} on Exception catch (_) {\n"
        "}\n"
        "void g() {\n"
        "  // export-guard: exempt — belongs to another clause\n"
        "}\n"
    )
    check("marker outside the clause does not count", lines(other) == [2], str(lines(other)))
    in_string = (
        "final f = x ?? saveBackupToFile;\n"
        "} on Exception catch (_) {\n"
        "  final s = 'export-guard: exempt — not a comment';\n"
        "}\n"
    )
    check("marker text in a string does not exempt", lines(in_string) == [2], str(lines(in_string)))
    nested = (
        "final f = x ?? saveBackupToFile;\n"
        "} on Exception catch (_) {\n"
        "  try {\n"
        "  } on Exception catch (_) { // export-guard: exempt — inner only\n"
        "  }\n"
        "}\n"
    )
    check("nested clause's marker does not exempt the outer", lines(nested) == [2], str(lines(nested)))
    both = nested.replace(
        "} on Exception catch (_) {\n  try {",
        "} on Exception catch (_) { // export-guard: exempt — outer\n  try {",
    )
    check("each clause needs its own marker", lines(both) == [], str(lines(both)))
    block = "final f = x ?? saveBackupToFile;\n} on Exception catch (_) { /* export-guard: exempt — r */ }\n"
    check("block-comment marker counts", lines(block) == [], str(lines(block)))
    above = (
        "final f = x ?? saveBackupToFile;\n"
        "// export-guard: exempt — on the line above, outside the clause\n"
        "} on Exception catch (_) {\n"
        "}\n"
    )
    check("marker on the line above does not count", lines(above) == [3], str(lines(above)))
    trailing = (
        "final f = x ?? saveBackupToFile;\n"
        "} on Exception catch (_) {\n"
        "} // export-guard: exempt — trailing the closing brace\n"
    )
    check("marker trailing the closing brace counts", lines(trailing) == [], str(lines(trailing)))
    obj = "final f = x ?? saveBackupToFile;\n} on Object catch (e) {\n"
    check("`on Object` is fine", lines(obj) == [])
    unrelated = "Future<void> g() async {\n} on Exception catch (e) {\n}\n"
    check("no export token: ignored", lines(unrelated) == [])
    doc = "/// See [saveBackupToFile] and [Printing.layoutPdf].\n} on Exception catch (e) {\n"
    check("dartdoc reference is not a use", lines(doc) == [])
    commented = "// saveBackupToFile(x);\n} on Exception catch (e) {\n"
    check("commented-out call is not a use", lines(commented) == [])
    string = "final s = 'saveBackupToFile';\n} on Exception catch (e) {\n"
    check("token inside a string is not a use", lines(string) == [])
    in_comment = "final f = saveBackupToFile;\n// } on Exception catch (e) {\n"
    check("on Exception inside a comment is ignored", lines(in_comment) == [])
    check("is_export_file true", is_export_file(mask_source("x = pickBackupFile;")))
    check("is_export_file false", not is_export_file(mask_source("x = other;")))


def test_real_tree_is_clean() -> None:
    print("real tree")
    bad = []
    for path in dart_app_files(REPO_ROOT):
        text = path.read_text(encoding="utf-8", errors="replace")
        for n, _ in find_offenders(text):
            bad.append(f"{path.relative_to(REPO_ROOT)}:{n}")
    check("app/lib has no unmarked export-guard catch", not bad, ", ".join(bad))


def main() -> int:
    test_flagged()
    test_passed()
    test_real_tree_is_clean()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("all check_export_guard_catches tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
