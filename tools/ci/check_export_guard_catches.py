#!/usr/bin/env python3
"""CI ratchet: export / share / backup files must catch ``Object``, not ``Exception``.

A ``try { ... } on Exception catch (e)`` around a share sheet, a PDF layout or a
backup save/pick lets an ``Error`` (``StateError``, ``RangeError``, a platform
channel ``AssertionError``) skip the user-facing message entirely, so the button
appears to do nothing. Issue #1395 fixed this for the dance export guard
(``export_guard.dart``); this ratchet keeps the same class out of that shared
clause and every file that drives an export.

Rule: in any ``app/lib/**/*.dart`` file whose code (comments and string literals
masked) mentions ``Printing.layoutPdf``, ``SharePlus.instance.share(``,
``saveBackupToFile`` or ``pickBackupFile``, or declares ``guardExport`` (the
shared clause, which receives its export as a callback and so names none of the
tokens), an ``on Exception catch`` /
``on Exception {`` clause is rejected unless a comment inside the clause carries

    // export-guard: exempt — <reason>

The clause runs from ``on Exception`` through the end of the line holding its
closing brace, so the marker may sit on the ``on Exception`` line (after the
``{``), or anywhere in the body, or trailing the closing brace. A comment on the
line above ``on`` is outside the clause and does not count, and a marker inside
a nested ``on Exception`` clause belongs to that nested clause only.

The detectors match the *token*, not only a call: the screens take these as
injectable seams (``widget.backupSaver ?? saveBackupToFile``,
``pdfLayouter ?? Printing.layoutPdf``), so the real function is torn off rather
than called. A file that merely *calls* ``guardExport`` is not swept in by that
call: the declaration, not a use, puts ``export_guard.dart`` in scope. Dartdoc references (``[saveBackupToFile]``) live in comments and are
masked away, so they never count.

The marker's presence is checked, not its prose; the reason is a review concern.

Exit codes: 0 = clean, 1 = at least one unmarked clause, 2 = bad input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_caught_error_logged import (  # noqa: E402
    REPO_ROOT,
    SEARCH_ROOT,
    _match_brace,
    _match_paren,
    dart_app_files,
    mask_source,
)

_EXPORT_TOKEN_RE = re.compile(
    r"\bPrinting\.layoutPdf\b"
    r"|\bSharePlus\.instance\.share\s*\("
    r"|\bsaveBackupToFile\b"
    r"|\bpickBackupFile\b"
    # The declaration of the shared guard (`Future<void> guardExport(`), not a
    # call to it.
    r"|\bFuture\s*<\s*void\s*>\s+guardExport\s*\("
)
_ON_EXCEPTION_RE = re.compile(r"\bon\s+Exception\b(?=\s*(?:catch\b|\{))")
_EXEMPT_RE = re.compile(r"export-guard:\s*exempt\b")


def _clause_end(masked: str, pos: int) -> int:
    """End of the catch clause whose `on Exception` ends at [pos]: the `}` that
    closes its body, extended to the end of that line for a trailing comment."""
    n = len(masked)
    i = pos
    while i < n and masked[i] in " \t\r\n":
        i += 1
    if masked.startswith("catch", i):
        open_paren = masked.find("(", i)
        close_paren = _match_paren(masked, open_paren) if open_paren != -1 else None
        if close_paren is None:
            eol = masked.find("\n", pos)
            return eol if eol != -1 else n
        i = close_paren + 1
        while i < n and masked[i] in " \t\r\n":
            i += 1
    close = _match_brace(masked, i) if i < n and masked[i] == "{" else None
    end = close if close is not None else i
    eol = masked.find("\n", end)
    return eol if eol != -1 else n


def is_export_file(masked: str) -> bool:
    return bool(_EXPORT_TOKEN_RE.search(masked))


def _comment_spans(text: str, masked: str) -> list[tuple[int, int]]:
    """`(start, end)` offsets of every real comment in [text].

    A comment is a run the masker blanked that begins with `//` or `/*` in the
    original; a blanked run starting with a quote is a string literal, whose
    contents (even `export-guard: exempt`) must never count as a marker.
    """
    spans: list[tuple[int, int]] = []
    i = 0
    n = len(text)
    while i < n:
        if masked[i] == " " and text[i] != " " and text.startswith(("//", "/*"), i):
            if text.startswith("//", i):
                end = text.find("\n", i)
                end = n if end == -1 else end
            else:
                end = text.find("*/", i + 2)
                end = n if end == -1 else end + 2
            spans.append((i, end))
            i = end
            continue
        i += 1
    return spans


def find_offenders(text: str) -> list[tuple[int, str]]:
    """``(line_no, source_line)`` of each unmarked ``on Exception`` clause in an
    export file; empty when [text] is not an export file.

    A clause is exempt only if a real comment inside its own extent (its line
    through the end of its body) carries the marker. Strings never count, and a
    marker inside a *nested* ``on Exception`` clause belongs to that nested
    clause, not to the clause that encloses it.
    """
    masked = mask_source(text)
    if not is_export_file(masked):
        return []
    lines = text.split("\n")
    comments = [
        (a, b) for a, b in _comment_spans(text, masked) if _EXEMPT_RE.search(text[a:b])
    ]
    clauses = [
        (m.start(), _clause_end(masked, m.end()))
        for m in _ON_EXCEPTION_RE.finditer(masked)
    ]
    offenders: list[tuple[int, str]] = []
    for start, end in clauses:
        nested = [(a, b) for a, b in clauses if start < a and b <= end]
        owns_marker = any(
            start <= a
            and b <= end
            and not any(na <= a and b <= nb for na, nb in nested)
            for a, b in comments
        )
        if not owns_marker:
            line_no = masked.count("\n", 0, start) + 1
            offenders.append((line_no, lines[line_no - 1].strip()))
    return offenders


def main() -> int:
    files = dart_app_files(REPO_ROOT)
    if not files:
        print(f"::error::no Dart files found under {REPO_ROOT / SEARCH_ROOT}")
        return 2
    offenders: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if "on Exception" not in text:
            continue
        rel = path.relative_to(REPO_ROOT)
        for line_no, src in find_offenders(text):
            offenders.append(f"{rel}:{line_no}: {src}")
    if offenders:
        for offender in offenders:
            print(f"::error::export-guard catch is `on Exception`: {offender}")
        print(
            f"::error::{len(offenders)} `on Exception` clause(s) in export/share/"
            "backup files. Catch `Object` so an Error still reaches the user, or "
            "put `// export-guard: exempt — <reason>` inside the clause."
        )
        return 1
    print(
        f"OK: no unmarked `on Exception` in export/share/backup files across "
        f"{len(files)} file(s) in app/lib."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
