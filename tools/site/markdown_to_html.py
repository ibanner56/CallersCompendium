#!/usr/bin/env python3
"""Minimal, security-first Markdown → HTML renderer (pure standard library).

Used by ``tools/site/render_user_docs.py`` to pre-render ``docs/user/*.md`` into
static pages for the GitHub Pages site. It is deliberately **hand-written and
dependency-free**:

* the Pages publish job runs plain ``python3`` with no ``pip install`` step (the
  whole ``tools/`` tree is stdlib-only), and
* the published site is dependency-free by design — a page linked from a
  privacy-policy-carrying app must not pull in third-party JS, CSS, or fonts.

Scope is the Markdown the user guides actually use (see
``docs/user/style-guide.md``): ATX headings, paragraphs, emphasis, inline code,
links, images, nested ordered/unordered lists, GitHub-flavored tables,
blockquotes, fenced code blocks, and thematic breaks. It is **not** a full
CommonMark implementation and does not try to be.

Security posture — the guides are repo-owned today, but this renders as if the
Markdown were an untrusted community contribution:

* **Everything is escaped.** Text is escaped for text context, attributes for
  attribute context. There is no raw-HTML passthrough: inline HTML in the source
  renders as literal, escaped text, so a guide can never inject an element.
* **HTML comments are dropped** (outside fenced code), so they can't smuggle
  markup or hide content from review.
* **Link targets are allow-listed** by :func:`sanitize_href` — ``http``,
  ``https``, ``mailto`` and site-relative paths only. ``javascript:``, ``data:``
  and ``vbscript:`` are rejected, including the obfuscated forms browsers still
  honour (mixed case, embedded tabs/newlines/NUL and other control characters,
  and HTML-entity-encoded colons). A rejected link degrades to its plain text.
* Heading anchors come from :func:`slugify`, a port of
  ``UserGuideDocs.slugify`` in
  ``app/lib/src/screens/user_guide/user_guide_docs.dart`` — the guides
  cross-link by ``#fragment``, so the web, the app, and GitHub must agree. A
  colliding slug is *reported*, never silently renamed, because GitHub and the
  app disagree about how to break the tie (see ``RenderResult``).
"""

from __future__ import annotations

import html
import re
import unicodedata
from dataclasses import dataclass, field
from typing import Callable, Optional

# ---------------------------------------------------------------------------
# Escaping
# ---------------------------------------------------------------------------


def escape_text(value: str) -> str:
    """Escape ``value`` for an HTML *text* node (``&``, ``<``, ``>``)."""
    return html.escape(value, quote=False)


def escape_attr(value: str) -> str:
    """Escape ``value`` for an HTML *attribute* (adds ``"`` and ``'``)."""
    return html.escape(value, quote=True)


# ---------------------------------------------------------------------------
# Link sanitisation
# ---------------------------------------------------------------------------

ALLOWED_SCHEMES = frozenset({"http", "https", "mailto"})

# A URL scheme per RFC 3986: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":".
_SCHEME_RE = re.compile(r"^([a-z][a-z0-9+.\-]*):")


def _probe(href: str) -> str:
    """Normalize ``href`` the way a browser would before honouring a scheme.

    Browsers ignore leading and embedded whitespace/control characters in a URL
    and decode HTML entities in attribute values, so ``java&#9;script:`` and
    ``javascript&#58;`` both still execute. Fold all of that away before
    deciding whether a scheme is present, so the allow-list below can't be
    tunnelled through.
    """
    decoded = html.unescape(href)
    stripped = "".join(ch for ch in decoded if ord(ch) > 0x20 and ord(ch) != 0x7F)
    return stripped.lower()


