#!/usr/bin/env python3
"""Offline tests for ``markdown_to_html.py`` — the user-guide Markdown renderer.

Pure-stdlib and assert-based (no pytest, matching every other ``test_*.py`` in
``tools/``). Run directly::

    python3 tools/site/test_markdown_to_html.py

Two things are under test, and the second matters more than the first:

1. **Coverage of the Markdown the guides actually use** — headings, emphasis,
   code spans, links, images, nested lists, GFM tables, blockquotes, fenced
   code, thematic breaks — plus anchor slugs that match the in-app reader and
   GitHub, because the guides cross-link by ``#fragment``.
2. **The security contract**: everything is escaped, raw HTML never passes
   through, HTML comments are dropped, and link targets are allow-listed —
   including against the obfuscated ``javascript:`` forms browsers still honour
   (mixed case, embedded control characters, HTML-entity-encoded colons).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import markdown_to_html as md  # noqa: E402


def _html(source: str, **kwargs) -> str:
    return md.render(source, **kwargs).html


# ---------------------------------------------------------------------------
# Security: escaping
# ---------------------------------------------------------------------------


def test_text_is_escaped() -> None:
    out = _html("A < B & C > D")
    assert "A &lt; B &amp; C &gt; D" in out, out
    assert "<b" not in out.replace("<blockquote", "")


def test_raw_html_is_never_passed_through() -> None:
    """Inline HTML in the source must render as literal text, not markup."""
    payloads = [
        "<script>alert(1)</script>",
        "<img src=x onerror=alert(1)>",
        "<iframe src='https://evil.example'></iframe>",
        "<style>body{display:none}</style>",
        "<svg/onload=alert(1)>",
    ]
    for payload in payloads:
        out = _html(payload)
        assert "<script" not in out, payload
        assert "<img" not in out, payload
        assert "<iframe" not in out, payload
        assert "<style" not in out, payload
        assert "<svg" not in out, payload
        assert "&lt;" in out, payload


def test_html_in_headings_tables_and_lists_is_escaped() -> None:
    for source in (
        "# <script>x</script>",
        "| a |\n|---|\n| <script>x</script> |",
        "- <script>x</script>",
        "> <script>x</script>",
    ):
        out = _html(source)
        assert "<script" not in out, source
        assert "&lt;script&gt;" in out, source


def test_code_span_and_fence_contents_are_escaped() -> None:
    assert "<code>&lt;script&gt;</code>" in _html("`<script>`")
    fenced = _html("```\n<script>alert(1)</script>\n```")
    assert "<script" not in fenced
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in fenced


def test_fence_language_is_sanitised_into_a_class() -> None:
    assert 'class="language-sh"' in _html("```sh\necho hi\n```")
    # A hostile info string cannot escape the class attribute.
    out = _html('```a" onmouseover="alert(1)\nx\n```')
    assert 'onmouseover="alert(1)"' not in out
    assert 'class="language-a"' in out


def test_html_comments_are_dropped_but_survive_inside_code_fences() -> None:
    out = _html("before\n\n<!-- secret <script>x</script> -->\n\nafter")
    assert "secret" not in out
    assert "<script" not in out
    assert "before" in out and "after" in out

    fenced = _html("```\n<!-- kept -->\n```")
    assert "&lt;!-- kept --&gt;" in fenced


def test_multi_line_html_comment_is_dropped() -> None:
    out = _html("keep\n\n<!--\nhidden\nstill hidden\n-->\n\ntail")
    assert "hidden" not in out
    assert "keep" in out and "tail" in out


def test_attribute_escaping_cannot_break_out() -> None:
    out = _html('[x](https://example.com/?a="><script>alert(1)</script>)')
    assert "<script" not in out
    assert "&quot;" in out or "%22" in out


def test_link_title_is_escaped() -> None:
    # Single-quoted title so `_split_dest_title` actually parses it, with a
    # payload that would break out of the attribute if titles went out raw.
    out = _html("""[x](https://e.com 'a" onmouseover=alert(1)')""")
    assert 'title="a&quot; onmouseover=alert(1)"' in out
    assert '" onmouseover=alert(1)"' not in out.replace("&quot;", "")


def test_link_title_quotes_are_escaped_both_ways() -> None:
    assert 'title="he said &#x27;hi&#x27;"' in _html("""[x](https://e.com "he said 'hi'")""")


# ---------------------------------------------------------------------------
# Security: href sanitisation
# ---------------------------------------------------------------------------


def test_allowed_schemes_survive() -> None:
    for href in (
        "https://example.com/a?b=c#d",
        "http://example.com",
        "mailto:compendium@contra.dance",
        "./imports.html",
        "imports.html#anchor",
        "#anchor",
        "../styles.css",
    ):
        assert md.sanitize_href(href) == href, href


def test_dangerous_schemes_are_rejected() -> None:
    for href in (
        "javascript:alert(1)",
        "JavaScript:alert(1)",
        "JAVASCRIPT:alert(1)",
        "  javascript:alert(1)",
        "java\tscript:alert(1)",
        "java\nscript:alert(1)",
        "java\rscript:alert(1)",
        "java\x00script:alert(1)",
        "jav\x01ascript:alert(1)",
        "javascript&#58;alert(1)",
        "javascript&#x3a;alert(1)",
        "javascript&colon;alert(1)",
        "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==",
        "DATA:text/html,<script>alert(1)</script>",
        "vbscript:msgbox(1)",
        "VBScript:msgbox(1)",
        "file:///etc/passwd",
        "\x00javascript:alert(1)",
    ):
        assert md.sanitize_href(href) is None, href


def test_protocol_relative_and_backslash_targets_are_rejected() -> None:
    for href in ("//evil.example/x", "\\\\evil.example\\x", "\\/evil.example"):
        assert md.sanitize_href(href) is None, href


def test_empty_and_control_only_hrefs_are_rejected() -> None:
    for href in ("", "   ", "\x00\x01", "\t\n"):
        assert md.sanitize_href(href) is None, repr(href)


def test_rejected_link_keeps_its_text_and_emits_no_anchor() -> None:
    out = _html("[click me](javascript:alert(1))")
    assert "<a " not in out
    assert "javascript" not in out
    assert "click me" in out


def test_dangerous_autolink_is_not_emitted() -> None:
    # Only http/https/mailto autolinks are recognised at all.
    out = _html("<javascript:alert(1)>")
    assert "<a " not in out
    assert "&lt;javascript:alert(1)&gt;" in out


def test_link_resolver_cannot_widen_the_allow_list() -> None:
    out = _html("[x](ok.md)", link_resolver=lambda href: "javascript:alert(1)")
    assert "<a " not in out
    assert "javascript" not in out


def test_link_resolver_can_drop_a_link() -> None:
    out = _html("[label](whatever.md)", link_resolver=lambda href: None)
    assert "<a " not in out
    assert "label" in out


def test_link_resolver_rewrites_targets() -> None:
    out = _html(
        "[x](./imports.md#anchor)",
        link_resolver=lambda href: href.replace(".md", ".html"),
    )
    assert 'href="./imports.html#anchor"' in out


# ---------------------------------------------------------------------------
# Anchors
# ---------------------------------------------------------------------------


def test_slugify_matches_the_in_app_reader() -> None:
    # Cases mirrored from UserGuideDocs.slugify (user_guide_docs.dart).
    cases = {
        "Getting started": "getting-started",
        "Collection & search": "collection--search",
        "FAQ & troubleshooting": "faq--troubleshooting",
        "Adjust on the fly": "adjust-on-the-fly",
        "Backup & portability": "backup--portability",
        "Print the programming matrix": "print-the-programming-matrix",
        "Dialect: put the app in your own words": (
            "dialect-put-the-app-in-your-own-words"
        ),
        "What's next?": "whats-next",
        "under_score and hyphen-ated": "under_score-and-hyphen-ated",
        "Verify your download (optional)": "verify-your-download-optional",
        "Étape suivante": "étape-suivante",
        "A — B": "a--b",
        "1. Numbered": "1-numbered",
    }
    for heading, expected in cases.items():
        assert md.slugify(heading) == expected, (heading, md.slugify(heading))


def test_heading_anchor_uses_plain_text_not_markup() -> None:
    result = md.render("## Use **Import** and `--flag`")
    assert result.headings[0].anchor == "use-import-and---flag"
    assert 'id="use-import-and---flag"' in result.html


def test_duplicate_heading_anchors_are_reported_not_renamed() -> None:
    """GitHub suffixes duplicates and the in-app reader doesn't; we refuse both.

    Silently renaming here would give the web a third anchor for the same
    heading, so a collision is surfaced for the author to fix.
    """
    result = md.render("## Notes\n\n## Notes\n\n## More\n\n## Notes")
    assert [h.anchor for h in result.headings] == ["notes", "notes", "more", "notes"]
    assert [h.text for h in result.duplicate_anchors] == ["Notes", "Notes"]
    assert 'id="notes-1"' not in result.html


def test_unique_headings_report_no_duplicates() -> None:
    result = md.render("# A\n\n## B\n\n### C")
    assert result.duplicate_anchors == []


def test_anchor_id_is_attribute_escaped() -> None:
    # Quotes are dropped by slugify, but assert the emitted attribute anyway.
    result = md.render('## a"b')
    assert '"' not in result.headings[0].anchor
    assert f'id="{result.headings[0].anchor}"' in result.html


def test_title_is_the_first_h1() -> None:
    result = md.render("# The title\n\n## Not the title")
    assert result.title == "The title"
    assert md.render("## No h1 here").title is None


# ---------------------------------------------------------------------------
# Markdown surface used by the guides
# ---------------------------------------------------------------------------


def test_headings_levels_one_to_four() -> None:
    out = _html("# a\n\n## b\n\n### c\n\n#### d")
    for level in (1, 2, 3, 4):
        assert f"<h{level} id=" in out, level
    # A hash without a space is not a heading.
    assert "<h1" not in _html("#nothashtag")


def test_paragraphs_join_wrapped_lines() -> None:
    assert _html("one\ntwo\n\nthree") == "<p>one two</p><p>three</p>"


def test_emphasis_strong_and_code() -> None:
    assert "<strong>bold</strong>" in _html("**bold**")
    assert "<em>italic</em>" in _html("*italic*")
    assert "<strong><em>both</em></strong>" in _html("***both***")
    assert "<code>code</code>" in _html("`code`")
    assert "<strong>b</strong>" in _html("__b__")
    assert "<em>i</em>" in _html("_i_")


def test_intra_word_underscores_are_literal() -> None:
    out = _html("a snake_case_name here")
    assert "<em>" not in out
    assert "snake_case_name" in out


def test_lone_asterisk_is_literal() -> None:
    out = _html("2 * 3 * 4")
    assert "<em>" not in out
    assert "2 * 3 * 4" in out


def test_emphasis_inside_link_text() -> None:
    out = _html("[**Installation**](installation.md)")
    assert '<a href="installation.md"><strong>Installation</strong></a>' in out


def test_code_span_with_pipes_and_backticks() -> None:
    assert "<code>a|b</code>" in _html("`a|b`")
    assert "<code>`</code>" in _html("`` ` ``")


def test_unordered_and_ordered_lists() -> None:
    assert _html("- a\n- b") == "<ul><li>a</li><li>b</li></ul>"
    assert _html("1. a\n2. b") == "<ol><li>a</li><li>b</li></ol>"
    assert '<ol start="3">' in _html("3. a\n4. b")


def test_nested_ordered_list_inside_unordered_item() -> None:
    source = (
        "- **AppImage** — a single file.\n"
        "  1. Download it.\n"
        "  2. Mark it as runnable. In your file manager, open the file's\n"
        "     **Properties**.\n"
        "- **Archive** — the other option.\n"
        "  1. Extract it.\n"
    )
    out = _html(source)
    assert out.count("<ol>") == 2
    assert out.count("<ul>") == 1
    assert "<strong>Properties</strong>" in out
    assert "open the file's <strong>Properties</strong>" in out


def test_loose_list_wraps_items_in_paragraphs() -> None:
    assert "<li><p>a</p></li>" in _html("- a\n\n- b")
    assert "<li>a</li>" in _html("- a\n- b")


def test_ordered_list_continuation_lines_join() -> None:
    out = _html("1. **[Installation](installation.md)** — get the app onto\n   your phone.")
    assert "get the app onto your phone." in out


def test_tables() -> None:
    out = _html("| I want to… | Go to |\n|---|---|\n| Install | [Installation](installation.md) |")
    assert "<th>I want to…</th>" in out
    assert '<td><a href="installation.md">Installation</a></td>' in out
    assert out.count("<tr>") == 2


def test_table_alignment() -> None:
    out = _html("| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |")
    assert 'style="text-align: left"' in out
    assert 'style="text-align: center"' in out
    assert 'style="text-align: right"' in out


def test_blockquote_with_emphasis_and_links() -> None:
    out = _html("> **Note.** See the [Glossary](./glossary.md).\n> Second line.")
    assert out.startswith("<blockquote><p><strong>Note.</strong>")
    assert '<a href="./glossary.md">Glossary</a>' in out
    assert "Second line." in out


def test_thematic_break() -> None:
    assert "<hr />" in _html("a\n\n---\n\nb")
    assert "<hr />" in _html("***")
    assert "<hr />" in _html("___")


def test_fenced_code_block_preserves_lines() -> None:
    out = _html("```sh\npython3 a.py\npython3 b.py\n```")
    assert "python3 a.py\npython3 b.py" in out
    assert out.startswith("<pre><code")


def test_image_renders_as_an_alt_text_caption_not_an_img() -> None:
    out = _html("![A wireframe of the Collection screen](../design/wireframes/1.svg)")
    assert "<img" not in out
    assert "1.svg" not in out
    assert '<em class="guide-figure">A wireframe of the Collection screen</em>' in out


def test_decorative_image_with_empty_alt_renders_nothing() -> None:
    assert _html("![](images/divider.png)") == "<p></p>"


def test_image_alt_text_is_escaped() -> None:
    out = _html("![<script>alert(1)</script>](x.png)")
    assert "<script" not in out
    assert "&lt;script&gt;" in out


def test_autolink() -> None:
    out = _html("<https://example.com/x>")
    assert '<a href="https://example.com/x">https://example.com/x</a>' in out


def test_backslash_escapes() -> None:
    out = _html(r"not \*emphasis\* here")
    assert "<em>" not in out
    assert "not *emphasis* here" in out


def test_crlf_input_is_normalised() -> None:
    assert _html("# a\r\n\r\nb\r\n") == '<h1 id="a">a</h1><p>b</p>'


def main() -> int:
    tests = [
        value
        for name, value in sorted(globals().items())
        if name.startswith("test_") and callable(value)
    ]
    for test in tests:
        test()
    print(f"OK: all {len(tests)} markdown_to_html tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
