#!/usr/bin/env python3
"""Generate the DRAFT GitHub Release body from ``app/CHANGELOG.md``.

The release pipeline (``.github/workflows/release.yml``) used to write a static,
generic notes blurb via a heredoc. This tool replaces that: it extracts the
``## [x.y.z]`` section for the release version out of the in-repo CHANGELOG and
emits it as the release-notes body, so every release gets meaningful notes that
are maintained alongside the code (ADR-002 / Keep a Changelog).

Behaviour:

* The release **version** may carry a prerelease suffix (``0.1.0-rc.3``); the
  CHANGELOG headings use the bare SemVer core (``## [0.1.0]``). We therefore
  match on the core ``x.y.z`` and ignore any ``- <date>`` heading suffix.
* For a prerelease (``--channel beta``) a clear **Beta / pre-release** banner is
  prepended so a ``-beta``/``-rc`` tag can never produce misleading "stable"
  wording.
* A short footer is always appended: the artifacts are UNSIGNED, verify against
  ``SHA256SUMS``, and a maintainer publishes the draft after review.
* If no matching section exists the tool does **not** fail the release (the
  release is a DRAFT, never public); it emits a minimal body with a loud
  "add release notes before publishing" banner and prints a ``::warning::`` so
  the publishing maintainer can't miss it.

This module is intentionally pure-stdlib and Flutter-free (mirroring
``gen_release_metadata.py``) so it stays reviewable and unit-testable.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Footer appended to every generated body. Kept in lock-step with the safety
# wording the pipeline has always shown (see ADR-002 §6).
_FOOTER = (
    "These artifacts are **UNSIGNED** (no code-signing this wave — see "
    "ADR-002 §6).\n"
    "Verify downloads against `SHA256SUMS`. A maintainer publishes this draft "
    "after review."
)


def _core_version(version: str) -> str:
    """Strip a prerelease/build suffix: ``0.1.0-rc.3`` -> ``0.1.0``."""
    return re.split(r"[-+]", version.strip(), maxsplit=1)[0]


def _beta_banner(tag: str) -> str:
    return (
        f"> ⚠️ **Beta / pre-release (`beta` channel).** This is a pre-release "
        f"build (`{tag}`) intended for testing and may be unstable. Use the "
        f"stable channel for production."
    )


def extract_section(changelog: str, core: str) -> str | None:
    """Return the trimmed body of the ``## [core]`` section, or None.

    The heading may be ``## [x.y.z]`` or ``## [x.y.z] - 2026-07-15``. The body
    runs until the next ``##``/``#`` heading or end of file, with surrounding
    blank lines stripped.
    """
    # Match a level-2 heading whose bracketed version equals the core version,
    # optionally followed by a " - <date>" suffix. Anchored per-line.
    heading = re.compile(
        r"^##[ \t]+\[" + re.escape(core) + r"\](?:[ \t]+-.*)?[ \t]*$"
    )
    lines = changelog.splitlines()
    start: int | None = None
    for i, line in enumerate(lines):
        if heading.match(line):
            start = i + 1
            break
    if start is None:
        return None

    body: list[str] = []
    for line in lines[start:]:
        # Any subsequent top-level ("# ") or section ("## ") heading ends it.
        if re.match(r"^#{1,2}[ \t]+\S", line):
            break
        body.append(line)

    # Trim leading/trailing blank lines.
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()

    return "\n".join(body) if body else None


def build_notes(
    *,
    version: str,
    tag: str,
    channel: str,
    changelog_text: str,
) -> tuple[str, bool]:
    """Build the release-notes body.

    Returns ``(body, found)`` where ``found`` is False when no matching
    CHANGELOG section existed (the caller can then emit a ``::warning::``).
    """
    core = _core_version(version)
    section = extract_section(changelog_text, core)
    is_beta = channel == "beta"

    blocks: list[str] = []
    if is_beta:
        blocks.append(_beta_banner(tag))

    if section is not None:
        blocks.append(section)
    else:
        blocks.append(
            f"> ⚠️ **No `## [{core}]` entry found in `app/CHANGELOG.md`.** "
            f"Add release notes for this version before publishing this draft."
        )

    blocks.append("---")
    blocks.append(_FOOTER)

    body = "\n\n".join(blocks).rstrip() + "\n"
    return body, section is not None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--version",
        required=True,
        help="release version (may include a prerelease suffix), e.g. 0.1.0 "
        "or 0.1.0-rc.3",
    )
    ap.add_argument("--tag", required=True, help="git tag, e.g. v0.1.0-rc.3")
    ap.add_argument("--channel", required=True, choices=["stable", "beta"])
    ap.add_argument(
        "--changelog",
        default="app/CHANGELOG.md",
        type=Path,
        help="path to the CHANGELOG (default: app/CHANGELOG.md)",
    )
    ap.add_argument(
        "--output",
        "-o",
        default=None,
        type=Path,
        help="write the notes to this file (default: stdout)",
    )
    args = ap.parse_args(argv)

    changelog: Path = args.changelog
    if not changelog.is_file():
        raise SystemExit(f"::error::changelog not found: {changelog}")

    body, found = build_notes(
        version=args.version,
        tag=args.tag,
        channel=args.channel,
        changelog_text=changelog.read_text(encoding="utf-8"),
    )

    if not found:
        core = _core_version(args.version)
        print(
            f"::warning::no '## [{core}]' section in {changelog}; emitting a "
            f"fallback notes body — add a CHANGELOG entry before publishing.",
            file=sys.stderr,
        )

    if args.output is not None:
        args.output.write_text(body, encoding="utf-8")
        print(f"Wrote {args.output} ({len(body.splitlines())} lines)")
    else:
        sys.stdout.write(body)

    return 0


if __name__ == "__main__":
    sys.exit(main())
