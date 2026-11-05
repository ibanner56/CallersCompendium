#!/usr/bin/env python3
"""CI ratchet: English app text uses straight quotes (``"`` and ``'``).

Fails when an ``app_en.arb`` *value* contains a curly double quote
(``“`` ``”``) or a curly apostrophe / single quote (``‘`` ``’``)
that is not on the allow-list. Maintainer decision, 2026-10-31: straight
everywhere. See ``arb_quote_style.py`` for the rule, the normaliser and the
exceptions (values only, English only, literal-syntax strings).

## The allow-list

``arb_quote_allowlist.json`` has two sections:

* ``violations`` -- ``{key: sha256-prefix of the exact value}``: today's curly
  strings, so the ratchet can ship before the sweep. Keyed on the *value hash*,
  not just the key, so **editing an allow-listed string** (keeping the curly
  quote or adding more) fails as a changed string. The hash is opaque on
  purpose: nobody should read the list as a catalogue of acceptable copy.
* ``literal`` -- ``{key: reason}``: strings exempt because a curly character is
  part of typed syntax (reason >= 20 characters). Empty today.

The list is **self-cleaning**: an entry whose key is gone, whose value no longer
has a curly quote, or whose value changed, fails as stale. That keeps the list
a true statement of what is left to burn down (U5b-2 empties it).

## Going green

Run the normaliser on just the reported keys: ``python3 tools/ci/arb_quote_style.py --only KEY...``
(without ``--only`` it rewrites every allow-listed string too -- the U5b-2 sweep). **Not**
``--regenerate``: that rewrites the allow-list to match the tree, which turns
the check green while shipping the violation. It exists for exactly two
occasions -- seeding the list, and re-seeding after merging a ``main`` whose
unrelated allow-listed strings moved -- and the allow-list diff is what a
reviewer reads to tell them apart.

Exit codes: 0 = clean, 1 = violation or stale entry, 2 = bad input.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arb_quote_style as style  # noqa: E402

MIN_REASON_LENGTH = 20


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


def load_allowlist(path: Path) -> dict:
    """Shape-checked allow-list; a malformed one is bad input, never empty."""
    if not path.exists():
        return {"violations": {}, "literal": {}}
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise style.StyleError(f"cannot read allow-list {path}: {exc}") from exc
    if not isinstance(doc, dict) or set(doc) - {"violations", "literal"}:
        raise style.StyleError(f'{path}: expected an object with only "violations" and "literal"')
    out = {"violations": doc.get("violations", {}), "literal": doc.get("literal", {})}
    for section in out:
        entries = out[section]
        if not isinstance(entries, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in entries.items()
        ):
            raise style.StyleError(f'{path}: "{section}" must map string -> string')
    for key, reason in out["literal"].items():
        if len(reason.strip()) < MIN_REASON_LENGTH:
            raise style.StyleError(
                f'{path}: literal exemption for "{key}" needs a real reason '
                f"(>= {MIN_REASON_LENGTH} characters)"
            )
    return out


def evaluate(data: dict, allow: dict) -> tuple[list[str], list[str]]:
    """``(violations, stale)`` as human-readable lines."""
    literal, listed = allow["literal"], allow["violations"]
    messages = dict(style.message_items(data))
    violations: list[str] = []
    for key, value in messages.items():
        if key in literal or not style.has_curly(value):
            continue
        if listed.get(key) != digest(value):
            state = "changed" if key in listed else "new"
            violations.append(f"{key} ({state}): {value[:80]}")
    stale: list[str] = []
    for key, h in listed.items():
        value = messages.get(key)
        if value is None:
            stale.append(f"{key}: no longer in app_en.arb")
        elif key in literal:
            stale.append(f"{key}: now exempt as literal")
        elif not style.has_curly(value):
            stale.append(f"{key}: already straight")
        elif digest(value) != h:
            pass  # reported as a changed violation above
    for key in literal:
        if key not in messages:
            stale.append(f"{key}: literal exemption for a key that is gone")
    return violations, stale


def regenerate(data: dict, allow: dict) -> dict:
    literal = allow["literal"]
    return {
        "violations": {
            k: digest(v)
            for k, v in style.message_items(data)
            if k not in literal and style.has_curly(v)
        },
        "literal": literal,
    }


def prune_stale(data: dict, allow: dict) -> dict:
    """``allow`` minus its stale violation entries; adds nothing."""
    messages = dict(style.message_items(data))
    literal = allow["literal"]
    keep = {
        k: h
        for k, h in allow["violations"].items()
        if k in messages and k not in literal and style.has_curly(messages[k])
    }
    return {"violations": keep, "literal": {k: r for k, r in literal.items() if k in messages}}


def write_allowlist(path: Path, doc: dict) -> None:
    ordered = {
        "violations": dict(sorted(doc["violations"].items())),
        "literal": dict(sorted(doc["literal"].items())),
    }
    path.write_text(json.dumps(ordered, indent=2) + "\n", encoding="utf-8")


def run(root: Path, do_regenerate: bool, prune: bool = False) -> int:
    allow_path = root / style.ALLOWLIST_PATH
    try:
        data = style.load_arb_text((root / style.ARB_PATH).read_text(encoding="utf-8"))
        allow = load_allowlist(allow_path)
    except (OSError, style.StyleError) as exc:
        print(f"::error::{exc}")
        return 2
    if do_regenerate:
        doc = regenerate(data, allow)
        write_allowlist(allow_path, doc)
        print(f"wrote {len(doc['violations'])} allow-listed string(s) to {style.ALLOWLIST_PATH}.")
        return 0
    violations, stale = evaluate(data, allow)
    if prune:
        # Shrink-only: drop entries that are stale, never add one. Safe to run
        # while a new violation is also present (--regenerate would admit it).
        doc = prune_stale(data, allow)
        write_allowlist(allow_path, doc)
        print(f"pruned {len(allow['violations']) - len(doc['violations'])} stale entr(ies); {len(violations)} violation(s) remain.")
        return 1 if violations else 0
    keys = [v.split(" ", 1)[0] for v in violations]
    for line in violations:
        print(f"::error::app_en.arb {line}")
    for line in stale:
        print(f"::error::{style.ALLOWLIST_PATH} stale entry, {line}")
    if violations:
        print(
            "::error::English app text uses straight quotes (\" and '), not curly ones "
            "(maintainer decision 2026-10-31). Fix: run "
            f"`python3 tools/ci/arb_quote_style.py --only {' '.join(keys)}` (just the string(s) "
            "reported; without --only it rewrites the whole allow-list, which is the U5b-2 sweep). "
            "Do NOT run this check with --regenerate to go green: that records the "
            "violation instead of fixing it."
        )
    if stale:
        print(
            "::error::Stale allow-list entries: if the strings were fixed on purpose, "
            "run `python3 tools/ci/check_arb_quote_style.py --prune` and commit the shrink "
            "(--prune only removes stale entries; --regenerate would also admit any new violation)."
        )
    if violations or stale:
        return 1
    print(f"OK: no new curly quotes in app_en.arb ({len(allow['violations'])} allow-listed, to burn down).")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--regenerate", action="store_true", help="rewrite the allow-list from the current ARB")
    ap.add_argument("--prune", action="store_true", help="drop stale allow-list entries only; never adds one")
    ap.add_argument("--root", type=Path, default=style.REPO_ROOT, help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    return run(args.root, args.regenerate, args.prune)


if __name__ == "__main__":
    sys.exit(main())
