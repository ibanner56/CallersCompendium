#!/usr/bin/env python3
"""Report: a changed figure definition has namesakes in the other taxonomies.

With more than one dance-form taxonomy, a change to a figure in one may need the
same change to its namesake in another, and nothing prompts the author to look:
contra ``box_the_gnat`` and ECD ``ecd_box_the_gnat`` (display name ``box the
gnat``) are the same figure danced in two forms, and #2230 asked for a prompt.
Squares will add a third taxonomy (ADR-007).

**This is a report, not a gate, and that is the maintainer's request** (#2230):
namesakes may legitimately differ, so the output is a prompt to check, never a
claim of drift. It always exits 0.

What it looks at, in the whole PR (``<base>...<head>``, against the merge base):

- Each **changed definition block**, not each changed file. A block is a
  ``MoveDef(...)`` or ``MoveAlias(...)`` constructor call with an ``id:``, or a
  ``'<id>': FigureDefinition(...)`` map entry, in a Dart file under
  ``packages/compendium_core/lib/src/taxonomy/``. It is *changed* when it is new
  or when its text, whitespace runs ignored, differs from the same figure's block
  at the merge base *anywhere in that directory*, so a block moved to another file
  or a file renamed or split is not reported. The block's text includes the
  ``//`` comment lines directly above it (the ``// TCB "Swing"`` citations),
  which are part of what the definition says. A deleted block is not reported. A
  change to something a block only *uses* (a shared ``ParamSpec`` constant, a
  helper) is not a change to the block's text and is not seen.
- For each, the same-named figures in **other** dance forms at the head, matched
  on the **display name** (the ask is homonyms) and on the **ID stem** after the
  form's prefix (``ecd_``, later ``sq_``). A figure's form is the one whose prefix
  its id starts with; an id with no prefix is the base taxonomy's (contra, ADR-006
  §5.1). A figure's display name is that of the ``MoveDef`` or ``MoveAlias`` with
  its id, so a ``FigureDefinition`` entry is matched by the name its figure has.

The forms and their prefixes are read from ``danceFormMovePrefixes`` in
``taxonomy_registry.dart``, not listed here, so a registered squares form is
picked up by that edit alone. An id written ``'${_p}name'`` is resolved through
the file's own string constant (``const``/``final``, typed or not, either quote).
An id that is not a string literal (``id: customMoveId``) is skipped; an id whose
interpolation cannot be resolved is *unavailable*, because skipping it would drop
a whole form without a word.

If it cannot tell -- an unresolvable ref, a git failure, a registry it cannot
read, a block it cannot close -- it prints ``unavailable`` and says why, rather
than guessing in either direction. It still exits 0.

Usage:
    report_figure_namesakes.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD``. Exit code: always 0.
"""

from __future__ import annotations

import re
import subprocess
import sys
from dataclasses import dataclass

TAXONOMY_DIR = "packages/compendium_core/lib/src/taxonomy/"
REGISTRY = TAXONOMY_DIR + "taxonomy_registry.dart"
# ADR-006 §5.1: an id with no prefix is contra's, whatever the dance's form.
BASE_FORM = "contra"
NOTICE = "::notice title=Figure namesake advisory::"
# How many changed figures an advisory lists before summarising the rest.
LISTED = 25


class Unavailable(Exception):
    """The report cannot answer; the message says why."""


@dataclass(frozen=True)
class Block:
    kind: str  # "move" (MoveDef/MoveAlias) or "definition" (FigureDefinition entry)
    id: str  # full id, `${_p}` resolved
    file: str
    text: str  # the block's source, whitespace runs collapsed
    display_name: str | None


