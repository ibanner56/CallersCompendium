#!/usr/bin/env python3
"""CI ratchet: every key an archive entity function writes names the version case that covers it.

A reader skips archive keys it does not know (``archive_codec.dart``). So when
an entity gains a key, an older build reads a file that carries it, drops the
key, and reports success, unless the file's version stamp makes that build
refuse it (a backup) or warn (an import). 0.6.0 added a program's pay and
Perform dialect with no stamp at all, and 0.5.2 to 0.5.4 restored backups
carrying them without a word (audit finding OUT-5). This ratchet makes the
question impossible to skip.

Rule: every key in the map literal of every top-level ``archive*ToJson``
function in ``archive_entity_codec.dart`` must appear, under that function, in
``archive_key_versions.json`` beside this file. Its value is either

- ``"baseline"``: every build from 0.5.2-beta reads the key. 0.5.2-beta is the
  first build whose restore refuses a newer backup, so an older build cannot be
  protected by any stamp; ``baseline`` claims nothing about it. Each baseline
  entry was checked against the decoder at the ``v0.5.2-beta`` tag when this
  ratchet was written. A new key is never baseline: no released build reads it.
- the name of a version constant, which must be declared (``const int NAME``)
  and used in the body of the function that stamps it:
  ``requiredSchemaVersion`` in ``compendium_archive.dart`` (core archive) or
  ``requiredBackupVersion`` in ``backup_document.dart`` (backup envelope).

It also fails on a manifest entry whose key or function no longer exists, so
the manifest cannot drift into describing keys nobody writes.

Keys are found with the source masked (comments and string contents blanked,
as ``check_caught_error_logged.mask_source`` does): a string literal followed
by ``:`` at the map literal's own nesting level. The keys of another helper's
map are not the function's own; each ``archive*ToJson`` helper is checked under
its own name. A shape whose keys this reader cannot see fails the check rather
than passing unread: a spread, a collection ``for``, a key that is not a plain
``'word'`` literal, a map literal nested inside the entity's own, and an
``archive*ToJson`` declared with any other signature than
``Map<String, Object?> archiveXToJson(``.

Scope: the entity functions in ``archive_entity_codec.dart`` only. The
envelope's own keys (``archiveToJson`` in ``archive_codec.dart``), a figure's
keys (``figureToJson``) and the backup's ``app`` section are not covered. A
key the function adds to its map after building it (``m['k'] = v``) is not
seen either; build the map as one literal.

What this does not check: that the case actually tests for the key's data.
That a constant is named is enforced; that its condition is the right one is a
review concern, as is the value for a key the share archive writes unstamped
by design (#1885).

Exit codes: 0 = clean, 1 = at least one unclassified, stale or unbacked entry,
2 = bad input.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_caught_error_logged import (  # noqa: E402
    REPO_ROOT,
    _match_brace,
    _match_paren,
    mask_source,
)

CODEC = "packages/compendium_core/lib/src/serialization/archive_entity_codec.dart"
MANIFEST = "tools/ci/archive_key_versions.json"
BASELINE = "baseline"

# The functions that stamp a version, and the file each lives in.
STAMPERS = (
    (
        "packages/compendium_core/lib/src/serialization/compendium_archive.dart",
        "requiredSchemaVersion",
    ),
    ("app/lib/src/data/backup_document.dart", "requiredBackupVersion"),
)

_FUNCTION_RE = re.compile(
    r"^Map\s*<\s*String\s*,\s*Object\?\s*>\s+(archive\w+ToJson)\s*\(", re.M
)
# Any top-level declaration of an `archive*ToJson`, whatever its return type
# or type parameters, so one this reader would skip is reported, not ignored.
_ANY_TO_JSON_RE = re.compile(r"^[A-Za-z_][^\n;=]*?\b(archive\w+ToJson)\s*[<(]", re.M)
_OPENERS = {"(": ")", "[": "]", "{": "}"}


def _body_map_open(masked: str, paren: int) -> int | None:
    """Offset of the `{` that opens the map literal [paren]'s function returns.

    An expression body (`) => {`) returns the literal directly; a block body
    (`) { ... return {` ) returns it from its first top-level `return`.
    """
    close = _match_paren(masked, paren)
    if close is None:
        return None
    m = re.compile(r"\s*(=>\s*)?\{").match(masked, close + 1)
    if m is None:
        return None
    brace = m.end() - 1
    if m.group(1):
        return brace
    end = _match_brace(masked, brace)
    if end is None:
        return None
    ret = re.compile(r"\breturn\s*\{").search(masked, brace, end)
    return ret.end() - 1 if ret else None


def _string_end(text: str, start: int) -> int:
    """Offset just past the string literal whose opening quote is at [start]."""
    quote = text[start]
    if text.startswith(quote * 3, start):
        end = text.find(quote * 3, start + 3)
        return len(text) if end == -1 else end + 3
    i = start + 1
    while i < len(text) and text[i] not in (quote, "\n"):
        i += 2 if text[i] == "\\" else 1
    return i + 1


def _comment_ends(text: str, masked: str) -> dict[int, int]:
    """Start offset of every real comment in [text] mapped to its end.

    The masker blanks comments and string literals alike; a blanked run that
    starts with `//` or `/*` in the original is a comment, so a quote inside
    it (an apostrophe in prose) never starts a string.
    """
    ends: dict[int, int] = {}
    i = 0
    n = len(text)
    while i < n:
        if masked[i] == " " and text.startswith(("//", "/*"), i):
            if text.startswith("//", i):
                end = text.find("\n", i)
                end = n if end == -1 else end
            else:
                end = text.find("*/", i + 2)
                end = n if end == -1 else end + 2
            ends[i] = end
            i = end
            continue
        if masked[i] == " " and text[i] in "'\"":
            # Skip a string literal whole, so `//` inside one is not a comment.
            i = _string_end(text, i)
            continue
        i += 1
    return ends


def _starts_entry(masked: str, open_idx: int, i: int) -> bool:
    """Whether offset [i] begins an entry of the collection opened at
    [open_idx]: first in it, after a `,`, or after a collection `if (...)` /
    `else`. A string after `?` is a ternary's value, not an entry."""
    before = masked[open_idx + 1 : i].rstrip()
    return before == "" or before.endswith((",", ")", "else"))


