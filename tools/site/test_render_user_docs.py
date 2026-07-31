#!/usr/bin/env python3
"""Offline tests for ``render_user_docs.py`` — the hosted user-guide builder.

Pure-stdlib and assert-based (no pytest, matching every other ``test_*.py`` in
``tools/``). Run directly::

    python3 tools/site/test_render_user_docs.py

What it proves:

* **Link classification matches the app.** A relative link to a published guide
  becomes its rendered page; a link that leaves ``docs/user/`` (or points at a
  deliberately unpublished guide like ``style-guide.md``) becomes a GitHub URL —
  ``tree/`` for a directory, ``blob/`` for a file — mirroring
  ``UserGuideDocs.resolveLink``.
* **Every repo-relative target is verified on disk.** A typo'd off-site path
  (``../design/serch.md``) fails the build rather than shipping as a live 404,
  and a link that escapes the repository is refused outright. Absolute URLs and
  ``mailto:`` are passed through untouched and never stat'ed.
* **The real corpus builds clean.** Every guide under ``docs/user/`` renders,
  and every on-site link *and* ``#fragment`` resolves — this is the gate that
  keeps a cross-link from silently 404-ing on the site.
* **Nothing escapes the output directory**, and no external JS/CSS/CDN
  reference is ever emitted.
"""

from __future__ import annotations

import contextlib
import io
import re
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import render_user_docs as rud  # noqa: E402

REPO_ROOT = rud.REPO_ROOT

_VOID = {"area", "base", "br", "col", "hr", "img", "input", "link", "meta", "source"}


