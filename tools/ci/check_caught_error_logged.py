#!/usr/bin/env python3
"""CI ratchet: every caught, user-facing error in ``app/lib`` must reach the
on-device diagnostic log — or say explicitly why not (issue #963).

Before this, the crash log had exactly four writers: three global handlers
(``FlutterError.onError``, ``PlatformDispatcher.onError``, ``runZonedGuarded``)
plus one manual call site (the startup integrity probe). Every error a screen
*caught* and turned into a snackbar or inline error state was invisible to the
log — a beta user reporting a failed import found nothing to export, because
the failure was never logged in the first place (see the issue for the full
diagnosis).

The fix added a process-wide seam (``app/lib/src/diagnostics/error_log.dart``):
``logCaughtError`` / ``logCaughtErrorTypeOnly``. This ratchet makes "every catch
either logs or says why not" mechanical rather than a convention that erodes the
next time someone adds a `catch` block under time pressure.

Every catch clause, ``.catchError(...)`` call, and ``onError:`` callback in
``app/lib`` must contain, within its own body:

* a call to ``logCaughtError(`` or ``logCaughtErrorTypeOnly(``, or
* a comment containing the literal marker ``diagnostics: silent`` (followed by
  a reason — the marker's presence is checked, not its prose, so the *reason*
  is a code-review concern, not this ratchet's).

The baseline is **clean** as of the PR that added this ratchet: every site in
``app/lib`` was read and classified by hand. There is deliberately no allowlist
— a future unmarked catch fails the build, the same way an unguarded
``debugPrint`` does (``check_debug_print.py``, which this mirrors structurally:
brace/paren-walking over a masked copy of the source rather than line-window
matching, so a multi-line catch body or a `{`/`}` inside a string can't
mis-count).

**Known, documented gap — not silent.** This ratchet's ``catch`` and
``on Type { … }`` detection walks balanced parens/braces, so it is reliable
regardless of how a catch body is formatted. Its ``.catchError(...)`` and
``onError:`` detection instead walks to the first *unnested* comma or closing
bracket, which is the correct extent for every shape found in this codebase
(a single callback argument, braced or arrow) but is a narrower guarantee than
the lexical `catch` walk: an unusual, deeply-parenthesized call-argument
expression around a callback could in principle confuse the "first unnested
comma" boundary. If that ever proves wrong in practice, fix the walker — do not
narrow this docstring's claim to match a bug instead of fixing it.

Exit codes: 0 = every site marked, 1 = at least one unmarked site, 2 = bad input.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Production app code only. Deliberately NOT `packages/*/lib`: `compendium_core`
# is Flutter-free (ADR-001, guarded elsewhere in `_checks.yml`) and has no UI,
# so "surfaced to the user" is not a property its catches can have.
SEARCH_ROOT = "app/lib"

_CATCH_RE = re.compile(r"\bcatch\s*\(")
# A catch clause with no bound exception object at all: `on SomeType { … }`.
# Requires a generic-aware, brace-terminated type name; the caller additionally
# checks this is preceded by `}` (closing a `try`/prior `on`/`catch` block) so
# an unrelated `on` identifier elsewhere can't match.
_ON_BLOCK_RE = re.compile(r"\bon\s+[A-Za-z_][\w.]*(?:\s*<[^{;()]*?>)?\s*\{")
_CATCHERROR_RE = re.compile(r"\.catchError\s*\(")
_ONERROR_RE = re.compile(r"\bonError\s*:")

_LOG_CALL_RE = re.compile(r"\blogCaughtError\w*\s*\(")
_SILENT_RE = re.compile(r"diagnostics:\s*silent\b")

_KINDS = {
    "catch": "catch (...) { ... }",
    "on-block": "on Type { ... }  (no bound exception object)",
    "catchError": ".catchError(...)",
    "onError": "onError: ...",
}


def _fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}")
    sys.exit(code)


def dart_app_files(root: Path) -> list[Path]:
    """Every `.dart` file under `app/lib`."""
    app_lib = root / SEARCH_ROOT
    if not app_lib.is_dir():
        return []
    return sorted(app_lib.rglob("*.dart"))


def mask_source(text: str) -> str:
    """Whole-file mask: every string literal and comment blanked to spaces.

    Returns a string the same length as [text] (newlines preserved), so byte
    offsets into the mask correspond 1:1 to offsets into the original text —
    the scan below walks the mask to find structure (so a `{`/`(`/`,` inside a
    string or comment is never mistaken for real syntax) but always slices the
    *original* text when checking for `logCaughtError(` or the
    `diagnostics: silent` marker, since both legitimately live inside a
    comment (the marker always does) or a call (the log call always does) —
    exactly the constructs this function blanks out.

    Mirrors `check_debug_print.py`'s `mask_source`, collapsed to a single
    string (rather than a per-line list) because the constructs scanned here
    — catch/on/catchError/onError bodies — are frequently multi-line, so
    offset arithmetic across the whole file is more natural than a per-line
    brace-depth stack.
    """
    out: list[str] = []
    i = 0
    n = len(text)
    quote: str | None = None
    block_depth = 0
    while i < n:
        c = text[i]
        if c == "\n":
            out.append("\n")
            i += 1
            continue
        if block_depth:
            if text.startswith("/*", i):
                block_depth += 1
                out.append("  ")
                i += 2
                continue
            if text.startswith("*/", i):
                block_depth -= 1
                out.append("  ")
                i += 2
                continue
            out.append(" ")
            i += 1
            continue
        if quote:
            if c == "\\":
                chunk = text[i : i + 2]
                out.append(" " * len(chunk))
                i += len(chunk)
                continue
            if text.startswith(quote, i):
                out.append(" " * len(quote))
                i += len(quote)
                quote = None
                continue
            out.append(" ")
            i += 1
            continue
        if text.startswith("/*", i):
            block_depth = 1
            out.append("  ")
            i += 2
            continue
        if text.startswith(("'''", '"""'), i):
            quote = text[i : i + 3]
            out.append("   ")
            i += 3
            continue
        if c in "'\"":
            quote = c
            out.append(" ")
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            end = text.find("\n", i)
            if end == -1:
                end = n
            out.append(" " * (end - i))
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _match_paren(masked: str, open_idx: int) -> int | None:
    """Index of the `)` balancing the `(` at [open_idx], or `None`."""
    depth = 0
    for i in range(open_idx, len(masked)):
        c = masked[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
    return None


def _match_brace(masked: str, open_idx: int) -> int | None:
    """Index of the `}` balancing the `{` at [open_idx], or `None`."""
    depth = 0
    for i in range(open_idx, len(masked)):
        c = masked[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
    return None


def _argument_extent(masked: str, start: int) -> int:
    """End offset of a single call-argument value beginning at [start].

    Walks forward tracking bracket depth, stopping at the first `,` or closing
    bracket seen at depth 0 — the boundary of one named/positional argument in
    an argument list. Used for `onError: <value>` — [start] is just after the
    `:`. See the module docstring's "Known, documented gap" note for this
    walk's precision relative to the brace/paren-exact `catch` handling.
    """
    depth = 0
    n = len(masked)
    i = start
    while i < n:
        c = masked[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif c == "," and depth == 0:
            return i
        i += 1
    return n


def _line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _onerror_is_callback(masked: str, value_start: int) -> bool:
    """Whether the value after an `onError:` label is an inline function
    literal (`(params) { ... }` or `(params) => ...`), i.e. an actual error
    handler with a body this ratchet can check.

    `onError` is also a plain **Color** field name on Flutter's
    `ColorScheme`/palette-mapping constructors (Material's "on-error" text/icon
    colour role) — completely unrelated to error handling — and this pattern
    was found to false-positive on exactly that in
    `app/lib/src/theme/color_schemes.dart` and `palette_schemes.dart` before
    this guard was added. A `Color(...)` value or a bare tear-off/member-access
    value (`onError: e.on`, `onError: c('onError')`) is syntactically similar
    (an identifier or call) but is not a parameter-list-then-body function
    literal, so requiring the `(params) {`/`(params) =>` shape specifically
    excludes both without needing to know the value's actual type.
    """
    n = len(masked)
    j = value_start
    while j < n and masked[j] in " \t\r\n":
        j += 1
    if j >= n or masked[j] != "(":
        return False  # a bare identifier/tear-off/member access — not a literal
    close_paren = _match_paren(masked, j)
    if close_paren is None:
        return False
    k = close_paren + 1
    while k < n and masked[k] in " \t\r\n":
        k += 1
    if k < n and masked[k] == "{":
        return True  # `(params) { ... }`
    if masked[k : k + 2] == "=>":
        return True  # `(params) => ...`
    return False  # e.g. `Color(...)` — a call whose *result* is the value


def _lookforward_end(text: str, pos: int) -> int:
    """End offset for a marker search, extended forward from [pos] to the end
    of its current physical line.

    A `// diagnostics: silent — <reason>` is also written as a trailing
    same-line comment after the statement it annotates closes (e.g.
    `x.catchError((_) {}); // diagnostics: silent — best-effort.`) — a real,
    pre-existing style in this codebase, not one invented for this ratchet.
    The construct's own natural end (a matched closing paren/brace) stops
    before that trailing `;`/comment, so without this the marker is present in
    the file but outside the span being checked. Stopping at the next newline
    is safe: it can only add more of the *same* line to the search, never
    reach into a following statement.
    """
    end = text.find("\n", pos)
    return end if end != -1 else len(text)


def _has_marker(text: str, masked: str, start: int, end: int) -> bool:
    """Whether the span `[start, end)` counts as marked.

    The two markers are checked against different copies of the text
    deliberately: `logCaughtError(`/`logCaughtErrorTypeOnly(` must be a real,
    live call, so it's checked against [masked] — a commented-out call
    (`// logCaughtError(...)`) is blanked there and correctly does NOT count,
    even though it's still literally present in the original source. The
    `diagnostics: silent` marker, conversely, only ever lives inside a comment
    by convention, so it's checked against the original [text] (masking would
    blank the very comment it needs to find). Both checks additionally reach
    to the end of the line containing [end] — see [_lookforward_end].
    """
    forward_end = max(end, _lookforward_end(text, end))
    return bool(
        _LOG_CALL_RE.search(masked[start:end])
        or _SILENT_RE.search(text[start:forward_end])
    )


def _match_open_backward(masked: str, close_idx: int) -> int | None:
    """Index of the opener matching the closer `masked[close_idx]`, scanning
    backward. The counterpart to [_match_paren]/[_match_brace], which scan
    forward from a known opener; this is used when walking backward and a
    closer is met first.
    """
    close_char = masked[close_idx]
    open_char = {")": "(", "]": "[", "}": "{"}[close_char]
    depth = 0
    for i in range(close_idx, -1, -1):
        c = masked[i]
        if c == close_char:
            depth += 1
        elif c == open_char:
            depth -= 1
            if depth == 0:
                return i
    return None


def _lookback_start(masked: str, pos: int) -> int:
    """Start offset for a marker search, extended backward from [pos] over any
    comment-only text up to (but not past) the previous real statement
    boundary — a `;` or an unmatched `{` (the block [pos] itself lives in).

    A `// diagnostics: silent — <reason>` is written wherever reads best —
    inside the catch/callback body (this codebase's dominant style) or on the
    line immediately above the statement it annotates (the pre-existing style
    already used by some `.catchError` fallbacks). Both must count. Since a
    bare comment line has no statement terminator of its own, nothing but a
    real prior boundary can separate it from the construct it explains, so
    walking back to that boundary is exactly the reachable-annotation span —
    no further and no less.

    Must skip over — not stop at — a fully bracketed span that closes before
    [pos]: `result.then((_) {}, onError: ...)` has a *sibling* callback
    (`(_) {}`) immediately before `onError:` whose own closing `}` is not a
    statement boundary at all, just the end of an earlier argument in the same
    call. Stopping there (as an earlier, naive version of this function did)
    cuts off a `// diagnostics: silent` comment written several lines above
    the whole statement — exactly the shape used in
    `crash_log_store.dart`'s `_enqueue`. Every closer is therefore matched to
    its own opener and the scan resumes before that opener, so only a
    genuinely unmatched `;`/`{` — one with no corresponding opener/closer pair
    fully contained in `(boundary, pos)` — ends the walk.
    """
    i = pos - 1
    while i >= 0:
        c = masked[i]
        if c in ")]}":
            opener = _match_open_backward(masked, i)
            if opener is None:
                return 0  # unbalanced; be conservative and stop at file start
            i = opener - 1
            continue
        if c == ";" or c == "{":
            return i + 1
        i -= 1
    return 0


def find_unmarked(text: str) -> list[tuple[int, str, str]]:
    """`(line_no, kind, snippet)` for each catch/catchError/onError site in
    [text] that contains neither a `logCaughtError`/`logCaughtErrorTypeOnly`
    call nor a `diagnostics: silent` comment within its own body or on an
    immediately preceding comment-only line (see [_lookback_start]).
    """
    masked = mask_source(text)
    n = len(masked)
    findings: list[tuple[int, int, str, str]] = []  # (offset, line, kind, snippet)

    def snippet(offset: int) -> str:
        line_start = text.rfind("\n", 0, offset) + 1
        line_end = text.find("\n", offset)
        if line_end == -1:
            line_end = len(text)
        return text[line_start:line_end].strip()

    for m in _CATCH_RE.finditer(masked):
        open_paren = m.end() - 1
        close_paren = _match_paren(masked, open_paren)
        if close_paren is None:
            continue
        i = close_paren + 1
        while i < n and masked[i] in " \t\r\n":
            i += 1
        if i >= n or masked[i] != "{":
            continue  # malformed/unexpected shape; skip defensively
        close_brace = _match_brace(masked, i)
        if close_brace is None:
            continue
        marker_start = _lookback_start(masked, m.start())
        if not _has_marker(text, masked, marker_start, close_brace + 1):
            findings.append(
                (m.start(), _line_of(text, m.start()), "catch", snippet(m.start()))
            )

    for m in _ON_BLOCK_RE.finditer(masked):
        j = m.start() - 1
        while j >= 0 and masked[j] in " \t\r\n":
            j -= 1
        if j < 0 or masked[j] != "}":
            continue  # not a catch-clause chain; `on` used for something else
        brace_pos = m.end() - 1
        close_brace = _match_brace(masked, brace_pos)
        if close_brace is None:
            continue
        marker_start = _lookback_start(masked, m.start())
        if not _has_marker(text, masked, marker_start, close_brace + 1):
            findings.append(
                (m.start(), _line_of(text, m.start()), "on-block", snippet(m.start()))
            )

    for m in _CATCHERROR_RE.finditer(masked):
        open_paren = m.end() - 1
        close_paren = _match_paren(masked, open_paren)
        if close_paren is None:
            continue
        marker_start = _lookback_start(masked, m.start())
        if not _has_marker(text, masked, marker_start, close_paren + 1):
            findings.append(
                (m.start(), _line_of(text, m.start()), "catchError", snippet(m.start()))
            )

    for m in _ONERROR_RE.finditer(masked):
        start = m.end()
        if not _onerror_is_callback(masked, start):
            continue  # a Color/value field (e.g. ColorScheme.onError), not a handler
        end = _argument_extent(masked, start)
        marker_start = _lookback_start(masked, m.start())
        if not _has_marker(text, masked, marker_start, end):
            findings.append(
                (m.start(), _line_of(text, m.start()), "onError", snippet(m.start()))
            )

    findings.sort(key=lambda f: f[0])
    return [(line, kind, src) for _offset, line, kind, src in findings]


def main() -> int:
    root = REPO_ROOT
    files = dart_app_files(root)
    if not files:
        _fail(f"no Dart files found under {root / SEARCH_ROOT}")

    offenders: list[str] = []
    site_count = 0
    for path in files:
        text = path.read_text(encoding="utf-8", errors="replace")
        if not (
            "catch" in text
            or "catchError" in text
            or "onError" in text
            or " on " in text
        ):
            continue
        findings = find_unmarked(text)
        site_count += len(findings)
        rel = path.relative_to(root)
        for line_no, kind, src in findings:
            offenders.append(f"{rel}:{line_no}: [{_KINDS[kind]}] {src}")

    if offenders:
        for offender in offenders:
            print(f"::error::unmarked caught error: {offender}")
        print(
            f"::error::{len(offenders)} caught-error site(s) neither log via "
            "logCaughtError()/logCaughtErrorTypeOnly() nor carry a "
            "`// diagnostics: silent — <reason>` comment (issue #963). Every "
            "catch/catchError/onError in app/lib must do one or the other.",
        )
        return 1

    print(
        f"OK: every catch/catchError/onError site across {len(files)} file(s) "
        "in app/lib logs the caught error or is explicitly marked silent.",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