def map_keys(
    text: str, masked: str, brace: int
) -> tuple[list[tuple[str, int]], list[str]]:
    """`(key, offset)` of each string-literal key directly inside the map
    literal opened at [brace], in source order, and a description of each
    shape whose keys this reader cannot see.

    Unsupported shapes are reported rather than skipped, so a key cannot slip
    past the ratchet by being written another way: a spread (`...{}` or
    `...helper()`), a collection `for`, a key that is not a plain
    `'word'` literal (raw, interpolated, hyphenated, or an identifier), and a
    map literal nested inside the entity's own (a value's keys are invisible
    here; build it in an `archive*ToJson` helper instead).
    """
    end = _match_brace(masked, brace)
    if end is None:
        return [], ["the map literal has no closing brace"]
    comments = _comment_ends(text, masked)
    keys: list[tuple[str, int]] = []
    unsupported: list[str] = []
    # Offset of each open bracket enclosing i, innermost last.
    stack: list[int] = [brace]
    i = brace + 1

    def line(at: int) -> int:
        return text.count("\n", 0, at) + 1

    while i < end:
        if i in comments:
            i = comments[i]
            continue
        ch = masked[i]
        if ch in _OPENERS:
            stack.append(i)
            i += 1
            continue
        if ch in ")]}":
            stack.pop()
            i += 1
            continue
        own = len(stack) == 1
        inner_map = masked[stack[-1]] == "{"
        if own and masked.startswith("...", i):
            unsupported.append(f"line {line(i)}: a spread")
            i += 3
            continue
        if own and _starts_entry(masked, stack[-1], i):
            word = re.compile(r"[A-Za-z_][\w.]*").match(masked, i)
            if word and word.group(0) == "for":
                unsupported.append(f"line {line(i)}: a collection `for`")
            elif word and word.group(0) not in ("if", "else"):
                after = re.compile(r"\s*:(?!:)").match(masked, word.end())
                if after:
                    raw = word.group(0) == "r" and text[word.end()] in "'\""
                    unsupported.append(
                        f"line {line(i)}: "
                        + ("a raw-string key" if raw else "an identifier key")
                    )
        if text[i] in "'\"" and ch == " ":
            close = _string_end(text, i)
            if close > end:
                break
            is_key = bool(re.compile(r"\s*:").match(masked, close)) and (
                _starts_entry(masked, stack[-1], i)
            )
            literal = text[i + 1 : close - 1]
            if is_key and own:
                if re.fullmatch(r"\w+", literal):
                    keys.append((literal, i))
                else:
                    unsupported.append(f"line {line(i)}: the key {text[i:close]}")
            elif is_key and inner_map:
                unsupported.append(
                    f"line {line(i)}: a nested map literal (key {text[i:close]})"
                )
            i = close
            continue
        i += 1
    return keys, unsupported