def sanitize_href(href: str) -> Optional[str]:
    """Return a safe href for ``href``, or ``None`` if it must not be emitted.

    Allows ``http:``/``https:``/``mailto:`` absolute URLs and relative URLs
    (including a bare ``#fragment``). Rejects every other scheme, and rejects
    protocol-relative (``//host``) and backslash-prefixed targets, which resolve
    off-origin and are a standard open-redirect vector.
    """
    candidate = href.strip()
    if not candidate:
        return None
    # Control characters are never meaningful in a URL and are the classic way
    # to hide a scheme; drop them from what we emit as well as from the probe.
    candidate = "".join(ch for ch in candidate if ord(ch) >= 0x20 and ord(ch) != 0x7F)
    if not candidate:
        return None

    probe = _probe(candidate)
    if not probe:
        return None
    if probe.startswith("//") or probe.startswith("\\"):
        return None

    match = _SCHEME_RE.match(probe)
    if match:
        return candidate if match.group(1) in ALLOWED_SCHEMES else None
    return candidate


# ---------------------------------------------------------------------------
# Heading anchors
# ---------------------------------------------------------------------------

# Above ASCII, drop punctuation, symbols, separators and "other" (control,
# format, unassigned) — keep letters, digits and combining marks.
_DROP_CATEGORIES = frozenset("PSZC")


def slugify(heading: str) -> str:
    """GitHub-compatible anchor slug for ``heading``.

    Port of ``UserGuideDocs.slugify`` (``user_guide_docs.dart``): lower-case,
    a space becomes ``-``, ``-``/``_``/alphanumerics are kept, and everything
    else is dropped. So ``"Collection & search"`` → ``"collection--search"``:
    the ``&`` vanishes and both surrounding spaces survive as hyphens.
    """
    out: list[str] = []
    for char in heading.lower():
        if char == " ":
            out.append("-")
        elif char in "-_":
            out.append(char)
        elif "a" <= char <= "z" or "0" <= char <= "9":
            out.append(char)
        elif ord(char) < 0x80:
            continue
        elif unicodedata.category(char)[0] not in _DROP_CATEGORIES:
            out.append(char)
    return "".join(out)


# ---------------------------------------------------------------------------
# Render result / context
# ---------------------------------------------------------------------------


@dataclass
class Heading:
    """A rendered heading: its level, anchor id, and plain-text content."""

    level: int
    anchor: str
    text: str


@dataclass
class RenderResult:
    html: str
    headings: list[Heading] = field(default_factory=list)
    # Headings whose slug collides with an earlier one. GitHub silently dedups
    # these with a ``-1`` suffix while the in-app reader keys a map by slug and
    # lets the *last* heading win, so a colliding slug means the same
    # ``#fragment`` lands in three different places. Callers are expected to
    # treat this as an error and have the author disambiguate the heading.
    duplicate_anchors: list[Heading] = field(default_factory=list)

    @property
    def title(self) -> Optional[str]:
        """The document's first H1 text, if it has one."""
        for heading in self.headings:
            if heading.level == 1:
                return heading.text
        return None

    @property
    def anchors(self) -> set[str]:
        return {heading.anchor for heading in self.headings}


# A link resolver maps a Markdown href to the href to emit, or ``None`` to drop
# the link (keeping its text). ``render`` sanitises whatever it returns.
LinkResolver = Callable[[str], Optional[str]]
ImageResolver = Callable[[str], Optional[str]]


class _Context:
    def __init__(
        self,
        link_resolver: Optional[LinkResolver],
        image_resolver: Optional[ImageResolver],
    ) -> None:
        self.link_resolver = link_resolver
        self.image_resolver = image_resolver
        self.headings: list[Heading] = []
        self.duplicate_anchors: list[Heading] = []
        self._seen_anchors: set[str] = set()

    def anchor_for(self, text: str) -> str:
        """The anchor for ``text``, recording a collision rather than renaming.

        Deliberately does NOT suffix duplicates the way GitHub does: the in-app
        reader doesn't suffix either, so silently renaming here would give the
        web a third, different anchor for the same heading. A collision is
        surfaced as a build error instead.
        """
        anchor = slugify(text)
        if anchor in self._seen_anchors:
            self.duplicate_anchors.append(Heading(level=0, anchor=anchor, text=text))
        self._seen_anchors.add(anchor)
        return anchor

    def resolve(self, href: str) -> Optional[str]:
        target = href
        if self.link_resolver is not None:
            resolved = self.link_resolver(href)
            if resolved is None:
                return None
            target = resolved
        return sanitize_href(target)

    def resolve_image(self, href: str) -> Optional[str]:
        if self.image_resolver is None:
            return None
        target = self.image_resolver(href)
        return sanitize_href(target) if target is not None else None


