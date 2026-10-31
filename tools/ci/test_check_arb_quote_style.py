#!/usr/bin/env python3
"""Offline tests for ``arb_quote_style.py`` (normaliser) and
``check_arb_quote_style.py`` (ratchet). Run directly::

    python3 tools/ci/test_check_arb_quote_style.py

Pure stdlib, assert-based. Each case builds a throwaway tree.
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arb_quote_style as style  # noqa: E402
import check_arb_quote_style as chk  # noqa: E402

FAILURES: list[str] = []

LDQ, RDQ, LSQ, RSQ = "“", "”", "‘", "’"


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if not ok:
        FAILURES.append(f"{name}: {detail}" if detail else name)


def tree(root: Path, arb: dict, allow: dict | None = None, l10n: str = "arb-dir: lib/l10n\n") -> None:
    (root / "app/lib/l10n").mkdir(parents=True)
    (root / "app/lib/l10n/app_en.arb").write_text(style.dump_arb(arb), encoding="utf-8")
    (root / "app/l10n.yaml").write_text(l10n, encoding="utf-8")
    (root / "tools/ci").mkdir(parents=True)
    if allow is not None:
        (root / "tools/ci/arb_quote_allowlist.json").write_text(json.dumps(allow), encoding="utf-8")


def quiet(fn, *a):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = fn(*a)
    return rc, out.getvalue() + err.getvalue()


def base_arb(**extra: str) -> dict:
    arb: dict = {"@@locale": "en", "plain": "Fine text"}
    arb.update(extra)
    return arb


def read_arb(root: Path) -> str:
    return (root / "app/lib/l10n/app_en.arb").read_text(encoding="utf-8")


def test_normalize_value() -> None:
    got = style.normalize_value(f"{LDQ}Hi{RDQ} it{RSQ}s {LSQ}x{RSQ}")
    check("curly -> straight, all four marks", got == "\"Hi\" it's 'x'", got)
    check("idempotent", style.normalize_value(got) == got)
    check("other characters untouched", style.normalize_value("a – b « c » „") == "a – b « c » „")
    check("a curly char is not left behind", not style.has_curly(got))


def test_normaliser_rewrites_values_only() -> None:
    arb = base_arb(
        greet=f"Caller{RSQ}s {LDQ}{{name}}{RDQ}",
        **{f"key{RSQ}s": "keys are never touched"},
    )
    arb["@@author"] = f"O{RSQ}Neil"  # a string-valued global: still not a message
    arb["@greet"] = {"description": f"A {LDQ}description{RDQ}", "placeholders": {"name": {"type": "String"}}}
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, arb)
        rc, _ = quiet(style.run, root, False)
        out = json.loads(read_arb(root))
        check("exit 0", rc == 0)
        check("value normalised", out["greet"] == "Caller's \"{name}\"", out["greet"])
        check("key with a curly char is not renamed", f"key{RSQ}s" in out)
        check("@ metadata left alone", out["@greet"]["description"] == f"A {LDQ}description{RDQ}")
        check("string-valued @@ global left alone", out["@@author"] == f"O{RSQ}Neil", out["@@author"])
        check("key order preserved", list(out) == list(arb))
        before = read_arb(root)
        rc, msg = quiet(style.run, root, False)
        check("second run is a no-op (idempotent)", read_arb(root) == before and "normalised 0" in msg, msg)


def test_normaliser_check_mode() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(a=f"it{RSQ}s"))
        before = read_arb(root)
        rc, msg = quiet(style.run, root, True)
        check("--check exits 1 on curly", rc == 1 and "a" in msg, msg)
        check("--check does not write", read_arb(root) == before)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(a="it's"))
        check("--check exits 0 when straight", quiet(style.run, root, True)[0] == 0)


def test_literal_exemption_is_never_rewritten() -> None:
    arb = base_arb(typed=f"Type {LDQ}x{RDQ} exactly", other=f"{LDQ}y{RDQ}")
    allow = {"violations": {}, "literal": {"typed": "the curly pair is the syntax the user types"}}
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, arb, allow)
        quiet(style.run, root, False)
        out = json.loads(read_arb(root))
        check("exempt string keeps its curly quotes", out["typed"] == f"Type {LDQ}x{RDQ} exactly", out["typed"])
        check("non-exempt string is normalised", out["other"] == '"y"')
        rc, msg = quiet(chk.run, root, False)
        check("ratchet does not flag the exempt string", rc == 0, msg)


def test_refusals() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        arb = base_arb(a=f"it{RSQ}s")
        arb["@@locale"] = "de"
        tree(root, arb)
        before = read_arb(root)
        rc, msg = quiet(style.run, root, False)
        check("a non-English ARB is refused (exit 2) and untouched", rc == 2 and read_arb(root) == before, msg)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(a=f"it{RSQ}s"), l10n="use-escaping: true\n")
        before = read_arb(root)
        rc, msg = quiet(style.run, root, False)
        check("use-escaping: true is refused", rc == 2 and read_arb(root) == before and "use-escaping" in msg, msg)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb())
        (root / "app/lib/l10n/app_en.arb").write_text('{"@@locale":"en","a":"x"}', encoding="utf-8")
        rc, msg = quiet(style.run, root, False)
        check("a non-canonical file is refused rather than reformatted", rc == 2 and "round-trip" in msg, msg)


def test_ratchet_flags_new_and_changed() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(), {"violations": {}, "literal": {}})
        check("clean tree passes", quiet(chk.run, root, False)[0] == 0)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(fresh=f"it{RSQ}s"), {"violations": {}, "literal": {}})
        rc, msg = quiet(chk.run, root, False)
        check("a new curly string fails", rc == 1 and "fresh (new)" in msg and "arb_quote_style.py" in msg, msg)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        old = f"it{RSQ}s"
        tree(root, base_arb(old=old + " more"), {"violations": {"old": chk.digest(old)}, "literal": {}})
        rc, msg = quiet(chk.run, root, False)
        check("an allow-listed string that is edited fails as changed", rc == 1 and "old (changed)" in msg, msg)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        v = f"it{RSQ}s"
        tree(root, base_arb(old=v), {"violations": {"old": chk.digest(v)}, "literal": {}})
        check("an unchanged allow-listed string passes", quiet(chk.run, root, False)[0] == 0)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(a=f"{LSQ}x{RSQ}", b=f"{LDQ}y{RDQ}"), {"violations": {}, "literal": {}})
        rc, msg = quiet(chk.run, root, False)
        check("single and double curly marks each fail", rc == 1 and "a (new)" in msg and "b (new)" in msg, msg)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        arb = base_arb()
        arb["@d"] = {"description": f"dev note {RSQ}s"}
        tree(root, arb, {"violations": {}, "literal": {}})
        check("curly quotes in @ metadata are not flagged", quiet(chk.run, root, False)[0] == 0)


def test_ratchet_stale_entries_fail() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(fixed="it's"), {"violations": {"fixed": "0" * 16, "gone": "1" * 16}, "literal": {}})
        rc, msg = quiet(chk.run, root, False)
        check("fixed and removed keys are stale", rc == 1 and "fixed: already straight" in msg and "gone: no longer" in msg, msg)


def test_regenerate_round_trip() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(a=f"it{RSQ}s", b="fine"), {"violations": {}, "literal": {}})
        check("fails before regenerate", quiet(chk.run, root, False)[0] == 1)
        rc, _ = quiet(chk.run, root, True)
        doc = json.loads((root / "tools/ci/arb_quote_allowlist.json").read_text())
        check("regenerate lists only violating keys", rc == 0 and list(doc["violations"]) == ["a"], str(doc))
        check("passes after regenerate", quiet(chk.run, root, False)[0] == 0)
        quiet(style.run, root, False)
        rc, msg = quiet(chk.run, root, False)
        check("normalising afterwards makes the entry stale, then regenerate empties it", rc == 1 and "already straight" in msg, msg)
        quiet(chk.run, root, True)
        doc = json.loads((root / "tools/ci/arb_quote_allowlist.json").read_text())
        check("allow-list shrinks to empty", doc["violations"] == {}, str(doc))


def test_allowlist_validation() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb(), {"violations": {}, "literal": {"x": "todo"}})
        check("a throwaway literal reason is bad input", quiet(chk.run, root, False)[0] == 2)
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        tree(root, base_arb())
        (root / "tools/ci/arb_quote_allowlist.json").write_text("{not json", encoding="utf-8")
        check("a malformed allow-list is bad input, not empty", quiet(chk.run, root, False)[0] == 2)


def main() -> int:
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            print(name)
            fn()
    if FAILURES:
        print(f"\n{len(FAILURES)} FAILED:")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
