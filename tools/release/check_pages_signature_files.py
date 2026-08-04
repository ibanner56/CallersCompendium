#!/usr/bin/env python3
"""Assert the published gh-pages invariant: every ``*.json`` at the site root
has a sibling ``*.json.sig`` file.

This checks **presence** of the signature file, not its cryptographic validity.
It closes the incident pattern from #714: a missing `.sig` file causes the
in-app update client to fail closed and silently report "no update" to all
users on that channel. Verifying the signature itself (against
``kUpdateManifestPublicKey``) requires Ed25519 tooling outside the Python
stdlib and is tracked as a follow-up.

Pure-stdlib, no third-party deps, offline once the target directory is
available. Run directly::

    python3 tools/release/check_pages_signature_files.py <path-to-gh-pages-root>

The check covers the root of the ``gh-pages`` branch only (not subdirectories)
because channel manifests (``stable.json``, ``beta.json``, …) are published at
the branch root while the ``guide/`` subtree and other assets under
subdirectories contain only HTML/CSS. A ``*.json`` at the root without a
sibling ``*.json.sig`` means the in-app update client will 404 on the
signature, fail closed, and silently report "no update" to every user on that
channel (issue #714, #759).

Exit codes:
  0   All ``*.json`` files have a sibling ``*.json.sig`` (invariant holds).
  1   One or more ``*.json`` files are missing their ``.sig`` (invariant violated).
  2   Usage error (wrong arguments, directory not found).
"""

from __future__ import annotations

import sys
from pathlib import Path


def check(root: Path) -> list[str]:
    """Return a list of ``*.json`` filenames that lack a sibling ``*.json.sig``.

    Only the top level of *root* is scanned — subdirectories are skipped
    because only the channel manifests (at the branch root) are subject to the
    invariant.
    """
    missing: list[str] = []
    for json_file in sorted(root.glob("*.json")):
        sig_file = json_file.with_suffix(".json.sig")
        if not sig_file.exists():
            missing.append(json_file.name)
    return missing


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) != 1:
        print(
            "usage: check_pages_signature_files.py <path-to-gh-pages-root>",
            file=sys.stderr,
        )
        return 2

    root = Path(args[0])
    if not root.is_dir():
        print(f"::error::directory not found: {root}", file=sys.stderr)
        return 2

    missing = check(root)

    if not missing:
        json_count = sum(1 for _ in root.glob("*.json"))
        print(f"OK: all {json_count} *.json file(s) at the gh-pages root have a sibling *.json.sig")
        return 0

    for name in missing:
        print(f"::error::FAIL: {name} has no sibling {name}.sig — in-app update checks will fail closed for this channel")
    print(
        f"\n{len(missing)} file(s) missing a .sig file. "
        "The in-app update client returns 'no update' when the signature file is absent (issue #714).",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
