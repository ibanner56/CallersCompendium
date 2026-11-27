#!/usr/bin/env python3
"""Guard the hand-maintained privacy-policy copies.

The page and its Markdown mirror must agree on their dates and, word for word,
on everything from the effective date to the last section.
"""

from __future__ import annotations

import difflib
import html
import re
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
POLICY_FILES = (
    ROOT / "docs" / "dev" / "store-submission" / "privacy-policy.md",
    ROOT / "site" / "privacy" / "index.html",
)
REQUIRED_PHRASES = (
    "operator can read the plaintext",
    "break-glass access",
    "timestamp-only aggregate",
    "freeform venue notes",
    "street address",
    "contact name",
    "random identifier for each connected device",
)
FORBIDDEN_PHRASES = (
    "before it ships",
    "device sync (planned)",
    "current release has no cloud sync",
)


def policy_text(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".html":
        text = re.sub(r"<[^>]+>", " ", text)
        text = html.unescape(text)
    return " ".join(text.lower().split())


def policy_words(path: Path) -> list[str]:
    """The policy's words from its effective date to its last section.

    Markup is removed (Markdown emphasis, list bullets, headings, links and
    autolinks; HTML tags and entities), link targets are reduced to the text a
    reader sees, and a space before punctuation is closed up, so two copies that
    say the same thing give the same words. The title is left out: the page and
    the mirror word their headings differently on purpose.
    """
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".html":
        text = text[text.index("Effective date:") : text.index("</main>")]
        text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    else:
        text = text[text.index("Effective date:") :]
        text = re.sub(r"^\s*(?:#+|-)\s+", "", text, flags=re.M)
        text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
        text = re.sub(r"<(https?://[^>]+)>", r"\1", text)
        text = text.replace("**", "").replace("`", "")
    text = re.sub(r"https?://", "", text)
    text = re.sub(r"\s+([.,;:)])", r"\1", text)
    return text.split()


def copies_differ(a: list[str], b: list[str]) -> list[str]:
    """Each run of words where the two copies differ, as `mirror | page`."""
    return [
        f"{' '.join(a[i1:i2])!r} | {' '.join(b[j1:j2])!r}"
        for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes()
        if op != "equal"
    ]


def main() -> None:
    texts = {path: policy_text(path) for path in POLICY_FILES}
    dates = {}
    for label in ("effective date", "last updated"):
        date_re = re.compile(label + r":\**\s*([a-z]+ \d{1,2}, \d{4})")
        found = {}
        for path, text in texts.items():
            matches = date_re.findall(text)
            assert len(matches) == 1, (
                f"{path} must state exactly one {label}, found {matches}"
            )
            try:
                datetime.strptime(matches[0], "%B %d, %Y")
            except ValueError:
                raise AssertionError(f"{path} has an invalid {label}: {matches[0]}")
            found[path] = matches[0]
        assert len(set(found.values())) == 1, (
            f"policy copies have different {label} values: {found}"
        )
        dates[label] = next(iter(found.values()))
    effective = datetime.strptime(dates["effective date"], "%B %d, %Y")
    updated = datetime.strptime(dates["last updated"], "%B %d, %Y")
    assert updated >= effective, (
        f"last updated {dates['last updated']} precedes "
        f"effective date {dates['effective date']}"
    )

    for path, text in texts.items():
        for phrase in REQUIRED_PHRASES:
            assert phrase in text, f"{path} is missing required disclosure: {phrase}"
        for phrase in FORBIDDEN_PHRASES:
            assert phrase not in text, f"{path} retains obsolete wording: {phrase}"

    mirror, page = (policy_words(path) for path in POLICY_FILES)
    differences = copies_differ(mirror, page)
    assert not differences, (
        "the privacy-policy copies must say the same thing word for word; "
        "they differ at (mirror | page):\n  " + "\n  ".join(differences)
    )
    # Positive control: the comparison must see a one-word change.
    assert copies_differ(mirror, [*page[:-1], "changed"]), "the word comparison sees nothing"

    print(
        "OK: privacy-policy copies agree on effective date "
        f"{dates['effective date']} and last updated {dates['last updated']}"
    )


if __name__ == "__main__":
    main()
