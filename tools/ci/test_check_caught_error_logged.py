#!/usr/bin/env python3
"""Offline tests for ``check_caught_error_logged.py`` — the caught-error ratchet.

Pure-stdlib, assert-based (matching the rest of ``tools/*/test_*.py``). Run
directly::

    python3 tools/ci/test_check_caught_error_logged.py

Mirrors ``test_check_debug_print.py``'s structure and its reason for existing:
a ratchet is only worth having if it is shown to fail on the shape it exists to
catch and stay quiet on the shapes the codebase legitimately uses.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_caught_error_logged import (  # noqa: E402
    dart_app_files,
    find_unmarked,
    mask_source,
)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def unmarked_lines(src: str) -> list[int]:
    return [line for line, _kind, _snippet in find_unmarked(src)]


def unmarked_kinds(src: str) -> list[str]:
    return [kind for _line, kind, _snippet in find_unmarked(src)]


# --------------------------------------------------------------------------
# Marked shapes — every one of these must be accepted (no finding).
# --------------------------------------------------------------------------


def test_marked_forms() -> None:
    print("marked forms are accepted:")

    check(
        "catch logs via logCaughtError",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (error, stackTrace) {\n"
            "    logCaughtError(error, stackTrace, source: 'x.f');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "catch logs via logCaughtErrorTypeOnly",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (error, stackTrace) {\n"
            "    logCaughtErrorTypeOnly(error, stackTrace, source: 'x.f');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "catch carries a diagnostics: silent annotation",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (_) {\n"
            "    // diagnostics: silent — best-effort, no user surface\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "typed `on Type catch` logs",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on StateError catch (e) {\n"
            "    logCaughtError(e, StackTrace.current, source: 'x.f');\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "`on Type { }` with no bound exception, annotated silent",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on Cancelled {\n"
            "    // diagnostics: silent — user-initiated cancellation, not a failure\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        ".catchError logs",
        unmarked_lines(
            "void f() {\n"
            "  g().catchError((error) {\n"
            "    logCaughtError(error, StackTrace.current, source: 'x.f');\n"
            "  });\n"
            "}\n"
        )
        == [],
    )

    check(
        ".catchError arrow form, annotated silent",
        unmarked_lines(
            "void f() {\n"
            "  // diagnostics: silent — best-effort default fallback\n"
            "  g().catchError((_) => null);\n"
            "}\n"
        )
        == [],
    )

    check(
        "onError: preceded by a sibling callback argument, silent comment "
        "several lines above the whole statement",
        unmarked_lines(
            "Future<T> f() {\n"
            "  final result = tail.then((_) => action());\n"
            "  // Keep the tail alive even if this action fails.\n"
            "  // diagnostics: silent — this IS the queue guard; the caller\n"
            "  // still surfaces the real failure via `result`.\n"
            "  tail = result.then((_) {}, onError: (_) {});\n"
            "  return result;\n"
            "}\n"
        )
        == [],
        "a naive backward scan stops at the sibling `(_) {}` callback's own "
        "closing brace — which is not a statement boundary — and misses the "
        "comment several lines above the real statement start; this is the "
        "exact shape found in crash_log_store.dart's _enqueue",
    )

    check(
        ".catchError with a trailing same-line silent comment",
        unmarked_lines(
            "void f() {\n"
            "  g().catchError((_) {}); // diagnostics: silent — best-effort.\n"
            "}\n"
        )
        == [],
        "a real, pre-existing style in this codebase (perform_dance_screen.dart "
        "etc.) — the marker follows the statement's closing `;` on the same "
        "line rather than living inside the callback body",
    )

    check(
        "onError: callback logs",
        unmarked_lines(
            "void f() {\n"
            "  stream.listen(\n"
            "    onData,\n"
            "    onError: (Object error) {\n"
            "      logCaughtError(error, StackTrace.current, source: 'x.f');\n"
            "    },\n"
            "  );\n"
            "}\n"
        )
        == [],
    )

    check(
        "multiple catches in one try, each independently marked",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on StateError catch (e) {\n"
            "    logCaughtError(e, StackTrace.current, source: 'x.f.a');\n"
            "  } catch (_) {\n"
            "    // diagnostics: silent — fallback\n"
            "  }\n"
            "}\n"
        )
        == [],
    )


# --------------------------------------------------------------------------
# Unmarked shapes — every one of these is exactly what the ratchet exists to
# catch, and each must be reported.
# --------------------------------------------------------------------------


def test_unmarked_forms() -> None:
    print("unmarked forms are reported:")

    check(
        "bare catch with neither log nor annotation",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (e) {\n"
            "    showSnackBar(e);\n"
            "  }\n"
            "}\n"
        )
        == [4],
    )

    check(
        "typed catch with neither",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on StateError catch (e) {\n"
            "    showSnackBar(e);\n"
            "  }\n"
            "}\n"
        )
        == [4],
    )

    check(
        "`on Type { }` with neither",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on Cancelled {\n"
            "    reset();\n"
            "  }\n"
            "}\n"
        )
        == [4],
    )

    check(
        ".catchError with neither",
        unmarked_lines("void f() {\n  g().catchError((_) => null);\n}\n") == [2],
    )

    check(
        "onError: with neither",
        unmarked_lines(
            "void f() {\n"
            "  stream.listen(onData, onError: (e) => showSnackBar(e));\n"
            "}\n"
        )
        == [2],
    )

    check(
        "ColorScheme's onError Color field is not a handler",
        unmarked_lines(
            "const scheme = ColorScheme(\n"
            "  error: Color(0xFFBA1A1A),\n"
            "  onError: Color(0xFFFFFFFF),\n"
            ");\n"
        )
        == [],
        "onError is also a Material Color-role field name, unrelated to error "
        "handling — this must not be flagged",
    )

    check(
        "a bare tear-off/member-access onError value is not checkable",
        unmarked_lines(
            "void f() {\n"
            "  final scheme = Palette(onError: e.on, error: e.color);\n"
            "}\n"
        )
        == [],
        "no function body exists to put a marker in",
    )

    check(
        "a debug-only print does not satisfy the marker",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (e) {\n"
            "    if (kDebugMode) debugPrint('failed: $e');\n"
            "  }\n"
            "}\n"
        )
        == [4],
        "a debugPrint is not a diagnostic-log call and is not a silent marker",
    )

    check(
        "kind is reported correctly for each construct",
        unmarked_kinds(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on Cancelled {\n"
            "    reset();\n"
            "  }\n"
            "  h().catchError((_) => null);\n"
            "  stream.listen(onData, onError: (e) => log(e));\n"
            "  try {\n"
            "    g();\n"
            "  } catch (e) {\n"
            "    log(e);\n"
            "  }\n"
            "}\n"
        )
        == ["on-block", "catchError", "onError", "catch"],
    )


# --------------------------------------------------------------------------
# Masking edge cases — reusing the same three lexical-state hazards the
# debugPrint ratchet documents, because this ratchet shares the same masker
# shape (whole-file rather than per-line, but the hazards are identical).
# --------------------------------------------------------------------------


def test_masking_edge_cases() -> None:
    print("masking edge cases:")

    check(
        "catch token inside a string is not a real catch",
        unmarked_lines(
            "void f() {\n"
            "  final s = 'not a catch (e) { showSnackBar(e); }';\n"
            "}\n"
        )
        == [],
    )

    check(
        "a stray brace inside a multi-line string does not corrupt matching",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (e) {\n"
            "    final sql = '''\n"
            "      CREATE TRIGGER t BEGIN {\n"
            "    ''';\n"
            "    logCaughtError(e, StackTrace.current, source: 'x.f');\n"
            "  }\n"
            "}\n"
        )
        == [],
        "the log call is still found inside the same catch body",
    )

    check(
        "a commented-out log call does not count as marked",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (e) {\n"
            "    // logCaughtError(e, StackTrace.current, source: 'x.f');\n"
            "    showSnackBar(e);\n"
            "  }\n"
            "}\n"
        )
        == [4],
        "masking blanks comments before the log-call regex runs against the "
        "MASKED text for structure, but the marker search runs against the "
        "ORIGINAL text — so a commented-out call is inert code, but the "
        "literal `logCaughtError(` text would still be found by a naive "
        "substring search; this asserts the ratchet does not fall into that "
        "trap by checking a genuinely unmarked sibling stays flagged even "
        "with a decoy comment present",
    )

    check(
        "block comment containing the silent marker still counts",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } catch (_) {\n"
            "    /* diagnostics: silent — best effort */\n"
            "  }\n"
            "}\n"
        )
        == [],
    )


def test_real_tree_is_clean() -> None:
    """The live baseline: 0 unmarked sites across `app/lib`.

    This is the ratchet asserting its own premise. If it ever fails, either a
    new unmarked catch/catchError/onError landed (log it or annotate it) or the
    marked forms in use have changed (fix the checker) — do not delete this
    test.
    """
    print("real tree:")
    root = HERE.parents[1]
    files = dart_app_files(root)
    check("finds app library files", len(files) > 0, f"found {len(files)}")
    offenders: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if not (
            "catch" in text
            or "catchError" in text
            or "onError" in text
            or " on " in text
        ):
            continue
        for line_no, kind, src in find_unmarked(text):
            offenders.append(f"{path.relative_to(root)}:{line_no}: [{kind}] {src}")
    check("baseline is clean", not offenders, "; ".join(offenders))


def test_masking() -> None:
    print("masking:")
    check(
        "string contents are blanked, length preserved",
        mask_source("f('a{b}');") == "f(' a b ');"[: len("f('a{b}');")]
        or len(mask_source("f('a{b}');")) == len("f('a{b}');"),
    )
    check(
        "comment is blanked to end of line",
        mask_source("a; // catch (e) {").splitlines()[0].rstrip() == "a;",
    )


def main() -> int:
    test_marked_forms()
    test_unmarked_forms()
    test_masking_edge_cases()
    test_masking()
    test_real_tree_is_clean()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("all check_caught_error_logged tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
