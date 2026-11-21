#!/usr/bin/env python3
"""Offline tests for ``check_doc_line_citations.py`` -- the doc line-citation ceiling.

Pure-stdlib, assert-based (no pytest, matching the rest of ``tools/ci/test_*.py``).
Run directly::

    python3 tools/ci/test_check_doc_line_citations.py

Each test builds a throwaway (non-git) tree, so the directory-walk path is used.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_doc_line_citations as checker  # noqa: E402

# Line 1 comment, 2 blank, 3 code, 4 block-comment open, 5 block-comment star, 6 code.
DART = "// header\n\nvoid a() {}\n/* c\n * d\nvoid b() {}\n"


def make_tree(files: dict[str, str]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="doc_cites_"))
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    return root


def stale(doc: str, extra: dict[str, str] | None = None) -> list[str]:
    files = {"app/lib/a.dart": DART, "docs/x.md": doc}
    files.update(extra or {})
    findings, _, _ = checker.scan(make_tree(files))
    return [f.citation for f in findings]


def run_main(root: Path, *args: str) -> tuple[int, str]:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = checker.main(["--root", str(root), *args])
    return code, buf.getvalue()


def test_code_line_is_clean() -> None:
    assert stale("See `a.dart:3` and `app/lib/a.dart:6`.\n") == []


def test_positive_control_known_stale_citations_are_counted() -> None:
    doc = "`a.dart:1` `a.dart:2` `a.dart:4` `a.dart:5` `a.dart:99` `a.dart:2-6`\n"
    assert stale(doc) == [
        "a.dart:1", "a.dart:2", "a.dart:4", "a.dart:5", "a.dart:99", "a.dart:2-6"
    ]


def test_range_checks_only_the_first_line() -> None:
    assert stale("`a.dart:3-99`\n") == []


def test_unbackticked_and_non_dart_citations_are_ignored() -> None:
    assert stale("a.dart:99 and `a.txt:99`\n") == []


def test_missing_file_is_stale() -> None:
    assert stale("`nope.dart:1`\n") == ["nope.dart:1"]


def test_ambiguous_basename_is_stale_but_repo_path_resolves() -> None:
    extra = {"app/test/a.dart": DART}
    assert stale("`a.dart:3`\n", extra) == ["a.dart:3"]
    assert stale("`app/lib/a.dart:3`\n", extra) == []


def test_partial_path_resolves_by_suffix_or_is_ambiguous() -> None:
    assert stale("`lib/a.dart:3` `lib/a.dart:1` `b/a.dart:3`\n") == ["lib/a.dart:1", "b/a.dart:3"]
    extra = {"packages/x/lib/a.dart": DART}
    assert stale("`lib/a.dart:3`\n", extra) == ["lib/a.dart:3"]  # two suffix matches
    assert stale("`x/lib/a.dart:3`\n", extra) == []


def test_audits_are_excluded() -> None:
    extra = {"docs/dev/audits/old.md": "`a.dart:99`\n"}
    assert stale("clean\n", extra) == []


def test_ceiling_is_exact() -> None:
    root = make_tree({"app/lib/a.dart": DART, "docs/x.md": "`a.dart:1` `a.dart:2`\n"})
    assert run_main(root, "--ceiling", "2")[0] == 0
    code, out = run_main(root, "--ceiling", "1")
    assert code == 1 and "exceeds" in out, out
    code, out = run_main(root, "--ceiling", "3")
    assert code == 1 and "below" in out, out


def test_no_markdown_is_bad_input() -> None:
    root = make_tree({"app/lib/a.dart": DART})
    assert run_main(root, "--ceiling", "0")[0] == 2


def test_ceiling_file_is_valid() -> None:
    assert checker.read_ceiling() >= 0


def test_real_tree_count_equals_the_ceiling() -> None:
    findings, _, _ = checker.scan(checker.REPO_ROOT)
    assert len(findings) == checker.read_ceiling(), len(findings)


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
