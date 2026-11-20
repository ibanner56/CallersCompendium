#!/usr/bin/env python3
"""Ratchet: the tool scripts the developer docs cite exist, and are tested.

The agent guide, ``CONTRIBUTING.md`` and the developer docs point at the CI
gates by path (``tools/ci/check_x.py``). A gate that is renamed or deleted
leaves those pointers dangling, and nothing noticed: #2230 (P11) found the
documents are the only thing that says a gate has a test. This checks, over
``AGENTS.md``, ``CONTRIBUTING.md``, ``docs/dev/**/*.md``,
``.github/instructions/**/*.md`` and ``.github/skills/**/*.md``:

1. every cited ``tools/**/*.py`` or ``tools/**/*.sh`` path exists;
2. every cited ``tools/ci/check_*.py`` has a sibling ``test_check_*.py``, and
   every cited ``tools/release/*.py`` a sibling ``test_*.py``.

A *citation* is such a path inside an inline backtick span, or on any line of a
fenced code block. Prose outside backticks is not read; neither are globs
(``tools/ci/check_*.py``) or placeholders (``tools/ci/check_<name>.py``), which
name no single file. A path preceded by another path character
(``app/tools/x.py``) is a different path and is skipped.

Files that carry a ``<!-- generated-by: ... -->`` first line are not read: their
source is the thing to check, and they are rewritten, not edited. They are
reported by the generator's own gate.

**Already covered elsewhere, not duplicated here:** that every ``test_*.py``
under ``tools/`` runs in a workflow and in preflight (``tools/test_preflight.py``).

Exemptions are by path, each with its reason and the one rule it waives. An
exemption that no document cites any more is itself an error, so the list cannot
outlive the citation that justified it.

Exit codes: 0 = clean, 1 = at least one finding, 2 = bad input.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

SCOPE_FILES = ("AGENTS.md", "CONTRIBUTING.md")
SCOPE_DIRS = ("docs/dev/", ".github/instructions/", ".github/skills/")

MISSING = "exists"
UNTESTED = "test"

# path -> (rule waived, reason). Each must still be cited somewhere.
EXEMPT: dict[str, tuple[str, str]] = {
    "tools/publish_collections.py": (
        MISSING,
        "lives in the Analect repository, not this one; docs/dev/releasing.md cites it as the "
        "tool that publishes there",
    ),
    "tools/ci/check_l10n_drift.py": (
        UNTESTED,
        "deliberately has no test: docs/dev/README.md calls it a thin wrapper, so there is "
        "nothing in it to test that its CI step does not already exercise",
    ),
}

_TOOL_PATH = re.compile(r"(?<![\w./*<>-])tools/[\w./-]*[\w]\.(?:py|sh)(?![\w*<>-]|\.\w)")
_SPAN = re.compile(r"`([^`\n]+)`")
_FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
GENERATED_MARKER = "<!-- generated-by:"


def citations(text: str) -> list[tuple[int, str]]:
    """``(1-based line, path)`` for every cited tool script in Markdown ``text``."""
    found: list[tuple[int, str]] = []
    fence: str | None = None
    for number, line in enumerate(text.splitlines(), start=1):
        match = _FENCE.match(line)
        if match:
            marker = match.group(1)
            if fence is None:
                fence = marker[0]
                continue
            if marker[0] == fence:
                fence = None
                continue
        if fence is not None:
            found.extend((number, m.group(0)) for m in _TOOL_PATH.finditer(line))
        else:
            for span in _SPAN.finditer(line):
                found.extend((number, m.group(0)) for m in _TOOL_PATH.finditer(span.group(1)))
    return found


def sibling_test(path: str) -> str | None:
    """The test file ``path`` is owed under the rules, or ``None`` if it owes none."""
    directory, _, name = path.rpartition("/")
    if name.startswith("test_"):
        return None
    if directory == "tools/ci" and name.startswith("check_") and name.endswith(".py"):
        return f"{directory}/test_{name}"
    if directory == "tools/release" and name.endswith(".py"):
        return f"{directory}/test_{name}"
    return None


def in_scope(path: str) -> bool:
    return path in SCOPE_FILES or (path.endswith(".md") and path.startswith(SCOPE_DIRS))


def scoped_files(root: Path) -> list[str]:
    out = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
        check=True,
        capture_output=True,
    ).stdout.decode("utf-8")
    return sorted(p for p in {q for q in out.split("\0") if q} if in_scope(p))


def _named_in_a_span(path: str, files: dict[str, str]) -> bool:
    """Whether any document names ``path`` by its file name inside backticks.

    docs/dev/README.md introduces ``tools/ci/`` and then names its scripts
    without the directory, so the exemption's own citation is of that form.
    """
    name = path.rpartition("/")[2]
    for text in files.values():
        if text.startswith(GENERATED_MARKER):
            continue
        for span in _SPAN.finditer(text):
            if re.search(rf"(?<![\w./-]){re.escape(name)}(?![\w-])", span.group(1)):
                return True
    return False


def check(root: Path, files: dict[str, str]) -> list[str]:
    """Every finding over ``files`` (``path -> text``), against the tree at ``root``."""
    findings: list[str] = []
    cited: set[str] = set()
    for doc in sorted(files):
        text = files[doc]
        if text.startswith(GENERATED_MARKER):
            continue
        for line, path in citations(text):
            cited.add(path)
            waived = EXEMPT.get(path, ("", ""))[0]
            if not (root / path).is_file():
                if waived != MISSING:
                    findings.append(f"{doc}:{line}: cites {path}, which does not exist")
                continue
            owed = sibling_test(path)
            if owed and waived != UNTESTED and not (root / owed).is_file():
                findings.append(f"{doc}:{line}: cites {path}, which has no sibling test ({owed})")
    for path, (rule, _reason) in sorted(EXEMPT.items()):
        if path not in cited and not _named_in_a_span(path, files):
            findings.append(
                f"EXEMPT entry {path} ({rule}) is cited by no document in scope; "
                "remove the entry from tools/ci/check_doc_gate_references.py"
            )
        elif rule == MISSING and (root / path).is_file():
            findings.append(f"EXEMPT entry {path} now exists here; drop its '{MISSING}' exemption")
        elif rule == UNTESTED and (sibling_test(path) is not None) and (root / str(sibling_test(path))).is_file():
            findings.append(f"EXEMPT entry {path} now has a test; drop its '{UNTESTED}' exemption")
    return findings


def main(argv: list[str]) -> int:
    root = Path(argv[1]).resolve() if len(argv) > 1 else REPO_ROOT
    if len(argv) > 2:
        print("usage: check_doc_gate_references.py [root]", file=sys.stderr)
        return 2
    try:
        names = scoped_files(root)
        files = {n: (root / n).read_text(encoding="utf-8") for n in names if (root / n).is_file()}
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        print(f"::error::cannot read the documents in scope: {error}")
        return 2
    if not files:
        print("::error::no documents in scope were found; the check read nothing")
        return 2
    findings = check(root, files)
    for finding in findings:
        print(f"::error::{finding}")
    if findings:
        print(f"{len(findings)} finding(s) across {len(files)} document(s)")
        return 1
    print(f"doc gate references: ok ({len(files)} documents)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
