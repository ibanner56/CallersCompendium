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

Additional non-binary release assets (e.g. the CycloneDX SBOM produced by
``gen_sbom.py``) can be folded into ``SHA256SUMS`` via ``--extra-file`` without
being treated as platform binaries: they are checksummed and listed in
``SHA256SUMS`` but never added to the ``<channel>.json`` manifest and never
subjected to the ``<platform>-<arch>.<ext>`` name contract. With no
``--extra-file`` the output is byte-identical to before.

End-of-life announcements (ADR-002 §2 ``retirements``) are read from the
checked-in ``--retirements`` file — ``tools/release/retirements.json`` in the
release workflow — validated here, and copied into every manifest this release
writes. Builds after 0.6.0-beta warn their users when a manifest they fetch
names an end-of-life date for them. An empty list adds no field, so the
manifest is byte-identical to one generated without the option.

This module is intentionally pure-stdlib and side-effect-free apart from the two
output files, so it stays reviewable and unit-testable.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import re
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


# SemVer 2.0.0 (https://semver.org), the grammar the client's SemVer.tryParse
# accepts minus its leniency about a leading "v": retirements are authored by
# hand, so a tag-style "v0.7.0" is more likely a slip than a convention.
_SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)
_ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_RETIREMENT_KEYS = {"through", "endOfLife"}


def _semver_key(version: str) -> tuple:
    """A sort key giving ``version`` its SemVer §11 precedence.

    Raises ``ValueError`` when ``version`` is not SemVer. A release (no
    pre-release) sorts after every pre-release of the same core; numeric
    identifiers sort before alphanumeric ones and compare numerically; a longer
    pre-release series sorts after a prefix of it. Build metadata is ignored.
    """
    match = _SEMVER.match(version)
    if match is None:
        raise ValueError(f"not a SemVer version: {version!r}")
    major, minor, patch, pre, _build = match.groups()
    core = (int(major), int(minor), int(patch))
    if pre is None:
        return core + ((1,),)
    idents = tuple(
        (0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split(".")
    )
    return core + ((0, idents),)


def load_retirements(path: Path, *, release_version: str) -> list[dict]:
    """Read and validate the retirements file at ``path``.

    The file is a JSON list of ``{"through": <SemVer>, "endOfLife":
    "YYYY-MM-DD"}`` objects: every build at or below ``through`` stops being
    supported on ``endOfLife``. Anything the client would refuse — and with it
    the whole manifest — fails the release here instead: a non-list, an unknown
    or missing key, a malformed version, or an impossible date. So does an entry
    whose ``through`` is not strictly older than ``release_version``, which
    would tell the build being released that it is already retired.
    """
    try:
        entries = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise SystemExit(f"::error::cannot read retirements file {path}: {exc}")
    if not isinstance(entries, list):
        raise SystemExit(f"::error::{path}: retirements must be a JSON list")

    release_key = _semver_key(release_version)
    validated: list[dict] = []
    for index, entry in enumerate(entries):
        where = f"{path}: retirements[{index}]"
        if not isinstance(entry, dict):
            raise SystemExit(f"::error::{where} is not an object")
        if set(entry) != _RETIREMENT_KEYS:
            raise SystemExit(
                f"::error::{where} must have exactly the keys "
                f"{sorted(_RETIREMENT_KEYS)}, got {sorted(entry)}"
            )
        through, end_of_life = entry["through"], entry["endOfLife"]
        if not isinstance(through, str) or not _SEMVER.match(through):
            raise SystemExit(
                f"::error::{where}.through is not a SemVer version: {through!r}"
            )
        if not isinstance(end_of_life, str) or not _ISO_DATE.match(end_of_life):
            raise SystemExit(
                f"::error::{where}.endOfLife is not YYYY-MM-DD: {end_of_life!r}"
            )
        try:
            _dt.date.fromisoformat(end_of_life)
        except ValueError:
            raise SystemExit(
                f"::error::{where}.endOfLife is not a real date: {end_of_life!r}"
            )
        if _semver_key(through) >= release_key:
            raise SystemExit(
                f"::error::{where}.through ({through}) is not older than the "
                f"version being released ({release_version}); a release cannot "
                f"retire itself"
            )
        validated.append({"through": through, "endOfLife": end_of_life})
    return validated


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
    codename: str | None = None,
    extra_files: list[Path] | None = None,
    retirements: list[dict] | None = None,
) -> tuple[str, dict]:
    """Compute the SHA256SUMS text and the manifest dict for ``dist``.

    ``retirements`` (already validated by :func:`load_retirements`) is copied
    into the manifest's ``retirements`` field when non-empty.

    ``extra_files`` are additional (non-binary) assets to include in
    ``SHA256SUMS`` only — they are checksummed and listed alongside the binaries
    but are NOT classified into the ``<channel>.json`` manifest and are exempt
    from the ``<platform>-<arch>.<ext>`` name contract.
    """
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

    # Extra (non-binary) assets — e.g. the SBOM — go into SHA256SUMS only. They
    # are exempt from the name contract and never touch the manifest.
    for extra in extra_files or []:
        if not extra.is_file():
            raise SystemExit(f"::error::--extra-file not found: {extra}")
        sums_lines.append(f"{_sha256(extra)}  {extra.name}")

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
    # Legacy tags use the tag itself as a release-title fallback, not a codename.
    normalized_codename = codename.strip() if codename else ""
    if normalized_codename and normalized_codename != tag:
        manifest["codename"] = normalized_codename
    if retirements:
        manifest["retirements"] = retirements

    sums_text = "\n".join(sorted(sums_lines)) + "\n"
    return sums_text, manifest


