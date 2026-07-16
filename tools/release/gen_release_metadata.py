#!/usr/bin/env python3
"""Generate the per-release integrity + update-channel metadata.

Writes two files into the distribution directory:

* ``SHA256SUMS`` — one ``<sha256>  <filename>`` line per release binary, sorted
  by filename (the free integrity layer mandated by ADR-002 §6).
* ``<channel>.json`` — the static update manifest (``stable.json`` /
  ``beta.json``) whose schema is the producer/consumer contract in ADR-002 §2.
  ``release.yml`` writes it; the future pure-Dart update client reads it.

Binaries are discovered by the ADR-002 deterministic name contract:

    CallersCompendium-<version>-<platform>-<arch>.<ext>

The manifest lists ONE artifact per (platform, arch) — the "primary" download
for that target (installer/image preferred over the portable archive) — while
``SHA256SUMS`` covers every published binary.

This module is intentionally pure-stdlib and side-effect-free apart from the two
output files, so it stays reviewable and unit-testable.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import sys
from pathlib import Path

# Per-platform "primary artifact" preference: the first extension present wins
# as the manifest entry for that platform+arch. SHA256SUMS still covers all.
_EXT_PRIORITY: dict[str, list[str]] = {
    "linux": ["AppImage", "tar.gz"],
    "macos": ["dmg", "zip"],
    "windows": ["exe", "zip"],
    "android": ["apk"],
}

_ASSET_PREFIX = "CallersCompendium-"


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _parse_asset(name: str, version: str) -> tuple[str, str, str] | None:
    """Return (platform, arch, ext) for a contract-named asset, else None."""
    prefix = f"{_ASSET_PREFIX}{version}-"
    if not name.startswith(prefix):
        return None
    rest = name[len(prefix):]
    if "-" not in rest or "." not in rest:
        return None
    platform, remainder = rest.split("-", 1)
    arch, ext = remainder.split(".", 1)
    if not platform or not arch or not ext:
        return None
    return platform, arch, ext


def _primary_rank(platform: str, ext: str) -> int:
    order = _EXT_PRIORITY.get(platform, [])
    return order.index(ext) if ext in order else len(order)


def build_metadata(
    *,
    version: str,
    tag: str,
    channel: str,
    repo: str,
    dist: Path,
    pub_date: str,
) -> tuple[str, dict]:
    """Compute the SHA256SUMS text and the manifest dict for ``dist``."""
    binaries: list[Path] = sorted(
        p
        for p in dist.iterdir()
        if p.is_file() and p.name.startswith(_ASSET_PREFIX)
    )
    if not binaries:
        raise SystemExit(
            f"::error::no '{_ASSET_PREFIX}*' artifacts found in {dist}"
        )

    sums_lines: list[str] = []
    # candidates[(platform, arch)] = list of (rank, artifact-entry)
    candidates: dict[tuple[str, str], list[tuple[int, dict]]] = {}

    for path in binaries:
        parsed = _parse_asset(path.name, version)
        if parsed is None:
            # A prefix match that doesn't satisfy the contract must fail the
            # release rather than land in SHA256SUMS but not the manifest —
            # that split is exactly the integrity drift this file guards.
            raise SystemExit(
                f"::error::artifact does not match the "
                f"CallersCompendium-{version}-<platform>-<arch>.<ext> "
                f"name contract: {path.name}"
            )
        platform, arch, ext = parsed

        digest = _sha256(path)
        size = path.stat().st_size
        sums_lines.append(f"{digest}  {path.name}")

        entry = {
            "platform": platform,
            "arch": arch,
            "url": (
                f"https://github.com/{repo}/releases/download/{tag}/{path.name}"
            ),
            "sha256": digest,
            "size": size,
        }
        candidates.setdefault((platform, arch), []).append(
            (_primary_rank(platform, ext), entry)
        )

    artifacts: list[dict] = []
    for key in sorted(candidates):
        # Lowest rank == most-preferred extension for this platform.
        _, entry = min(candidates[key], key=lambda re: re[0])
        artifacts.append(entry)

    if not artifacts:
        raise SystemExit("::error::no artifacts matched the name contract")

    manifest = {
        "manifestSchemaVersion": 1,
        "channel": channel,
        "version": version,
        "releaseNotesUrl": (
            f"https://github.com/{repo}/releases/tag/{tag}"
        ),
        "pubDate": pub_date,
        "artifacts": artifacts,
    }

    sums_text = "\n".join(sorted(sums_lines)) + "\n"
    return sums_text, manifest


def _default_pub_date() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--version", required=True, help="bare SemVer, e.g. 0.1.0")
    ap.add_argument("--tag", required=True, help="git tag, e.g. v0.1.0")
    ap.add_argument("--channel", required=True, choices=["stable", "beta"])
    ap.add_argument("--repo", required=True, help="owner/name")
    ap.add_argument("--dist", required=True, type=Path, help="artifact dir")
    ap.add_argument("--pub-date", default=None, help="RFC3339 UTC; default now")
    args = ap.parse_args(argv)

    dist: Path = args.dist
    if not dist.is_dir():
        raise SystemExit(f"::error::dist dir not found: {dist}")

    if args.channel not in ("stable", "beta"):
        raise SystemExit(f"::error::bad channel: {args.channel}")

    sums_text, manifest = build_metadata(
        version=args.version,
        tag=args.tag,
        channel=args.channel,
        repo=args.repo,
        dist=dist,
        pub_date=args.pub_date or _default_pub_date(),
    )

    sums_path = dist / "SHA256SUMS"
    manifest_path = dist / f"{args.channel}.json"
    sums_path.write_text(sums_text, encoding="utf-8")
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )

    print(f"Wrote {sums_path} ({len(sums_text.splitlines())} entries)")
    print(f"Wrote {manifest_path} ({len(manifest['artifacts'])} artifacts)")
    print(sums_text, end="")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