def entity_keys(text: str) -> tuple[dict[str, list[str]], list[str]]:
    """Each top-level `archive*ToJson` function in [text] mapped to its keys,
    and every shape that hides keys from this reader."""
    masked = mask_source(text)
    found: dict[str, list[str]] = {}
    problems: list[str] = []
    for m in _FUNCTION_RE.finditer(masked):
        name = m.group(1)
        brace = _body_map_open(masked, m.end() - 1)
        if brace is None:
            problems.append(f"{name}: could not find the map literal it returns")
            continue
        keys, unsupported = map_keys(text, masked, brace)
        found[name] = [key for key, _ in keys]
        problems += [
            f"{name}, {u}: this reader cannot see the keys it writes. Write "
            "each key as a plain 'word' literal in the returned map." for u in unsupported
        ]
    for m in _ANY_TO_JSON_RE.finditer(masked):
        if m.group(1) not in found and not any(m.group(1) in p for p in problems):
            problems.append(
                f"{m.group(1)}: declared with a shape this reader does not "
                "check. Declare it as `Map<String, Object?> "
                f"{m.group(1)}(...)` returning a map literal."
            )
    return found, problems


def stamper_constants(text: str, function: str) -> set[str]:
    """Identifiers used in the body of top-level [function] in [text]."""
    masked = mask_source(text)
    m = re.compile(rf"^int\s+{re.escape(function)}\s*\(", re.M).search(masked)
    if m is None:
        raise ValueError(f"{function}: declaration not found")
    close = _match_paren(masked, m.end() - 1)
    brace = masked.find("{", close) if close is not None else -1
    end = _match_brace(masked, brace) if brace != -1 else None
    if end is None:
        raise ValueError(f"{function}: body not found")
    return set(re.findall(r"\b[A-Za-z_]\w*\b", masked[brace:end]))


def declared_constants(text: str) -> set[str]:
    return set(re.findall(r"^const\s+int\s+(\w+)\s*=", mask_source(text), re.M))


def check(
    keys: dict[str, list[str]],
    manifest: dict[str, dict[str, str]],
    stamped: dict[str, set[str]],
    declared: set[str],
) -> list[str]:
    """Problems found comparing the codec's [keys] with the [manifest].

    [stamped] maps each stamping function to the identifiers its body uses;
    [declared] holds every version constant declared beside them.
    """
    problems: list[str] = []
    used_anywhere = set().union(*stamped.values()) if stamped else set()
    for function, function_keys in keys.items():
        entries = manifest.get(function, {})
        for key in function_keys:
            if key not in entries:
                problems.append(
                    f"{function} writes '{key}', which {MANIFEST} does not "
                    "classify. Give it a version case: a constant stamped by "
                    "requiredSchemaVersion or requiredBackupVersion when the "
                    "key is present. 'baseline' is only for keys 0.5.2-beta "
                    "already reads."
                )
        for key in entries:
            if key not in function_keys:
                problems.append(
                    f"{MANIFEST} classifies {function} '{key}', which the "
                    "function no longer writes. Remove the entry."
                )
    for function in manifest:
        if function not in keys:
            problems.append(
                f"{MANIFEST} lists {function}, which is not a top-level "
                f"archive*ToJson function in {CODEC}."
            )
    for function, entries in manifest.items():
        for key, case in entries.items():
            if case == BASELINE:
                continue
            if case.endswith("Base"):
                problems.append(
                    f"{function} '{key}' names {case}, the version every file "
                    "gets: nothing about the key raises it. Name the constant "
                    "of the case that stamps the key."
                )
                continue
            if case not in declared:
                problems.append(
                    f"{function} '{key}' names {case}, which is not a "
                    "declared `const int` version."
                )
            elif case not in used_anywhere:
                problems.append(
                    f"{function} '{key}' names {case}, which neither "
                    + " nor ".join(stamped)
                    + " uses, so nothing stamps it."
                )
    return problems


def main() -> int:
    try:
        codec = (REPO_ROOT / CODEC).read_text(encoding="utf-8")
        manifest = json.loads((REPO_ROOT / MANIFEST).read_text(encoding="utf-8"))
        stamped: dict[str, set[str]] = {}
        declared: set[str] = set()
        for path, function in STAMPERS:
            source = (REPO_ROOT / path).read_text(encoding="utf-8")
            stamped[function] = stamper_constants(source, function)
            declared |= declared_constants(source)
        keys, shape_problems = entity_keys(codec)
    except (OSError, ValueError) as error:
        print(f"::error::{error}")
        return 2
    if not keys:
        print(f"::error::no archive*ToJson functions found in {CODEC}")
        return 2
    problems = shape_problems + check(keys, manifest, stamped, declared)
    if problems:
        for problem in problems:
            print(f"::error::{problem}")
        return 1
    total = sum(len(v) for v in keys.values())
    print(
        f"OK: {total} key(s) across {len(keys)} archive entity function(s) "
        "each name a version case."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