# ---------------------------------------------------------------------------
# Inline parsing
# ---------------------------------------------------------------------------

_ESCAPABLE = set("\\`*_{}[]()#+-.!|<>~\"'")
_AUTOLINK_RE = re.compile(r"<((?:https?|mailto):[^<>\s]+)>")
_PUNCT_OR_SPACE = re.compile(r"[\s\W]")


def _inline(text: str, ctx: _Context) -> str:
    out: list[str] = []
    i = 0
    length = len(text)
    while i < length:
        char = text[i]

        if char == "\\" and i + 1 < length and text[i + 1] in _ESCAPABLE:
            out.append(escape_text(text[i + 1]))
            i += 2
            continue

        if char == "`":
            code = _code_span_at(text, i)
            if code is not None:
                body, end = code
                out.append(f"<code>{escape_text(body)}</code>")
                i = end
                continue

        if char == "!" and i + 1 < length and text[i + 1] == "[":
            parsed = _link_at(text, i + 1)
            if parsed is not None:
                label, dest, title, end = parsed
                alt = _plain_text(label).strip()
                image_src = ctx.resolve_image(dest)
                if image_src is not None:
                    title_attr = (
                        f' title="{escape_attr(title)}"' if title is not None else ""
                    )
                    out.append(
                        f'<img src="{escape_attr(image_src)}" '
                        f'alt="{escape_attr(alt)}"{title_attr} />'
                    )
                elif alt:
                    out.append(f'<em class="guide-figure">{escape_text(alt)}</em>')
                i = end
                continue

        if char == "[":
            parsed = _link_at(text, i)
            if parsed is not None:
                label, dest, title, end = parsed
                out.append(_render_link(label, dest, title, ctx))
                i = end
                continue

        if char == "<":
            match = _AUTOLINK_RE.match(text, i)
            if match:
                out.append(_render_link(match.group(1), match.group(1), None, ctx))
                i = match.end()
                continue

        if char in "*_":
            emphasis = _emphasis_at(text, i, ctx)
            if emphasis is not None:
                rendered, end = emphasis
                out.append(rendered)
                i = end
                continue

        out.append(escape_text(char))
        i += 1

    return "".join(out)


def _render_link(label: str, dest: str, title: Optional[str], ctx: _Context) -> str:
    inner = _inline(label, ctx)
    href = ctx.resolve(dest)
    if href is None:
        # Disallowed or unresolvable target: keep the words, drop the link.
        return inner
    attrs = f' href="{escape_attr(href)}"'
    if title:
        attrs += f' title="{escape_attr(title)}"'
    return f"<a{attrs}>{inner}</a>"


def _code_span_at(text: str, start: int) -> Optional[tuple[str, int]]:
    """Parse a backtick code span at ``start``; returns ``(body, end)``."""
    run = 0
    while start + run < len(text) and text[start + run] == "`":
        run += 1
    fence = "`" * run
    search = start + run
    while True:
        close = text.find(fence, search)
        if close < 0:
            return None
        after = close + run
        # The closing run must be exactly ``run`` backticks long.
        if after < len(text) and text[after] == "`":
            search = after
            while search < len(text) and text[search] == "`":
                search += 1
            continue
        body = text[start + run : close]
        # CommonMark strips one leading and trailing space from a code span
        # that has both, so `` ` `` can render a literal backtick.
        if len(body) > 1 and body.startswith(" ") and body.endswith(" "):
            body = body[1:-1]
        return body, after


