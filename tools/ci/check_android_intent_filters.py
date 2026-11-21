#!/usr/bin/env python3
"""Guard: no web page can launch the app on a local file or content URI.

``app/android/app/src/main/AndroidManifest.xml`` lets other apps hand the app
a CompendiumArchive ``.json`` with ``ACTION_VIEW`` ("Open with" from a file
manager). ``MainActivity.kt`` then opens that URI with ``openInputStream``
**under the app's own identity** and stages the bytes for import. Adding
``android.intent.category.BROWSABLE`` to that filter would let any web page
start the activity on a ``file:`` or ``content:`` URI of its choosing, so a
page could make the app read a file with the app's permissions (post-audit
finding security-6). "Open with" from a file manager does not need
``BROWSABLE``; only a browser-originated launch does.

This parses every ``AndroidManifest.xml`` under ``app/android`` and fails when
an ``<intent-filter>`` that

- declares ``android.intent.action.VIEW``,
- declares ``android.intent.category.BROWSABLE``, and
- accepts the ``file`` or ``content`` scheme

exists anywhere in it. A filter accepts a scheme when one of its ``<data>``
elements names it (a filter's ``<data>`` attributes are merged, so any element
counts), **or** when it declares a ``mimeType`` and no scheme at all: Android
then matches ``content:`` and ``file:`` implicitly. A ``BROWSABLE`` deep link
on ``https`` (or any other scheme) is not this guard's concern.

Usage: ``check_android_intent_filters.py`` (no arguments). Exit 0 when no
filter matches, 1 otherwise.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ANDROID_ROOT = Path("app/android")

_NS = "{http://schemas.android.com/apk/res/android}"
_VIEW = "android.intent.action.VIEW"
_BROWSABLE = "android.intent.category.BROWSABLE"
_LOCAL_SCHEMES = {"file", "content"}


def _names(filt: ET.Element, tag: str) -> set[str]:
    return {
        el.get(f"{_NS}name", "")
        for el in filt.findall(tag)
    }


def local_schemes(filt: ET.Element) -> set[str]:
    """The ``file``/``content`` schemes ``filt`` accepts, explicit or implied."""
    data = filt.findall("data")
    schemes = {(d.get(f"{_NS}scheme") or "").lower() for d in data} - {""}
    if not schemes and any(d.get(f"{_NS}mimeType") for d in data):
        # A typed filter with no scheme matches content: and file: URIs.
        return set(_LOCAL_SCHEMES)
    return schemes & _LOCAL_SCHEMES


def offending_filters(text: str) -> list[str]:
    """Describes each browsable VIEW filter on a local scheme in ``text``."""
    root = ET.fromstring(text)
    found: list[str] = []
    for parent in root.iter():
        for filt in parent.findall("intent-filter"):
            if _VIEW not in _names(filt, "action"):
                continue
            if _BROWSABLE not in _names(filt, "category"):
                continue
            schemes = local_schemes(filt)
            if schemes:
                owner = parent.get(f"{_NS}name") or parent.tag
                found.append(
                    f"{owner}: a VIEW intent filter on "
                    f"{', '.join(sorted(schemes))} is BROWSABLE"
                )
    return found


def manifests(root: Path) -> list[Path]:
    base = root / ANDROID_ROOT
    return sorted(
        p
        for p in base.rglob("AndroidManifest.xml")
        if "build" not in p.relative_to(base).parts
    )


def check(root: Path = REPO_ROOT) -> list[str]:
    paths = manifests(root)
    if not paths:
        return [f"{ANDROID_ROOT}: no AndroidManifest.xml found."]
    errors: list[str] = []
    for path in paths:
        rel = path.relative_to(root)
        for problem in offending_filters(path.read_text(encoding="utf-8")):
            errors.append(
                f"{rel}: {problem}. A web page could then launch the app on a "
                "local file or content URI, which it reads with its own "
                "permissions. Remove android.intent.category.BROWSABLE from "
                "that filter (security-6)."
            )
    return errors


def main() -> int:
    errors = check()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print("OK: no BROWSABLE VIEW intent filter accepts file: or content: URIs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
