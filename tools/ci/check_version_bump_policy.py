#!/usr/bin/env python3
"""Version-bump policy gate: do not bump a versioned format that is already vNext.

``CONTRIBUTING.md`` ("Versioned formats: bank changes in the unreleased vNext")
says that when the latest release tag carries an older value of a versioned
constant than ``main`` does, ``main``'s value is the unreleased *vNext*: a change
amends it rather than bumping again, so every unreleased change ships under one
number. "Bump only when the tag's value matches ``main``'s."

For each of the constants in that table, this compares three commits --
the latest release tag, the PR's base, and its head:

====================================  ==========================================
base == head                          pass: no bump
base == tag, head > base              pass: the first bump after a release
base > tag,  head > base              FAIL: base is already vNext; amend it
head < base                           FAIL: a version never goes down
base < tag                            exit 2: base is behind the release
any value unreadable at base or head  exit 2: never a pass
tag has no such constant              treated as "not shipped": base is vNext
====================================  ==========================================

Each constant is judged on its own: bumping one does not excuse another.

What this cannot see, and says so: an *amend* of vNext (the constant does not
move) is indistinguishable from an unrelated change, so amending a ledger entry
and its tests stays on the author. Only the second *bump* is observable.

The tag is the only reference. A server deployed ahead of release does not make
vNext shipped (``CONTRIBUTING.md``, "The wire version needs one more step"), so
nothing here asks what is deployed.

Usage:
    check_version_bump_policy.py <base_ref> [head_ref] [--tag <ref>]

``head_ref`` defaults to ``HEAD``. ``--tag`` defaults to the newest ``v*`` tag by
creation date, the same selection ``CONTRIBUTING.md``'s hand check uses (tags
created in the same second tie, and git then orders them by name). Exit
codes: 0 = policy held, 1 = a bump broke it, 2 = a usage or git error or an
unreadable input, which must never be mistaken for "nothing to check".
"""

from __future__ import annotations

import sys
from dataclasses import dataclass

from check_version_history import _const_int, _git, _require_commit

CORE_LIB = "packages/compendium_core/lib/src"


@dataclass(frozen=True)
class Constant:
    """One versioned format and the file that declares it."""

    name: str
    source: str


# The rows of CONTRIBUTING.md's versioned-formats table. Adding a constant here
# extends the vNext policy, which is the maintainer's call, not a tooling one
# (ecdTaxonomyVersion was added on the maintainer's go-ahead, #2254;
# squareTaxonomyVersion on the maintainer's approval of pre-release audit
# finding H-06). The same five are the ledgers check_version_history.py gates.
CONSTANTS = (
    Constant("kCompendiumSchemaVersion", f"{CORE_LIB}/storage/database.dart"),
    Constant("contraTaxonomyVersion", f"{CORE_LIB}/taxonomy/contra_taxonomy.dart"),
    Constant("syncWireVersion", f"{CORE_LIB}/sync/sync_codec.dart"),
    Constant("ecdTaxonomyVersion", f"{CORE_LIB}/taxonomy/ecd_taxonomy.dart"),
    Constant("squareTaxonomyVersion", f"{CORE_LIB}/taxonomy/square_taxonomy.dart"),
)

OK, FAIL, UNANSWERABLE = 0, 1, 2


def latest_release_tag() -> str | None:
    """The newest ``v*`` tag by creation date, or None when there is none."""
    res = _git(
        "for-each-ref",
        "--sort=-creatordate",
        "--count=1",
        "--format=%(refname:short)",
        "refs/tags/v*",
    )
    if res.returncode != 0:
        return None
    return res.stdout.strip() or None


def value_at(ref: str, constant: Constant) -> int | None:
    """The constant's value at ``ref``; None when the file or constant is absent."""
    res = _git("show", f"{ref}:{constant.source}")
    if res.returncode != 0:
        return None
    return _const_int(res.stdout, constant.name)