def _link_at(text: str, start: int) -> Optional[tuple[str, str, Optional[str], int]]:
    """Parse ``[label](dest "title")`` at ``start``; returns the parts + end."""
    depth = 0
    i = start
    length = len(text)
    label_end = -1
    while i < length:
        char = text[i]
        if char == "\\":
            i += 2
            continue
        if char == "`":
            code = _code_span_at(text, i)
            if code is not None:
                i = code[1]
                continue
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                label_end = i
                break
        i += 1
    if label_end < 0 or label_end + 1 >= length or text[label_end + 1] != "(":
        return None

    label = text[start + 1 : label_end]
    i = label_end + 2
    depth = 1
    dest_start = i
    while i < length:
        char = text[i]
        if char == "\\":
            i += 2
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    if i >= length:
        return None

    dest, title = _split_dest_title(text[dest_start:i])
    return label, dest, title, i + 1


def _split_dest_title(inner: str) -> tuple[str, Optional[str]]:
    inner = inner.strip()
    title: Optional[str] = None
    match = re.search(r'\s+"([^"]*)"$|\s+\'([^\']*)\'$', inner)
    if match:
        title = match.group(1) if match.group(1) is not None else match.group(2)
        inner = inner[: match.start()].strip()
    if inner.startswith("<") and inner.endswith(">"):
        inner = inner[1:-1]
    return inner, title


def _emphasis_span_at(text: str, start: int) -> Optional[tuple[str, int, int]]:
    """Match an emphasis delimiter run at ``start`` *without* rendering it.

    Returns ``(inner_source, end, run)`` — the text between the delimiters, the
    index just past the closing run, and the run length (1 = em, 2 = strong,
    3 = both) — or ``None`` when this is not emphasis.

    This is the single source of truth for what counts as emphasis. Both
    :func:`_inline` (which renders it) and :func:`_plain_text` (which strips it
    for heading slugs) go through here, so the slug is always the text content
    of the rendered markup. They used to carry separate rules, and the copy in
    ``_plain_text`` was naive enough to leave ``_Import_``'s underscores in the
    anchor while the body rendered ``<em>Import</em>`` — an anchor that matched
    neither GitHub nor the in-app reader.
    """
    char = text[start]
    run = 0
    while start + run < len(text) and text[start + run] == char:
        run += 1
    run = min(run, 3)
    open_end = start + run
    if open_end >= len(text) or text[open_end].isspace():
        return None  # not left-flanking: `a * b` is literal
    if char == "_":
        # Intra-word underscores (snake_case, some_file_name) are never emphasis.
        before = text[start - 1] if start > 0 else " "
        if not _PUNCT_OR_SPACE.match(before):
            return None

    delim = char * run
    i = open_end
    while i < len(text):
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == "`":
            code = _code_span_at(text, i)
            if code is not None:
                i = code[1]
                continue
        if text.startswith(delim, i) and not text[i - 1].isspace():
            if char == "_":
                after = text[i + run] if i + run < len(text) else " "
                if not _PUNCT_OR_SPACE.match(after):
                    i += 1
                    continue
            return text[open_end:i], i + run, run
        i += 1
    return None


def _emphasis_at(text: str, start: int, ctx: _Context) -> Optional[tuple[str, int]]:
    span = _emphasis_span_at(text, start)
    if span is None:
        return None
    inner_source, end, run = span
    inner = _inline(inner_source, ctx)
    if run == 1:
        return f"<em>{inner}</em>", end
    if run == 2:
        return f"<strong>{inner}</strong>", end
    return f"<strong><em>{inner}</em></strong>", end