def mask(src: str) -> str:
    """``src`` with comment text and string contents blanked, newlines and length kept.

    Dart's string forms, nested block comments and ``${...}`` interpolation are
    walked so that a parenthesis or ``//`` inside a string or comment is never
    read as code. Raises :class:`Unavailable` for an unterminated construct.
    """
    out = list(src)
    n = len(src)
    i = 0

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
        elif src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            if depth:
                raise Unavailable("unterminated block comment")
            blank(i, j)
            i = j
        elif c in "'\"" or (c == "r" and i + 1 < n and src[i + 1] in "'\"" and not (i and (src[i - 1].isalnum() or src[i - 1] == "_"))):
            raw = c == "r"
            start = i + 1 if raw else i
            quote = src[start]
            triple = src.startswith(quote * 3, start)
            delim = quote * 3 if triple else quote
            j = start + len(delim)
            while True:
                if j >= n:
                    raise Unavailable("unterminated string")
                if not raw and src[j] == "\\":
                    j += 2
                elif not raw and src.startswith("${", j):
                    depth, j = 1, j + 2
                    while j < n and depth:
                        depth += {"{": 1, "}": -1}.get(src[j], 0)
                        j += 1
                elif src.startswith(delim, j):
                    break
                elif not triple and src[j] == "\n":
                    raise Unavailable("a string runs past the end of its line")
                else:
                    j += 1
            blank(start + len(delim), j)
            i = j + len(delim)
        else:
            i += 1
    return "".join(out)


def _close(masked: str, open_at: int) -> int:
    depth = 0
    for k in range(open_at, len(masked)):
        ch = masked[k]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return k
    raise Unavailable("a definition block never closes")


_CONSTS = re.compile(r"^[ \t]*(?:static\s+)?(?:const|final)\s+(?:String\s+)?(\w+)\s*=\s*(['\"])([^'\"\n$\\]*)\2\s*;", re.MULTILINE)
_MOVE_CALL = re.compile(r"\b(?:MoveDef|MoveAlias)\(")
_ID_ARG = re.compile(r"\bid:\s*(['\"])(.*?)\1", re.DOTALL)
_NAME_ARG = re.compile(r"\bdisplayName:\s*(['\"])(.*?)\1", re.DOTALL)
_DEFINITION_ENTRY = re.compile(r"^[ \t]*(['\"])([A-Za-z0-9_${}]+)\1\s*:\s*FigureDefinition\(", re.MULTILINE)
_INTERP = re.compile(r"\$\{(\w+)\}|\$(\w+)")


def _resolve(literal: str, consts: dict[str, str], file: str) -> str:
    unresolved = False

    def sub(m: re.Match[str]) -> str:
        nonlocal unresolved
        name = m.group(1) or m.group(2)
        if name in consts:
            return consts[name]
        unresolved = True
        return m.group(0)

    value = _INTERP.sub(sub, literal)
    if unresolved:
        raise Unavailable(f"{file}: cannot resolve the interpolation in {literal!r} (no string constant of that name)")
    return value


def _collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def _with_leading_comments(src: str, start: int, end: int) -> str:
    """``src[start:end]`` with the ``//`` comment lines directly above it."""
    line_start = src.rfind("\n", 0, start) + 1
    while line_start > 0:
        prev_start = src.rfind("\n", 0, line_start - 1) + 1
        if not src[prev_start : line_start - 1].lstrip().startswith("//"):
            break
        line_start = prev_start
    return src[line_start:end]


def blocks(src: str, file: str) -> list[Block]:
    """Every definition block in the Dart source ``src`` of ``file``."""
    masked = mask(src)
    # A dropped closer would let a block swallow its neighbours and close at the
    # wrong place, so a source that does not balance is not read at all.
    for opener, closer in ("()", "[]", "{}"):
        if masked.count(opener) != masked.count(closer):
            raise Unavailable(f"{file}: unbalanced {opener}{closer} after blanking strings and comments")
    # String contents are blank in `masked`, so the values come from the real text,
    # and a match counts only where the masked text still shows code (not a comment).
    consts = {}
    for m in _CONSTS.finditer(src):
        if masked[m.end() - 1] == ";":
            consts[m.group(1)] = m.group(3)
    found: list[Block] = []
    for m in _MOVE_CALL.finditer(masked):
        end = _close(masked, m.end() - 1)
        text = src[m.start() : end + 1]
        id_arg = _ID_ARG.search(text)
        full = _with_leading_comments(src, m.start(), end + 1)
        if id_arg is None:
            continue
        ident = _resolve(id_arg.group(2), consts, file)
        name_arg = _NAME_ARG.search(text)
        name = _resolve(name_arg.group(2), consts, file) if name_arg else None
        found.append(Block("move", ident, file, _collapse(full), name))
    for m in _DEFINITION_ENTRY.finditer(src):
        open_at = m.end() - 1
        if masked[open_at] != "(":
            continue  # inside a comment or a string
        end = _close(masked, open_at)
        ident = _resolve(m.group(2), consts, file)
        found.append(Block("definition", ident, file, _collapse(_with_leading_comments(src, m.start(), end + 1)), None))
    return found


