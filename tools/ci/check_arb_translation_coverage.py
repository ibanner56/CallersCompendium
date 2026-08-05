#!/usr/bin/env python3
"""CI ratchet: no user-facing string may ship untranslated in a shipped locale.

Every key in ``app_en.arb`` must have a real translation in every
``app_<locale>.arb``. A key that is absent renders in **English** for that
locale's users, because ``gen-l10n`` emits the template value into the locale
class when the key is missing. That fallback is a good failure mode — it beats a
crash or an empty label — but it is a fallback, not a feature, and until now
nothing surfaced how often it fired. The count existed only if someone thought
to run ``arb_translate.py extract``, so it never appeared in a PR, a review, or
a CI log, and it grew silently: 40 -> 45 -> 65 -> 77 -> 100 over the life of #813.

The baseline is **clean** — every locale is fully translated as of the commit
that introduced this check — so this hard-fails at zero. Ratcheting at a nonzero
baseline was considered and rejected: it needs an allowlist seeded with the
existing backlog, and a ratchet that starts with 500 exceptions is a ratchet
that has already lost the argument.

There IS an escape hatch, and it starts empty: see ``untranslated_allowlist.json``.
A string can be knowingly shipped untranslated, but only by naming it and saying
**why**, in a diff a reviewer sees.

## What this measures that ``arb_translate.py validate`` does not

``validate`` enforces that a locale's keys are a **subset** of the template.
Missing keys pass it by design, because absence *is* the work queue that
``extract`` reads. So ``validate --all`` returned ``OK ... 0 warning(s)`` on a
tree with 100 untranslated strings per locale. The two checks are complementary
and neither subsumes the other: ``validate`` asks "is what's here correct and
safe", this asks "is it all here".

## The wrong fix, and why the failure message names it

Pasting the **English** value into a locale ARB turns this check green while
changing nothing a user sees — and it marks the key *translated*, which removes
it from ``extract``'s queue permanently. A missing key falls back to English and
**stays queued**; a key filled with English looks done and is silently lost.
That near-miss is on the record (PR #812), and an automated reviewer has since
asked for exactly that change on several PRs, so it is a live failure mode
rather than a theoretical one.

Detecting it mechanically is not viable: 415 locale values in this repo are
legitimately byte-identical to their English source (``appTitle``, ``commonOk``,
``Formation`` in Danish and German, ``September`` in three languages), so an
identical-to-English rule would need a 415-entry allowlist on day one. Instead,
the failure annotation below names the wrong fix explicitly — that annotation is
what a contributor is reading at the moment they decide how to go green.

## Definition of "untranslated"

Imported from ``arb_translate`` rather than reimplemented, so this check and the
extractor cannot drift: a key is untranslated when it is **absent**, **not a
string**, or **blank/whitespace-only** — byte-identical to ``cmd_extract``'s
rule.

Exit codes: 0 = every locale complete, 1 = at least one untranslated string,
2 = bad input (missing template, no locales, malformed allowlist).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from arb_translate import (  # noqa: E402
    DEFAULT_ARB_DIR,
    DEFAULT_TEMPLATE,
    ArbError,
    is_translatable,
    load_arb,
    message_keys,
)

REPO_ROOT = HERE.parents[1]

DEFAULT_ALLOWLIST = "tools/ci/untranslated_allowlist.json"

# A reason has to actually be a reason. "TODO", "n/a" and "" are not, and the
# whole point of the allowlist is that the diff carries the justification.
MIN_REASON_LENGTH = 20


def _fail(msg: str, code: int = 2) -> None:
    # `::error::` renders as an annotation in the GitHub Actions UI.
    print(f"::error::{msg}")
    sys.exit(code)


def _display_path(path: Path) -> str:
    """Repo-relative when possible, so the annotation names a path a reader can
    act on rather than a runner's absolute checkout directory."""
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def locale_arb_paths(arb_dir: Path, template_name: str) -> list[Path]:
    """Every ``app_<locale>.arb`` in [arb_dir] except the template.

    Discovery is by glob rather than a hardcoded list so a newly contributed
    locale is covered the moment its file lands, with no registration step to
    forget. That matters more than it sounds: the failure mode of a registry is
    a locale that silently isn't checked, which is indistinguishable from a
    locale that passes.
    """
    return sorted(p for p in arb_dir.glob("app_*.arb") if p.name != template_name)