def build_channel_manifests(
    *,
    version: str,
    tag: str,
    channel: str,
    repo: str,
    dist: Path,
    pub_date: str,
    codename: str | None = None,
    extra_files: list[Path] | None = None,
    retirements: list[dict] | None = None,
    metadata: dict | None = None,
) -> dict[str, dict]:
    """Build all manifests refreshed by a selected release channel.

    ``metadata`` lets callers that already built release metadata avoid hashing
    every artifact again merely to change the manifest's channel field.
    """
    channels = ("stable", "beta") if channel == "stable" else ("beta",)
    if metadata is None:
        _, metadata = build_metadata(
            version=version,
            tag=tag,
            channel=channel,
            repo=repo,
            dist=dist,
            pub_date=pub_date,
            codename=codename,
            extra_files=extra_files,
            retirements=retirements,
        )
    return {
        manifest_channel: {**metadata, "channel": manifest_channel}
        for manifest_channel in channels
    }


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
    ap.add_argument(
        "--codename",
        default=None,
        help="release codename for display on the Pages site",
    )
    ap.add_argument(
        "--extra-file",
        action="append",
        type=Path,
        default=None,
        metavar="PATH",
        help="additional asset to include in SHA256SUMS only (repeatable); not "
        "added to the channel manifest and exempt from the name contract",
    )
    ap.add_argument(
        "--retirements",
        type=Path,
        default=None,
        metavar="PATH",
        help="JSON list of end-of-life announcements to copy into every "
        "manifest (tools/release/retirements.json)",
    )
    args = ap.parse_args(argv)

    dist: Path = args.dist
    if not dist.is_dir():
        raise SystemExit(f"::error::dist dir not found: {dist}")

    if args.channel not in ("stable", "beta"):
        raise SystemExit(f"::error::bad channel: {args.channel}")

    pub_date = args.pub_date or _default_pub_date()
    retirements = (
        load_retirements(args.retirements, release_version=args.version)
        if args.retirements is not None
        else None
    )
    sums_text, manifest = build_metadata(
        version=args.version,
        tag=args.tag,
        channel=args.channel,
        repo=args.repo,
        dist=dist,
        pub_date=pub_date,
        codename=args.codename,
        extra_files=args.extra_file,
        retirements=retirements,
    )
    manifests = build_channel_manifests(
        version=args.version,
        tag=args.tag,
        channel=args.channel,
        repo=args.repo,
        dist=dist,
        pub_date=pub_date,
        codename=args.codename,
        extra_files=args.extra_file,
        metadata=manifest,
    )

    sums_path = dist / "SHA256SUMS"
    sums_path.write_text(sums_text, encoding="utf-8")

    print(f"Wrote {sums_path} ({len(sums_text.splitlines())} entries)")
    for channel, channel_manifest in manifests.items():
        manifest_path = dist / f"{channel}.json"
        manifest_path.write_text(
            json.dumps(channel_manifest, indent=2, sort_keys=False) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {manifest_path} ({len(channel_manifest['artifacts'])} artifacts)")
    print(sums_text, end="")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