def _plain_text(text: str) -> str:
    """The text a reader sees, with inline markup removed.

    Must equal the *text content* of what :func:`_inline` renders for the same
    source — heading slugs are built from this, and they have to match the app
    and GitHub. It shares :func:`_emphasis_span_at`, :func:`_code_span_at` and
    :func:`_link_at` with the renderer so the two cannot drift apart.
    """
    out: list[str] = []
    i = 0
    length = len(text)
    while i < length:
        char = text[i]
        if char == "\\" and i + 1 < length and text[i + 1] in _ESCAPABLE:
            out.append(text[i + 1])
            i += 2
            continue
        if char == "`":
            code = _code_span_at(text, i)
            if code is not None:
                out.append(code[0])
                i = code[1]
                continue
        if char == "!" and i + 1 < length and text[i + 1] == "[":
            parsed = _link_at(text, i + 1)
            if parsed is not None:
                out.append(_plain_text(parsed[0]))
                i = parsed[3]
                continue
        if char == "[":
            parsed = _link_at(text, i)
            if parsed is not None:
                out.append(_plain_text(parsed[0]))
                i = parsed[3]
                continue
        if char == "<":
            match = _AUTOLINK_RE.match(text, i)
            if match:
                out.append(match.group(1))
                i = match.end()
                continue
        if char in "*_":
            span = _emphasis_span_at(text, i)
            if span is not None:
                inner_source, end, _run = span
                out.append(_plain_text(inner_source))
                i = end
                continue
            # Not emphasis: a literal `*` or `_`, kept exactly as the renderer
            # keeps it (slugify then drops `*` and preserves `_`).
        out.append(char)
        i += 1
    return "".join(out)


# ---------------------------------------------------------------------------
# Block parsing
# ---------------------------------------------------------------------------

