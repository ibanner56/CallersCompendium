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
        "nested generics in `on Type<...> { }` are matched to the true closing "
        "brace, not the first `>` — a suppressed Copilot review finding on "
        "PR #970 questioned whether the non-greedy `<...>` group could stop "
        "early on nested angle brackets; it cannot, because `{` is excluded "
        "from the group's character class so only the TRUE final `>` can be "
        "followed by `\\s*\\{`, and Python backtracks the non-greedy group "
        "forward until that holds",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on Result<Map<String, List<int>>> {\n"
            "    // diagnostics: silent — nested-generic catch clause\n"
            "  }\n"
            "}\n"
        )
        == [],
    )

    check(
        "nested generics in `on Type<...> { }` are still reported when unmarked "
        "(proves the match above isn't vacuously accepting everything)",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    g();\n"
            "  } on Result<Map<String, List<int>>> {\n"
            "    handle();\n"
            "  }\n"
            "}\n"
        )
        == [4],
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
        ".onError logs",
        unmarked_lines(
            "void f() {\n"
            "  g().onError((error, stackTrace) {\n"
            "    logCaughtError(error, stackTrace, source: 'x.f');\n"
            "    return null;\n"
            "  });\n"
            "}\n"
        )
        == [],
    )

    check(
        ".handleError with a trailing same-line silent comment",
        unmarked_lines(
            "void f() {\n"
            "  stream.handleError((_) {}); // diagnostics: silent — best-effort.\n"
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

    # A marker in the try body, or in an EARLIER sibling clause, does not mark
    # a later clause: each clause is its own handler. (An earlier lookback
    # walked back over the whole try statement, so these passed unmarked.)
    check(
        "later clause is not marked by an earlier clause's log call",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    a();\n"
            "  } on Foo catch (e, st) {\n"
            "    logCaughtError(e, st);\n"
            "  } on Object catch (e) {\n"
            "    show(e);\n"
            "  }\n"
            "}\n"
        )
        == [6],
    )
    check(
        "clause is not marked by a log call in the try body",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    logCaughtError(1, 2);\n"
            "  } catch (e) {\n"
            "    show(e);\n"
            "  }\n"
            "}\n"
        )
        == [4],
    )
    check(
        "on-block is not marked by an earlier clause's annotation",
        unmarked_lines(
            "void f() {\n"
            "  try {\n"
            "    a();\n"
            "  } on Foo {\n"
            "    // diagnostics: silent — expected\n"
            "  } on Object {\n"
            "    b();\n"
            "  }\n"
            "}\n"
        )
        == [6],
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

    # `future.onError(...)` is the post-2.12 idiom that replaced
    # `.catchError(...)`, and `stream.handleError(...)` is its stream
    # counterpart. Both are exactly the honest, under-time-pressure swallow
    # the ratchet exists for, and both were invisible to it: the module
    # docstring's stated purpose ("every caught, user-facing error") was
    # broader than the four shapes it actually walked.
    check(
        ".onError with neither",
        unmarked_lines(
            "void f() {\n"
            "  g().onError((e, s) {\n"
            "    return null;\n"
            "  });\n"
            "}\n"
        )
        == [2],
    )

    check(
        ".onError<Type> with type arguments, with neither",
        unmarked_lines(
            "void f() {\n"
            "  g().onError<StateError>((e, s) => fallback);\n"
            "}\n"
        )
        == [2],
    )

    check(
        ".onError<Nested<Generic>> with neither",
        unmarked_lines(
            "void f() {\n"
            "  g().onError<Result<Map<String, int>>>((e, s) => fallback);\n"
            "}\n"
        )
        == [2],
    )

    check(
        ".handleError with neither",
        unmarked_lines("void f() {\n  stream.handleError((e) {});\n}\n") == [2],
    )

    # Documented exemptions, pinned so a later widening is a decision and not
    # an accident. `runZonedGuarded`'s handler is the global log writer itself
    # (crash_reporter.dart) -- the one site in app/lib, and the thing every
    # other marker ultimately feeds. A tear-off `onError:` has no body to hold
    # a marker (see the module docstring).
    check(
        "runZonedGuarded's handler is not a checkable site",
        unmarked_lines("void f() {\n  runZonedGuarded(body, (e, s) {});\n}\n") == [],
        "exempt by design: it is the log's own writer, not a swallow",
    )
    check(
        "an onError: tear-off has no body and stays exempt",
        unmarked_lines("void f() {\n  g().then(ok, onError: _forward);\n}\n") == [],
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

    check(
        "kind is reported correctly for the method-call shapes",
        unmarked_kinds(
            "void f() {\n"
            "  h().onError((e, s) => null);\n"
            "  s.handleError((e) {});\n"
            "}\n"
        )
        == ["onError-method", "handleError"],
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
            or "handleError" in text
            or " on " in text
        ):
            continue
        for line_no, kind, src in find_unmarked(text):
            offenders.append(f"{path.relative_to(root)}:{line_no}: [{kind}] {src}")
    check("baseline is clean", not offenders, "; ".join(offenders))


def test_masking() -> None:
    print("masking:")
    check(
        "string contents (and delimiters) are blanked, length preserved",
        mask_source("f('a{b}');") == "f(      );",
        repr(mask_source("f('a{b}');")),
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
