#!/usr/bin/env python3
"""Generate the DRAFT GitHub Release body from ``app/CHANGELOG.md``.

The release pipeline (``.github/workflows/release.yml``) used to write a static,
generic notes blurb via a heredoc. This tool replaces that: it extracts the
``## [x.y.z]`` section for the release version out of the in-repo CHANGELOG and
emits it as the release-notes body, so every release gets meaningful notes that
are maintained alongside the code (ADR-002 / Keep a Changelog).

Behaviour:

* Selected releases are exactly stable ``vX.Y.Z`` or bare beta ``vX.Y.Z-beta``.
  Both use the shared CHANGELOG heading ``## [X.Y.Z]``.
* For a bare beta (``--channel beta``) a clear **Beta / pre-release** banner is
  prepended so ``-beta`` never produces misleading stable wording.
* A short footer is always appended: it states the per-platform signing
  posture, tells users to verify against ``SHA256SUMS``, and notes that a
  maintainer publishes the draft after review. The macOS sentence is
  **conditional on the actual signing outcome** (``--macos-signing``): macOS is
  described as **Developer ID-signed & notarized** only when the pipeline
  actually signed it (the Apple secrets were configured — ADR-002 §6);
  otherwise all three desktops are reported as **unsigned**, so the notes never
  over-claim provenance.
* Every selected release requires its matching CHANGELOG section. ``--check``
  and normal note emission both fail before a draft can be created when it is
  absent.

This module is intentionally pure-stdlib and Flutter-free (mirroring
``gen_release_metadata.py``) so it stays reviewable and unit-testable.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Footer appended to every generated body. The verify/publish reminder
# (``_VERIFY_LINE``) is invariant; the signing sentence above it is chosen at
# runtime from the ACTUAL macOS signing outcome (see ``_signing_line``) so the
# notes never over-claim provenance. macOS signing is gated on the Apple secrets
# (ADR-002 §6); when they're absent the macOS leg ships UNSIGNED like
# Windows/Linux, and the footer says exactly that.
_VERIFY_LINE = (
    "Verify downloads against `SHA256SUMS`. A maintainer publishes this draft "
    "after review."
)
_CORE = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
_STABLE_VERSION_RE = re.compile(rf"^{_CORE}$")
_BETA_VERSION_RE = re.compile(rf"^{_CORE}-beta$")


def _signing_line(*, macos_signed: bool) -> str:
    """Per-platform signing sentence, honest about the macOS outcome."""
    if macos_signed:
        return (
            "Windows and Linux desktop builds are **unsigned**; macOS is "
            "**Developer ID-signed & notarized** (see ADR-002 §6)."
        )
    return (
        "Windows, Linux, and macOS desktop builds are **unsigned** this "
        "release — macOS Developer ID signing + notarization activates once "
        "the Apple secrets are configured (see ADR-002 §6)."
    )


def _footer(*, macos_signed: bool) -> str:
    return f"{_signing_line(macos_signed=macos_signed)}\n{_VERIFY_LINE}"


def _core_version(version: str) -> str:
    """Return the core of a validated selected release version."""
    return version.removesuffix("-beta")


def validate_release(*, version: str, tag: str, channel: str) -> str:
    """Validate one selected release identity and return its SemVer core."""
    if channel == "stable" and _STABLE_VERSION_RE.fullmatch(version):
        expected_tag = f"v{version}"
    elif channel == "beta" and _BETA_VERSION_RE.fullmatch(version):
        expected_tag = f"v{version}"
    else:
        raise ValueError(
            "release must be stable X.Y.Z/vX.Y.Z or bare beta "
            "X.Y.Z-beta/vX.Y.Z-beta with a valid no-leading-zero core"
        )
    if tag != expected_tag:
        raise ValueError(
            f"tag '{tag}' does not match validated {channel} version '{version}'"
        )
    return _core_version(version)


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


def check_section(
    *,
    version: str,
    tag: str,
    channel: str,
    changelog_text: str,
) -> tuple[bool, str]:
    """Presence check for the ``meta`` job's fail-fast guard.

    Returns ``(ok, message)``. Every selected release requires the shared
    ``## [x.y.z]`` section before the build matrix runs.
    """
    try:
        core = validate_release(version=version, tag=tag, channel=channel)
    except ValueError as error:
        return False, str(error)
    present = extract_section(changelog_text, core) is not None
    if not present:
        return False, (
            f"no '## [{core}]' section in app/CHANGELOG.md for {channel} release "
            f"{version}; promote '## [Unreleased]' -> '## [{core}] - <date>' "
            "(with no version suffix) before tagging."
        )
    return True, f"OK: CHANGELOG has a '## [{core}]' section."


def build_notes(
    *,
    version: str,
    tag: str,
    channel: str,
    changelog_text: str,
    macos_signed: bool = False,
) -> tuple[str, bool]:
    """Build the release-notes body.

    ``macos_signed`` selects the footer's macOS signing sentence: True only when
    the pipeline actually Developer ID-signed + notarized the macOS artifacts
    (the Apple secrets were configured). It defaults to False so the notes never
    over-claim provenance when the signing outcome is unknown.

    Returns ``(body, True)`` after validating the required CHANGELOG section.
    """
    core = validate_release(version=version, tag=tag, channel=channel)
    section = extract_section(changelog_text, core)
    is_beta = channel == "beta"

    blocks: list[str] = []
    if is_beta:
        blocks.append(_beta_banner(tag))

    if section is None:
        raise ValueError(f"no '## [{core}]' section in app/CHANGELOG.md")
    blocks.append(section)

    blocks.append("---")
    blocks.append(_footer(macos_signed=macos_signed))

    body = "\n\n".join(blocks).rstrip() + "\n"
    return body, section is not None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--version",
        required=True,
        help="release version: X.Y.Z or bare beta X.Y.Z-beta",
    )
    ap.add_argument("--tag", required=True, help="git tag, e.g. v0.1.0-beta")
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
    ap.add_argument(
        "--macos-signing",
        choices=["configured", "missing"],
        default="missing",
        help="the macOS signing outcome for this release: 'configured' when the "
        "pipeline Developer ID-signed + notarized the macOS artifacts (Apple "
        "secrets present), else 'missing'. Selects the footer's macOS signing "
        "sentence so the notes never over-claim provenance. Default: missing.",
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="presence-check mode: require the selected release's CHANGELOG "
        "section and emit no notes body.",
    )
    args = ap.parse_args(argv)

    changelog: Path = args.changelog
    if not changelog.is_file():
        raise SystemExit(f"::error::changelog not found: {changelog}")

    changelog_text = changelog.read_text(encoding="utf-8")

    if args.check:
        ok, message = check_section(
            version=args.version,
            tag=args.tag,
            channel=args.channel,
            changelog_text=changelog_text,
        )
        if not ok:
            print(f"::error::{message}", file=sys.stderr)
            return 1
        print(message)
        return 0

    try:
        body, _ = build_notes(
            version=args.version,
            tag=args.tag,
            channel=args.channel,
            changelog_text=changelog_text,
            macos_signed=args.macos_signing == "configured",
        )
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    if args.output is not None:
        args.output.write_text(body, encoding="utf-8")
        print(f"Wrote {args.output} ({len(body.splitlines())} lines)")
    else:
        sys.stdout.write(body)

    return 0


if __name__ == "__main__":
    sys.exit(main())
