#!/usr/bin/env python3
"""Normalise ``app_en.arb`` to straight quotes: ``"`` and ``'`` (D-4, conflict 10).

The maintainer chose *straight everywhere* for English app text (decision
"Conflict 10, quote style for U5b", 2026-10-31): curly double quotes
(``“`` ``”``) become ``"`` and curly apostrophes / single quotes
(``‘`` ``’``) become ``'``. Straight is the easier character to type
and grep; the cost is typography.

This module is both the normaliser CLI and the library the ratchet
(``check_arb_quote_style.py``) imports, so the two cannot disagree about what a
violation is.

    python3 tools/ci/arb_quote_style.py            # rewrite app_en.arb in place
    python3 tools/ci/arb_quote_style.py --check    # report only; exit 1 if it would change

After a rewrite it also drops the fixed strings' allow-list entries (shrink-only)
and reminds you to re-run ``gen-l10n`` so the ``l10n-drift`` gate stays green.
It is **idempotent** and meant to be re-run on a fresh ``main`` rather than
resolving ARB merge hunks by hand (U5b-2's conflict plan).

## Own calls (not maintainer decisions)

* **Values only.** Keys are never touched. ``@key`` metadata (descriptions,
  placeholder examples) is also left alone: it is developer-facing, never
  rendered, and rewriting it would add merge-conflict surface for no user
  benefit. Four descriptions (and two placeholder examples) contain curly quotes today. Rejected: normalising
  descriptions too, for a uniform file; the ratchet does not read them either.
* **English only, enforced structurally.** The file must declare
  ``"@@locale": "en"``; anything else is refused (exit 2). German, French,
  Danish, Dutch and Japanese have their own quote conventions
  („…“, « … », 「…」), so forcing English marks on them would be wrong.
* **Byte-stable output.** The ARB is parsed and re-serialised in the repo's
  format (2-space indent, ``ensure_ascii=False``, trailing newline). If the
  *unmodified* file does not round-trip byte-for-byte, the tool refuses rather
  than reformat the file under cover of a quote fix.

## Exceptions

* **Literal-syntax strings.** A key listed under ``"literal"`` in
  ``arb_quote_allowlist.json`` (with a reason) is never rewritten and never
  flagged: use it for a string that shows text the user types where a curly
  character is itself part of the syntax. It is empty today. With straight
  quotes as the rule, typed syntax is already compliant, so the section exists
  to keep the normaliser from ever rewriting such a character.
* **ICU / apostrophes.** ``app/l10n.yaml`` sets no ``use-escaping``, so
  gen-l10n treats ``'`` as a literal character, never as the ICU quote
  character. ``’`` -> ``'`` is therefore a pure character substitution. If
  ``use-escaping: true`` is ever set, that stops being true (a lone ``'`` would
  start an escape and swallow braces), so this tool refuses to run (exit 2)
  until it is reviewed. ``test_arb_quote_style_gen_l10n.py`` proves the
  literal-apostrophe behaviour against the real gen-l10n.

Exit codes: 0 = clean / rewritten, 1 = ``--check`` found strings to normalise,
2 = bad input.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ARB_PATH = Path("app/lib/l10n/app_en.arb")
L10N_YAML = Path("app/l10n.yaml")
ALLOWLIST_PATH = Path("tools/ci/arb_quote_allowlist.json")

CURLY_DOUBLE = "“”"
CURLY_SINGLE = "‘’"
CURLY_RE = re.compile(f"[{CURLY_DOUBLE}{CURLY_SINGLE}]")
_TABLE = str.maketrans({"“": '"', "”": '"', "‘": "'", "’": "'"})


class StyleError(Exception):
    """Bad input (exit 2): not a violation, a refusal to guess."""


def normalize_value(value: str) -> str:
    """Straighten curly quotes and apostrophes in one string. Idempotent."""
    return value.translate(_TABLE)


def has_curly(value: str) -> bool:
    return CURLY_RE.search(value) is not None


def message_items(data: dict) -> list[tuple[str, str]]:
    """``(key, value)`` for string messages: no ``@`` metadata, no non-strings."""
    return [(k, v) for k, v in data.items() if not k.startswith("@") and isinstance(v, str)]


def dump_arb(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def load_arb_text(raw: str, name: str = "app_en.arb") -> dict:
    """Parse an English ARB, refusing anything this tool must not rewrite."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise StyleError(f"{name} is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise StyleError(f"{name}: ARB root is not an object")
    if data.get("@@locale") != "en":
        raise StyleError(
            f'{name}: "@@locale" is {data.get("@@locale")!r}, not "en". This tool '
            "normalises English only; other locales keep their own quote conventions."
        )
    if dump_arb(data) != raw:
        raise StyleError(
            f"{name} does not round-trip byte-for-byte through json (indent=2, "
            "ensure_ascii=False). Refusing to reformat the file as a side effect of "
            "a quote fix; re-save it canonically first (e.g. `python3 -c \"import json,pathlib;"
            "p=pathlib.Path('app/lib/l10n/app_en.arb');"
            "p.write_text(json.dumps(json.loads(p.read_text()),ensure_ascii=False,indent=2)+chr(10))\"`)."
        )
    return data


