#!/usr/bin/env python3
"""Offline tests for ``check_doc_gate_references.py``.

Run directly: ``python3 tools/ci/test_check_doc_gate_references.py``.

``citations`` and ``sibling_test`` are pure and table-driven. ``check`` runs
against a throwaway tree. The last group runs the real script against a
throwaway git repository, and against this repository as a positive control: a
scan that read nothing would also be "clean", so the real run must find the
citations it is known to contain.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_doc_gate_references.py"
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import check_doc_gate_references as gate  # noqa: E402

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(name)
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def paths(text: str) -> list[tuple[int, str]]:
    return gate.citations(text)


CITE_TABLE = [
    ("run `tools/ci/check_a.py` first", [(1, "tools/ci/check_a.py")], "inline span"),
    ("run `python3 tools/ci/check_a.py \"$BASE\"`", [(1, "tools/ci/check_a.py")], "path inside a command span"),
    ("see tools/ci/check_a.py in prose", [], "prose outside backticks is not read"),
    ("`tools/ci/check_*.py` and `tools/ci/check_<name>.py`", [], "globs and placeholders name no file"),
    ("`app/tools/x.py` and `docs/tools/x.py`", [], "a longer path is a different path"),
    ("`tools/a.sh` and `tools/b/c.py`", [(1, "tools/a.sh"), (1, "tools/b/c.py")], "sh and py, two in a line"),
    ("`tools/ci/readme.md`", [], "only py and sh"),
    ("```sh\npython3 tools/ci/check_a.py\n```\n`tools/x.py`", [(2, "tools/ci/check_a.py"), (4, "tools/x.py")], "fenced lines are read, with their line"),
    ("~~~\ntools/ci/check_a.py\n~~~", [(2, "tools/ci/check_a.py")], "tilde fence"),
    ("```\n~~~\ntools/ci/check_a.py\n```\ntools/ci/check_b.py", [(3, "tools/ci/check_a.py")], "a tilde inside a backtick fence does not close it"),
    ("`tools/ci/check_a.py.bak`", [], "no trailing extension continuation"),
    ("see `tools/ci/check_a.py`.", [(1, "tools/ci/check_a.py")], "a sentence-ending period is not a continuation"),
]

OWED_TABLE = [
    ("tools/ci/check_a.py", "tools/ci/test_check_a.py"),
    ("tools/ci/report_a.py", None),
    ("tools/ci/test_check_a.py", None),
    ("tools/ci/helper.py", None),
    ("tools/release/compile.py", "tools/release/test_compile.py"),
    ("tools/release/test_compile.py", None),
    ("tools/preflight.py", None),
    ("tools/site/render.py", None),
]


def build(root: Path, present: list[str]) -> None:
    for rel in present:
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("", encoding="utf-8")


def git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, check=False)


def main() -> int:
    for text, expected, why in CITE_TABLE:
        got = paths(text)
        check(f"citations: {why}", got == expected, repr(got))
    for path, expected in OWED_TABLE:
        check(f"sibling_test: {path}", gate.sibling_test(path) == expected, repr(gate.sibling_test(path)))

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        build(root, [
            "tools/ci/check_ok.py", "tools/ci/test_check_ok.py",
            "tools/ci/check_untested.py",
            "tools/release/rel.py",
            "tools/ci/check_l10n_drift.py",
        ])
        doc = "`tools/ci/check_ok.py` is fine\n`tools/ci/check_gone.py` is not\n`tools/ci/check_untested.py` has no test\n`tools/release/rel.py` neither\n"
        # Exemptions are cited, so only the real findings remain.
        exempt_docs = "`tools/publish_collections.py` and `check_l10n_drift.py` in a table\n"
        found = gate.check(root, {"docs/dev/a.md": doc, "docs/dev/b.md": exempt_docs})
        joined = "\n".join(found)
        check("missing path is named with document and line", "docs/dev/a.md:2: cites tools/ci/check_gone.py, which does not exist" in joined, joined)
        check("untested check_ is named", "docs/dev/a.md:3: cites tools/ci/check_untested.py, which has no sibling test (tools/ci/test_check_untested.py)" in joined, joined)
        check("untested release tool is named", "docs/dev/a.md:4: cites tools/release/rel.py, which has no sibling test (tools/release/test_rel.py)" in joined, joined)
        check("a good citation is silent", "check_ok.py" not in joined, joined)
        check("both exemptions hold when cited", "EXEMPT" not in joined and "publish_collections" not in joined and "l10n_drift" not in joined, joined)
        check("exactly the three findings", len(found) == 3, joined)

        # An exemption waives only its own rule: l10n_drift is owed no test, but must exist;
        # publish_collections may be absent, but must not be exempt from anything else.
        by_path = "`tools/ci/check_l10n_drift.py` cited by its full path\n"
        check("exempt-untested: cited by full path, present, no test: silent", gate.check(root, {"docs/dev/c.md": by_path, "docs/dev/b.md": exempt_docs}) == [])
        (root / "tools/ci/check_l10n_drift.py").unlink()
        gone = "\n".join(gate.check(root, {"docs/dev/c.md": by_path, "docs/dev/b.md": exempt_docs}))
        check("exempt-untested still has to exist", "docs/dev/c.md:1: cites tools/ci/check_l10n_drift.py, which does not exist" in gone, gone)
        build(root, ["tools/ci/check_l10n_drift.py"])

        stale = gate.check(root, {"docs/dev/a.md": "`tools/ci/check_ok.py`\n"})
        check("an exemption cited nowhere is stale", sum("EXEMPT entry" in f and "cited by no document" in f for f in stale) == 2, "\n".join(stale))

        gen = "<!-- generated-by: x -->\n`tools/ci/check_gone.py`\n"
        check("a generated document is not read", not any("check_gone" in f for f in gate.check(root, {"docs/dev/g.md": gen, "docs/dev/b.md": exempt_docs})))

        # An exemption that stopped being true must be dropped.
        build(root, ["tools/publish_collections.py", "tools/ci/test_check_l10n_drift.py"])
        late = "\n".join(gate.check(root, {"docs/dev/b.md": exempt_docs}))
        check("exempt-missing that now exists is flagged", "tools/publish_collections.py now exists" in late, late)
        check("exempt-untested that now has a test is flagged", "tools/ci/check_l10n_drift.py now has a test" in late, late)

    # The real script against a throwaway git repository.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        git(root, "init", "-q", ".")
        build(root, ["tools/ci/check_ok.py", "tools/ci/test_check_ok.py", "tools/publish_collections.py", "tools/ci/check_l10n_drift.py"])
        (root / "docs/dev").mkdir(parents=True)
        (root / "docs/dev/a.md").write_text("`tools/ci/check_ok.py`\n", encoding="utf-8")
        (root / "docs/dev/ex.md").write_text("`tools/publish_collections.py` `check_l10n_drift.py`\n", encoding="utf-8")
        run = lambda: subprocess.run([sys.executable, str(SCRIPT), str(root)], capture_output=True, text=True)
        (root / "tools/publish_collections.py").unlink()  # it lives in another repository
        res = run()
        check("e2e: clean tree exit 0", res.returncode == 0, res.stdout + res.stderr)
        (root / "docs/dev/a.md").write_text("`tools/ci/check_ok.py`\nSee `tools/ci/check_does_not_exist.py`.\n", encoding="utf-8")
        res = run()
        check("e2e: a cited script that does not exist fails with document and line",
              res.returncode == 1 and "docs/dev/a.md:2: cites tools/ci/check_does_not_exist.py" in res.stdout and "1 finding(s)" in res.stdout,
              res.stdout)
        empty = Path(tmp) / "nothing"
        empty.mkdir()
        git(empty, "init", "-q", ".")
        res = subprocess.run([sys.executable, str(SCRIPT), str(empty)], capture_output=True, text=True)
        check("e2e: nothing in scope is exit 2, not a pass", res.returncode == 2, res.stdout + res.stderr)

    # Positive control on the real tree: the scan must see what it is known to hold.
    agents = (REPO / "AGENTS.md").read_text(encoding="utf-8")
    seen = {p for _n, p in gate.citations(agents)}
    check("control: AGENTS.md's cited gates are found", {"tools/preflight.py", "tools/ci/check_pr_review_gates.py"} <= seen, repr(sorted(seen)))
    res = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True, cwd=REPO)
    check("control: the repository passes", res.returncode == 0, res.stdout + res.stderr)
    total = sum(len(gate.citations((REPO / n).read_text(encoding="utf-8"))) for n in gate.scoped_files(REPO) if (REPO / n).is_file())
    check("control: the repository has many citations (a scan that reads nothing would pass too)", total >= 50, str(total))

    if FAILURES:
        print(f"\n{len(FAILURES)} check(s) failed")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
