#!/usr/bin/env python3
"""Offline tests for ``report_comment_weight.py``.

The classifier is the part worth testing: it is a line scanner, not a lexer, and
its known blind spots are documented in the tool rather than fixed. A test suite
that only covered the cases it gets right would read as though it had none, so
the deliberate miscounts are asserted here too -- if someone later writes a real
lexer, these are the assertions that should flip.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "report_comment_weight.py"

sys.path.insert(0, str(HERE))

from report_comment_weight import (  # noqa: E402
    RESIDENT_BUDGET_BYTES,
    collect,
    is_generated,
    measure,
    report,
)


def run(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(repo), *args],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )


def build(tmp: str | Path, files: dict[str, str]) -> Path:
    repo = Path(tmp) / "repo"
    (repo / ".github").mkdir(parents=True)
    for name, contents in files.items():
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")
    return repo


def test_doc_and_line_comments_count_as_comment() -> None:
    weight = measure("/// doc\n// line\nfinal x = 1;\n")
    assert weight.comment_bytes == len("/// doc\n") + len("// line\n"), weight
    assert weight.code_bytes == len("final x = 1;\n"), weight


def test_block_comment_spans_lines() -> None:
    weight = measure("/*\n * why\n */\nfinal x = 1;\n")
    assert weight.code_bytes == len("final x = 1;\n"), weight
    assert weight.comment_bytes == len("/*\n * why\n */\n"), weight


def test_single_line_block_comment_does_not_open_a_block() -> None:
    # The `*/` is on the same line, so the following line is code. Getting this
    # wrong would silently reclassify the entire rest of the file as comment.
    weight = measure("/* short */\nfinal x = 1;\n")
    assert weight.code_bytes == len("final x = 1;\n"), weight


def test_blank_lines_count_as_neither() -> None:
    # Otherwise reformatting would move the share without changing a word.
    weight = measure("\n\n\nfinal x = 1;\n\n\n")
    assert weight.total_bytes == len("final x = 1;\n"), weight


def test_share_of_an_empty_file_is_zero_not_an_error() -> None:
    assert measure("").share == 0.0
    assert measure("\n\n").share == 0.0


def test_trailing_comments_are_undercounted() -> None:
    # Documented limitation, asserted so it is a known state rather than a
    # surprise: the comment here is billed to code.
    weight = measure("final x = 1; // why\n")
    assert weight.comment_bytes == 0, weight
    assert weight.code_bytes == len("final x = 1; // why\n"), weight


def test_a_comment_like_line_inside_a_string_is_overcounted() -> None:
    # The other documented limitation, in the opposite direction.
    weight = measure("const s = '''\n// not really a comment\n''';\n")
    assert weight.comment_bytes == len("// not really a comment\n"), weight


def test_generated_files_are_detected_by_suffix_and_dir_and_marker() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(
            tmp,
            {
                "app/lib/thing.g.dart": "final x = 1;\n",
                "app/lib/l10n/app_localizations.dart": "final x = 1;\n",
                "app/lib/marked.dart": "// GENERATED CODE - DO NOT MODIFY BY HAND\n",
                "app/lib/hand_written.dart": "/// why\nfinal x = 1;\n",
            },
        )
        assert is_generated(repo / "app/lib/thing.g.dart")
        assert is_generated(repo / "app/lib/l10n/app_localizations.dart")
        assert is_generated(repo / "app/lib/marked.dart")
        assert not is_generated(repo / "app/lib/hand_written.dart")

        measured = collect(repo, ["app/lib"])
        assert list(measured) == [Path("app/lib/hand_written.dart")], measured


def test_report_names_files_over_the_resident_budget() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        heavy = "// " + "x" * 100 + "\n"
        repo = build(
            tmp,
            {
                "app/lib/heavy.dart": heavy * 200,
                "app/lib/light.dart": "/// why\nfinal x = 1;\n",
            },
        )
        measured = collect(repo, ["app/lib"])
        assert measured[Path("app/lib/heavy.dart")].comment_bytes > RESIDENT_BUDGET_BYTES
        lines = "\n".join(report(measured, top=5))
        assert "resident budget" in lines, lines
        assert "app/lib/heavy.dart" in lines, lines


def test_a_tree_with_no_heavy_files_says_nothing_about_the_budget() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(tmp, {"app/lib/light.dart": "/// why\nfinal x = 1;\n"})
        lines = "\n".join(report(collect(repo, ["app/lib"]), top=5))
        assert "resident budget" not in lines, lines


def test_json_output_is_parseable_and_per_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(tmp, {"app/lib/thing.dart": "/// why\nfinal x = 1;\n"})
        result = run(repo, "--json")
        assert result.returncode == 0, result.stdout + result.stderr
        payload = json.loads(result.stdout)
        entry = payload["files"]["app/lib/thing.dart"]
        assert entry["comment_bytes"] == len("/// why\n"), payload
        assert entry["code_bytes"] == len("final x = 1;\n"), payload


def test_a_heavy_tree_still_exits_zero() -> None:
    # The point of the tool: it reports, it does not gate. If this ever starts
    # failing the build, the incentive flips to deleting rationale.
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(tmp, {"app/lib/heavy.dart": ("// " + "x" * 100 + "\n") * 500})
        result = run(repo)
        assert result.returncode == 0, result.stdout + result.stderr


def test_a_directory_that_is_not_the_repository_root_exits_two() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        result = run(Path(tmp))
        assert result.returncode == 2, result.stdout + result.stderr


def test_an_empty_scan_says_so_rather_than_dividing_by_zero() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = build(tmp, {"README.md": "not dart\n"})
        result = run(repo)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "no hand-written Dart found" in result.stdout, result.stdout


def test_this_repository_reports_without_error() -> None:
    result = run(HERE.parent.parent)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "hand-written Dart:" in result.stdout, result.stdout


def main() -> int:
    tests = [
        value for name, value in sorted(globals().items()) if name.startswith("test_")
    ]
    for test in tests:
        test()
    print(f"OK: {len(tests)} comment-weight report tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