class _Balance(HTMLParser):
    """Minimal well-formedness check: every non-void tag must be closed."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag not in _VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag in _VOID:
            return
        if not self.stack:
            self.errors.append(f"stray </{tag}>")
            return
        if self.stack[-1] != tag:
            self.errors.append(f"</{tag}> closes <{self.stack[-1]}>")
            return
        self.stack.pop()


def _assert_balanced(html: str, label: str) -> None:
    parser = _Balance()
    parser.feed(html)
    parser.close()
    assert not parser.errors, f"{label}: {parser.errors}"
    assert not parser.stack, f"{label}: unclosed {parser.stack}"


def _make_docs(root: Path) -> Path:
    """A miniature repo tree exercising every link classification."""
    user = root / "docs" / "user"
    user.mkdir(parents=True)
    design = root / "docs" / "design"
    design.mkdir(parents=True)
    # Off-site link targets are now verified against the working tree, so the
    # fixture has to contain the files (and directories) its guides point at.
    (design / "ux.md").write_text("# UX\n", encoding="utf-8")
    (root / "CONTRIBUTING.md").write_text("# Contributing\n", encoding="utf-8")
    (user / "README.md").write_text(
        "# User Guide\n\n"
        "Welcome to the guides.\n\n"
        "1. [Installation](installation.md)\n"
        "2. [Imports](imports.md)\n\n"
        "Contributors: read the [style guide](style-guide.md).\n"
        "Designers: see the [design docs](../design/ux.md) and "
        "[contributing](../../CONTRIBUTING.md).\n",
        encoding="utf-8",
    )
    (user / "installation.md").write_text(
        "# Installation\n\n"
        "Install it.\n\n"
        "## Install on Linux\n\n"
        "See [imports](./imports.md#bring-dances-in) and "
        "[back to the top](#installation).\n"
        "Also the [hub](./README.md) and [the web](https://example.com/x).\n",
        encoding="utf-8",
    )
    (user / "imports.md").write_text(
        "# Imports\n\n"
        "Bring dances in.\n\n"
        "## Bring dances in\n\n"
        "Back to [installation](installation.md#install-on-linux).\n",
        encoding="utf-8",
    )
    (user / "style-guide.md").write_text("# Style guide\n\nContributors only.\n", encoding="utf-8")
    return user


# ---------------------------------------------------------------------------
# Discovery and output naming
# ---------------------------------------------------------------------------


def test_style_guide_exclusion_is_single_sourced() -> None:
    assert "style-guide.md" in rud.EXCLUDED_GUIDES


def test_discovery_skips_excluded_guides() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        assert rud.discover_guides(user) == ["README.md", "imports.md", "installation.md"]


def test_output_name_maps_the_hub_to_the_index() -> None:
    assert rud.output_name("README.md") == "index.html"
    assert rud.output_name("perform.md") == "perform.html"
    assert rud.output_name("backup-portability.md") == "backup-portability.html"


def test_output_name_rejects_path_traversal() -> None:
    for name in (
        "../evil.md",
        "../../etc/passwd.md",
        "nested/guide.md",
        "..\\evil.md",
        "a\x00b.md",
        "-rf.md",
        "..md",
    ):
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                rud.output_name(name)
        except SystemExit as exc:
            assert exc.code == 2, name
        else:  # pragma: no cover - only on a regression
            raise AssertionError(f"unsafe name accepted: {name!r}")


def test_build_refuses_protected_output_directories() -> None:
    """The guard is an allow-list: only a new, empty, build/ or temp path."""
    refused = [
        REPO_ROOT,
        rud.SITE_DIR,
        rud.DOCS_ROOT,
        rud.SITE_DIR / "guide",
        REPO_ROOT / "app",
        REPO_ROOT / "tools",
        REPO_ROOT / ".github",
        REPO_ROOT / "app" / "lib",
        Path.home(),
    ]
    for target in refused:
        if not target.exists():
            continue
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                rud._guard_out_dir(target)
        except SystemExit as exc:
            assert exc.code == 2, target
        else:  # pragma: no cover - only on a regression
            raise AssertionError(f"protected path accepted as --out: {target}")


def test_build_allows_new_empty_build_and_temp_directories() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        rud._guard_out_dir(root / "does-not-exist-yet")  # new
        (root / "empty").mkdir()
        rud._guard_out_dir(root / "empty")  # empty
        (root / "full").mkdir()
        (root / "full" / "x.txt").write_text("x", encoding="utf-8")
        rud._guard_out_dir(root / "full")  # under the temp dir
        rud._guard_out_dir(REPO_ROOT / "build" / "site")  # under build/


def test_guides_cannot_collide_on_one_output_page() -> None:
    """`index.md` would silently overwrite the README.md hub — refuse instead."""
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "index.md").write_text("# Impostor\n\nHello.\n", encoding="utf-8")
        try:
            with contextlib.redirect_stdout(io.StringIO()) as captured:
                rud.render_guides(user)
        except SystemExit as exc:
            assert exc.code == 2
            assert "guide/index.html" in captured.getvalue()
        else:  # pragma: no cover - only on a regression
            raise AssertionError("index.md was allowed to overwrite the hub")


# ---------------------------------------------------------------------------
# Link classification (mirrors UserGuideDocs.resolveLink)
# ---------------------------------------------------------------------------


def _rendered(user: Path) -> dict[str, rud.Guide]:
    return {guide.doc: guide for guide in rud.render_guides(user)}


def test_relative_guide_links_become_pages() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        guides = _rendered(_make_docs(Path(tmp)))
        body = guides["installation.md"].body
        assert 'href="imports.html#bring-dances-in"' in body
        assert 'href="index.html"' in body, "a link to README.md must reach the hub"
        assert 'href="#installation"' in body, "same-page anchors stay on the page"
        assert ".md" not in re.sub(r"<code>.*?</code>", "", body)


def test_links_that_leave_the_guides_go_to_github() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        guides = _rendered(_make_docs(Path(tmp)))
        body = guides["README.md"].body
        assert f'href="{rud.REPO_BLOB_BASE}/docs/design/ux.md"' in body
        assert f'href="{rud.REPO_BLOB_BASE}/CONTRIBUTING.md"' in body


def test_repo_directories_get_tree_urls_and_files_get_blob_urls() -> None:
    """`blob/<ref>/<dir>` only 301-redirects to `tree/`; point straight at it."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        user = _make_docs(root)
        (user / "imports.md").write_text(
            "# Imports\n\n## Bring dances in\n\n"
            "The [design docs](../design/) and the [UX doc](../design/ux.md).\n",
            encoding="utf-8",
        )
        body = _rendered(user)["imports.md"].body
        assert f'href="{rud.REPO_TREE_BASE}/docs/design"' in body
        assert f'href="{rud.REPO_BLOB_BASE}/docs/design/ux.md"' in body
        assert f'href="{rud.REPO_BLOB_BASE}/docs/design"' not in body


