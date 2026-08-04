#!/usr/bin/env python3
"""Assert the published gh-pages invariant: every ``*.json`` at the site root
has a sibling ``*.json.sig`` that is a **valid Ed25519 signature** over the
exact bytes of that manifest, verified against the public key pinned in
``app/lib/src/update/update_config.dart`` (``kUpdateManifestPublicKey``).

This delivers the full invariant from #759: the original title was *"every
``*.json`` has a valid sibling ``*.json.sig``"* and the issue body explicitly
proposed verifying against the pinned key. PR #806 checked presence only; this
script closes the gap (issue #810). A stale ``.sig`` (e.g. from a previous
release beside an updated manifest) causes the in-app update client to fail
closed and silently report "no update" just like a missing one does (issue #714).

The pinned key is read from ``kUpdateManifestPublicKey`` in
``app/lib/src/update/update_config.dart`` at runtime so a key rotation updates
the gate automatically. The gate must never hold its own copy of the key; if
the parse fails, the gate exits with code 2 rather than falling back to a
hardcoded constant.

Requires the ``cryptography`` package::

    python3 -m pip install cryptography==50.0.0

Run directly::

    python3 tools/release/check_pages_signature_files.py <path-to-gh-pages-root>

The check covers the root of the ``gh-pages`` branch only (not subdirectories)
because channel manifests (``stable.json``, ``beta.json``, …) are published at
the branch root while the ``guide/`` subtree contains only HTML/CSS.

Exit codes:
  0   All ``*.json`` files have a valid ``*.json.sig`` (invariant holds).
  1   One or more ``*.json`` files are missing or have an invalid ``.sig``
      (invariant violated).
  2   Usage error (wrong arguments, directory not found, key parse failure).
"""

from __future__ import annotations

import base64
import re
import sys
from pathlib import Path

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature
except ImportError:
    print(
        "::error::the 'cryptography' package is required. "
        "Install it with: python3 -m pip install cryptography==50.0.0",
        file=sys.stderr,
    )
    sys.exit(2)

# Matches the (possibly two-line) Dart constant declaration, e.g.:
#   const String kUpdateManifestPublicKey =
#       '/39VzhfG58PnR5RlMzDB5ertil945PWRgA+usAj4qvw=';
# \s* covers the newline + indent between = and the opening quote.
# re.DOTALL is not needed for \s*, but is kept defensively.
_KEY_PATTERN = re.compile(
    r"kUpdateManifestPublicKey\s*=\s*'([^']*)'",
    re.DOTALL,
)

_DEFAULT_KEY_SOURCE = (
    Path(__file__).resolve().parents[2] / "app/lib/src/update/update_config.dart"
)


def parse_pinned_key(source: Path) -> bytes:
    """Parse ``kUpdateManifestPublicKey`` from *source* (a Dart source file).

    Returns the raw 32 key bytes.  Prints a ``::error::`` annotation and exits
    with code 2 if the key cannot be read, found, or decoded — never falls back
    to a hardcoded constant.
    """
    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        print(f"::error::cannot read key source {source}: {exc}", file=sys.stderr)
        sys.exit(2)

    m = _KEY_PATTERN.search(text)
    if not m:
        print(
            f"::error::could not parse kUpdateManifestPublicKey from {source} — "
            "key rotation or file moved?",
            file=sys.stderr,
        )
        sys.exit(2)

    try:
        raw = base64.b64decode(m.group(1).strip(), validate=True)
    except Exception as exc:
        print(
            f"::error::kUpdateManifestPublicKey in {source} is not valid base64: {exc}",
            file=sys.stderr,
        )
        sys.exit(2)

    if len(raw) != 32:
        print(
            f"::error::kUpdateManifestPublicKey in {source} decoded to {len(raw)} bytes; "
            "expected 32 (Ed25519 public key is always 32 bytes)",
            file=sys.stderr,
        )
        sys.exit(2)

    return raw


def check(root: Path) -> list[str]:
    """Return a list of ``*.json`` filenames that lack a sibling ``*.json.sig``.

    Only the top level of *root* is scanned — subdirectories are skipped
    because only the channel manifests (at the branch root) are subject to the
    invariant.
    """
    missing: list[str] = []
    for json_file in sorted(f for f in root.glob("*.json") if f.is_file()):
        sig_file = json_file.with_suffix(".json.sig")
        if not sig_file.is_file():
            missing.append(json_file.name)
    return missing


