#!/usr/bin/env python3
"""Render ``docs/user/*.md`` into a browsable section of the Pages site.

``docs/user/`` is the single source of truth for the user guides. It already has
two consumers — GitHub's Markdown renderer, and the **offline in-app reader**
(mirrored into ``app/assets/docs/`` by ``tools/ci/sync_user_docs.py``). This
script adds the third: static HTML under ``guide/`` on the public Pages site
(https://ibanner56.github.io/CallersCompendium/guide/).

**Why pre-rendered.** ``gh-pages`` carries a ``.nojekyll`` marker so the update
manifests (``stable.json`` / ``beta.json``) are served verbatim — which also
means Jekyll will not render Markdown for us. So we render it ourselves, with
``tools/site/markdown_to_html.py`` (stdlib-only; the Pages job has no
``pip install`` step and the site is deliberately dependency-free).

**How it is published.** This script stages a COMPLETE site — the contents of
``site/`` plus the rendered ``guide/`` tree — into an output directory, which is
then handed to the existing ``tools/release/publish_pages_site.sh --site <dir>``.
That publisher already merges non-destructively into ``gh-pages`` (preserving
``*.json``, ``*.json.sig`` and ``.nojekyll`` by pattern) and already retries on a
concurrent manifest push, so hosting the guides needs **no change** to it.

**Consistency with the app and GitHub.** Heading anchors use the same slug rule
as ``UserGuideDocs.slugify``, relative ``*.md`` links are rewritten to their
rendered ``.html`` counterparts, and links that leave ``docs/user/`` (design
docs, ``CONTRIBUTING.md``, the contributor-only style guide) are rewritten to
GitHub URLs — mirroring ``UserGuideDocs.resolveLink``. Images render as real
``<img>`` elements on Pages; the in-app reader still renders their alt text.

**Link integrity is enforced.** A relative link to a guide that doesn't exist,
a ``#fragment`` with no matching heading, two headings in one guide that slug to
the same anchor, or a stale ``guide/…`` link on the landing page all fail the
build, naming the source ``.md`` file. On top of that, every GitHub repo URL in
the **built** site — including the ones the page shell writes directly, which
never pass through the link resolver — is checked against the working tree: the
path must exist, and ``blob/`` must be a file while ``tree/`` must be a
directory. The gate runs on every PR that touches the guides, so a broken
cross-link can't reach ``main``.

Usage::

    python3 tools/site/render_user_docs.py                 # -> build/site
    python3 tools/site/render_user_docs.py --out build/x   # explicit output
    python3 tools/site/render_user_docs.py --check         # temp dir, no writes

``--out`` is erased and rewritten, so it must be a new or empty directory, or
sit **below** ``build/`` or a temp directory — never one of those roots itself.

Exit codes: 0 = rendered, 1 = broken links, 2 = bad input.
"""

from __future__ import annotations

import argparse
import html as html_module
import importlib.util
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