def prefixes(registry_src: str) -> dict[str, str]:
    """``{form: prefix}`` from ``danceFormMovePrefixes``, read by walking its braces."""
    masked = mask(registry_src)
    start = re.search(r"\bdanceFormMovePrefixes\s*=\s*(?:const\s+)?\{", masked)
    if start is None:
        raise Unavailable("danceFormMovePrefixes not found in taxonomy_registry.dart")
    depth, k = 0, start.end() - 1
    for k in range(start.end() - 1, len(masked)):
        depth += {"{": 1, "}": -1}.get(masked[k], 0)
        if depth == 0:
            break
    else:
        raise Unavailable("danceFormMovePrefixes never closes")
    found: dict[str, str] = {}
    for m in re.finditer(r"DanceForm\.(\w+)\s*:\s*", masked[start.end() : k]):
        at = start.end() + m.end()
        value = re.match(r"(['\"])([^'\"\n$\\]+)\1", registry_src[at:k])
        if value is None:
            raise Unavailable(f"the prefix of DanceForm.{m.group(1)} is not a plain string literal")
        found[m.group(1)] = value.group(2)
    if not found:
        raise Unavailable("danceFormMovePrefixes lists no form with a prefix")
    return found


def form_and_stem(ident: str, by_form: dict[str, str]) -> tuple[str, str]:
    """The form an id belongs to and the id without that form's prefix."""
    for form, prefix in sorted(by_form.items(), key=lambda kv: -len(kv[1])):
        if ident.startswith(prefix):
            return form, ident[len(prefix) :]
    return BASE_FORM, ident


def normal_name(name: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[-_]", " ", name)).strip().casefold()


def namesakes(
    changed: list[Block], head: list[Block], by_form: dict[str, str]
) -> list[tuple[str, list[str], list[tuple[str, str, list[str]]]]]:
    """``(id, files where it changed, [(namesake id, file, reasons)])`` per changed id.

    Only ids with at least one namesake in another form are returned.
    """
    names: dict[str, str] = {}
    for block in head:
        if block.kind == "move" and block.display_name:
            names[block.id] = block.display_name
    result = []
    for ident in sorted({b.id for b in changed}):
        form, stem = form_and_stem(ident, by_form)
        name = names.get(ident)
        found: dict[str, tuple[str, set[str]]] = {}
        for other in head:
            other_form, other_stem = form_and_stem(other.id, by_form)
            if other_form == form:
                continue
            reasons = set()
            if other_stem == stem:
                reasons.add("id stem")
            other_name = names.get(other.id)
            if name and other_name and normal_name(name) == normal_name(other_name):
                reasons.add("display name")
            if reasons:
                file, known = found.get(other.id, (other.file, set()))
                if other.kind == "move":
                    file = other.file  # where the figure is defined, not its prose
                found[other.id] = (file, known | reasons)
        if found:
            result.append(
                (
                    ident,
                    sorted({b.file for b in changed if b.id == ident}),
                    [(i, f, sorted(r)) for i, (f, r) in sorted(found.items())],
                )
            )
    return result


def _git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], capture_output=True, text=True)


def _show(ref: str, path: str) -> str | None:
    res = _git("show", f"{ref}:{path}")
    return res.stdout if res.returncode == 0 else None


