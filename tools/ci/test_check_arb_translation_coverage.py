#!/usr/bin/env python3
"""Offline tests for ``check_arb_translation_coverage.py`` — the untranslated-string ratchet.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_check_arb_translation_coverage.py

A ratchet is only worth having if it fails on the shape it exists to catch and
stays quiet on the shapes the repo legitimately uses, so the cases below are
split into exactly those two groups, plus a third for the allowlist's own
no-rot rules.

Every case runs against a synthetic ARB tree in a temp directory rather than the
real ``app/lib/l10n``. That is deliberate: the live baseline is asserted by the
checker itself as a CI step, and a test that also asserted it would report one
regression as two failures while making the negative cases impossible to write
(you cannot add a missing key to a tree you must not modify).
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import check_arb_translation_coverage as c  # noqa: E402

FAILURES: list[str] = []

TEMPLATE = {
    "@@locale": "en",
    "greeting": "Hello",
    "@greeting": {"description": "A greeting."},
    "farewell": "Goodbye",
    "count": "{n, plural, other{{n} items}}",
    "@count": {"placeholders": {"n": {"type": "int"}}},
}


def check(label: str, actual, expected) -> None:
    if actual != expected:
        FAILURES.append(f"{label}: expected {expected!r}, got {actual!r}")


def check_in(label: str, needle: str, haystack: str) -> None:
    if needle not in haystack:
        FAILURES.append(f"{label}: expected {needle!r} in output:\n{haystack}")


def write_tree(
    root: Path,
    locales: dict[str, dict],
    *,
    template: dict | None = None,
    allowlist: dict | None = None,
) -> tuple[Path, Path]:
    """Materialise a synthetic ARB dir plus allowlist; return (arb_dir, allowlist)."""
    arb_dir = root / "l10n"
    arb_dir.mkdir(parents=True, exist_ok=True)
    if template is not None:
        (arb_dir / "app_en.arb").write_text(
            json.dumps(template, ensure_ascii=False), encoding="utf-8"
        )
    for locale, data in locales.items():
        (arb_dir / f"app_{locale}.arb").write_text(
            json.dumps(data, ensure_ascii=False), encoding="utf-8"
        )
    allowlist_path = root / "untranslated_allowlist.json"
    if allowlist is not None:
        allowlist_path.write_text(json.dumps(allowlist, ensure_ascii=False), encoding="utf-8")
    return arb_dir, allowlist_path


def run(
    locales: dict[str, dict],
    *,
    template: dict | None = TEMPLATE,
    allowlist: dict | None = None,
) -> tuple[int, str]:
    """Run the checker over a synthetic tree; return (exit_code, stdout).

    ``SystemExit`` is caught because the bad-input path exits rather than
    returning — the test needs the code either way.
    """
    with tempfile.TemporaryDirectory() as tmp:
        arb_dir, allowlist_path = write_tree(
            Path(tmp), locales, template=template, allowlist=allowlist
        )
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                code = c.run(arb_dir, "app_en.arb", allowlist_path)
        except SystemExit as exc:
            code = int(exc.code or 0)
        return code, buf.getvalue()


def complete(locale: str) -> dict:
    return {
        "@@locale": locale,
        "greeting": f"Hello[{locale}]",
        "farewell": f"Goodbye[{locale}]",
        "count": "{n, plural, other{{n} items}}",
    }


# ---------------------------------------------------------------------------
# Clean: shapes the repo legitimately uses, which must NOT fail
# ---------------------------------------------------------------------------
def test_complete_locales_pass() -> None:
    code, out = run({"fr": complete("fr"), "de": complete("de")})
    check("complete tree exits 0", code, 0)
    check_in("complete tree reports per-locale counts", "OK: fr 3/3 translated", out)
    check_in("complete tree reports a total", "3 translatable key(s) x 2 locale(s)", out)


def test_metadata_only_keys_are_not_counted() -> None:
    """``@@locale`` and ``@key`` blocks are metadata, not translatable messages.

    If they were counted, every locale would be permanently short by however
    many ``@key`` blocks the template carries and the ratchet could never reach
    zero.
    """
    code, _ = run({"fr": complete("fr")})
    check("metadata is not counted as a message", code, 0)


def test_translation_identical_to_english_passes() -> None:
    """KNOWN LIMITATION, asserted so it is a documented property rather than a
    surprise: a locale value byte-identical to English passes.

    This is the paste-English anti-pattern the failure message warns about, and
    the checker genuinely cannot catch it. It is not a detection gap that could
    be closed by a stricter rule: 415 values in the real corpus are legitimately
    identical to their English source (``appTitle``, ``commonOk``, ``Formation``
    in Danish and German, ``September`` in three languages), so a
    identical-to-English rule would need a several-hundred-entry allowlist on
    day one — a ratchet that starts out full of exceptions.

    The mitigation is the failure annotation, which names this as the wrong fix
    and says why. See ``test_failure_message_names_the_paste_english_trap``.
    """
    pasted = dict(complete("fr"))
    pasted["greeting"] = TEMPLATE["greeting"]  # verbatim English
    code, _ = run({"fr": pasted})
    check("identical-to-English is not detected", code, 0)


# ---------------------------------------------------------------------------
# Violations: the shapes this ratchet exists to catch
# ---------------------------------------------------------------------------
def test_missing_key_fails() -> None:
    partial = complete("fr")
    del partial["farewell"]
    code, out = run({"fr": partial})
    check("a missing key fails", code, 1)
    check_in("the offender names locale and key", "app_fr.arb is missing farewell", out)


def test_blank_value_fails() -> None:
    """A whitespace-only value is the case ``arb_translate.py validate`` misses.

    ``validate`` only requires locale keys to be a SUBSET of the template, so a
    present-but-empty string satisfies it. ``extract`` treats blank as
    untranslated, and so must this.
    """
    blank = complete("fr")
    blank["farewell"] = "   "
    code, out = run({"fr": blank})
    check("a blank value fails", code, 1)
    check_in("the blank offender is named", "app_fr.arb is missing farewell", out)


def test_non_string_value_fails() -> None:
    broken = complete("fr")
    broken["farewell"] = 42
    code, _ = run({"fr": broken})
    check("a non-string value fails", code, 1)


def test_one_bad_locale_fails_the_run() -> None:
    partial = complete("de")
    del partial["greeting"]
    code, out = run({"fr": complete("fr"), "de": partial})
    check("one bad locale fails the whole run", code, 1)
    check_in("the clean locale still reports its count", "OK: fr 3/3 translated", out)
    check_in("the total counts only the offenders", "1 untranslated string(s)", out)


def test_failure_message_names_the_paste_english_trap() -> None:
    """The annotation must name the wrong fix, because that annotation is what a
    contributor reads at the moment they decide how to go green.

    This is the whole mitigation for the limitation asserted in
    ``test_translation_identical_to_english_passes``, so it is worth a test of
    its own rather than being left to survive by good intentions.
    """
    partial = complete("fr")
    del partial["farewell"]
    _, out = run({"fr": partial})
    check_in("names the wrong fix", "Do NOT paste the English value", out)
    check_in("says why it is wrong", "removes it from the extractor's queue", out)
    check_in("points at the tooling", "arb_translate_plan", out)
    check_in("points at the escape hatch", "untranslated_allowlist.json", out)


# ---------------------------------------------------------------------------
# Bad input: must never green out
# ---------------------------------------------------------------------------
def test_missing_template_is_bad_input() -> None:
    code, out = run({"fr": complete("fr")}, template=None)
    check("a missing template exits 2", code, 2)
    check_in("says what was missing", "template ARB not found", out)


def test_no_locales_is_bad_input() -> None:
    """A check that passes because it found nothing to check is worse than no
    check, because it reports success."""
    code, out = run({})
    check("an empty locale set exits 2", code, 2)
    check_in("says what was missing", "no locale ARBs found", out)


def test_malformed_allowlist_is_bad_input() -> None:
    """A typo must not be silently read as "no exceptions"."""
    code, out = run({"fr": complete("fr")}, allowlist={"fr": "not-a-map"})
    check("a malformed allowlist exits 2", code, 2)
    check_in("says what is wrong", "must map keys to reasons", out)


# ---------------------------------------------------------------------------
# The allowlist, and its no-rot rules
# ---------------------------------------------------------------------------
REASON = "Shipped untranslated on purpose, for a reason stated here."


def test_allowlisted_key_passes() -> None:
    partial = complete("fr")
    del partial["farewell"]
    code, out = run({"fr": partial}, allowlist={"fr": {"farewell": REASON}})
    check("an allowlisted key passes", code, 0)
    check_in("the exception is visible in the log", "1 knowingly allow-listed", out)


def test_allowlist_comment_keys_are_ignored() -> None:
    """The file documents itself with ``_comment`` keys; those are not locales."""
    partial = complete("fr")
    del partial["farewell"]
    code, _ = run(
        {"fr": partial},
        allowlist={"_comment": "prose", "fr": {"farewell": REASON}},
    )
    check("underscore keys are not treated as locales", code, 0)


def test_allowlist_entry_for_translated_key_fails() -> None:
    """No-rot: once the string is translated the exception must be removed."""
    code, out = run({"fr": complete("fr")}, allowlist={"fr": {"farewell": REASON}})
    check("a stale allowlist entry fails", code, 1)
    check_in("says the entry is obsolete", "is already translated", out)


def test_allowlist_entry_for_unknown_key_fails() -> None:
    """No-rot: a renamed or deleted key must not linger as an excuse."""
    partial = complete("fr")
    del partial["farewell"]
    code, out = run(
        {"fr": partial},
        allowlist={"fr": {"farewell": REASON, "ghostKey": REASON}},
    )
    check("an entry for a non-template key fails", code, 1)
    check_in("says the key is gone", "is not a key in the template", out)


def test_allowlist_entry_for_unknown_locale_fails() -> None:
    partial = complete("fr")
    del partial["farewell"]
    code, out = run(
        {"fr": partial},
        allowlist={"fr": {"farewell": REASON}, "zz": {"farewell": REASON}},
    )
    check("an entry for a non-existent locale fails", code, 1)
    check_in("says the locale is unknown", "has no app_zz.arb", out)


def test_allowlist_entry_without_a_real_reason_fails() -> None:
    """The list's whole value is the justification, so a bump without one is not
    an exception — it's a silent bump wearing an exception's clothes."""
    partial = complete("fr")
    del partial["farewell"]
    for reason in ("", "   ", "TODO", "n/a"):
        code, out = run({"fr": partial}, allowlist={"fr": {"farewell": reason}})
        check(f"reason {reason!r} is rejected", code, 1)
        check_in(f"reason {reason!r} explains itself", "needs a real reason", out)


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------
def test_locale_discovery_excludes_the_template() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        arb_dir, _ = write_tree(
            Path(tmp), {"fr": complete("fr"), "pt_BR": complete("pt_BR")}, template=TEMPLATE
        )
        found = sorted(c.locale_of(p) for p in c.locale_arb_paths(arb_dir, "app_en.arb"))
    check("discovery finds locales and skips the template", found, ["fr", "pt_BR"])


def main() -> int:
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for test in tests:
        test()
    if FAILURES:
        for failure in FAILURES:
            print(f"FAIL: {failure}")
        print(f"\n{len(FAILURES)} failure(s) across {len(tests)} test(s).")
        return 1
    print(f"OK: {len(tests)} test(s) passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