def check_use_escaping(l10n_yaml_text: str) -> None:
    """Refuse to run if gen-l10n would treat ``'`` as an escape character."""
    if re.search(r"^\s*use-escaping\s*:\s*true\b", l10n_yaml_text, re.M | re.I):
        raise StyleError(
            "l10n.yaml sets use-escaping: true, so ' is the ICU escape character and "
            "converting a curly apostrophe to it changes what renders. Review this "
            "tool before running it."
        )


def load_literal(allowlist_path: Path) -> dict[str, str]:
    """The ``literal`` exemptions (``{key: reason}``); empty if no file."""
    if not allowlist_path.exists():
        return {}
    try:
        doc = json.loads(allowlist_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise StyleError(f"cannot read {allowlist_path}: {exc}") from exc
    lit = doc.get("literal", {}) if isinstance(doc, dict) else None
    if not isinstance(lit, dict) or not all(
        isinstance(k, str) and isinstance(v, str) for k, v in lit.items()
    ):
        raise StyleError(f'{allowlist_path}: "literal" must map key -> reason string')
    return lit


def normalize_arb(data: dict, literal: dict[str, str] | None = None) -> tuple[dict, list[str]]:
    """Return ``(new_data, changed_keys)``. Key order and metadata are preserved."""
    literal = literal or {}
    out: dict = {}
    changed: list[str] = []
    for key, value in data.items():
        if (
            not key.startswith("@")
            and isinstance(value, str)
            and key not in literal
            and has_curly(value)
        ):
            out[key] = normalize_value(value)
            changed.append(key)
        else:
            out[key] = value
    return out, changed


def run(root: Path, check_only: bool) -> int:
    arb = root / ARB_PATH
    try:
        check_use_escaping((root / L10N_YAML).read_text(encoding="utf-8"))
        raw = arb.read_text(encoding="utf-8")
        data = load_arb_text(raw, arb.name)
        new, changed = normalize_arb(data, load_literal(root / ALLOWLIST_PATH))
    except (OSError, StyleError) as exc:
        print(f"::error::{exc}", file=sys.stderr)
        return 2
    if check_only:
        if changed:
            print(f"{len(changed)} string(s) in {arb.name} contain curly quotes: {', '.join(changed)}")
            return 1
        print("OK: no curly quotes in app_en.arb values.")
        return 0
    if changed:
        arb.write_text(dump_arb(new), encoding="utf-8")
        pruned = prune_allowlist(root / ALLOWLIST_PATH, set(changed))
        print(f"normalised {len(changed)} string(s) in {arb.name}; dropped {pruned} fixed allow-list entr(ies).")
        print("Next: `fvm flutter gen-l10n` in app/ and commit lib/l10n (the l10n-drift gate).")
    else:
        print(f"normalised 0 string(s) in {arb.name}.")
    return 0


def prune_allowlist(path: Path, fixed: set[str]) -> int:
    """Drop ``violations`` entries for strings just fixed; never adds anything.

    Keeps the ratchet green after a normalise (a fixed string's entry would
    otherwise be stale). Shrink-only, so it cannot hide a violation.
    """
    if not path.exists():
        return 0
    doc = json.loads(path.read_text(encoding="utf-8"))
    listed = doc.get("violations", {})
    drop = [k for k in listed if k in fixed]
    for k in drop:
        del listed[k]
    if drop:
        path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    return len(drop)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="report only; exit 1 if anything would change")
    ap.add_argument("--root", type=Path, default=REPO_ROOT, help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    return run(args.root, args.check)


if __name__ == "__main__":
    sys.exit(main())
