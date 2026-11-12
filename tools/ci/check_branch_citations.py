#!/usr/bin/env python3
"""CI ratchet: documentation and code comments cite no git branch but ``main``.

The maintainer's rule (2026-11-12): "Design documentation on ``main`` should
not point to files or recorded decisions on another branch." A branch is
deleted, rebased or force-pushed long before the design doc that cites it is
retired, and a decision whose only record lives on a branch has no provenance
once that branch goes. On ``main`` at ``0e2ad7a`` this check found forty
citations: thirty-five of the October 2026 behaviour audit's working branch
(``claude/app-audit-categories-k2pdon``, or "the audit branch"), whose files
were then brought onto ``main`` under ``docs/dev/audits/2026-10-behavior/``,
and five of the branches of merged PRs.

Scope: every Markdown file, the ``.txt``/``.svg``/``.html`` files under
``docs/``, and the comments of hand-written Dart under ``app/``, ``packages/``
and ``server/`` (generated Dart, including ``app/lib/l10n/``, is skipped).
"Every file" is what git tracks plus untracked files it does not ignore, so a
local run sees a new file before it is staged.
Workflow YAML, release tooling and test fixtures that genuinely operate on
branches are not in scope -- they are code, not citations.

What counts as a branch citation (each rule is narrow on purpose; see the
tests for the legitimate text each one must leave alone):

1. An agent-session branch name, ``claude/<slug>``, ``copilot/<slug>`` or
   ``codex/<slug>``, anywhere, including as ``origin/claude/<slug>`` or
   ``refs/heads/claude/<slug>`` -- unless it is part of another path
   (``.claude/``, ``foo/claude/``) or a glob (``claude/*``). These are session branches: they
   are deleted or abandoned once their PR merges, so a citation of one is
   a pointer at content that will not stay reachable. Cite the PR instead.
2. ``branch `<name>``` (also ``branch, `<name>``` and ``branch: `<name>```)
   where ``<name>`` looks like a branch -- it has a ``-`` or ``/`` and no file
   extension -- and is not an allowed branch (``main``, plus ``gh-pages``, which
   the release pipeline owns); or ```<name>` branch``, where ``<name>`` must
   also contain a ``/``. The second form is the one prose uses for a branch of
   an ``if`` ("the ``else-if`` branch"), so it asks for more; the shape test is
   what keeps "the ``existenceAt`` branch" legal.
3. A GitHub ``blob``/``tree``/``commits``/``compare`` URL whose ref (each side
   of a ``compare`` range) is not ``main``, ``HEAD``, a commit SHA or a
   ``v``-tag. A SHA passes without a check that it is on ``main``: CI checks
   out one commit, so reachability cannot be decided here. Pin a SHA that is
   on ``main``; ``docs/dev/README.md`` says so.
4. "the audit branch" -- the wording the 2026-10 citations used in place of
   a name.

Deliberately NOT a rule: a conventional branch name (``feat/…``, ``fix/…``)
on its own. Implementation plans in ``docs/design/`` name the branch each
planned piece of work will be built on ("| H1 | ``feat/called-filter-scopes``
| …"). That names work, not a place where a record lives, and flagging it would
push every plan table into an allow-list. Only the backticked forms of rule 2
catch a sentence that puts a record *on* such a branch; "recorded in ``x.md``
on ``feat/foo``" is a known miss, as are unnamed references such as "on that
branch". The check is a ratchet on the shapes that occurred, not a proof.

Exemptions (``EXEMPT_PREFIXES``) are by path, each with its reason.

Exit codes: 0 = clean, 1 = at least one citation, 2 = bad input.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Branches a document may name. `gh-pages` is the persistent Pages branch that
# release tooling writes and docs/dev/releasing.md describes; it holds no design
# record.
ALLOWED_BRANCHES = frozenset({"main", "gh-pages"})

# Paths not read, each with its reason.
EXEMPT_PREFIXES: dict[str, str] = {
    "docs/dev/audits/2026-10-behavior/": (
        "the October 2026 behaviour audit record, a byte-for-byte copy kept so "
        "file:line citations into it stay exact. Its logs and plans name the "
        "session branches the audit's work was built on; that is history in a "
        "frozen record, not a design document pointing at a record elsewhere, "
        "and editing it would break the citations"
    ),
}

CODE_ROOTS = ("app/", "packages/", "server/")
GENERATED_DART_PREFIXES = ("app/lib/l10n/",)
GENERATED_DART_SUFFIXES = (".g.dart", ".freezed.dart", ".mocks.dart")

_SLUG = r"[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*"

# Rule 1. Not preceded by a path character, so `.claude/` and `a/claude/b`
# pass -- except a remote or ref prefix, which names the branch outright.
_AGENT_BRANCH_RE = re.compile(
    rf"(?:(?<![\w./-])|(?<=origin/)|(?<=refs/heads/)|(?<=refs/remotes/))"
    rf"(?:claude|copilot|codex)/{_SLUG}"
)
# Rule 2.
_BRANCH_BEFORE_RE = re.compile(r"\bbranch(?:es)?[,:]?\s+`([^`\s]+)`", re.IGNORECASE)
_BRANCH_AFTER_RE = re.compile(r"`([^`\s]+)`\s+branch\b", re.IGNORECASE)
# Rule 3.
_GITHUB_REF_RE = re.compile(
    r"github\.com/[\w.-]+/[\w.-]+/(?:blob|tree|commits|compare)/([^/\s)#?]+)"
)
_SHA_RE = re.compile(r"[0-9a-f]{7,40}")
_RANGE_SPLIT_RE = re.compile(r"\.{2,3}")
_TAG_RE = re.compile(r"v\d[\w.+-]*")
# Rule 4.
_AUDIT_BRANCH_RE = re.compile(r"\baudit\s+branch\b", re.IGNORECASE)
# Rule 2's shape test: a ref name with a separator, no spaces or punctuation
# that a code identifier or expression would carry, and no file extension.
_BRANCH_SHAPE_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_/-]*(?:\.[0-9]+)*[A-Za-z0-9_/-]*")


def looks_like_branch(name: str) -> bool:
    return (
        bool(_BRANCH_SHAPE_RE.fullmatch(name))
        and ("-" in name or "/" in name)
        and not name.endswith("/")
    )


def tracked_files(root: Path) -> list[str]:
    """Tracked files plus untracked, unignored ones (a local run sees new files)."""
    out = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
        check=True,
        capture_output=True,
    ).stdout.decode("utf-8")
    return sorted({p for p in out.split("\0") if p})


def is_exempt(path: str) -> bool:
    return path.startswith(tuple(EXEMPT_PREFIXES))


def in_scope(path: str) -> str | None:
    """`"doc"`, `"dart"` or `None` for a tracked [path]."""
    if is_exempt(path):
        return None
    if path.endswith(".md"):
        return "doc"
    if path.startswith("docs/") and path.endswith((".txt", ".svg", ".html")):
        return "doc"
    if (
        path.startswith(CODE_ROOTS)
        and path.endswith(".dart")
        and not path.endswith(GENERATED_DART_SUFFIXES)
        and not path.startswith(GENERATED_DART_PREFIXES)
    ):
        return "dart"
    return None


def dart_comment_lines(src: str) -> list[tuple[int, str]]:
    """(1-based line, comment text) for every comment in Dart [src].

    A small scanner: it tracks `/* */` blocks and single- and double-quoted
    string literals (including triple-quoted ones) so that `//` inside a string
    or a URL in a string is not read as a comment.
    """
    result: list[tuple[int, str]] = []
    block_depth = 0  # Dart block comments nest
    in_string: str | None = None  # the delimiter: ', ", ''' or """
    for lineno, line in enumerate(src.splitlines(), start=1):
        i = 0
        comment = []
        while i < len(line):
            if block_depth:
                if line.startswith("/*", i):
                    block_depth += 1
                    comment.append(" ")
                    i += 2
                elif line.startswith("*/", i):
                    block_depth -= 1
                    comment.append(" ")
                    i += 2
                else:
                    comment.append(line[i])
                    i += 1
                continue
            if in_string:
                if line.startswith("\\", i) and not in_string.startswith("r"):
                    i += 2
                    continue
                delim = in_string.lstrip("r")
                if line.startswith(delim, i):
                    i += len(delim)
                    in_string = None
                    continue
                i += 1
                continue
            if line.startswith("//", i):
                # `///` doc comments: drop the third slash too, so a wrapped
                # citation joins as words ("audit" + "branch").
                comment.append(line[i + 2 :].lstrip("/"))
                break
            if line.startswith("/*", i):
                block_depth = 1
                i += 2
                continue
            raw = i > 0 and line[i - 1] == "r" and (i < 2 or not line[i - 2].isalnum())
            for delim in ('"""', "'''", '"', "'"):
                if line.startswith(delim, i):
                    in_string = ("r" if raw else "") + delim
                    i += len(delim)
                    break
            else:
                i += 1
        # A single-quoted string never spans a line; a triple-quoted one can.
        if in_string and len(in_string.lstrip("r")) == 1:
            in_string = None
        # A block comment's continuation lines usually lead with `*`.
        text = "".join(comment).strip().lstrip("*").strip()
        if text:
            result.append((lineno, text))
    return result