def locale_of(path: Path) -> str:
    """``app_pt_BR.arb`` -> ``pt_BR``."""
    return path.stem[len("app_") :]


def untranslated_keys(template: dict, target: dict) -> list[str]:
    """Template keys with no real translation in [target], in template order.

    Mirrors ``arb_translate.cmd_extract``: absent, non-string, or blank. Uses
    the imported ``message_keys`` / ``is_translatable`` so the two definitions
    are the same code, not merely the same intent.
    """
    missing: list[str] = []
    for key in message_keys(template):
        if not is_translatable(template[key]):
            continue
        value = target.get(key)
        if isinstance(value, str) and value.strip():
            continue
        missing.append(key)
    return missing


def load_allowlist(path: Path) -> dict[str, dict[str, str]]:
    """Load and shape-check the allowlist, raising :class:`ArbError` on trouble.

    Shape: ``{"<locale>": {"<key>": "<reason>"}}``. Anything else is a bad
    input (exit 2), not a violation (exit 1) — a malformed allowlist must never
    be silently read as an empty one, because that would turn a typo into a
    green build with the exceptions quietly dropped.
    """
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ArbError(f"cannot read allowlist {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ArbError(f"allowlist {path} is not valid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ArbError(f"allowlist {path} must be a JSON object")
    out: dict[str, dict[str, str]] = {}
    for locale, entries in data.items():
        # A `_comment`-style key would otherwise have to be shaped like a
        # locale; keep the file's own documentation out of the data.
        if locale.startswith("_"):
            continue
        if not isinstance(entries, dict):
            raise ArbError(
                f"allowlist {path}: '{locale}' must map keys to reasons, "
                f"got {type(entries).__name__}",
            )
        for key, reason in entries.items():
            if not isinstance(reason, str):
                raise ArbError(
                    f"allowlist {path}: reason for {locale}/{key} must be a "
                    f"string, got {type(reason).__name__}",
                )
        out[locale] = dict(entries)
    return out


def stale_allowlist_entries(
    allowlist: dict[str, dict[str, str]],
    template: dict,
    per_locale_untranslated: dict[str, set[str]],
) -> list[str]:
    """Allowlist entries that no longer describe reality.

    The allowlist can't be allowed to rot: an entry whose string has since been
    translated, or whose key has left the template entirely, is a stale excuse
    that makes the list look like it is carrying more weight than it is. This
    mirrors ``hardcoded_ui_strings_allowlist.dart``, which fails when a listed
    file no longer has anything to flag — a file can't be parked on the list
    once it's clean, and neither can a string.

    A too-short reason is reported here for the same reason: the list's value is
    the justification, so an entry without one is not an exception, it's a
    silent bump wearing an exception's clothes.
    """
    template_keys = set(message_keys(template))
    problems: list[str] = []
    for locale in sorted(allowlist):
        if locale not in per_locale_untranslated:
            problems.append(
                f"allowlist names locale '{locale}', which has no "
                f"app_{locale}.arb — remove the entry or add the locale",
            )
            continue
        for key in sorted(allowlist[locale]):
            reason = allowlist[locale][key].strip()
            if key not in template_keys:
                problems.append(
                    f"allowlist entry {locale}/{key} is not a key in the "
                    "template — it was renamed or removed; drop the entry",
                )
                continue
            if key not in per_locale_untranslated[locale]:
                problems.append(
                    f"allowlist entry {locale}/{key} is already translated — "
                    "drop the entry, the exception is no longer needed",
                )
                continue
            if len(reason) < MIN_REASON_LENGTH:
                problems.append(
                    f"allowlist entry {locale}/{key} needs a real reason "
                    f"(at least {MIN_REASON_LENGTH} characters) saying why this "
                    "string is knowingly shipped untranslated",
                )
    return problems


def run(arb_dir: Path, template_name: str, allowlist_path: Path) -> int:
    template_path = arb_dir / template_name
    if not template_path.exists():
        _fail(f"template ARB not found: {template_path}")
    try:
        template = load_arb(template_path)
    except ArbError as exc:
        _fail(str(exc))

    paths = locale_arb_paths(arb_dir, template_name)
    if not paths:
        # A check that greens out on an empty input set is worse than no check,
        # because it reports success. Fail loudly instead.
        _fail(f"no locale ARBs found in {arb_dir} (expected app_<locale>.arb)")

    per_locale: dict[str, set[str]] = {}
    ordered: dict[str, list[str]] = {}
    for path in paths:
        locale = locale_of(path)
        try:
            target = load_arb(path)
        except ArbError as exc:
            _fail(str(exc))
        keys = untranslated_keys(template, target)
        ordered[locale] = keys
        per_locale[locale] = set(keys)

    try:
        allowlist = load_allowlist(allowlist_path)
    except ArbError as exc:
        _fail(str(exc))

    stale = stale_allowlist_entries(allowlist, template, per_locale)
    for problem in stale:
        print(f"::error::{problem}")

    total_keys = len([k for k in message_keys(template) if is_translatable(template[k])])
    offenders = 0
    for locale in sorted(ordered):
        allowed = allowlist.get(locale, {})
        flagged = [k for k in ordered[locale] if k not in allowed]
        if flagged:
            offenders += len(flagged)
            for key in flagged:
                print(
                    f"::error::untranslated string: app_{locale}.arb has no "
                    f"translation for {key}",
                )
            print(
                f"::error::{locale}: {len(flagged)} untranslated string(s) "
                f"({len(allowed)} knowingly allow-listed).",
            )
        else:
            done = total_keys - len(ordered[locale])
            suffix = f" ({len(allowed)} knowingly allow-listed)" if allowed else ""
            print(f"OK: {locale} {done}/{total_keys} translated{suffix}")

    if offenders or stale:
        if offenders:
            print(
                f"::error::{offenders} untranslated string(s) across "
                f"{len(ordered)} locale(s). Translate them with "
                "`arb_translate_plan` / `arb_translate_apply` (or "
                "`python3 tools/ci/arb_translate.py extract --locale <code>`).",
            )
            print(
                "::error::Do NOT paste the English value into the locale ARB to "
                "clear this. That marks the key TRANSLATED and removes it from "
                "the extractor's queue permanently, so it is never offered to a "
                "translator again — a missing key falls back to English AND "
                "stays queued, which is strictly better. If a string genuinely "
                "must ship untranslated, add it to "
                f"{_display_path(allowlist_path)} with a reason.",
            )
        return 1

    # A pass achieved by exception is not a pass achieved by coverage, and the
    # summary is the one line a reader takes away. Saying "none untranslated"
    # while strings are knowingly exempt would make this checker the same kind
    # of instrument it exists to replace: one whose green result means something
    # other than what it says. The allowlist is defensible *because* it is
    # visible, so the summary has to carry it.
    exempt = sum(len(allowlist.get(locale, {})) for locale in ordered)
    exempt_locales = sum(1 for locale in ordered if allowlist.get(locale))
    if exempt:
        print(
            f"OK: {total_keys} translatable key(s) x {len(ordered)} locale(s); "
            f"none untranslated except {exempt} string(s) allow-listed in "
            f"{exempt_locales} locale(s).",
        )
    else:
        print(
            f"OK: {total_keys} translatable key(s) x {len(ordered)} locale(s), "
            "none untranslated.",
        )
    return 0


def main(argv: list[str] | None = None) -> int:
    del argv  # No options: the paths are repo constants, like its sibling checks.
    return run(
        REPO_ROOT / DEFAULT_ARB_DIR,
        DEFAULT_TEMPLATE,
        REPO_ROOT / DEFAULT_ALLOWLIST,
    )


if __name__ == "__main__":
    sys.exit(main())