def judge(
    name: str, tag: int | None, base: int | None, head: int | None, labels: tuple[str, str, str]
) -> tuple[int, str]:
    """Apply the policy table to one constant. Pure: no git, no I/O."""
    tag_ref, base_ref, head_ref = labels
    tag_note: str | None = None
    if tag is None and base is not None and head is not None:
        # The release does not declare the constant at all (it was added after the
        # release was cut), so nothing of it has shipped: whatever base carries is
        # the unreleased vNext. A rename at head still reads as unreadable below.
        tag = 0
        tag_note = f"absent from {tag_ref}, so unreleased"
    for what, ref, value in (("base", base_ref, base), ("head", head_ref, head), ("tag", tag_ref, tag)):
        if value is None:
            return UNANSWERABLE, (
                f"{name}: could not read it at the {what} ({ref}); refusing to "
                "call that a pass. A constant that was renamed or whose file "
                "moved must stay readable at base and head."
            )
    assert tag is not None and base is not None and head is not None  # for type checkers
    if base < tag:
        return UNANSWERABLE, (
            f"{name}: base {base_ref} has {base} but release tag {tag_ref} has "
            f"{tag}; the base is behind the release, so the policy cannot be "
            "judged. Update the branch onto current main."
        )
    if head < base:
        return FAIL, (
            f"{name}: {base} at base -> {head} at head. A version never goes down."
        )
    shown = tag_note or f"tag {tag_ref} has {tag}"
    if head == base:
        return OK, f"{name} unchanged ({head}); {shown}."
    if base == tag:
        return OK, (
            f"{name} {base} -> {head}: first bump after release {tag_ref} "
            f"({tag})."
        )
    return FAIL, (
        f"{name} {base} -> {head}, but base already carries {base} while the "
        f"latest release {tag_ref} carries {tag if tag_note is None else 'no such constant'}: base is already the "
        f"unreleased vNext. Amend vNext ({base}) instead of bumping again, and "
        "update its ledger entry and tests. See CONTRIBUTING.md, \"Versioned "
        "formats: bank changes in the unreleased vNext\"."
    )


def parse_args(argv: list[str]) -> tuple[str, str, str | None] | None:
    """(base, head, tag) or None for a usage error."""
    args = list(argv[1:])
    tag: str | None = None
    if "--tag" in args:
        i = args.index("--tag")
        if i + 1 >= len(args) or not args[i + 1].strip():
            return None
        tag = args[i + 1].strip()
        del args[i : i + 2]
    if not 1 <= len(args) <= 2 or not args[0].strip():
        return None
    # A head ref that is present but blank is an unset CI variable, not a request
    # for the default; defaulting there would check a different pair of commits.
    if len(args) == 2 and not args[1].strip():
        return None
    return args[0].strip(), args[1].strip() if len(args) == 2 else "HEAD", tag


def main(argv: list[str]) -> int:
    parsed = parse_args(argv)
    if parsed is None:
        print("::error::usage: check_version_bump_policy.py <base_ref> [head_ref] [--tag <ref>]")
        return UNANSWERABLE
    base, head, tag = parsed
    if tag is None:
        tag = latest_release_tag()
        if tag is None:
            print(
                "::error::no v* release tag found. Fetch tags (checkout "
                "fetch-depth: 0 and `git fetch --tags`); without one the "
                "policy cannot be judged."
            )
            return UNANSWERABLE
    for ref in (base, head, tag):
        _require_commit(ref)

    worst = OK
    for constant in CONSTANTS:
        code, message = judge(
            constant.name,
            value_at(tag, constant),
            value_at(base, constant),
            value_at(head, constant),
            (tag, base, head),
        )
        print(("OK: " if code == OK else "::error::") + message)
        # A definite violation outranks "could not tell": it is the actionable one.
        if code == FAIL or (code == UNANSWERABLE and worst == OK):
            worst = code
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv))
