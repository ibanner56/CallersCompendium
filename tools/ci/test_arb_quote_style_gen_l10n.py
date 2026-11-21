#!/usr/bin/env python3
"""Prove a normalised ``'`` survives the real ``flutter gen-l10n`` unchanged.

``arb_quote_style.py`` turns ``’`` into ``'``. That is only a pure character
substitution because ``app/l10n.yaml`` sets no ``use-escaping`` (so gen-l10n treats
``'`` as literal text, not the ICU quote character). This test runs the real
generator, with the app's own ``l10n.yaml``, over a throwaway project and decodes
the Dart string literals it emits, for plain strings, placeholders next to
apostrophes, quoted placeholders (``'{name}'``) and plural branches. It asserts:

1. the normalised ARB compiles through gen-l10n, and
2. what it renders equals the curly original with exactly the quote characters
   substituted -- nothing dropped, doubled or escaped away.

Needs the Flutter SDK (``fvm exec`` in CI/preflight). Skips visibly, exit 0, if
there is no ``flutter`` on PATH -- ``preflight`` only schedules it where one exists.

    python3 tools/ci/test_arb_quote_style_gen_l10n.py
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arb_quote_style as style  # noqa: E402

RSQ, LDQ, RDQ, LSQ = "’", "“", "”", "‘"

PUBSPEC = """name: probe
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any
flutter:
  generate: true
"""

# key -> (curly ICU message, placeholders). Plural bodies exercise apostrophes
# beside braces, which is where use-escaping would bite.
CASES = {
    "plain": (f"Can{RSQ}t open {LSQ}x{RSQ} – it{RSQ}s {LDQ}here{RDQ}", {}),
    "named": (f"Hi {RSQ}{{name}}{RSQ}, it{RSQ}s {{n}}", {"name": "String", "n": "int"}),
    "plural": (
        f"{{count, plural, =0{{Didn{RSQ}t find {LDQ}{{name}}{RDQ}}} other{{{{count}} won{RSQ}t {RSQ}{{name}}{RSQ}}}}}",
        {"count": "int", "name": "String"},
    ),
}


# Independent of arb_quote_style's own table, so a wrong mapping there cannot
# make this test agree with itself.
EXPECT = str.maketrans({"\u201c": '"', "\u201d": '"', "\u2018": "'", "\u2019": "'"})


def arb_for(messages: dict[str, str]) -> dict:
    arb: dict = {"@@locale": "en"}
    for key, (_, placeholders) in CASES.items():
        arb[key] = messages[key]
        if placeholders:
            arb[f"@{key}"] = {"placeholders": {p: {"type": t} for p, t in placeholders.items()}}
    return arb


def dart_literals(src: str, key: str) -> list[str]:
    """Decoded string literals inside the generated member named [key]."""
    m = re.search(rf"String (?:get {key}\b|{key}\()(.*?)(?=\n  @override|\n}})", src, re.S)
    if not m:
        raise AssertionError(f"member {key} not found in generated code")
    out = []
    for lit in re.finditer(r"'((?:[^'\\]|\\.)*)'", m.group(1), re.S):
        out.append(re.sub(r"\\(.)", lambda e: {"n": "\n"}.get(e.group(1), e.group(1)), lit.group(1)))
    return out


def generate(arb: dict, work: Path, l10n_yaml: str) -> str:
    (work / "lib/l10n").mkdir(parents=True)
    (work / "pubspec.yaml").write_text(PUBSPEC)
    (work / "l10n.yaml").write_text(l10n_yaml)
    (work / "lib/l10n/app_en.arb").write_text(style.dump_arb(arb), encoding="utf-8")
    proc = subprocess.run(
        [shutil.which("flutter") or "flutter", "gen-l10n"], cwd=work, capture_output=True, text=True
    )
    if proc.returncode:
        raise AssertionError(f"gen-l10n failed:\n{proc.stdout}\n{proc.stderr}")
    return (work / "lib/l10n/app_localizations_en.dart").read_text(encoding="utf-8")


def main() -> int:
    if not shutil.which("flutter"):
        if os.environ.get("ARB_QUOTE_REQUIRE_FLUTTER"):
            print("FAIL: no flutter on PATH but ARB_QUOTE_REQUIRE_FLUTTER is set.")
            return 1
        print("SKIP: no flutter on PATH; this test needs gen-l10n.")
        return 0
    l10n_yaml = (style.REPO_ROOT / style.L10N_YAML).read_text(encoding="utf-8")
    style.check_use_escaping(l10n_yaml)  # the premise of the whole test
    curly = {k: v for k, (v, _) in CASES.items()}
    straight = {k: style.normalize_value(v) for k, v in curly.items()}
    failures = []
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        src_curly = generate(arb_for(curly), Path(a), l10n_yaml)
        src_straight = generate(arb_for(straight), Path(b), l10n_yaml)
    for key in CASES:
        want_curly = [s.translate(EXPECT) for s in dart_literals(src_curly, key)]
        got = dart_literals(src_straight, key)
        ok = got == want_curly and "'" in "".join(got)
        print(f"  {'ok  ' if ok else 'FAIL'} {key}: rendered text == curly original, straightened")
        if not ok:
            failures.append(f"{key}: got {got!r}, want {want_curly!r}")
    # Counter-proof the decoder sees the apostrophes: `'x'` must survive literally.
    named = dart_literals(src_straight, "named")
    if not any("'$" in s and "name" in s for s in named):
        failures.append(f"quoted placeholder lost its apostrophes: {named!r}")
    if failures:
        print("\n".join(f"  - {f}" for f in failures))
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