_ATX_RE = re.compile(r"^ {0,3}(#{1,6})(?:\s+(.*?))?\s*#*\s*$")
_FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*([^`]*?)\s*$")
_FENCE_CLOSE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})\s*$")
_HR_RE = re.compile(r"^ {0,3}(?:\*\s*){3,}$|^ {0,3}(?:-\s*){3,}$|^ {0,3}(?:_\s*){3,}$")
_QUOTE_RE = re.compile(r"^ {0,3}>\s?(.*)$")
_ITEM_RE = re.compile(r"^( *)([-*+]|\d{1,9}[.)])(\s+|$)(.*)$")
_TABLE_ROW_RE = re.compile(r"^ {0,3}\|.*\|\s*$")
_TABLE_DELIM_RE = re.compile(r"^ {0,3}\|(?:\s*:?-+:?\s*\|)+\s*$")


def _strip_html_comments(lines: list[str]) -> list[str]:
    """Drop ``<!-- … -->`` comments, leaving fenced code blocks untouched."""
    out: list[str] = []
    fence_char: Optional[str] = None
    fence_len = 0
    in_comment = False

    for line in lines:
        if fence_char is not None:
            out.append(line)
            close = _FENCE_CLOSE_RE.match(line)
            if close and close.group(1)[0] == fence_char and len(close.group(1)) >= fence_len:
                fence_char = None
            continue

        if not in_comment:
            fence = _FENCE_RE.match(line)
            if fence:
                fence_char = fence.group(1)[0]
                fence_len = len(fence.group(1))
                out.append(line)
                continue

        rest = line
        cleaned: list[str] = []
        while rest:
            if in_comment:
                end = rest.find("-->")
                if end < 0:
                    break
                rest = rest[end + 3 :]
                in_comment = False
                continue
            begin = rest.find("<!--")
            if begin < 0:
                cleaned.append(rest)
                break
            cleaned.append(rest[:begin])
            rest = rest[begin + 4 :]
            in_comment = True
        out.append("".join(cleaned))

    return out


def _is_block_start(line: str) -> bool:
    """Whether ``line`` begins a block that interrupts a paragraph."""
    if not line.strip():
        return True
    return bool(
        _ATX_RE.match(line)
        or _FENCE_RE.match(line)
        or _HR_RE.match(line)
        or _QUOTE_RE.match(line)
        or _ITEM_RE.match(line)
    )


def _parse_blocks(lines: list[str], ctx: _Context) -> str:
    out: list[str] = []
    i = 0
    total = len(lines)
    while i < total:
        line = lines[i]

        if not line.strip():
            i += 1
            continue

        fence = _FENCE_RE.match(line)
        if fence:
            marker = fence.group(1)
            info = (fence.group(2) or "").split()
            body: list[str] = []
            i += 1
            while i < total:
                close = _FENCE_CLOSE_RE.match(lines[i])
                if close and close.group(1)[0] == marker[0] and len(close.group(1)) >= len(marker):
                    break
                body.append(lines[i])
                i += 1
            i = min(i + 1, total)
            lang = re.sub(r"[^A-Za-z0-9_-]", "", info[0]) if info else ""
            attr = f' class="language-{escape_attr(lang)}"' if lang else ""
            out.append(f"<pre><code{attr}>{escape_text(chr(10).join(body))}\n</code></pre>")
            continue

        heading = _ATX_RE.match(line)
        if heading:
            level = len(heading.group(1))
            raw = (heading.group(2) or "").strip()
            text = _plain_text(raw).strip()
            anchor = ctx.anchor_for(text)
            ctx.headings.append(Heading(level=level, anchor=anchor, text=text))
            out.append(
                f'<h{level} id="{escape_attr(anchor)}">{_inline(raw, ctx)}</h{level}>'
            )
            i += 1
            continue

        if _HR_RE.match(line):
            out.append("<hr />")
            i += 1
            continue

        if _QUOTE_RE.match(line):
            quoted: list[str] = []
            while i < total:
                quote = _QUOTE_RE.match(lines[i])
                if quote:
                    quoted.append(quote.group(1))
                    i += 1
                    continue
                # Lazy continuation: a plain line keeps the quote going.
                if lines[i].strip() and not _is_block_start(lines[i]):
                    quoted.append(lines[i].strip())
                    i += 1
                    continue
                break
            out.append(f"<blockquote>{_parse_blocks(quoted, ctx)}</blockquote>")
            continue

        if (
            _TABLE_ROW_RE.match(line)
            and i + 1 < total
            and _TABLE_DELIM_RE.match(lines[i + 1])
        ):
            rendered, i = _parse_table(lines, i, ctx)
            out.append(rendered)
            continue

        if _ITEM_RE.match(line):
            rendered, i = _parse_list(lines, i, ctx)
            out.append(rendered)
            continue

        paragraph: list[str] = [line.strip()]
        i += 1
        while i < total and lines[i].strip() and not _is_block_start(lines[i]):
            paragraph.append(lines[i].strip())
            i += 1
        out.append(f"<p>{_inline(' '.join(paragraph), ctx)}</p>")

    return "".join(out)


def _split_row(line: str) -> list[str]:
    """Split a table row on unescaped pipes, respecting code spans."""
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    cells: list[str] = []
    current: list[str] = []
    i = 0
    while i < len(stripped):
        char = stripped[i]
        if char == "\\" and i + 1 < len(stripped):
            current.append(stripped[i : i + 2])
            i += 2
            continue
        if char == "`":
            code = _code_span_at(stripped, i)
            if code is not None:
                current.append(stripped[i : code[1]])
                i = code[1]
                continue
        if char == "|":
            cells.append("".join(current).strip())
            current = []
            i += 1
            continue
        current.append(char)
        i += 1
    cells.append("".join(current).strip())
    return cells


def _parse_table(lines: list[str], start: int, ctx: _Context) -> tuple[str, int]:
    header = _split_row(lines[start])
    aligns: list[str] = []
    for cell in _split_row(lines[start + 1]):
        left = cell.startswith(":")
        right = cell.endswith(":")
        aligns.append(
            "center" if left and right else "right" if right else "left" if left else ""
        )

    i = start + 2
    rows: list[list[str]] = []
    while i < len(lines) and _TABLE_ROW_RE.match(lines[i]):
        rows.append(_split_row(lines[i]))
        i += 1

    def cell(tag: str, value: str, index: int) -> str:
        align = aligns[index] if index < len(aligns) else ""
        style = f' style="text-align: {align}"' if align else ""
        return f"<{tag}{style}>{_inline(value, ctx)}</{tag}>"

    out = ['<div class="guide-table-wrap"><table><thead><tr>']
    out += [cell("th", value, idx) for idx, value in enumerate(header)]
    out.append("</tr></thead><tbody>")
    for row in rows:
        out.append("<tr>")
        out += [cell("td", value, idx) for idx, value in enumerate(row)]
        out.append("</tr>")
    out.append("</tbody></table></div>")
    return "".join(out), i


def _marker_kind(marker: str) -> str:
    return "ul" if marker in "-*+" else "ol"


def _parse_list(lines: list[str], start: int, ctx: _Context) -> tuple[str, int]:
    first = _ITEM_RE.match(lines[start])
    assert first is not None
    base_indent = len(first.group(1))
    kind = _marker_kind(first.group(2))
    ordered_start = first.group(2)[:-1] if kind == "ol" else None

    items: list[list[str]] = []
    loose = False
    i = start
    total = len(lines)

    while i < total:
        match = _ITEM_RE.match(lines[i])
        if match is None:
            break
        if len(match.group(1)) != base_indent or _marker_kind(match.group(2)) != kind:
            break

        content_indent = len(match.group(1)) + len(match.group(2)) + len(match.group(3))
        item: list[str] = [match.group(4)]
        i += 1
        blanks = 0
        while i < total:
            nxt = lines[i]
            if not nxt.strip():
                blanks += 1
                i += 1
                continue
            indent = len(nxt) - len(nxt.lstrip(" "))
            if indent >= content_indent:
                if blanks:
                    # A blank line inside an item makes the whole list loose.
                    loose = True
                    item.append("")
                    blanks = 0
                item.append(nxt[content_indent:])
                i += 1
                continue
            if blanks == 0 and not _is_block_start(nxt):
                item.append(nxt.strip())  # lazy paragraph continuation
                i += 1
                continue
            break
        items.append(item)

        if blanks:
            if i >= total:
                break
            nxt_item = _ITEM_RE.match(lines[i])
            if (
                nxt_item is None
                or len(nxt_item.group(1)) != base_indent
                or _marker_kind(nxt_item.group(2)) != kind
            ):
                break
            loose = True

    body: list[str] = []
    for item in items:
        rendered = _parse_blocks(item, ctx)
        if not loose:
            # Tight list: unwrap the leading paragraph so the text sits directly
            # in the <li>, but keep any nested list or table intact.
            rendered = re.sub(r"^<p>(.*?)</p>", r"\1", rendered, count=1, flags=re.S)
        body.append(f"<li>{rendered}</li>")

    if kind == "ol" and ordered_start and ordered_start != "1":
        opening = f'<ol start="{escape_attr(ordered_start)}">'
    else:
        opening = f"<{kind}>"
    return f"{opening}{''.join(body)}</{kind}>", i


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def render(
    markdown: str,
    *,
    link_resolver: Optional[LinkResolver] = None,
    image_resolver: Optional[ImageResolver] = None,
) -> RenderResult:
    """Render ``markdown`` to HTML.

    ``link_resolver`` maps each Markdown href to the href to emit (or ``None``
    to drop the link, keeping its text). ``image_resolver`` does the same for
    image sources. Whatever either resolver returns still goes through
    :func:`sanitize_href` — a resolver can narrow the allow-list, never widen it.
    """
    ctx = _Context(link_resolver, image_resolver)
    normalized = markdown.replace("\r\n", "\n").replace("\r", "\n")
    lines = _strip_html_comments(normalized.split("\n"))
    return RenderResult(
        html=_parse_blocks(lines, ctx),
        headings=ctx.headings,
        duplicate_anchors=ctx.duplicate_anchors,
    )
