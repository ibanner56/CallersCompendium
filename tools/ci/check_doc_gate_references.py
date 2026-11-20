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

A *citation* is such a path
- inside an inline code span (backtick runs pair by length, so a span may be wrapped
  across lines and a double-backtick span counts);
- on any line of a fenced code block (CommonMark closing rules: same character, at
  least as long, no info string; an unclosed fence runs to the end of the file);
- as the target of a Markdown link (``[x](../../tools/ci/y.py)``, resolved against
  the document's directory); or
- anywhere in a document's YAML front matter (the quoted ``applyTo`` paths).

Prose outside those is not read; neither are globs (``tools/ci/check_*.py``) or
placeholders (``tools/ci/check_<name>.py``), which name no single file. A path
preceded by another path character (``app/tools/x.py``) is a different path and is
skipped. A citation inside an HTML comment is read like any other.

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

import posixpath
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

SCOPE_FILES = ("AGENTS.md", "CONTRIBUTING.md")
SCOPE_DIRS = ("docs/dev/", ".github/instructions/", ".github/skills/")

MISSING = "exists"
UNTESTED = "test"

# path -> (rule waived, document that justifies it, reason). That document must
# still cite the path (or, in a table that introduces its directory, the file name).
EXEMPT: dict[str, tuple[str, str, str]] = {
    "tools/publish_collections.py": (
        MISSING,
        "docs/dev/releasing.md",
        "lives in the Analect repository, not this one; docs/dev/releasing.md cites it as the "
        "tool that publishes there",
    ),
    "tools/ci/check_l10n_drift.py": (
        UNTESTED,
        "docs/dev/README.md",
        "deliberately has no test: docs/dev/README.md calls it a thin wrapper, so there is "
        "nothing in it to test that its CI step does not already exercise",
    ),
}

_TOOL_PATH = re.compile(r"(?<![\w./*<>-])tools/[\w./-]*[\w]\.(?:py|sh)(?![\w*<>-]|\.\w)")
# A code span: a run of N backticks, then the shortest text up to a run of exactly N.
_SPAN = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)", re.DOTALL)
_FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")
_LINK_TARGET = re.compile(r"\]\(<?([^)\s>#]+\.(?:py|sh))(?:#[^)\s>]*)?>?\)")
GENERATED_MARKER = "<!-- generated-by:"


def _resolve_link(doc: str, target: str) -> str | None:
    """The repo-relative path a link target names, if it names a ``tools/`` script."""
    if "://" in target or target.startswith(("/", "#", "mailto:")):
        return None
    base = posixpath.dirname(doc)
    resolved = posixpath.normpath(posixpath.join(base, target))
    if resolved.startswith(("../", "/")) or not _TOOL_PATH.fullmatch(resolved):
        return None
    return resolved


def citations(text: str, doc: str = "") -> list[tuple[int, str]]:
    """``(1-based line, path)`` for every cited tool script in Markdown ``text``.

    ``doc`` is the document's repo-relative path, used to resolve link targets.
    """
    found: set[tuple[int, str]] = set()
    lines = text.splitlines()
    fence: tuple[str, int] | None = None
    front_matter_end = -1
    if lines and lines[0].strip() == "---":
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                front_matter_end = index
                break
    paragraph: list[tuple[int, str]] = []

    def flush() -> None:
        if not paragraph:
            return
        start = paragraph[0][0]
        body = "\n".join(line for _n, line in paragraph)
        for span in _SPAN.finditer(body):
            for m in _TOOL_PATH.finditer(span.group(2)):
                found.add((start + body.count("\n", 0, span.start(2) + m.start()), m.group(0)))
        for link in _LINK_TARGET.finditer(body):
            resolved = _resolve_link(doc, link.group(1))
            if resolved:
                found.add((start + body.count("\n", 0, link.start(1)), resolved))
        paragraph.clear()

    for index, line in enumerate(lines):
        number = index + 1
        if index <= front_matter_end:
            found.update((number, m.group(0)) for m in _TOOL_PATH.finditer(line))
            continue
        match = _FENCE.match(line)
        if fence is not None:
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= fence[1] and not match.group(2).strip():
                fence = None
            else:
                found.update((number, m.group(0)) for m in _TOOL_PATH.finditer(line))
            continue
        if match and not (match.group(1)[0] == "`" and "`" in match.group(2)):
            flush()
            fence = (match.group(1)[0], len(match.group(1)))
            continue
        if not line.strip():
            flush()
        else:
            paragraph.append((number, line))
    flush()
    return sorted(found)


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


def _named_in_a_span(path: str, text: str) -> bool:
    """Whether ``text`` names ``path`` by its file name inside a code span.

    docs/dev/README.md introduces ``tools/ci/`` and then names its scripts
    without the directory, so the exemption's own citation is of that form.
    """
    name = path.rpartition("/")[2]
    pattern = re.compile(rf"(?<![\w./-]){re.escape(name)}(?![\w-]|\.\w)")
    return any(pattern.search(span.group(2)) for span in _SPAN.finditer(text))


def check(root: Path, files: dict[str, str]) -> list[str]:
    """Every finding over ``files`` (``path -> text``), against the tree at ``root``."""
    findings: list[str] = []
    cited_by: dict[str, set[str]] = {}
    for doc in sorted(files):
        text = files[doc]
        if text.startswith(GENERATED_MARKER):
            continue
        for line, path in citations(text, doc):
            cited_by.setdefault(doc, set()).add(path)
            waived = EXEMPT.get(path, ("", "", ""))[0]
            if not (root / path).is_file():
                if waived != MISSING:
                    findings.append(f"{doc}:{line}: cites {path}, which does not exist")
                continue
            owed = sibling_test(path)
            if owed and waived != UNTESTED and not (root / owed).is_file():
                findings.append(f"{doc}:{line}: cites {path}, which has no sibling test ({owed})")
    for path, (rule, doc, _reason) in sorted(EXEMPT.items()):
        text = files.get(doc)
        if text is None or text.startswith(GENERATED_MARKER):
            findings.append(f"EXEMPT entry {path} ({rule}) is justified by {doc}, which was not read")
        elif path not in cited_by.get(doc, set()) and not _named_in_a_span(path, text):
            findings.append(
                f"EXEMPT entry {path} ({rule}) is cited no longer by {doc}, the document that "
                "justifies it; remove the entry from tools/ci/check_doc_gate_references.py"
            )
        if rule == UNTESTED and not (root / path).is_file():
            findings.append(f"EXEMPT entry {path} ({rule}) does not exist; the exemption waives only the test rule")
        elif rule == MISSING and (root / path).is_file():
            findings.append(f"EXEMPT entry {path} now exists here; drop its '{MISSING}' exemption")
        elif rule == UNTESTED and sibling_test(path) and (root / str(sibling_test(path))).is_file():
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