def base_blocks(root: str) -> list[Block]:
    """Every block under the taxonomy directory at commit ``root`` (empty if it had none)."""
    listing = _git("ls-tree", "-r", "--name-only", root, "--", TAXONOMY_DIR)
    if listing.returncode != 0:
        raise Unavailable(f"cannot list {TAXONOMY_DIR} at {root}: {listing.stderr.strip()}")
    found: list[Block] = []
    for path in sorted(p for p in listing.stdout.splitlines() if p.endswith(".dart")):
        src = _show(root, path)
        if src is not None:
            found.extend(blocks(src, path))
    return found


def changed_blocks(base: str, head: str) -> tuple[list[Block], list[Block]]:
    """``(changed blocks, every block at head)`` under the taxonomy directory."""
    merge = _git("merge-base", base, head)
    if merge.returncode != 0 or not merge.stdout.strip():
        raise Unavailable(f"cannot find a merge base of {base} and {head}")
    root = merge.stdout.strip()
    listing = _git("ls-tree", "-r", "--name-only", head, "--", TAXONOMY_DIR)
    if listing.returncode != 0:
        raise Unavailable(f"cannot list {TAXONOMY_DIR} at {head}: {listing.stderr.strip()}")
    head_blocks: list[Block] = []
    touched: list[Block] = []
    for path in sorted(p for p in listing.stdout.splitlines() if p.endswith(".dart")):
        head_src = _show(head, path)
        if head_src is None:
            raise Unavailable(f"cannot read {path} at {head}")
        now = blocks(head_src, path)
        head_blocks.extend(now)
        if _show(root, path) != head_src:
            touched.extend(now)
    before = {(b.kind, b.id): b.text for b in base_blocks(root)}
    changed = [b for b in touched if before.get((b.kind, b.id)) != b.text]
    return changed, head_blocks


def advise(base: str, head: str) -> list[str]:
    """The lines to print: the advisory, or nothing when none is owed."""
    registry = _show(head, REGISTRY)
    if registry is None:
        raise Unavailable(f"cannot read {REGISTRY} at {head}")
    by_form = prefixes(registry)
    changed, head_blocks = changed_blocks(base, head)
    hits = namesakes(changed, head_blocks, by_form)
    if not hits:
        return []
    lines = [
        f"{NOTICE}{len(hits)} changed figure(s) have a same-named figure in another dance "
        "form's taxonomy. Namesakes may legitimately differ; check, do not assume drift. "
        "Advisory only; it never fails the build.",
        f"Advisory: {len(hits)} changed figure definition(s) have a namesake in another taxonomy "
        "(matched on display name and on the id after the form's prefix). Each form's figures may "
        "legitimately differ; this is a prompt to check, not a claim of drift:",
    ]
    for ident, files, others in hits[:LISTED]:
        form, _stem = form_and_stem(ident, by_form)
        lines.append(f"  {ident} ({form}; changed in {', '.join(f.rpartition('/')[2] for f in files)})")
        for other, file, reasons in others:
            lines.append(f"    -> {other} ({form_and_stem(other, by_form)[0]}; {file.rpartition('/')[2]}; same {' and '.join(reasons)})")
    if len(hits) > LISTED:
        lines.append(f"  ... and {len(hits) - LISTED} more")
    return lines


def main(argv: list[str]) -> int:
    args = argv[1:]
    try:
        if not 1 <= len(args) <= 2 or not all(a.strip() for a in args):
            raise Unavailable("usage: report_figure_namesakes.py <base_ref> [head_ref]")
        base = args[0].strip()
        head = args[1].strip() if len(args) == 2 else "HEAD"
        for line in advise(base, head):
            print(line)
    except Unavailable as error:
        print(f"{NOTICE}Figure namesake advisory unavailable: {error}")
    except Exception as error:  # noqa: BLE001 -- a report must never fail a build
        print(f"{NOTICE}Figure namesake advisory unavailable: unexpected {type(error).__name__}: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
