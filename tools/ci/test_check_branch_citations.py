#!/usr/bin/env python3
"""Offline tests for ``check_branch_citations.py`` -- the branch-citation ratchet.

Pure-stdlib, assert-based, like the rest of ``tools/*/test_*.py``. Run::

    python3 tools/ci/test_check_branch_citations.py

The cases split into what the ratchet exists to catch and the legitimate text
that must stay quiet. Where a case quotes a real line it says so: most flagged
cases are lines that were on ``main`` at ``0e2ad7a`` before the October 2026
audit record was brought onto it; the rest are synthetic variants of the same
shapes. The last group builds a throwaway git repository so
the whole-tree path (``git ls-files``, scope, line numbers) is exercised too.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_branch_citations import (  # noqa: E402
    dart_comment_lines,
    find_citations,
    in_scope,
    main,
    scan_file,
    scan_tree,
)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def rules(text: str) -> list[str]:
    return [rule for rule, _ in find_citations(text)]


def test_flags_branch_citations() -> None:
    print("branch citations are flagged:")
    cases = {
        "agent branch in backticks": (
            "`maintainer-decisions-2026-10-30.md`, on "
            "`claude/app-audit-categories-k2pdon`).",
            "agent-branch",
        ),
        "agent branch, bare": (
            "built on claude/called-filter-scopes yesterday",
            "agent-branch",
        ),
        "copilot branch": ("see copilot/fix-123 for the probe", "agent-branch"),
        "remote-tracking name": (
            "diff against origin/claude/app-audit-categories-k2pdon",
            "agent-branch",
        ),
        "full ref name": ("pushed to refs/heads/claude/foo-bar", "agent-branch"),
        "upstream remote name": ("compare upstream/claude/x-y", "agent-branch"),
        "the audit branches, plural": ("on the audit branches", "audit-branch"),
        "branch `name`": (
            "  - PR2 delivered (branch `isaacbanner-dialect-pr2`): the library",
            "named-branch",
        ),
        "this branch, `name`": (
            "  - PR1 (this branch, `dialect-term-editor`): core",
            "named-branch",
        ),
        "`name` branch": ("read it on the `feat/batch-delete` branch", "named-branch"),
        "compare to a branch": (
            "https://github.com/o/r/compare/main...claude/x",
            "github-ref",
        ),
        "github blob on a branch": (
            "https://github.com/o/r/blob/claude/x/docs/a.md",
            "github-ref",
        ),
        "github tree on a branch": (
            "https://github.com/o/r/tree/feature-y/docs",
            "github-ref",
        ),
        "the audit branch": (
            "/// `docs/dev/audits/2026-10-behavior/` on the audit branch).",
            "audit-branch",
        ),
    }
    for name, (text, rule) in cases.items():
        got = rules(text)
        check(name, rule in got, f"got {got}")


def test_leaves_legitimate_text() -> None:
    print("legitimate text is not flagged:")
    quiet = {
        "dot-claude path": "see `.claude/settings.json`",
        "nested claude dir": "tools/claude/run.py",
        "glob of session branches": "Remote `claude/*` branches can be pruned.",
        "planned branch in a plan table": (
            "| H1 | `feat/called-filter-scopes` | `CalledFilter` gains `venue` |"
        ),
        "planned fix branch named in prose": "B14 (`feat/picker-parity`, FIND-7)",
        "a code branch of an if": "the `existenceAt` branch keeps the row",
        "an expression branch": "the `give=true` branch of the parser",
        "a qualified identifier": "the `ParamKind.rotation` branch",
        "a file in backticks": "the `docs/dev/releasing.md` branch section",
        "main": "merged to the `main` branch",
        "gh-pages": "a persistent `gh-pages` branch (cross-channel-preserving)",
        "github blob at a SHA": (
            "https://github.com/o/r/blob/c650d90c2839619f6b9987dbe260cdf8c3d76cf9/a.md"
        ),
        "github blob on main": "https://github.com/o/r/blob/main/a.md",
        "github tree at a tag": "https://github.com/o/r/tree/v0.10.0/app",
        "github compare of two SHAs": "https://github.com/o/r/compare/abc1234...def5678",
        "github blob at HEAD": "https://github.com/o/r/blob/HEAD/a.md",
        "a hyphenated code branch": "the `else-if` branch returns early",
        "another hyphenated code branch": "the `null-aware` branch",
        "implementation branch, generic": "Each implementation branch updates these",
        "relative docs path": "[releasing.md](dev/releasing.md)",
    }
    for name, text in quiet.items():
        got = find_citations(text)
        check(name, got == [], f"got {got}")


def test_wrapped_citation() -> None:
    print("a citation wrapped across two lines is caught:")
    doc = "accepted (`design-work-plan.md` ambiguity 5, on the audit\nbranch): one\n"
    found = scan_file("docs/design/x.md", doc)
    check("wrapped audit branch", [f[1:3] for f in found] == [(1, "audit-branch")], f"{found}")
    doc = "in `maintainer-decisions-2026-10-30.md` on\nbranch `claude/x-y`): \"Merges\n"
    found = scan_file("docs/design/x.md", doc)
    check(
        "wrapped agent branch reported once, on its own line",
        [(f[1], f[3]) for f in found] == [(2, "claude/x-y")],
        f"{found}",
    )
    doc = "> recorded in\n> `docs/dev/audits/` on the audit branch. The guard\n"
    found = scan_file("docs/design/x.md", doc)
    check("blockquoted line", [f[1] for f in found] == [2], f"{found}")


def test_trailing_period() -> None:
    print("a sentence-ending period is not part of the name:")
    got = find_citations("It was built on claude/fix-windows-company-name.")
    check("period stripped", got == [("agent-branch", "claude/fix-windows-company-name")], f"{got}")


def test_dart_comments_only() -> None:
    print("Dart: only comments are read:")
    src = (
        "/// recorded in `docs/x/` on the audit branch).\n"
        "const ref = 'refs/heads/claude/real-branch'; // a fixture, fine\n"
        'final url = "https://github.com/o/r/tree/claude/x"; // ok\n'
        "/* see claude/block-branch */\n"
        "final s = '''\n"
        "// claude/inside-a-raw-string\n"
        "''';\n"
        "int x = 1; // trailing: on branch `claude/trailing`\n"
    )
    comments = dart_comment_lines(src)
    lines = [n for n, _ in comments]
    check("comment lines found", lines == [1, 2, 3, 4, 8], f"{comments}")
    found = scan_file("app/lib/x.dart", src)
    got = sorted((f[1], f[3]) for f in found)
    check(
        "string literals ignored, comments flagged",
        got
        == [
            (1, "audit branch"),
            (4, "claude/block-branch"),
            (8, "claude/trailing"),
        ],
        f"{got}",
    )
    wrapped = "/// recorded in `docs/x/` on the audit\n/// branch, not main.\n"
    found = scan_file("app/lib/x.dart", wrapped)
    check(
        "wrapped /// doc comment",
        [(f[1], f[2]) for f in found] == [(1, "audit-branch")],
        f"{found}",
    )
    nested = "/* outer /* inner */ still a comment: claude/nested-x */\nint y;\n"
    found = scan_file("app/lib/x.dart", nested)
    check(
        "nested block comment",
        [f[3] for f in found] == ["claude/nested-x"],
        f"{found}",
    )


def test_scope() -> None:
    print("scope:")
    check("markdown anywhere", in_scope("tools/README.md") == "doc")
    check("docs svg", in_scope("docs/user/images/x.svg") == "doc")
    check("app dart", in_scope("app/lib/a.dart") == "dart")
    check("server dart", in_scope("server/bin/a.dart") == "dart")
    check("generated dart skipped", in_scope("packages/c/lib/a.g.dart") is None)
    check(
        "generated directory skipped",
        in_scope("packages/c/test/storage/generated/schema_v3.dart") is None,
    )
    check(
        "generated_ file skipped",
        in_scope("packages/c/lib/src/sync/generated_sync_allow_list.dart") is None,
    )
    check(
        "generated localizations skipped",
        in_scope("app/lib/l10n/app_localizations_de.dart") is None,
    )
    check(
        "the audit record is exempt",
        in_scope("docs/dev/audits/2026-10-behavior/followups-log.md") is None,
    )
    check("other audits are not", in_scope("docs/dev/audits/2027-01-x/a.md") == "doc")
    check("workflow yaml out of scope", in_scope(".github/workflows/ci.yml") is None)
    check("python tooling out of scope", in_scope("tools/release/x.py") is None)
    check("tool dart outside roots", in_scope("tools/x.dart") is None)


def _git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def test_tree() -> None:
    print("whole tree:")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        _git(root, "init", "-q")
        (root / "docs").mkdir()
        (root / "docs/a.md").write_text("ok\nsee `claude/foo-bar` for it\n")
        (root / "docs/b.md").write_text("all on `main`\n")
        (root / "untracked.md").write_text("claude/not-yet-staged\n")
        (root / ".gitignore").write_text("ignored.md\n")
        (root / "ignored.md").write_text("claude/ignored\n")
        (root / ".github/workflows").mkdir(parents=True)
        (root / ".github/workflows/x.yml").write_text("branches: [claude/x]\n")
        _git(root, "add", "docs", ".github")
        found = scan_tree(root)
        # The unstaged file is read: a local preflight before `git add` once
        # passed a tree whose CI run would have failed.
        check(
            "tracked and unstaged docs flagged; ignored file and yaml are not",
            [(f[0], f[1]) for f in found] == [("docs/a.md", 2), ("untracked.md", 1)],
            f"{found}",
        )
        check("exit code 1 on a finding", main(["--root", str(root)]) == 1)
        (root / "docs/a.md").write_text("ok\nsee #2059 for it\n")
        (root / "untracked.md").unlink()
        check("exit code 0 once fixed", main(["--root", str(root)]) == 0)
    check("bad arguments exit 2", main(["--nope"]) == 2)


def main_() -> int:
    test_flags_branch_citations()
    test_leaves_legitimate_text()
    test_wrapped_citation()
    test_trailing_period()
    test_dart_comments_only()
    test_scope()
    test_tree()
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s):")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nall branch-citation tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main_())