def test_real_corpus_directory_links_use_tree_urls() -> None:
    bodies = "".join(guide.body for guide in rud.render_guides())
    assert f'href="{rud.REPO_TREE_BASE}/docs/design"' in bodies
    assert f'href="{rud.REPO_BLOB_BASE}/docs/design"' not in bodies
    # ...and a real file link still uses blob/.
    assert f'href="{rud.REPO_BLOB_BASE}/docs/design/ux.md"' in bodies


def test_missing_repo_link_target_fails_the_build() -> None:
    """A typo'd off-site path must fail, not ship as a live 404 on GitHub."""
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "imports.md").write_text(
            "# Imports\n\n## Bring dances in\n\nSee the [search doc](../design/serch.md).\n",
            encoding="utf-8",
        )
        errors = rud.check_guides(rud.render_guides(user))
        assert len(errors) == 1, errors
        assert errors[0].startswith("docs/user/imports.md:")
        assert "../design/serch.md" in errors[0]
        assert "docs/design/serch.md" in errors[0]
        assert "does not exist" in errors[0]


def test_link_escaping_the_repository_is_rejected_not_stated() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "imports.md").write_text(
            "# Imports\n\n## Bring dances in\n\n"
            "[secrets](../../../../etc/passwd) and [up](../../..).\n",
            encoding="utf-8",
        )
        guides = rud.render_guides(user)
        errors = rud.check_guides(guides)
        assert len(errors) == 2, errors
        assert all("resolves outside the repository" in e for e in errors), errors
        # Nothing outside the tree may be linked at all.
        body = {g.doc: g for g in guides}["imports.md"].body
        assert "etc/passwd" not in body
        assert "<a " not in body


def test_absolute_urls_are_passed_through_and_never_treated_as_repo_paths() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "imports.md").write_text(
            "# Imports\n\n## Bring dances in\n\n"
            "[issues](https://github.com/ibanner56/CallersCompendium/issues), "
            "[new](https://github.com/ibanner56/CallersCompendium/issues/new/choose), "
            "[releases](https://github.com/ibanner56/CallersCompendium/releases), "
            "[web](https://example.com/x) and [mail](mailto:compendium@contra.dance).\n",
            encoding="utf-8",
        )
        guides = rud.render_guides(user)
        body = {g.doc: g for g in guides}["imports.md"].body
        for url in (
            "https://github.com/ibanner56/CallersCompendium/issues",
            "https://github.com/ibanner56/CallersCompendium/issues/new/choose",
            "https://github.com/ibanner56/CallersCompendium/releases",
            "https://example.com/x",
            "mailto:compendium@contra.dance",
        ):
            assert f'href="{url}"' in body, url
        assert rud.check_guides(guides) == []


def test_an_unpublished_but_existing_guide_still_resolves() -> None:
    """`style-guide.md` is excluded from the site but must exist in the repo."""
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        assert rud.check_guides(rud.render_guides(user)) == []
        (user / "style-guide.md").unlink()
        errors = rud.check_guides(rud.render_guides(user))
        assert len(errors) == 1, errors
        assert "docs/user/style-guide.md" in errors[0]
        assert "does not exist" in errors[0]


def test_unpublished_guide_links_go_to_github_not_a_dead_page() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        guides = _rendered(_make_docs(Path(tmp)))
        body = guides["README.md"].body
        assert f'href="{rud.REPO_BLOB_BASE}/docs/user/style-guide.md"' in body
        assert 'href="style-guide.html"' not in body


def test_external_links_are_left_alone() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        guides = _rendered(_make_docs(Path(tmp)))
        assert 'href="https://example.com/x"' in guides["installation.md"].body


def test_dangerous_links_are_dropped_even_from_a_guide() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "installation.md").write_text(
            "# Installation\n\n[boom](javascript:alert(1))\n", encoding="utf-8"
        )
        body = _rendered(user)["installation.md"].body
        assert "<a " not in body
        assert "javascript" not in body


# ---------------------------------------------------------------------------
# Link integrity
# ---------------------------------------------------------------------------


