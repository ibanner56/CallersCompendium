#!/usr/bin/env python3
"""CI ratchet: every key an archive entity writes names the version case that covers it.

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
by ``:`` at the map literal's own nesting level. Keys of nested literals (a
``switch`` arm) and the keys of other helpers' maps are not the function's own;
each helper is checked under its own name.

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


def map_keys(text: str, masked: str, brace: int) -> list[tuple[str, int]]:
    """`(key, offset)` of each string-literal key directly inside the map
    literal opened at [brace], in source order."""
    end = _match_brace(masked, brace)
    if end is None:
        return []
    keys: list[tuple[str, int]] = []
    depth = 0
    i = brace + 1
    while i < end:
        ch = masked[i]
        if ch in _OPENERS:
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and text[i] in "'\"" and ch == " ":
            quote = text[i]
            close = text.find(quote, i + 1)
            if close == -1 or close >= end:
                break
            after = re.compile(r"\s*:").match(masked, close + 1)
            literal = text[i + 1 : close]
            before = masked[brace + 1 : i].rstrip()
            # An entry starts the map, follows a `,`, or follows a collection
            # `if (...)` / `else`; a string after `?` is a ternary's value.
            starts_entry = before == "" or before.endswith((",", ")", "else"))
            if after and starts_entry and re.fullmatch(r"\w+", literal):
                keys.append((literal, i))
            i = close + 1
            continue
        i += 1
    return keys


def entity_keys(text: str) -> dict[str, list[str]]:
    """Each top-level `archive*ToJson` function in [text] mapped to its keys."""
    masked = mask_source(text)
    found: dict[str, list[str]] = {}
    for m in _FUNCTION_RE.finditer(masked):
        name = m.group(1)
        brace = _body_map_open(masked, m.end() - 1)
        if brace is None:
            raise ValueError(f"{name}: could not find the map literal it returns")
        found[name] = [key for key, _ in map_keys(text, masked, brace)]
    return found


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
        keys = entity_keys(codec)
    except (OSError, ValueError) as error:
        print(f"::error::{error}")
        return 2
    if not keys:
        print(f"::error::no archive*ToJson functions found in {CODEC}")
        return 2
    problems = check(keys, manifest, stamped, declared)
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