def find_citations(text: str) -> list[tuple[str, str]]:
    """(rule, matched text) for every branch citation in one line of [text]."""
    hits: list[tuple[str, str]] = []
    for m in _AGENT_BRANCH_RE.finditer(text):
        # A sentence-ending period is punctuation, not part of the name.
        hits.append(("agent-branch", m.group(0).rstrip(".")))
    for regex in (_BRANCH_BEFORE_RE, _BRANCH_AFTER_RE):
        for m in regex.finditer(text):
            name = m.group(1)
            if name in ALLOWED_BRANCHES or not looks_like_branch(name):
                continue
            if regex is _BRANCH_AFTER_RE and "/" not in name:
                continue
            if any(name in h for _, h in hits):
                continue
            hits.append(("named-branch", name))
    for m in _GITHUB_REF_RE.finditer(text):
        refs = _RANGE_SPLIT_RE.split(m.group(1))
        if all(
            r in ALLOWED_BRANCHES
            or r == "HEAD"
            or _SHA_RE.fullmatch(r)
            or _TAG_RE.fullmatch(r)
            for r in refs
        ):
            continue
        hits.append(("github-ref", m.group(0)))
    for m in _AUDIT_BRANCH_RE.finditer(text):
        hits.append(("audit-branch", m.group(0)))
    return hits