def test_check_links_flags_a_missing_fragment() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "installation.md").write_text(
            "# Installation\n\n## Install on Linux\n\n"
            "See [imports](./imports.md#no-such-heading).\n",
            encoding="utf-8",
        )
        errors = rud.check_links(rud.render_guides(user))
        assert len(errors) == 1, errors
        assert "no-such-heading" in errors[0]


def test_check_links_flags_a_link_to_a_guide_that_does_not_exist() -> None:
    """A typo'd or renamed cross-link must fail, not quietly become a 404.

    ``UserGuideDocs.resolveLink`` distinguishes this case (``GuideMissingLink``)
    from a genuine off-site link, and so must the build.
    """
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "installation.md").write_text(
            "# Installation\n\n## Install on Linux\n\n"
            "See [typo](./importz.md) and [ghost](./does-not-exist.md#nope).\n",
            encoding="utf-8",
        )
        errors = rud.check_guides(rud.render_guides(user))
        assert len(errors) == 2, errors
        joined = "\n".join(errors)
        assert "docs/user/installation.md" in joined
        assert "./importz.md" in joined and "docs/user/importz.md" in joined
        assert "./does-not-exist.md#nope" in joined


def test_a_missing_guide_link_is_flagged_even_though_it_renders() -> None:
    """The page still renders (with a GitHub URL); the build fails anyway."""
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "installation.md").write_text(
            "# Installation\n\n## Install on Linux\n\nSee [x](./gone.md).\n",
            encoding="utf-8",
        )
        guides = rud.render_guides(user)
        body = {g.doc: g for g in guides}["installation.md"].body
        assert f'href="{rud.REPO_BLOB_BASE}/docs/user/gone.md"' in body
        assert rud.check_guides(guides), "a link to a missing guide must fail"


def test_excluded_style_guide_link_is_not_treated_as_broken() -> None:
    """`style-guide.md` is deliberately unpublished — it is not a broken link."""
    with tempfile.TemporaryDirectory() as tmp:
        # The hub already links to style-guide.md; it must not raise an error.
        assert rud.check_guides(rud.render_guides(_make_docs(Path(tmp)))) == []


def test_check_links_accepts_a_clean_corpus() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        assert rud.check_guides(rud.render_guides(_make_docs(Path(tmp)))) == []


def test_check_anchors_flags_a_duplicate_heading_anchor() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "imports.md").write_text(
            "# Imports\n\n## Bring dances in\n\nOne way.\n\n"
            "## Bring dances in\n\nAnother way.\n",
            encoding="utf-8",
        )
        errors = rud.check_anchors(rud.render_guides(user))
        assert len(errors) == 1, errors
        assert "docs/user/imports.md" in errors[0]
        assert "#bring-dances-in" in errors[0]
        assert "Bring dances in" in errors[0]
        assert errors[0] in rud.check_guides(rud.render_guides(user))


def test_errors_name_the_markdown_source_not_the_html() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "installation.md").write_text(
            "# Installation\n\n## Install on Linux\n\n"
            "See [imports](./imports.md#gone).\n",
            encoding="utf-8",
        )
        errors = rud.check_guides(rud.render_guides(user))
        assert errors and errors[0].startswith("docs/user/installation.md:"), errors
        assert "./imports.md#gone" in errors[0]


def test_links_that_leave_the_site_are_checked_on_disk_not_over_the_network() -> None:
    """An off-site *repo* path is verified; a `#fragment` on it is not.

    We can stat a repo-relative target, so a typo fails the build. We cannot
    resolve an anchor inside a file we don't render, so those are left alone.
    """
    with tempfile.TemporaryDirectory() as tmp:
        user = _make_docs(Path(tmp))
        (user / "imports.md").write_text(
            "# Imports\n\n## Bring dances in\n\n"
            "See [ux](../design/ux.md#any-anchor-at-all) and "
            "[style](style-guide.md#nope).\n",
            encoding="utf-8",
        )
        guides = rud.render_guides(user)
        assert rud.check_guides(guides) == []
        body = {g.doc: g for g in guides}["imports.md"].body
        assert f'{rud.REPO_BLOB_BASE}/docs/design/ux.md#any-anchor-at-all' in body
        assert f'{rud.REPO_BLOB_BASE}/docs/user/style-guide.md#nope' in body