from markdown_to_html import (  # noqa: E402
    escape_attr,
    escape_text,
    render,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS_ROOT = REPO_ROOT / "docs"
USER_DOCS = DOCS_ROOT / "user"
SITE_DIR = REPO_ROOT / "site"
DEFAULT_OUT = REPO_ROOT / "build" / "site"

# Path prefix the guides' relative links are resolved in, so `./imports.md` and
# `../design/ux.md` behave exactly as they do in the repo.
USER_DOCS_REPO_DIR = "docs/user"

# The guide that becomes the section's landing page.
HUB_DOC = "README.md"

SITE_URL = "https://ibanner56.github.io/CallersCompendium/"
REPO_URL = "https://github.com/ibanner56/CallersCompendium"
REPO_BLOB_BASE = f"{REPO_URL}/blob/main"
REPO_TREE_BASE = f"{REPO_URL}/tree/main"
CONTACT_EMAIL = "compendium@contra.dance"

# Output file names must be plain, single-segment names. Anything else (a slash,
# `..`, a leading dash, a NUL) is refused rather than sanitised — a guide file
# name is fully under our control, so a surprising one is a bug, not input.
_SAFE_STEM = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$")


def _fail(msg: str, code: int = 2) -> None:
    # ``::error::`` renders as an annotation in the GitHub Actions UI.
    print(f"::error::{msg}")
    sys.exit(code)


def _load_excluded_guides() -> frozenset[str]:
    """The guides deliberately not shipped to users, from ``sync_user_docs``.

    Single-sourced rather than re-listed here: ``style-guide.md`` is contributor
    documentation, and the in-app bundle, the app's link resolver
    (``kBundleExcludedGuides``) and this site must agree on that.
    """
    module_path = REPO_ROOT / "tools" / "ci" / "sync_user_docs.py"
    spec = importlib.util.spec_from_file_location("sync_user_docs", module_path)
    if spec is None or spec.loader is None:  # pragma: no cover - defensive
        _fail(f"cannot load {module_path}")
        raise AssertionError  # unreachable; keeps type checkers happy
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return frozenset(module.EXCLUDED_GUIDES)


EXCLUDED_GUIDES = _load_excluded_guides()


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------


def discover_guides(user_docs: Path = USER_DOCS) -> list[str]:
    """User-facing guide file names under ``user_docs`` (sorted).

    Guides are **discovered**, never enumerated, so a new ``docs/user/*.md``
    is published automatically — the same contract the in-app bundle has.
    """
    if not user_docs.is_dir():
        _fail(f"missing source docs directory: {user_docs}")
    names = [
        path.name
        for path in sorted(user_docs.glob("*.md"))
        if path.name not in EXCLUDED_GUIDES
    ]
    if not names:
        _fail(f"no user guides found under {user_docs}")
    return names


def output_name(doc: str) -> str:
    """Map a guide file name to its page name under ``guide/``.

    The hub becomes the section index; every other guide keeps its stem. Raises
    on anything that isn't a plain file name, so a crafted path can never escape
    the output directory.
    """
    if "/" in doc or "\\" in doc or "\x00" in doc:
        _fail(f"unsafe guide name: {doc!r}")
    if doc == HUB_DOC:
        return "index.html"
    if not doc.endswith(".md"):
        _fail(f"not a markdown guide: {doc!r}")
    stem = doc[: -len(".md")]
    if stem in {".", ".."} or not _SAFE_STEM.match(stem):
        _fail(f"unsafe guide name: {doc!r}")
    return f"{stem}.html"


# ---------------------------------------------------------------------------
# Link resolution (mirrors UserGuideDocs.resolveLink)
# ---------------------------------------------------------------------------


def _normalize_repo_path(path: str) -> str:
    """Collapse ``.``/``..`` segments in a posix-style path."""
    segments: list[str] = []
    for segment in path.split("/"):
        if not segment or segment == ".":
            continue
        if segment == "..":
            if segments and segments[-1] != "..":
                segments.pop()
            else:
                segments.append(segment)
            continue
        segments.append(segment)
    return "/".join(segments)


def _split_fragment(href: str) -> tuple[str, Optional[str]]:
    path, sep, fragment = href.partition("#")
    if not sep or not fragment:
        return path, None
    return path, fragment


@dataclass
class LinkRef:
    """A link emitted by a page, kept so integrity can be checked afterwards."""

    source: str
    href: str
    target_page: Optional[str] = None
    fragment: Optional[str] = None
    # Set when the link is already known to be broken at resolve time — the
    # phrase completes "link <href> …" in the reported error.
    problem: Optional[str] = None


class GuideLinkResolver:
    """Rewrites a guide's Markdown hrefs for the hosted site.

    Mirrors ``UserGuideDocs.resolveLink``: a relative link that lands on another
    **published** guide becomes its rendered page; a link to a repo file outside
    the published set (design docs, ``CONTRIBUTING.md``, the deliberately
    unpublished style guide) becomes a GitHub URL so it still works; and a link
    to a ``docs/user/*.md`` that doesn't exist is recorded as broken — the app
    surfaces that case as ``GuideMissingLink`` rather than pretending it is an
    external link, and here it fails the build.

    Every link that resolves to a **path inside the repository** is verified
    against the working tree: the target must exist, and a directory gets a
    ``tree/`` URL while a file gets ``blob/``. GitHub 301-redirects
    ``blob/<ref>/<dir>`` to ``tree/``, so the old blanket ``blob/`` was not
    broken — but pointing straight at the right form skips the redirect, and
    stat'ing the target is what catches a typo like ``../design/serch.md``
    before it ships as a live 404.

    Absolute URLs (``https://…/issues``, ``mailto:``) are not repo paths: they
    are passed through untouched for ``sanitize_href`` to vet, never stat'ed.
    """

    def __init__(
        self, source_doc: str, published: dict[str, str], repo_root: Path
    ) -> None:
        self.source_doc = source_doc
        self.published = published
        self.repo_root = repo_root
        self.refs: list[LinkRef] = []

    def _repo_url(
        self, repo_path: str, fragment: Optional[str], *, directory: bool
    ) -> str:
        if not repo_path:
            url = REPO_URL
        else:
            base = REPO_TREE_BASE if directory else REPO_BLOB_BASE
            url = f"{base}/{repo_path}"
        return f"{url}#{fragment}" if fragment else url

    def _note(self, href: str, problem: str) -> None:
        self.refs.append(LinkRef(self.source_doc, href, problem=problem))

    def __call__(self, href: str) -> Optional[str]:
        trimmed = href.strip()
        if not trimmed:
            return None

        if re.match(r"^[A-Za-z][A-Za-z0-9+.\-]*:", trimmed):
            return trimmed  # absolute URL; sanitize_href decides if it may ship

        path, fragment = _split_fragment(trimmed)

        if not path:
            # A pure `#anchor` stays on this page.
            self.refs.append(
                LinkRef(self.source_doc, trimmed, self.published[self.source_doc], fragment)
            )
            return f"#{fragment}" if fragment else None

        base_dir = f"{USER_DOCS_REPO_DIR}/{self.source_doc}".rsplit("/", 1)[0]
        resolved = _normalize_repo_path(f"{base_dir}/{path}")

        prefix = f"{USER_DOCS_REPO_DIR}/"
        if resolved.startswith(prefix) and resolved.endswith(".md"):
            doc = resolved[len(prefix) :]
            page = self.published.get(doc)
            if page is not None:
                self.refs.append(LinkRef(self.source_doc, trimmed, page, fragment))
                return f"{page}#{fragment}" if fragment else page
            if doc not in EXCLUDED_GUIDES:
                # A guide that simply isn't there — almost always a typo or a
                # rename. Report it once here (rather than again as a missing
                # repo path below) and still emit a URL so the page renders.
                self._note(
                    trimmed,
                    f"points at docs/user/{doc}, which is not a published guide",
                )
                return self._repo_url(resolved, fragment, directory=False)
            # An excluded guide (style-guide.md) still has to exist; fall
            # through so a rename is caught like any other repo path.

        if not resolved:
            return REPO_URL  # a link to the repository root

        if resolved == ".." or resolved.startswith("../"):
            self._note(trimmed, "resolves outside the repository")
            return None

        target = self.repo_root / resolved
        try:
            inside = target.resolve().is_relative_to(self.repo_root.resolve())
        except (OSError, ValueError):
            inside = False
        if not inside:
            # A symlink or an odd path that leaves the tree: never stat further.
            self._note(trimmed, "resolves outside the repository")
            return None

        if target.is_dir():
            return self._repo_url(resolved, fragment, directory=True)
        if not target.exists():
            self._note(
                trimmed, f"points at {resolved}, which does not exist in the repository"
            )
        return self._repo_url(resolved, fragment, directory=False)


# ---------------------------------------------------------------------------
# Page shell
# ---------------------------------------------------------------------------


@dataclass
class Guide:
    doc: str
    page: str
    title: str
    summary: str
    body: str
    anchors: set[str] = field(default_factory=set)
    refs: list[LinkRef] = field(default_factory=list)
    duplicate_anchors: list[tuple[str, str]] = field(default_factory=list)

    @property
    def nav_label(self) -> str:
        """A short label for the sidebar.

        Some guides carry a subtitle in their H1 ("Dialect: put the app in your
        own words"); the sidebar wants the noun the hub uses for it.
        """
        head = self.title.split(":", 1)[0].strip()
        return head if head else self.title


_TAG_RE = re.compile(r"<[^>]+>")


def _summarize(body_html: str, limit: int = 155) -> str:
    """A plain-text meta description from the first rendered paragraph."""
    match = re.search(r"<p>(.*?)</p>", body_html, re.S)
    if not match:
        return "Caller's Compendium user guide."
    text = html_module.unescape(_TAG_RE.sub("", match.group(1)))
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    clipped = text[:limit].rsplit(" ", 1)[0]
    return f"{clipped}…"


def _nav_order(guides: list[str], hub_source: str) -> list[str]:
    """Guide order for the sidebar, taken from the hub's own link order.

    The hub (``docs/user/README.md``) is the curated front door, so it — not
    this script — decides the reading order. Anything the hub doesn't link is
    appended alphabetically so a new guide still shows up.
    """
    ordered: list[str] = []
    for match in re.finditer(r"\]\(([^)\s]+)\)", hub_source):
        target = _split_fragment(match.group(1).strip())[0]
        if "/" in target or not target.endswith(".md"):
            continue
        if target in guides and target != HUB_DOC and target not in ordered:
            ordered.append(target)
    ordered += [
        doc for doc in guides if doc != HUB_DOC and doc not in ordered
    ]
    return ordered


def _head(title: str, description: str, page: str) -> str:
    full_title = (
        "User guide — Caller's Compendium"
        if page == "index.html"
        else f"{title} — Caller's Compendium user guide"
    )
    canonical = f"{SITE_URL}guide/{'' if page == 'index.html' else page}"
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{escape_text(full_title)}</title>
  <meta name="description" content="{escape_attr(description)}" />
  <link rel="canonical" href="{escape_attr(canonical)}" />
  <link rel="icon" href="../assets/favicon.svg" type="image/svg+xml" />
  <link rel="stylesheet" href="../styles.css" />

  <!-- Open Graph / social preview -->
  <meta property="og:type" content="article" />
  <meta property="og:title" content="{escape_attr(full_title)}" />
  <meta property="og:description" content="{escape_attr(description)}" />
  <meta property="og:url" content="{escape_attr(canonical)}" />
  <meta property="og:image" content="../assets/social-card.svg" />
  <meta name="twitter:card" content="summary_large_image" />
</head>"""


_HEADER = f"""  <header class="site-header">
    <div class="wrap header-inner">
      <a class="brand" href="../" aria-label="Caller's Compendium home">
        <img src="../assets/logo.svg" alt="" width="34" height="34" />
        <span>Caller's Compendium</span>
      </a>
      <nav class="site-nav" aria-label="Primary">
        <a href="../#features">Features</a>
        <a href="../#screenshots">Screenshots</a>
        <a href="../#downloads">Download</a>
        <a href="../#beta">Beta</a>
        <a href="./">User guide</a>
        <a href="{REPO_URL}" rel="noopener">GitHub</a>
      </nav>
    </div>
  </header>"""


_FOOTER = f"""  <footer class="site-footer">
    <div class="wrap footer-inner">
      <div class="footer-brand">
        <img src="../assets/logo.svg" alt="" width="28" height="28" />
        <div>
          <p class="footer-name">Caller's Compendium</p>
          <p class="tiny">Open-source, local-first software for dance callers.</p>
        </div>
      </div>
      <nav class="footer-links" aria-label="Footer">
        <a href="../">Home</a>
        <a href="./">User guide</a>
        <a href="{REPO_URL}" rel="noopener">Source code</a>
        <a href="{REPO_URL}/releases" rel="noopener">Releases</a>
        <a href="../privacy/">Privacy</a>
        <a href="{REPO_URL}/blob/main/LICENSE" rel="noopener">License (AGPL-3.0)</a>
        <a href="mailto:{CONTACT_EMAIL}">Contact</a>
      </nav>
    </div>
    <div class="wrap footer-fine">
      <p class="tiny">These pages are generated from
        <a href="{REPO_TREE_BASE}/docs/user" rel="noopener">docs/user/</a> — the same
        Markdown the app reads offline. Spotted something wrong?
        <a href="{REPO_URL}/issues/new/choose" rel="noopener">Tell us</a>.</p>
    </div>
  </footer>"""


def _sidebar(current_page: str, entries: list[tuple[str, str]]) -> str:
    """The guide switcher: site chrome, never part of the rendered Markdown.

    A ``<details>`` disclosure so a narrow screen can fold fifteen links away
    without a line of JavaScript (the site ships none, and the guide pages add
    none). It is ``open`` by default, so the list is there for a reader with CSS
    disabled, with JavaScript off, or on a printout.
    """
    items = [
        '<li><a href="./"'
        + (' aria-current="page"' if current_page == "index.html" else "")
        + ">All guides</a></li>"
    ]
    for page, label in entries:
        current = ' aria-current="page"' if page == current_page else ""
        items.append(
            f'<li><a href="{escape_attr(page)}"{current}>{escape_text(label)}</a></li>'
        )
    return (
        '<nav class="guide-nav" aria-label="User guides">'
        "<details open><summary>User guide</summary>"
        f"<ul>{''.join(items)}</ul></details></nav>"
    )


def _breadcrumb(title: str, page: str) -> str:
    if page == "index.html":
        trail = '<a href="../">Home</a> <span aria-hidden="true">›</span> User guide'
    else:
        trail = (
            '<a href="../">Home</a> <span aria-hidden="true">›</span> '
            f'<a href="./">User guide</a> <span aria-hidden="true">›</span> '
            f"{escape_text(title)}"
        )
    return f'<nav class="guide-breadcrumb" aria-label="Breadcrumb">{trail}</nav>'


def build_page(guide: Guide, entries: list[tuple[str, str]]) -> str:
    # The skip link targets the article, not <main>, so it lands past the guide
    # switcher rather than on top of it. <main id="main"> stays as the landmark.
    # The guide's own `# Heading` is the page's only <h1>; the shell adds none.
    return "\n".join(
        [
            _head(guide.title, guide.summary, guide.page),
            "<body>",
            '  <a class="skip-link" href="#guide-content">Skip to content</a>',
            "",
            _HEADER,
            "",
            '  <main id="main">',
            '    <div class="wrap guide-layout">',
            f"      {_sidebar(guide.page, entries)}",
            '      <article class="guide-body" id="guide-content" tabindex="-1">',
            f"        {_breadcrumb(guide.title, guide.page)}",
            f"        {guide.body}",
            "      </article>",
            "    </div>",
            "  </main>",
            "",
            _FOOTER,
            "</body>",
            "</html>",
            "",
        ]
    )


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------


def render_guides(user_docs: Path = USER_DOCS) -> list[Guide]:
    """Render every published guide to HTML (no files written)."""
    docs = discover_guides(user_docs)
    published = {doc: output_name(doc) for doc in docs}
    # `docs/user` sits two levels under the repo root, in the real tree and in
    # the synthetic ones the tests build. Repo-relative link targets are
    # verified against this.
    repo_root = user_docs.resolve().parents[1]

    # Two guides must never map to the same page. The obvious way to trip this
    # is adding `index.md` alongside the `README.md` hub: both want
    # `index.html`, one would silently overwrite the other, and link checking
    # would then validate anchors against the wrong document.
    collisions: dict[str, list[str]] = {}
    for doc, page in published.items():
        collisions.setdefault(page, []).append(doc)
    for page, docs_for_page in sorted(collisions.items()):
        if len(docs_for_page) > 1:
            names = ", ".join(f"docs/user/{doc}" for doc in sorted(docs_for_page))
            _fail(
                f"{names} would all publish as guide/{page}. "
                f"Rename all but one ({HUB_DOC} is the guide hub and owns "
                f"guide/index.html)."
            )

    guides: list[Guide] = []
    for doc in docs:
        source = (user_docs / doc).read_text(encoding="utf-8")
        resolver = GuideLinkResolver(doc, published, repo_root)
        image_dir = user_docs / "images"

        def image_resolver(href: str, *, source_doc: str = doc) -> Optional[str]:
            if not href or href.startswith(("/", "\\", "#")):
                return None
            candidate = (user_docs / source_doc).parent / href
            try:
                relative = candidate.resolve().relative_to(image_dir.resolve())
            except ValueError:
                return None
            if not (image_dir / relative).is_file():
                return None
            return f"images/{relative.as_posix()}"

        result = render(
            source,
            link_resolver=resolver,
            image_resolver=image_resolver,
        )
        title = result.title or doc[: -len(".md")].replace("-", " ").capitalize()
        guides.append(
            Guide(
                doc=doc,
                page=published[doc],
                title=title,
                summary=_summarize(result.html),
                body=result.html,
                anchors=result.anchors,
                refs=resolver.refs,
                duplicate_anchors=[
                    (heading.anchor, heading.text)
                    for heading in result.duplicate_anchors
                ],
            )
        )
    return guides


def check_anchors(guides: list[Guide]) -> list[str]:
    """No two headings in a guide may slug to the same anchor. Returns errors.

    GitHub would dedup with a ``-1`` suffix and the in-app reader lets the last
    heading win, so a collision means one ``#fragment`` points at three
    different places. Fail and let the author retitle the heading instead.
    """
    errors: list[str] = []
    for guide in guides:
        for anchor, text in guide.duplicate_anchors:
            errors.append(
                f"docs/user/{guide.doc}: the heading \"{text}\" repeats the "
                f"anchor #{anchor} — rename one of them so every cross-link "
                f"lands somewhere unambiguous."
            )
    return errors


def check_links(guides: list[Guide]) -> list[str]:
    """Every link a guide emits must resolve. Returns errors.

    Three kinds are checked, all naming the source ``.md`` and the link exactly
    as it was authored:

    * a link to another published guide, and its ``#fragment``;
    * a link to a ``docs/user/*.md`` that isn't published (a typo or a rename);
    * a link to any other path **inside the repository**, which must exist on
      disk — so ``../design/serch.md`` fails here instead of shipping as a live
      404 on GitHub.

    Absolute URLs (``https://…/issues``, ``mailto:``) are not repo paths and are
    deliberately left alone; verifying those would need the network.
    """
    anchors = {guide.page: guide.anchors for guide in guides}
    errors: list[str] = []
    for guide in guides:
        for ref in guide.refs:
            if ref.problem is not None:
                errors.append(
                    f"docs/user/{guide.doc}: link {ref.href} {ref.problem}"
                )
                continue
            if ref.target_page is None:
                continue
            if ref.fragment and ref.fragment not in anchors[ref.target_page]:
                errors.append(
                    f"docs/user/{guide.doc}: link {ref.href} has no matching "
                    f"heading (no #{ref.fragment} in {ref.target_page})"
                )
    return errors


def check_guides(guides: list[Guide]) -> list[str]:
    """All build-blocking problems in the rendered guide set."""
    return check_anchors(guides) + check_links(guides)


_SITE_GUIDE_HREF = re.compile(r'href="(guide/[^"#]*)(#[^"]*)?"')

# Any GitHub blob/tree URL for this repo, wherever it appears in the built site.
_REPO_URL_RE = re.compile(re.escape(REPO_URL) + r"/(blob|tree)/main/([^\"'#\s>]*)")


def check_repo_urls(out: Path, repo_root: Path = REPO_ROOT) -> list[str]:
    """Every repo URL in the *built site* must match the working tree.

    A corpus-level backstop over the rendered HTML rather than over the
    resolver's return values, because the page shell (header, footer,
    breadcrumb) writes repo links directly and never goes through
    :class:`GuideLinkResolver` — so the ``tree/``-vs-``blob/`` rule and the
    existence check would otherwise not apply to them. The landing and privacy
    pages copied into the site are covered too.

    Asserts the property, not examples: for every ``blob``/``tree`` URL, the
    path exists, and ``blob`` means file while ``tree`` means directory.
    """
    seen: dict[tuple[str, str], str] = {}
    for page in sorted(out.rglob("*.html")):
        rel = page.relative_to(out).as_posix()
        for kind, raw in _REPO_URL_RE.findall(page.read_text(encoding="utf-8")):
            path = html_module.unescape(raw).rstrip("/")
            if path:
                seen.setdefault((kind, path), rel)

    errors: list[str] = []
    for (kind, path), page in sorted(seen.items()):
        url = f"{REPO_URL}/{kind}/main/{path}"
        target = repo_root / path
        try:
            inside = target.resolve().is_relative_to(repo_root.resolve())
        except (OSError, ValueError):
            inside = False
        if path == ".." or path.startswith("../") or not inside:
            errors.append(f"{page}: {url} does not resolve inside the repository")
            continue
        if not target.exists():
            errors.append(
                f"{page}: {url} points at {path}, which does not exist in the repository"
            )
            continue
        if target.is_dir() and kind != "tree":
            errors.append(f"{page}: {url} is a directory and must use tree/, not blob/")
        elif target.is_file() and kind != "blob":
            errors.append(f"{page}: {url} is a file and must use blob/, not tree/")
    return errors


def check_site_links(out: Path, guides: list[Guide]) -> list[str]:
    """Hand-written ``guide/…`` links on the rest of the site must resolve.

    ``site/index.html`` links straight at ten guide pages, so renaming or
    removing a guide would silently 404 the home page. Those links live outside
    ``docs/user/`` and so are invisible to :func:`check_links`; check them here
    against what was actually rendered.
    """
    pages = {guide.page for guide in guides}
    anchors = {guide.page: guide.anchors for guide in guides}
    errors: list[str] = []
    for source in sorted(out.rglob("*.html")):
        if source.parent == out / "guide":
            continue  # already covered by check_links
        rel = source.relative_to(out).as_posix()
        for target, fragment in _SITE_GUIDE_HREF.findall(source.read_text("utf-8")):
            page = target[len("guide/") :] or "index.html"
            if page not in pages:
                errors.append(
                    f"site/{rel}: links to {target}, which is not a rendered guide"
                )
                continue
            anchor = fragment[1:] if fragment else ""
            if anchor and anchor not in anchors[page]:
                errors.append(
                    f"site/{rel}: link {target}{fragment} has no matching heading"
                )
    return errors


def _guard_out_dir(out: Path) -> None:
    """Only ever delete a directory we can prove is disposable.

    ``build_site`` wipes ``out`` before writing, so this is an **allow-list**,
    not a blocklist: the directory must not exist yet, be empty, or sit
    **strictly below** ``build/`` or the system temp directory.

    Strictly below matters. Those two roots are *containers* of build outputs,
    never outputs themselves: ``--out build`` would wipe every other build
    product beside the site, and ``--out "$TMPDIR"`` would wipe the whole
    per-user temp directory — on Linux CI ``tempfile.gettempdir()`` is literally
    ``/tmp``, so that would take other processes' state with it. They are
    refused explicitly, before the "empty directory" allowance, so the answer
    doesn't depend on whether they happen to be empty right now.
    """
    resolved = out.resolve()
    safe_roots = (
        (REPO_ROOT / "build").resolve(),
        Path(tempfile.gettempdir()).resolve(),
    )

    if (
        resolved == Path(resolved.anchor)
        or resolved == REPO_ROOT.resolve()
        or resolved in safe_roots
    ):
        _fail(
            f"refusing to use a protected path as --out: {resolved} "
            f"(use a subdirectory, e.g. build/site)"
        )
    if not resolved.exists():
        return  # nothing to destroy
    if not resolved.is_dir():
        _fail(f"--out exists and is not a directory: {resolved}")

    for root in safe_roots:
        if root in resolved.parents:
            return
    if not any(resolved.iterdir()):
        return  # empty: safe to replace
    _fail(
        f"refusing to erase {resolved}: --out must be a new or empty "
        f"directory, or sit below build/ or a temp directory."
    )


def _stage_image_assets(source: Path, target: Path) -> None:
    """Copy regular image assets without dereferencing repository symlinks."""
    target.mkdir(parents=True, exist_ok=True)
    for asset in sorted(source.iterdir()):
        if asset.is_symlink():
            _fail(f"refusing to publish symlinked image asset: {asset}")
        if asset.is_file():
            shutil.copy2(asset, target / asset.name)


def build_site(out: Path, site_dir: Path = SITE_DIR, user_docs: Path = USER_DOCS) -> list[Guide]:
    """Stage a complete site (``site/`` + rendered ``guide/``) into ``out``."""
    if not (site_dir / "index.html").is_file():
        _fail(f"missing landing page: {site_dir / 'index.html'}")

    guides = render_guides(user_docs)
    hub_source = (user_docs / HUB_DOC).read_text(encoding="utf-8")
    by_doc = {guide.doc: guide for guide in guides}
    entries = [
        (by_doc[doc].page, by_doc[doc].nav_label)
        for doc in _nav_order([guide.doc for guide in guides], hub_source)
    ]

    _guard_out_dir(out)
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(site_dir, out)

    guide_dir = (out / "guide").resolve()
    guide_dir.mkdir(parents=True, exist_ok=True)
    image_source = user_docs / "images"
    if image_source.is_dir():
        _stage_image_assets(image_source, guide_dir / "images")
    for guide in guides:
        target = (guide_dir / guide.page).resolve()
        if target.parent != guide_dir:
            _fail(f"refusing to write outside {guide_dir}: {target}")
        target.write_text(build_page(guide, entries), encoding="utf-8")
    return guides


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=(
            "directory to stage the complete site into (default: build/site). "
            "It is erased and rewritten, so it must be new, empty, or sit below "
            "build/ or a temp directory — never build/ or $TMPDIR themselves."
        ),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="render into a temporary directory to validate links; no writes.",
    )
    args = parser.parse_args(argv)

    def report(errors: list[str]) -> None:
        for error in errors:
            print(f"::error::{error}")
        print(
            "::error::the user guides did not pass their integrity check — "
            "fix the sources listed above."
        )

    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "site"
            guides = build_site(out)
            errors = (
                check_guides(guides)
                + check_site_links(out, guides)
                + check_repo_urls(out)
            )
            if errors:
                report(errors)
                return 1
            print(f"OK: {len(guides)} user guides render with all links resolving.")
            return 0

    guides = build_site(args.out)
    errors = (
        check_guides(guides)
        + check_site_links(args.out, guides)
        + check_repo_urls(args.out)
    )
    if errors:
        report(errors)
        return 1

    try:
        shown = args.out.resolve().relative_to(REPO_ROOT)
    except ValueError:
        shown = args.out.resolve()
    print(f"Rendered {len(guides)} user guides into {shown}/guide/ (site staged in {shown}/).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
