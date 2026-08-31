#!/usr/bin/env python3
"""Guard the hand-maintained privacy-policy copies."""

from __future__ import annotations

import html
import re
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


def main() -> None:
    texts = {path: policy_text(path) for path in POLICY_FILES}
    date_re = re.compile(r"effective date:\**\s*([a-z]+ \d{1,2}, \d{4})")
    dates = {m.group(1) for text in texts.values() for m in [date_re.search(text)] if m}
    assert len(dates) == 1, f"policy copies have different effective dates: {dates}"

    for path, text in texts.items():
        for phrase in REQUIRED_PHRASES:
            assert phrase in text, f"{path} is missing required disclosure: {phrase}"
        for phrase in FORBIDDEN_PHRASES:
            assert phrase not in text, f"{path} retains obsolete wording: {phrase}"

    print(f"OK: privacy-policy copies agree on {next(iter(dates))}")


if __name__ == "__main__":
    main()