# ---------------------------------------------------------------------------
# The real corpus
# ---------------------------------------------------------------------------


def test_every_real_guide_renders_with_a_title_and_headings() -> None:
    guides = rud.render_guides()
    assert len(guides) >= 10, "the guide set shrank unexpectedly"
    for guide in guides:
        assert guide.title, guide.doc
        assert guide.anchors, f"{guide.doc} has no headings"
        assert guide.summary, guide.doc
        assert guide.body.strip(), guide.doc


def test_the_real_corpus_has_no_broken_on_site_links() -> None:
    errors = rud.check_guides(rud.render_guides())
    assert errors == [], errors


def test_the_real_corpus_has_no_duplicate_heading_anchors() -> None:
    assert rud.check_anchors(rud.render_guides()) == []


def test_real_pages_are_well_formed_html() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        rud.build_site(out)
        for page in sorted((out / "guide").glob("*.html")):
            _assert_balanced(page.read_text(encoding="utf-8"), page.name)


# ---------------------------------------------------------------------------
# Site staging
# ---------------------------------------------------------------------------


def test_build_site_stages_a_complete_publishable_site() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        guides = rud.build_site(out)
        # The publisher requires an index.html at the root of --site.
        assert (out / "index.html").is_file()
        assert (out / "styles.css").is_file()
        assert (out / "privacy" / "index.html").is_file()
        assert (out / "guide" / "index.html").is_file()
        for guide in guides:
            assert (out / "guide" / guide.page).is_file(), guide.page
        assert not (out / "guide" / "README.html").exists()
        assert not (out / "guide" / "style-guide.html").exists()


def test_build_site_is_idempotent_and_prunes_stale_pages() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        rud.build_site(out)
        stale = out / "guide" / "removed-guide.html"
        stale.write_text("<!-- stale -->", encoding="utf-8")
        rud.build_site(out)
        assert not stale.exists(), "a rebuild must not carry stale pages forward"


def test_pages_reference_only_first_party_assets() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        rud.build_site(out)
        # rel values that make the browser FETCH something. `canonical` is
        # metadata and is deliberately the absolute public URL.
        fetching = {"stylesheet", "icon", "preconnect", "preload", "prefetch", "dns-prefetch"}
        for page in sorted((out / "guide").glob("*.html")):
            html = page.read_text(encoding="utf-8")
            assert "<script" not in html, f"{page.name} added JS"
            for tag in re.findall(r"<link[^>]*>", html):
                rel = re.search(r'rel="([^"]+)"', tag)
                href = re.search(r'href="([^"]+)"', tag)
                if rel and href and rel.group(1) in fetching:
                    assert not href.group(1).startswith("http"), (page.name, tag)
            for match in re.finditer(r"<img[^>]*src=\"([^\"]+)\"", html):
                assert match.group(1).startswith("../assets/"), (page.name, match.group(1))


def test_guides_render_images_as_captions_not_img_tags() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        rud.build_site(out)
        for page in sorted((out / "guide").glob("*.html")):
            html = page.read_text(encoding="utf-8")
            body = html.split('<article class="guide-body"')[1].split("</article>")[0]
            assert "<img" not in body, f"{page.name} embedded an image"
            assert ".svg" not in body and ".png" not in body, page.name


def test_sidebar_lists_every_guide_and_marks_the_current_page() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        guides = rud.build_site(out)
        page = (out / "guide" / "perform.html").read_text(encoding="utf-8")
        nav = page.split('<nav class="guide-nav"')[1].split("</nav>")[0]
        for guide in guides:
            if guide.page == "index.html":
                continue
            assert f'href="{guide.page}"' in nav, guide.page
        assert 'href="perform.html" aria-current="page"' in nav


def test_sidebar_is_a_labelled_landmark_with_a_js_free_disclosure() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        rud.build_site(out)
        page = (out / "guide" / "perform.html").read_text(encoding="utf-8")
        assert '<nav class="guide-nav" aria-label="User guides">' in page
        # A <details> disclosure folds the list away on a narrow screen without
        # any JavaScript, and ships `open` so it is never hidden by default.
        assert "<details open><summary>User guide</summary>" in page
        assert "<script" not in page