def verify_signatures(root: Path, pubkey_raw: bytes) -> list[tuple[str, str]]:
    """Verify Ed25519 signatures for ``*.json`` files that have a ``*.json.sig``.

    Only checks files whose ``.sig`` is present; missing-sig cases are handled
    separately by :func:`check`.  Returns a list of ``(json_filename, reason)``
    for files whose signature fails verification — either the ``.sig`` body is
    not valid base64, is the wrong length, or does not verify against the
    pinned key.
    """
    pub_key = Ed25519PublicKey.from_public_bytes(pubkey_raw)
    failed: list[tuple[str, str]] = []

    for json_file in sorted(f for f in root.glob("*.json") if f.is_file()):
        sig_file = json_file.with_suffix(".json.sig")
        if not sig_file.is_file():
            continue  # missing-sig case is handled by check()

        try:
            manifest_bytes = json_file.read_bytes()
        except OSError as exc:
            failed.append((json_file.name, f"could not read manifest: {exc}"))
            continue

        try:
            sig_text = sig_file.read_text(encoding="utf-8").strip()
        except (OSError, UnicodeDecodeError) as exc:
            failed.append((json_file.name, f"could not read signature file: {exc}"))
            continue

        try:
            sig_bytes = base64.b64decode(sig_text, validate=True)
        except Exception as exc:
            failed.append((json_file.name, f"signature is not valid base64: {exc}"))
            continue

        if len(sig_bytes) != 64:
            failed.append(
                (json_file.name,
                 f"signature is {len(sig_bytes)} bytes; Ed25519 signatures are always 64 bytes")
            )
            continue

        try:
            pub_key.verify(sig_bytes, manifest_bytes)
        except InvalidSignature:
            failed.append(
                (json_file.name,
                 "signature does not verify against the pinned key (kUpdateManifestPublicKey)")
            )

    return failed


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])

    # Parse optional --key-source <path> flag alongside the required positional.
    key_source_str: str | None = None
    positional: list[str] = []
    i = 0
    while i < len(args):
        if args[i] == "--key-source":
            if i + 1 >= len(args):
                print(
                    "usage: check_pages_signature_files.py <path-to-gh-pages-root> "
                    "[--key-source <path-to-update_config.dart>]",
                    file=sys.stderr,
                )
                return 2
            key_source_str = args[i + 1]
            i += 2
        else:
            positional.append(args[i])
            i += 1

    if len(positional) != 1:
        print(
            "usage: check_pages_signature_files.py <path-to-gh-pages-root> "
            "[--key-source <path-to-update_config.dart>]",
            file=sys.stderr,
        )
        return 2

    root = Path(positional[0])
    if not root.is_dir():
        print(f"::error::directory not found: {root}", file=sys.stderr)
        return 2

    key_source = Path(key_source_str) if key_source_str is not None else _DEFAULT_KEY_SOURCE
    pubkey_raw = parse_pinned_key(key_source)  # exits with code 2 on failure

    # Phase 1: presence check.
    missing = check(root)
    if missing:
        for name in missing:
            print(
                f"::error::FAIL: {name} has no sibling {name}.sig — "
                "in-app update checks will fail closed for this channel"
            )
        print(
            f"\n{len(missing)} file(s) missing a .sig file. "
            "The in-app update client returns 'no update' when the signature file is absent "
            "(issue #714).",
            file=sys.stderr,
        )
        return 1

    # Phase 2: validity check.
    invalid = verify_signatures(root, pubkey_raw)
    if invalid:
        for name, reason in invalid:
            print(
                f"::error::FAIL: {name}.sig {reason} — "
                "the in-app update client will fail closed for this channel"
            )
        print(
            f"\n{len(invalid)} file(s) with an invalid signature. "
            "A stale or wrong-key signature causes the in-app update client to fail closed "
            "(issue #810).",
            file=sys.stderr,
        )
        return 1

    json_count = sum(1 for p in root.glob("*.json") if p.is_file())
    print(
        f"OK: all {json_count} *.json file(s) at the gh-pages root have a valid *.json.sig"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