def scan_file(path: str, content: str) -> list[tuple[str, int, str, str]]:
    kind = in_scope(path)
    if kind is None:
        return []
    if kind == "dart":
        lines = dart_comment_lines(content)
    else:
        lines = list(enumerate(content.splitlines(), start=1))
    # A citation can be wrapped across two lines ("on the audit\nbranch"), so
    # each line is also read joined to the next; a hit found only in the join
    # is reported on the first line.
    found: list[tuple[str, int, str, str]] = []
    seen: set[tuple[int, str]] = set()
    for idx, (lineno, text) in enumerate(lines):
        joined = text
        if idx + 1 < len(lines) and lines[idx + 1][0] == lineno + 1:
            nxt = lines[idx + 1][1].lstrip()
            if kind == "doc":
                nxt = nxt.lstrip("> ")
            joined = f"{text} {nxt}"
        for rule, hit in find_citations(joined):
            # Attribute to the line that contains it, if either alone does.
            key_line = lineno
            if hit not in text and idx + 1 < len(lines) and hit in lines[idx + 1][1]:
                key_line = lines[idx + 1][0]
            if (key_line, hit) in seen:
                continue
            seen.add((key_line, hit))
            found.append((path, key_line, rule, hit))
    return found


def scan_tree(root: Path) -> list[tuple[str, int, str, str]]:
    files = tracked_files(root)
    findings: list[tuple[str, int, str, str]] = []
    for path in files:
        if in_scope(path) is None:
            continue
        full = root / path
        if not full.is_file():
            continue
        try:
            content = full.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        findings.extend(scan_file(path, content))
    return findings


def main(argv: list[str]) -> int:
    root = REPO_ROOT
    if len(argv) == 2 and argv[0] == "--root":
        root = Path(argv[1]).resolve()
    elif argv:
        print("usage: check_branch_citations.py [--root DIR]", file=sys.stderr)
        return 2
    findings = scan_tree(root)
    if not findings:
        print("branch citations: none outside main (docs and code comments)")
        return 0
    print(
        f"branch citations: {len(findings)} reference(s) to a branch other "
        "than main.\n"
        "Design documentation on main must not point to files or recorded "
        "decisions on another branch (maintainer's rule, 2026-11-12). Bring "
        "the cited record onto main and cite it there, or cite the merged PR "
        "(#N), or a commit SHA that is on main, instead of its branch.\n"
    )
    for path, line, rule, hit in findings:
        print(f"  {path}:{line}: [{rule}] {hit}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