def test_pages_have_exactly_one_h1_and_it_is_the_guide_title() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        guides = rud.build_site(out)
        for guide in guides:
            html = (out / "guide" / guide.page).read_text(encoding="utf-8")
            headings = re.findall(r"<h1[ >]", html)
            assert len(headings) == 1, f"{guide.page} has {len(headings)} h1s"


def test_pages_carry_the_same_chrome_as_the_privacy_page() -> None:
    privacy = (rud.SITE_DIR / "privacy" / "index.html").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        guides = rud.build_site(out)
        for guide in guides:
            html = (out / "guide" / guide.page).read_text(encoding="utf-8")
            assert '<html lang="en">' in html, guide.page
            assert '<link rel="stylesheet" href="../styles.css" />' in html, guide.page
            assert '<link rel="icon" href="../assets/favicon.svg"' in html, guide.page
            assert 'property="og:image" content="../assets/social-card.svg"' in html
            assert '<main id="main">' in html, guide.page
            assert 'class="skip-link"' in html, guide.page
            assert '<footer class="site-footer">' in html, guide.page
        for marker in ('<html lang="en">', 'class="skip-link"', '<main id="main">'):
            assert marker in privacy, marker


def test_skip_link_lands_past_the_guide_switcher() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        rud.build_site(out)
        html = (out / "guide" / "perform.html").read_text(encoding="utf-8")
        assert '<a class="skip-link" href="#guide-content">' in html
        assert 'id="guide-content"' in html
        # ...and the target must come after the nav, or the skip does nothing.
        assert html.index('class="guide-nav"') < html.index('id="guide-content"')


def test_each_page_has_a_unique_title_description_and_canonical_url() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        guides = rud.build_site(out)
        titles, descriptions, canonicals = set(), set(), set()
        for guide in guides:
            html = (out / "guide" / guide.page).read_text(encoding="utf-8")
            titles.add(re.search(r"<title>(.*?)</title>", html).group(1))
            descriptions.add(
                re.search(r'<meta name="description" content="(.*?)"', html).group(1)
            )
            canonical = re.search(r'<link rel="canonical" href="(.*?)"', html).group(1)
            canonicals.add(canonical)
            expected = "" if guide.page == "index.html" else guide.page
            assert canonical == f"{rud.SITE_URL}guide/{expected}", guide.page
        assert len(titles) == len(guides)
        assert len(descriptions) == len(guides)
        assert len(canonicals) == len(guides)


def test_nav_order_follows_the_hub() -> None:
    hub = "[Installation](installation.md) then [Imports](imports.md)"
    order = rud._nav_order(["README.md", "imports.md", "installation.md", "zzz.md"], hub)
    assert order == ["installation.md", "imports.md", "zzz.md"]


def test_landing_page_guide_links_all_resolve() -> None:
    """site/index.html hard-codes guide/*.html; a renamed guide must fail CI."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        guides = rud.build_site(out)
        landing = (out / "index.html").read_text(encoding="utf-8")
        targets = re.findall(r'href="(guide/[^"#]*)', landing)
        assert len(targets) >= 10, targets
        assert rud.check_site_links(out, guides) == []


def test_check_site_links_flags_a_stale_landing_page_link() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "site"
        guides = rud.build_site(out)
        (out / "index.html").write_text(
            '<a href="guide/retired-guide.html">gone</a>'
            '<a href="guide/perform.html#no-such-heading">bad anchor</a>',
            encoding="utf-8",
        )
        errors = rud.check_site_links(out, guides)
        assert len(errors) == 2, errors
        assert "retired-guide.html" in errors[0]
        assert "no matching heading" in errors[1]


def test_main_check_mode_passes_on_the_real_corpus() -> None:
    with contextlib.redirect_stdout(io.StringIO()):
        assert rud.main(["--check"]) == 0


def main() -> int:
    tests = [
        value
        for name, value in sorted(globals().items())
        if name.startswith("test_") and callable(value)
    ]
    for test in tests:
        test()
    print(f"OK: all {len(tests)} render_user_docs tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
