#!/usr/bin/env python3
"""Unit tests for ``arb_translate.py``.

Pure-stdlib, assert-based (no pytest / no third-party deps), matching the
free/offline tooling constraint of the other ``tools/`` tests. Run directly::

    python3 tools/ci/test_arb_translate.py

Exits non-zero on the first failed assertion (prints a traceback), or prints an
"OK" summary when every case passes.
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import arb_translate as a  # noqa: E402


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def _run(argv: list[str]) -> tuple[int, str]:
    """Invoke the CLI, capturing stdout; return (exit_code, stdout)."""
    buf = io.StringIO()
    with redirect_stdout(buf):
        code = a.main(argv)
    return code, buf.getvalue()


def _write(path: Path, obj: dict) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", "utf-8")


def _template() -> dict:
    return {
        "@@locale": "en",
        "appTitle": "Caller's Compendium",
        "@appTitle": {"description": "The app name."},
        "greeting": "Hello",
        "@greeting": {"description": "A greeting."},
        "search": "Search ({hint})",
        "@search": {
            "description": "Search tooltip.",
            "placeholders": {"hint": {"type": "String", "example": "Ctrl K"}},
        },
        "danceCount": "{count, plural, =1{1 dance} other{{count} dances}}",
        "@danceCount": {
            "description": "How many dances.",
            "placeholders": {"count": {"type": "int"}},
        },
    }


def _expect_raises(fn, exc) -> None:
    try:
        fn()
    except exc:
        return
    raise AssertionError(f"expected {exc.__name__} to be raised")


# ---------------------------------------------------------------------------
# ICU parser
# ---------------------------------------------------------------------------
def _icu_cases() -> None:
    assert a.parse_icu("Hello") == {}
    assert a.parse_icu("Search ({hint})") == {"hint": "simple"}
    assert a.parse_icu("{appName} · Version {version} · {license}") == {
        "appName": "simple",
        "version": "simple",
        "license": "simple",
    }
    # ICU plural: the selector is the only top-level argument; the `#`/nested
    # `{count}` are the same argument.
    assert a.parse_icu("{count, plural, =1{1 dance} other{{count} dances}}") == {
        "count": "plural"
    }
    # A placeholder that appears only inside one branch is still collected.
    assert a.parse_icu(
        "{count, plural, =1{Set on {name}} other{Set {count} on {name}}}"
    ) == {"count": "plural", "name": "simple"}
    # ICU apostrophe rules: a lone apostrophe (You're) is a literal, not a quote.
    assert a.parse_icu("You're on version {version}.") == {"version": "simple"}
    # Quoted literal braces are NOT placeholders.
    assert a.parse_icu("literal '{' not a placeholder {real}") == {"real": "simple"}
    # select (forward-compatible; not yet used in the app).
    assert a.parse_icu("{g, select, male{he} female{she} other{they}}") == {
        "g": "select"
    }
    # Formatted argument (number/date): collected as a simple argument.
    assert a.parse_icu("{n, number} items on {d, date, short}") == {
        "n": "simple",
        "d": "simple",
    }

    # Malformed messages raise.
    _expect_raises(lambda: a.parse_icu("unbalanced }"), a.IcuError)
    _expect_raises(lambda: a.parse_icu("{1bad}"), a.IcuError)
    _expect_raises(lambda: a.parse_icu("{count, plural, =1{one}}"), a.IcuError)  # no other
    _expect_raises(
        lambda: a.parse_icu("{count, plural, bogus{x} other{y}}"), a.IcuError
    )
    _expect_raises(lambda: a.parse_icu("{unterminated"), a.IcuError)


# ---------------------------------------------------------------------------
# parity
# ---------------------------------------------------------------------------
def _parity_cases() -> None:
    assert a._parity({"a": "simple"}, {"a": "simple"}) == []
    # Plural selector preserved; different plural CATEGORIES are fine (parity
    # compares argument names/kinds, not branch keywords).
    t = a.parse_icu("{count, plural, =1{1 dance} other{{count} dances}}")
    v = a.parse_icu(
        "{count, plural, one{{count} danse} few{{count} danses} other{{count} danses}}"
    )
    assert a._parity(t, v) == []
    # Dropped placeholder.
    assert a._parity({"a": "simple", "b": "simple"}, {"a": "simple"}) == [
        "drops placeholder(s): b"
    ]
    # Added (unknown) placeholder — an injection vector.
    assert a._parity({"a": "simple"}, {"a": "simple", "evil": "simple"}) == [
        "adds unknown placeholder(s): evil"
    ]
    # Kind change (plural -> simple loses count formatting).
    assert a._parity({"count": "plural"}, {"count": "simple"}) == [
        "placeholder 'count' changed kind (plural -> simple)"
    ]


# ---------------------------------------------------------------------------
# content-safety scan
# ---------------------------------------------------------------------------
def _scan_cases() -> None:
    assert a.scan_value("Bonjour le monde") == []
    assert a.scan_value("line1\nline2\twith tab") == []  # whitespace allowed
    sev = [s for s, _ in a.scan_value("safe\u202eevil")]
    assert "error" in sev  # bidi override
    assert any(s == "error" for s, _ in a.scan_value("null\x00byte"))  # control
    assert any(s == "error" for s, _ in a.scan_value("nonchar\uFFFEhere"))
    assert any(s == "error" for s, _ in a.scan_value("tap javascript:alert(1)"))
    assert any(s == "error" for s, _ in a.scan_value("go DATA : text/html,x"))
    warn = a.scan_value("Click <b>here</b>")
    assert warn and all(s == "warning" for s, _ in warn)  # html is warn-only


# ---------------------------------------------------------------------------
# model helpers
# ---------------------------------------------------------------------------
def _model_cases() -> None:
    t = _template()
    assert a.message_keys(t) == ["appTitle", "greeting", "search", "danceCount"]
    assert a.is_translatable("x") and not a.is_translatable(3)
    assert a.declared_placeholders(t, "search") == {
        "hint": {"type": "String", "example": "Ctrl K"}
    }
    assert a.declared_placeholders(t, "greeting") == {}

    glossary = {
        "doNotTranslate": ["ContraDB"],
        "terms": {"caller": {"note": "dance leader"}, "set": {"note": "formation"}},
    }
    hits = a.glossary_hints("The caller prompts the set.", glossary)
    terms = {h["term"] for h in hits}
    assert terms == {"caller", "set"}
    # Word-boundary: a substring match must NOT fire.
    assert a.glossary_hints("miscallers everywhere", glossary) == []


# ---------------------------------------------------------------------------
# extract
# ---------------------------------------------------------------------------
def _extract_cases() -> None:
    with tempfile.TemporaryDirectory() as d:
        arb = Path(d)
        _write(arb / "app_en.arb", _template())
        # A partial French file: greeting translated, danceCount present-but-blank.
        _write(
            arb / "app_fr.arb",
            {"@@locale": "fr", "greeting": "Bonjour", "danceCount": "   "},
        )
        gloss = arb / "glossary.json"
        _write(gloss, {"doNotTranslate": ["ContraDB"], "terms": {}})

        code, out = _run(
            ["--arb-dir", str(arb), "extract", "--locale", "fr", "--glossary", str(gloss)]
        )
        assert code == 0, out
        payload = json.loads(out)
        keys = [it["key"] for it in payload["items"]]
        # appTitle (missing), search (missing), danceCount (blank) need work;
        # greeting is already translated so it is excluded.
        assert "greeting" not in keys
        assert set(keys) == {"appTitle", "search", "danceCount"}
        assert payload["count"] == 3
        assert payload["doNotTranslate"] == ["ContraDB"]
        # Placeholders are surfaced for the model.
        search_item = next(it for it in payload["items"] if it["key"] == "search")
        assert "hint" in search_item["placeholders"]

        # --limit caps the batch.
        code, out = _run(
            ["--arb-dir", str(arb), "extract", "--locale", "fr",
             "--glossary", str(gloss), "--limit", "1"]
        )
        assert json.loads(out)["count"] == 1


# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
def _apply_cases() -> None:
    with tempfile.TemporaryDirectory() as d:
        arb = Path(d)
        _write(arb / "app_en.arb", _template())
        batch = arb / "batch.json"
        _write(
            batch,
            {
                "greeting": "Bonjour",
                "search": "Rechercher ({hint})",
                "appTitle": "Caller's Compendium",
                "danceCount": "{count, plural, one{{count} danse} other{{count} danses}}",
            },
        )
        code, out = _run(
            ["--arb-dir", str(arb), "apply", "--locale", "fr", "--input", str(batch)]
        )
        assert code == 0, out
        result = json.loads((arb / "app_fr.arb").read_text("utf-8"))
        assert result["@@locale"] == "fr"
        assert result["greeting"] == "Bonjour"
        # Values only: no @key metadata is invented into the translation file.
        assert "@greeting" not in result
        # Deterministic template key order, @@locale first.
        assert list(result.keys())[0] == "@@locale"
        assert a.message_keys(result) == ["appTitle", "greeting", "search", "danceCount"]

        # Unknown keys are refused (drift/tampering guard).
        bad = arb / "bad.json"
        _write(bad, {"greeting": "x", "notAKey": "y"})
        code, _ = _run(
            ["--arb-dir", str(arb), "apply", "--locale", "fr", "--input", str(bad)]
        )
        assert code == 1

        # Non-string values are refused.
        badv = arb / "badv.json"
        _write(badv, {"greeting": 123})
        code, _ = _run(
            ["--arb-dir", str(arb), "apply", "--locale", "fr", "--input", str(badv)]
        )
        assert code == 1

        # The {"items": [...]} echo form is accepted.
        items = arb / "items.json"
        _write(items, {"items": [{"key": "greeting", "translation": "Salut"}]})
        code, _ = _run(
            ["--arb-dir", str(arb), "apply", "--locale", "es", "--input", str(items)]
        )
        assert code == 0
        assert json.loads((arb / "app_es.arb").read_text("utf-8"))["greeting"] == "Salut"

        # Pre-existing @key metadata (human copy-the-template file) is preserved.
        _write(
            arb / "app_de.arb",
            {"@@locale": "de", "greeting": "Hallo", "@greeting": {"description": "keep"}},
        )
        keep = arb / "keep.json"
        _write(keep, {"appTitle": "Caller's Compendium"})
        code, _ = _run(
            ["--arb-dir", str(arb), "apply", "--locale", "de", "--input", str(keep)]
        )
        assert code == 0
        de = json.loads((arb / "app_de.arb").read_text("utf-8"))
        assert de["@greeting"] == {"description": "keep"}


# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------
def _validate_cases() -> None:
    with tempfile.TemporaryDirectory() as d:
        arb = Path(d)
        _write(arb / "app_en.arb", _template())

        # A fully valid translation (different plural categories allowed).
        _write(
            arb / "app_fr.arb",
            {
                "@@locale": "fr",
                "appTitle": "Caller's Compendium",
                "greeting": "Bonjour",
                "search": "Rechercher ({hint})",
                "danceCount": "{count, plural, one{{count} danse} other{{count} danses}}",
            },
        )
        code, out = _run(["--arb-dir", str(arb), "validate", "--locale", "fr"])
        assert code == 0, out
        assert "OK" in out

        def _one_locale(name: str, obj: dict) -> tuple[int, str]:
            _write(arb / f"app_{name}.arb", obj)
            return _run(["--arb-dir", str(arb), "validate", "--locale", name])

        base = {
            "@@locale": "xx",
            "greeting": "Hi",
            "search": "S ({hint})",
            "danceCount": "{count, plural, other{{count} d}}",
        }

        # @@locale mismatch with the filename.
        code, out = _one_locale("de", {**base, "@@locale": "fr"})
        assert code == 1 and "@@locale" in out

        # Unknown key not in the template.
        code, out = _one_locale("de", {**base, "@@locale": "de", "ghost": "x"})
        assert code == 1 and "ghost" in out

        # Dropped placeholder (parity).
        code, out = _one_locale("de", {**base, "@@locale": "de", "search": "Suche"})
        assert code == 1 and "drops placeholder" in out

        # Added (unknown) placeholder.
        code, out = _one_locale(
            "de", {**base, "@@locale": "de", "greeting": "Hi {evil}"}
        )
        assert code == 1 and "adds unknown placeholder" in out

        # Invalid ICU in the translation.
        code, out = _one_locale(
            "de", {**base, "@@locale": "de", "danceCount": "{count, plural, one{x}}"}
        )
        assert code == 1 and "ICU" in out

        # Metadata tampering (a @key block that differs from the template).
        code, out = _one_locale(
            "de", {**base, "@@locale": "de", "@greeting": {"description": "changed"}}
        )
        assert code == 1 and "metadata" in out

        # Content safety: a bidi-override control is a hard error.
        code, out = _one_locale(
            "de", {**base, "@@locale": "de", "greeting": "Hi\u202eevil"}
        )
        assert code == 1 and "bidirectional" in out

        # NFC normalization is a warning, not an error (still exits 0).
        decomposed = "e\u0301"  # 'é' as e + combining acute
        code, out = _one_locale(
            "de", {**base, "@@locale": "de", "greeting": decomposed}
        )
        assert code == 0 and "NFC" in out

    # A broken template fails validate even with no locales present.
    with tempfile.TemporaryDirectory() as d:
        arb = Path(d)
        _write(
            arb / "app_en.arb",
            {"@@locale": "en", "broken": "{count, plural, one{x}}"},
        )
        code, out = _run(["--arb-dir", str(arb), "validate", "--all"])
        assert code == 1 and "template" in out


# ---------------------------------------------------------------------------
# The real repository ARB must always be self-consistent.
# ---------------------------------------------------------------------------
def _real_template_cases() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    template = repo_root / "app" / "lib" / "l10n" / "app_en.arb"
    if not template.exists():
        return  # tolerate running outside the repo layout
    data = a.load_arb(template)
    for key in a.message_keys(data):
        if a.is_translatable(data[key]):
            a.parse_icu(data[key])  # must not raise
    # The bundled glossary parses and has the expected shape.
    gloss = a.load_glossary(repo_root / "tools" / "ci" / "i18n_glossary.json")
    assert isinstance(gloss["doNotTranslate"], list)
    assert "caller" in gloss["terms"]


def main() -> int:
    _icu_cases()
    _parity_cases()
    _scan_cases()
    _model_cases()
    _extract_cases()
    _apply_cases()
    _validate_cases()
    _real_template_cases()
    print("OK: all arb_translate tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
