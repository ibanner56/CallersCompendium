#!/usr/bin/env python3
"""Gate: a release-preparation PR's title names the version it prepares.

``.github/instructions/release-tooling.instructions.md`` requires the PR that
changes ``version:`` in ``app/pubspec.yaml`` to be titled
``docs(release): prepare vX.Y.Z`` (stable) or ``docs(release): prepare
vX.Y.Z-beta`` (beta), never ``chore(release)``. Nothing linted it (#1262 used
``chore(release)``).

What it checks, and what it deliberately does not:

- It applies only to a PR whose head changes the app version relative to the
  PR base. Every other PR passes untouched.
- It checks the **PR title only**. Commits are squash-merged, so the title
  becomes ``main``'s subject; intermediate commits legitimately differ, so their
  subjects are never read.
- The title's ``X.Y.Z`` must equal the head's ``app/pubspec.yaml`` version. The
  pubspec carries the bare core (``0.10.0``) while the title carries the tag form
  (``v0.10.0-beta``); a title naming another version is as wrong as a wrong prefix.

The title arrives in ``PR_TITLE`` (not argv), because a title is attacker-chosen
text and an environment variable is not re-parsed by a shell.

Usage:
    PR_TITLE='docs(release): prepare v0.10.0-beta' check_release_pr_title.py <base_ref> [head_ref]

``head_ref`` defaults to ``HEAD``. Exit codes: 0 = passes or not a release PR,
1 = wrong title, 2 = could not decide (unreadable ref or pubspec, no title).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

PUBSPEC = "app/pubspec.yaml"
_CORE = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
TITLE_RE = re.compile(rf"^docs\(release\): prepare v(?P<core>{_CORE})(?:-beta)?$")
_VERSION_RE = re.compile(rf"^version:\s*(?P<v>{_CORE})\s*$", re.MULTILINE)
EXAMPLE = "docs(release): prepare v0.10.0-beta"


class Undecidable(Exception):
    """The gate cannot decide; the message says why."""


def pubspec_version(text: str) -> str | None:
    match = _VERSION_RE.search(text)
    return match.group("v") if match else None


def judge(title: str, base_version: str | None, head_version: str) -> str | None:
    """The error for a release PR whose title is wrong, else ``None``.

    ``base_version`` is ``None`` when the PR base has no readable version, which
    counts as a change.
    """
    if base_version == head_version:
        return None
    match = TITLE_RE.fullmatch(title)
    if match is None:
        return (
            f"this PR changes the app version to {head_version}, so it is a "
            f"release-preparation PR, and its title {title!r} must be "
            f"`docs(release): prepare vX.Y.Z` or `docs(release): prepare "
            f"vX.Y.Z-beta` (for example {EXAMPLE!r}); never `chore(release)`."
        )
    if match.group("core") != head_version:
        return (
            f"the title names {match.group('core')} but app/pubspec.yaml is "
            f"{head_version}: the title's X.Y.Z must equal the pubspec version."
        )
    return None


def _show(ref: str) -> str | None:
    res = subprocess.run(["git", "show", f"{ref}:{PUBSPEC}"], capture_output=True, text=True)
    if res.returncode != 0:
        return None
    return res.stdout


def decide(title: str, base: str, head: str) -> str | None:
    head_text = _show(head)
    if head_text is None:
        raise Undecidable(f"cannot read {PUBSPEC} at {head}")
    head_version = pubspec_version(head_text)
    if head_version is None:
        raise Undecidable(f"no X.Y.Z `version:` in {PUBSPEC} at {head}")
    verify = subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}"], capture_output=True)
    if verify.returncode != 0:
        raise Undecidable(f"cannot resolve base ref {base}")
    base_text = _show(base)
    base_version = pubspec_version(base_text) if base_text is not None else None
    return judge(title, base_version, head_version)


def main(argv: list[str]) -> int:
    args = argv[1:]
    if not 1 <= len(args) <= 2 or not all(a.strip() for a in args):
        print("::error::usage: PR_TITLE=... check_release_pr_title.py <base_ref> [head_ref]")
        return 2
    title = os.environ.get("PR_TITLE")
    if title is None:
        print("::error::PR_TITLE is not set; the title is what this gate checks.")
        return 2
    try:
        error = decide(title.strip(), args[0].strip(), args[1].strip() if len(args) == 2 else "HEAD")
    except Undecidable as exc:
        print(f"::error::release PR title not checked: {exc}")
        return 2
    if error:
        print(f"::error::{error}")
        return 1
    print("release PR title check: ok (or not a release-preparation PR)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
