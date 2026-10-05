#!/usr/bin/env python3
"""Offline tests for ``check_stale_comment_refs.py`` -- the comment-citation ceiling.

Pure-stdlib, assert-based (no pytest, matching the rest of ``tools/ci/test_*.py``).
Run directly::

    python3 tools/ci/test_check_stale_comment_refs.py

Each test builds a throwaway tree shaped like the repo (``app/lib``,
``packages/compendium_core/lib``, ``app/lib/l10n/app_en.arb``) so the real
scan roots and ARB path are exercised, not a mock of them.
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_stale_comment_refs as checker  # noqa: E402


def make_tree(files: dict[str, str], arb: dict[str, str] | None = None) -> Path:
    root = Path(tempfile.mkdtemp(prefix="stale_refs_"))
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    if arb is not None:
        arb_path = root / checker.ARB_PATH
        arb_path.parent.mkdir(parents=True, exist_ok=True)
        arb_path.write_text(json.dumps(arb), encoding="utf-8")
    return root


def names(files: dict[str, str], arb: dict[str, str] | None = None) -> list[str]:
    findings, _ = checker.scan(make_tree(files, arb))
    return [f.name for f in findings]


def lib(text: str) -> dict[str, str]:
    return {"app/lib/a.dart": text}


def test_resolving_citation_is_clean() -> None:
    src = "/// Uses [Widget] and [Widget.build].\nclass Widget { void build() {} }\n"
    assert names(lib(src)) == []


def test_reports_unresolved_dartdoc_ref() -> None:
    src = "/// See [nothingHere].\nclass Widget {}\n"
    assert names(lib(src)) == ["nothingHere"]


def test_unresolved_member_segment() -> None:
    src = "/// See [Widget.gone].\nclass Widget {}\n"
    assert names(lib(src)) == ["Widget.gone"]


def test_backtick_citation_is_checked() -> None:
    src = "// Calls `resolveGone` and `_privateGone` and `Widget.gone`.\nclass Widget {}\n"
    assert names(lib(src)) == ["Widget.gone", "_privateGone", "resolveGone"]


def test_backtick_prose_is_not_a_citation() -> None:
    src = (
        "// Returns `null` from `main`, see `foo.dart`, `snake_case`, `a + b`,\n"
        "// `README.md` and `x.y`.\nclass Widget {}\n"
    )
    assert names(lib(src)) == []


def test_acronym_leading_type_member_is_checked() -> None:
    src = "// `IOSink.add` and `IOSink.gone`; also [HTTPThing.gone].\nclass IOSink { void add() {} }\n"
    assert names(lib(src)) == ["HTTPThing.gone", "IOSink.gone"]


def test_arb_key_resolves() -> None:
    src = "// Uses `someMessageKey`; the old `goneMessageKey` was removed.\nclass W {}\n"
    arb = {"@@locale": "en", "someMessageKey": "x", "@someMessageKey": "{}"}
    assert names(lib(src), arb) == ["goneMessageKey"]


def test_cross_package_symbol_resolves() -> None:
    files = {
        "app/lib/a.dart": "/// See [CoreThing].\nclass A {}\n",
        "packages/compendium_core/lib/c.dart": "class CoreThing {}\n",
    }
    assert names(files) == []


def test_symbol_only_in_comment_is_unresolved() -> None:
    files = {
        "app/lib/a.dart": "/// See `onlyHereInComment`.\nclass A {}\n",
        "app/lib/b.dart": "// `onlyHereInComment` again.\nclass B {}\n",
    }
    assert names(files) == ["onlyHereInComment", "onlyHereInComment"]


def test_string_literal_text_resolves_and_is_not_a_comment() -> None:
    src = (
        "const url = 'https://example.com/[notACitation]'; // `realKey`\n"
        "const k = 'realKey';\n"
        "final s = '${m['nestedQuote']} // `alsoNotAComment`';\n"
    )
    assert names(lib(src)) == []


def test_markdown_links_and_index_expressions_are_skipped() -> None:
    src = "/// [text](http://x) and args[0] and f(x)[i] and [a, b] and [1].\nclass A {}\n"
    assert names(lib(src)) == []


def test_fenced_code_is_skipped() -> None:
    src = "/// ```dart\n/// final y = [goneName]; `goneTick`\n/// ```\nclass A {}\n"
    assert names(lib(src)) == []


def test_backtick_span_wrapped_over_two_lines() -> None:
    src = "/// Mentions `wrappedGone\n/// Name` then `found`.\nclass found {}\n"
    # The wrapped span is not an identifier (it contains a newline); the pairing
    # must stay aligned so `found` is still read as its own span and resolves.
    assert names(lib(src)) == []


def test_block_comments_and_nesting() -> None:
    src = "/* outer [goneInBlock] /* inner */ `stillComment` */\nclass A {}\n"
    assert names(lib(src)) == ["goneInBlock", "stillComment"]


def test_generated_files_are_indexed_not_scanned() -> None:
    files = {
        "app/lib/l10n/app_localizations.dart": "/// [goneInGenerated]\nclass GeneratedSym {}\n",
        "app/lib/a.dart": "/// [GeneratedSym]\nclass A {}\n",
    }
    assert names(files) == []


def test_stop_list() -> None:
    src = "/// [this] [null] [true] [Foo.new]\nclass Foo {}\n"
    assert names(lib(src)) == []


def run_main(root: Path, *argv: str) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = checker.main(["--root", str(root), *argv])
    return code, out.getvalue()


def test_ceiling_fails_when_exceeded() -> None:
    root = make_tree(lib("/// [goneA] [goneB]\nclass A {}\n"))
    assert run_main(root, "--ceiling", "2")[0] == 0
    code, out = run_main(root, "--ceiling", "1")
    assert code == 1 and "exceeds the ceiling of 1" in out
    code, out = run_main(root, "--ceiling", "3")
    assert code == 0 and "lower" in out  # a ceiling above the count nags


def test_ceiling_file_is_read_and_valid() -> None:
    assert checker.read_ceiling() >= 0
    bad = Path(tempfile.mkdtemp()) / "c.json"
    for text in ('{"ceiling": -1}', '{"ceiling": "5"}', '{"ceiling": true}', "{}"):
        bad.write_text(text)
        try:
            checker.read_ceiling(bad)
        except (ValueError, KeyError):
            continue
        raise AssertionError(f"accepted bad ceiling file {text}")


def test_empty_tree_is_bad_input() -> None:
    root = Path(tempfile.mkdtemp())
    assert run_main(root, "--ceiling", "0")[0] == 2


def test_real_tree_is_at_or_under_the_ceiling() -> None:
    findings, _ = checker.scan(checker.REPO_ROOT)
    assert len(findings) <= checker.read_ceiling(), len(findings)


def main() -> int:
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  ok   {name}")
            except AssertionError as e:
                failures += 1
                print(f"  FAIL {name}: {e!r}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
