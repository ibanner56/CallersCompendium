#!/usr/bin/env python3
"""Guard the hand-maintained privacy-policy copies."""

from __future__ import annotations

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

    print(
        "OK: privacy-policy copies agree on effective date "
        f"{dates['effective date']} and last updated {dates['last updated']}"
    )


if __name__ == "__main__":
    main()
