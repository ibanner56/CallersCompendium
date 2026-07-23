#!/usr/bin/env python3
"""Assisted ARB translation pipeline for Caller's Compendium.

Caller's Compendium is localized with Flutter ``gen-l10n``: English is the
source locale (``app/lib/l10n/app_en.arb``) and each other language is a sibling
``app_<locale>.arb`` translating the *values* only (keys, ``@key`` metadata, and
ICU placeholders/plural structure are the template's contract). Translations
arrive from the community (PRs) and, in future, from import/sharing features, so
a translated ARB is **untrusted input** and must be validated (OWASP) before it
is trusted or regenerated into Dart.

This tool is model-agnostic: it does the *deterministic* halves of an assisted
translation — deciding **what** to translate and checking **that** a translation
is safe and gen-l10n-valid — while the actual translation is produced by the
Copilot session model (via the ``arb-translate`` extension). It deliberately
shells out to nothing and imports only the standard library, matching the
free/offline tooling constraint of the other ``tools/ci`` scripts.

Subcommands
-----------
``extract``   Emit the keys missing (or empty) in a locale as a JSON batch with
              each key's English source, description, declared placeholders, and
              any matched glossary hints — the payload the model translates.
``apply``     Merge a ``{key: value}`` translation map into ``app_<locale>.arb``
              (values only, template key order, never inventing keys/metadata).
``validate``  Gate a locale (or ``--all``) against the template: subset keys,
              ICU argument/placeholder parity (allowing locale-specific plural
              categories), metadata integrity, a sane ``@@locale``, and a
              content-safety scan (control/bidi-override chars, dangerous URI
              schemes). Exit non-zero on any error; ``::error::`` annotations.

Usage::

    python3 tools/ci/arb_translate.py extract  --locale fr
    python3 tools/ci/arb_translate.py apply     --locale fr --input batch.json
    python3 tools/ci/arb_translate.py validate  --all

Exit codes: 0 = OK (validate may still print warnings), 1 = validation error /
bad input, 2 = usage / IO error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

# ---------------------------------------------------------------------------
# Defaults (relative to the repo root, which is CI's / the scripts' cwd).
# ---------------------------------------------------------------------------
DEFAULT_ARB_DIR = "app/lib/l10n"
DEFAULT_TEMPLATE = "app_en.arb"
DEFAULT_GLOSSARY = "tools/ci/i18n_glossary.json"

# A translated value is bounded relative to its English source purely as an
# anti-abuse guard (a pathologically long string is a resource/DoS smell, not a
# real translation). Legitimate expansion is generous — German/Finnish can be
# far longer than English — so this only *warns*, never fails.
LENGTH_WARN_FACTOR = 8
LENGTH_WARN_FLOOR = 200  # chars; below this, short strings may expand a lot

_LOCALE_RE = re.compile(r"^[A-Za-z]{2,3}(?:_[A-Za-z0-9]{2,8}){0,2}$")
_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
_PLURAL_KEY_RE = re.compile(r"^(?:=\d+|zero|one|two|few|many|other)$")
_SELECT_KEY_RE = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*|other)$")

# Unicode bidirectional *override/embedding/isolate* controls — the "Trojan
# Source" (CVE-2021-42574) vectors that let text render in a deceptive order.
# LRM/RLM/ALM (U+200E/200F/061C) are intentionally NOT here: they are legitimate
# directional marks an RTL translation may genuinely need.
_BIDI_DANGER = {
    "\u202a", "\u202b", "\u202c", "\u202d", "\u202e",  # LRE RLE PDF LRO RLO
    "\u2066", "\u2067", "\u2068", "\u2069",            # LRI RLI FSI PDI
}
# Dangerous URI schemes have no place in a UI string; hard-fail them so a
# translation can never smuggle one into a place that later resolves a link.
_DANGEROUS_URI_RE = re.compile(
    r"(?i)(?:(?:javascript|vbscript)\s*:|data\s*:\s*text/html)"
)
_HTML_TAG_RE = re.compile(r"</?[A-Za-z][A-Za-z0-9]*(?:\s[^<>]*)?/?>")


class ArbError(Exception):
    """A fatal problem reading or interpreting an ARB file."""


class IcuError(Exception):
    """The message string is not well-formed ICU MessageFormat."""


# ---------------------------------------------------------------------------
# ICU MessageFormat parsing
# ---------------------------------------------------------------------------
def parse_icu(msg: str) -> dict[str, str]:
    """Return ``{argument_name: kind}`` for an ICU message.

    ``kind`` is ``"plural"``, ``"select"`` or ``"simple"`` (a bare ``{name}`` or
    a formatted arg like ``{n, number}``). Raises :class:`IcuError` if the
    message is malformed (unbalanced braces, missing ``other`` branch, invalid
    plural keyword, bad argument name). Implements ICU apostrophe quoting so a
    literal apostrophe (``You're``) is not mistaken for a quote.
    """
    args: dict[str, str] = {}
    end = _collect(msg, 0, args)
    if end != len(msg):
        raise IcuError(f"unbalanced '}}' at index {end}")
    return args


def _collect(s: str, i: int, args: dict[str, str]) -> int:
    """Parse a (sub)message from ``i``; return the index of the terminating
    ``}`` (for a submessage) or ``len(s)`` (at top level)."""
    n = len(s)
    while i < n:
        c = s[i]
        if c == "'":
            # ICU apostrophe quoting.
            if i + 1 < n and s[i + 1] == "'":
                i += 2  # escaped literal apostrophe
                continue
            if i + 1 < n and s[i + 1] in "{}#":
                i += 2  # begin quoted literal, runs to next apostrophe
                while i < n and s[i] != "'":
                    i += 1
                i += 1  # consume closing apostrophe (tolerate EOF)
                continue
            i += 1  # lone apostrophe = literal
            continue
        if c == "}":
            return i
        if c == "{":
            i = _parse_arg(s, i, args)
            continue
        i += 1
    return i


def _parse_arg(s: str, i: int, args: dict[str, str]) -> int:
    n = len(s)
    i += 1  # consume '{'
    start = i
    while i < n and s[i] not in ",}":
        i += 1
    name = s[start:i].strip()
    if not _NAME_RE.match(name):
        raise IcuError(f"invalid placeholder name {name!r}")
    if i < n and s[i] == "}":
        args.setdefault(name, "simple")
        return i + 1
    if i >= n:
        raise IcuError(f"unterminated placeholder {{{name}")
    i += 1  # consume ','
    start = i
    while i < n and s[i] not in ",}":
        i += 1
    argtype = s[start:i].strip()
    if argtype in ("plural", "select", "selectordinal"):
        kind = "select" if argtype == "select" else "plural"
        # A name used as a plural/select selector wins over a bare use.
        args[name] = kind
        if i >= n or s[i] != ",":
            raise IcuError(f"expected ',' after '{argtype}' for {{{name}}}")
        i += 1
        i = _parse_branches(s, i, args, kind, name)
        if i >= n or s[i] != "}":
            raise IcuError(f"expected '}}' to close '{argtype}' for {{{name}}}")
        return i + 1
    # Any other formatted argument (number/date/time/…): no submessages, so
    # skip to its matching close brace.
    args.setdefault(name, "simple")
    depth = 1
    while i < n and depth:
        if s[i] == "{":
            depth += 1
        elif s[i] == "}":
            depth -= 1
        i += 1
    if depth:
        raise IcuError(f"unterminated argument {{{name}")
    return i


def _parse_branches(
    s: str, i: int, args: dict[str, str], kind: str, name: str
) -> int:
    n = len(s)
    seen: list[str] = []
    key_re = _PLURAL_KEY_RE if kind == "plural" else _SELECT_KEY_RE
    while i < n:
        while i < n and s[i].isspace():
            i += 1
        if i < n and s[i] == "}":
            break
        start = i
        while i < n and s[i] != "{":
            if s[i] == "}":
                raise IcuError(f"missing submessage for a branch of {{{name}}}")
            i += 1
        key = s[start:i].strip()
        if not key_re.match(key):
            raise IcuError(f"invalid {kind} branch keyword {key!r} in {{{name}}}")
        seen.append(key)
        if i >= n or s[i] != "{":
            raise IcuError(f"expected '{{' after branch {key!r} in {{{name}}}")
        i += 1  # consume '{'
        i = _collect(s, i, args)
        if i >= n or s[i] != "}":
            raise IcuError(f"unterminated branch {key!r} in {{{name}}}")
        i += 1  # consume '}'
    if "other" not in seen:
        raise IcuError(f"{kind} {{{name}}} is missing the required 'other' branch")
    return i


# ---------------------------------------------------------------------------
# ARB model
# ---------------------------------------------------------------------------
def load_arb(path: Path) -> dict:
    """Load an ARB file as an ordered dict; raise :class:`ArbError` on trouble."""
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ArbError(f"cannot read {path}: {exc}") from exc
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ArbError(f"{path} is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ArbError(f"{path} must be a JSON object")
    return data


def message_keys(data: dict) -> list[str]:
    """Ordered message keys: top-level keys that are neither ``@@x`` globals nor
    ``@key`` metadata blocks."""
    return [k for k in data if not k.startswith("@")]


def is_translatable(value) -> bool:
    return isinstance(value, str)


def declared_placeholders(data: dict, key: str) -> dict:
    meta = data.get("@" + key)
    if isinstance(meta, dict) and isinstance(meta.get("placeholders"), dict):
        return meta["placeholders"]
    return {}


# ---------------------------------------------------------------------------
# extract
# ---------------------------------------------------------------------------
def load_glossary(path: Path):
    """Load the domain glossary, raising :class:`ArbError` on any trouble so a
    malformed file yields a clean ``::error::`` + exit code, not a traceback."""
    if not path.exists():
        return {"doNotTranslate": [], "terms": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ArbError(f"cannot read glossary {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ArbError(f"glossary {path} is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ArbError(f"glossary {path} must be a JSON object")
    dnt = data.setdefault("doNotTranslate", [])
    terms = data.setdefault("terms", {})
    if not isinstance(dnt, list):
        raise ArbError(f"glossary {path}: 'doNotTranslate' must be a list")
    if not isinstance(terms, dict):
        raise ArbError(f"glossary {path}: 'terms' must be a JSON object")
    return data


def glossary_hints(source: str, glossary: dict) -> list[dict]:
    """Return glossary entries whose term occurs (word-boundary, case-insensitive)
    in ``source``, so the model gets targeted guidance for domain jargon."""
    hits: list[dict] = []
    lowered = source.lower()
    for term, info in glossary.get("terms", {}).items():
        if re.search(r"\b" + re.escape(term.lower()) + r"\b", lowered):
            entry = {"term": term}
            if isinstance(info, dict):
                entry.update(info)
            hits.append(entry)
    return hits


def cmd_extract(args) -> int:
    arb_dir = Path(args.arb_dir)
    template = load_arb(arb_dir / args.template)
    target_path = arb_dir / f"app_{args.locale}.arb"
    target = load_arb(target_path) if target_path.exists() else {}
    glossary = load_glossary(Path(args.glossary))

    existing = set(message_keys(target))
    items = []
    for key in message_keys(template):
        src = template[key]
        if not is_translatable(src):
            continue
        translated = target.get(key)
        # A key needs translating if it is absent, non-string, or blank.
        if key in existing and isinstance(translated, str) and translated.strip():
            continue
        items.append(
            {
                "key": key,
                "source": src,
                "description": (template.get("@" + key) or {}).get("description", ""),
                "placeholders": declared_placeholders(template, key),
                "glossary": glossary_hints(src, glossary),
            }
        )
        if args.limit and len(items) >= args.limit:
            break

    payload = {
        "locale": args.locale,
        "sourceLocale": template.get("@@locale", "en"),
        "count": len(items),
        "doNotTranslate": glossary.get("doNotTranslate", []),
        "items": items,
    }
    json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
    return 0


# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
def cmd_apply(args) -> int:
    arb_dir = Path(args.arb_dir)
    template = load_arb(arb_dir / args.template)
    valid_keys = set(message_keys(template))

    raw = sys.stdin.read() if args.input == "-" else Path(args.input).read_text("utf-8")
    try:
        translations = json.loads(raw)
    except json.JSONDecodeError as exc:
        _err(f"--input is not valid JSON: {exc}")
        return 1
    # Accept either a flat {key: value} map or the {"items":[{key,value}]} echo.
    if isinstance(translations, dict) and "items" in translations and isinstance(
        translations["items"], list
    ):
        translations = {
            it["key"]: it.get("translation", it.get("value"))
            for it in translations["items"]
            if isinstance(it, dict) and "key" in it
        }
    if not isinstance(translations, dict):
        _err("--input must be a JSON object mapping keys to translated strings")
        return 1

    unknown = [k for k in translations if k not in valid_keys]
    if unknown:
        _err(
            "refusing to apply unknown keys not present in the template: "
            + ", ".join(sorted(unknown)[:10])
        )
        return 1
    non_str = [k for k, v in translations.items() if not isinstance(v, str)]
    if non_str:
        _err("every translation value must be a string; offenders: "
             + ", ".join(sorted(non_str)[:10]))
        return 1

    target_path = arb_dir / f"app_{args.locale}.arb"
    result = load_arb(target_path) if target_path.exists() else {}
    result["@@locale"] = args.locale
    for key, value in translations.items():
        result[key] = value

    ordered = _reorder(result, template, args.locale)
    target_path.write_text(
        json.dumps(ordered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"OK: wrote {len(translations)} translation(s) to {target_path} "
        f"({len(message_keys(ordered))} of {len(valid_keys)} keys now present)."
    )
    return 0


def _reorder(result: dict, template: dict, locale: str) -> dict:
    """Deterministic output: ``@@locale`` first, then message keys in *template*
    order (only those present), each followed by its ``@key`` block if the file
    already carried one (preserving a human copy-the-template file's metadata).
    Other pre-existing ``@@`` globals are kept up front. Message keys absent from
    the template are pruned here: ``apply`` rejects unknown keys in the *input
    map*, but a stale key already sitting in the locale file (e.g. one since
    removed from the template) would otherwise survive — so it is dropped and a
    warning is emitted, keeping the removal explicit rather than silent."""
    ordered: dict = {}
    ordered["@@locale"] = locale
    for gk in [k for k in result if k.startswith("@@") and k != "@@locale"]:
        ordered[gk] = result[gk]
    template_keys = set(message_keys(template))
    dropped = [k for k in message_keys(result) if k not in template_keys]
    if dropped:
        _warn(
            "dropping %d key(s) not present in the template: %s"
            % (len(dropped), ", ".join(sorted(dropped)[:10]))
        )
    for key in message_keys(template):
        if key in result:
            ordered[key] = result[key]
            meta = "@" + key
            if meta in result:
                ordered[meta] = result[meta]
    return ordered


# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------
def scan_value(value: str) -> list[tuple[str, str]]:
    """Content-safety scan of a translated string. Returns ``(severity, msg)``
    where severity is ``"error"`` or ``"warning"``."""
    problems: list[tuple[str, str]] = []
    for ch in value:
        cp = ord(ch)
        if ch in _BIDI_DANGER:
            problems.append(("error", f"bidirectional override control U+{cp:04X} "
                                      "(Trojan-Source risk)"))
            break
    for ch in value:
        cp = ord(ch)
        if ch in ("\t", "\n", "\r"):
            continue
        if cp < 0x20 or 0x7F <= cp <= 0x9F:
            problems.append(("error", f"disallowed control character U+{cp:04X}"))
            break
        if cp in (0xFFFE, 0xFFFF) or 0xFDD0 <= cp <= 0xFDEF:
            problems.append(("error", f"Unicode noncharacter U+{cp:04X}"))
            break
    if _DANGEROUS_URI_RE.search(value):
        problems.append(("error", "dangerous URI scheme (javascript:/vbscript:/data:text/html)"))
    if _HTML_TAG_RE.search(value):
        problems.append(("warning", "looks like an HTML/XML tag; UI strings render "
                                    "as plain text — confirm this is intentional"))
    return problems


def validate_locale(arb_dir: Path, template: dict, locale: str) -> tuple[list[str], list[str]]:
    """Validate one ``app_<locale>.arb`` against ``template``.
    Returns ``(errors, warnings)``."""
    errors: list[str] = []
    warnings: list[str] = []
    path = arb_dir / f"app_{locale}.arb"
    try:
        data = load_arb(path)
    except ArbError as exc:
        return [str(exc)], []

    # @@locale sanity + agreement with the filename.
    at_locale = data.get("@@locale")
    if not isinstance(at_locale, str) or not _LOCALE_RE.match(at_locale or ""):
        errors.append(f"{path.name}: @@locale {at_locale!r} is missing or malformed")
    elif at_locale != locale:
        errors.append(
            f"{path.name}: @@locale {at_locale!r} does not match filename locale "
            f"{locale!r} (gen-l10n can misfile translations)"
        )

    template_keys = set(message_keys(template))
    for key in message_keys(data):
        value = data[key]
        # Unknown keys: never allowed (drift or tampering).
        if key not in template_keys:
            errors.append(f"{path.name}: key {key!r} is not in the template")
            continue
        if not is_translatable(value):
            errors.append(f"{path.name}: value for {key!r} must be a string")
            continue
        # Metadata integrity: if the file carries a @key block, it must be
        # byte-identical to the template's (translators change values only).
        meta = "@" + key
        if meta in data and data[meta] != template.get(meta):
            errors.append(f"{path.name}: metadata {meta!r} differs from the template")
        # ICU argument / placeholder parity.
        try:
            t_args = parse_icu(template[key])
        except IcuError:
            # A broken template is reported once, separately, below.
            t_args = None
        try:
            v_args = parse_icu(value)
        except IcuError as exc:
            errors.append(f"{path.name}: {key!r} is not valid ICU: {exc}")
            v_args = None
        if t_args is not None and v_args is not None:
            errors.extend(
                f"{path.name}: {key!r} {p}" for p in _parity(t_args, v_args)
            )
        # Content safety.
        for sev, msg in scan_value(value):
            (errors if sev == "error" else warnings).append(
                f"{path.name}: {key!r} {msg}"
            )
        # Anti-abuse length guard (warn only).
        src = template[key]
        if len(value) > max(LENGTH_WARN_FLOOR, LENGTH_WARN_FACTOR * len(src)):
            warnings.append(
                f"{path.name}: {key!r} is {len(value)} chars vs {len(src)} in the "
                "source — unusually long, please double-check"
            )
        if isinstance(value, str) and unicodedata.normalize("NFC", value) != value:
            warnings.append(f"{path.name}: {key!r} is not Unicode-NFC normalized")

    # Orphan metadata: an @key with no corresponding message key.
    for key in [k for k in data if k.startswith("@") and not k.startswith("@@")]:
        if key[1:] not in message_keys(data):
            warnings.append(f"{path.name}: metadata {key!r} has no matching message key")
    return errors, warnings


def _parity(t_args: dict[str, str], v_args: dict[str, str]) -> list[str]:
    problems: list[str] = []
    missing = set(t_args) - set(v_args)
    extra = set(v_args) - set(t_args)
    if missing:
        problems.append("drops placeholder(s): " + ", ".join(sorted(missing)))
    if extra:
        problems.append("adds unknown placeholder(s): " + ", ".join(sorted(extra)))
    for name in set(t_args) & set(v_args):
        if t_args[name] != v_args[name]:
            problems.append(
                f"placeholder {name!r} changed kind ({t_args[name]} -> {v_args[name]})"
            )
    return problems


def cmd_validate(args) -> int:
    arb_dir = Path(args.arb_dir)
    template_path = arb_dir / args.template
    try:
        template = load_arb(template_path)
    except ArbError as exc:
        _err(str(exc))
        return 1

    # Sanity: the template's own messages must be valid ICU.
    template_errors = []
    for key in message_keys(template):
        if is_translatable(template[key]):
            try:
                parse_icu(template[key])
            except IcuError as exc:
                template_errors.append(f"{args.template}: template {key!r} invalid ICU: {exc}")
    for e in template_errors:
        _err(e)

    if args.all:
        locales = sorted(
            p.name[len("app_"):-len(".arb")]
            for p in arb_dir.glob("app_*.arb")
            if p.name != args.template
        )
    elif args.locale:
        locales = [args.locale]
    else:
        _err("validate needs --locale <code> or --all")
        return 2

    all_errors = list(template_errors)
    all_warnings: list[str] = []
    for locale in locales:
        errors, warnings = validate_locale(arb_dir, template, locale)
        all_errors.extend(errors)
        all_warnings.extend(warnings)

    for w in all_warnings:
        print(f"::warning::{w}")
    for e in all_errors:
        print(f"::error::{e}")

    if all_errors:
        print(f"FAIL: {len(all_errors)} error(s) across {len(locales)} locale(s).")
        return 1
    scope = "all locales" if args.all else ", ".join(locales) or "(none)"
    print(
        f"OK: {scope} valid against {args.template} "
        f"({len(all_warnings)} warning(s))."
    )
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _err(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)


def _warn(msg: str) -> None:
    print(f"::warning::{msg}", file=sys.stderr)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--arb-dir", default=DEFAULT_ARB_DIR, dest="arb_dir")
    parser.add_argument("--template", default=DEFAULT_TEMPLATE)
    sub = parser.add_subparsers(dest="command", required=True)

    p_extract = sub.add_parser("extract", help="emit the untranslated batch as JSON")
    p_extract.add_argument("--locale", required=True)
    p_extract.add_argument("--glossary", default=DEFAULT_GLOSSARY)
    p_extract.add_argument("--limit", type=int, default=0,
                           help="cap the number of items (0 = all)")
    p_extract.set_defaults(func=cmd_extract)

    p_apply = sub.add_parser("apply", help="merge a translation map into a locale ARB")
    p_apply.add_argument("--locale", required=True)
    p_apply.add_argument("--input", required=True,
                         help="path to a JSON {key: value} map, or - for stdin")
    p_apply.set_defaults(func=cmd_apply)

    p_validate = sub.add_parser("validate", help="validate locale ARB(s) against the template")
    group = p_validate.add_mutually_exclusive_group()
    group.add_argument("--locale")
    group.add_argument("--all", action="store_true")
    p_validate.set_defaults(func=cmd_validate)
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except ArbError as exc:
        _err(str(exc))
        return 2
    except FileNotFoundError as exc:
        _err(str(exc))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
