#!/usr/bin/env python3
"""Generate a CycloneDX 1.5 Software Bill of Materials (SBOM) for a release.

The release pipeline (``.github/workflows/release.yml``) attaches this SBOM to
every desktop release and cryptographically attests it (``actions/attest-sbom``),
so downstream users can see exactly which dependencies went into the build with
signed provenance. This complements the existing keyless SLSA build-provenance
attestation.

Input is the resolved dependency graph emitted by ``dart pub deps --json`` (read
from a file or stdin). Because Caller's Compendium is a **pub workspace**
(``callers_compendium_workspace`` with members ``app`` / ``compendium_core``),
``dart pub deps --json`` reports every non-root package as ``kind: transitive``
at the top level, so direct/dev classification is computed from the *roots'*
``directDependencies`` / ``devDependencies`` lists rather than the per-package
``kind`` field.

Output is a CycloneDX 1.5 JSON document:

* ``metadata.component`` — the released application (``type: application``) with
  the release version.
* ``metadata.tools`` — this generator.
* ``metadata.properties`` — the real Dart + Flutter SDK versions from the deps
  ``sdks`` block (recorded here rather than as ``0.0.0`` component noise).
* ``components[]`` — one ``type: library`` component per resolved **hosted** pub
  package: ``name``, ``version``, ``purl: pkg:pub/<name>@<version>``, a stable
  ``bom-ref`` (the purl), and a ``pub:dependency:type`` property classifying it
  as ``direct`` / ``dev`` / ``transitive``.

First-party workspace roots (the app + local path packages) and SDK-sourced
packages (``flutter``/``sky_engine``/... , which carry meaningless ``0.0.0``
versions and no pub purl) are intentionally excluded from ``components[]``; the
app is represented by ``metadata.component`` and the SDK versions by
``metadata.properties``.

Determinism: components are sorted by purl and the ``serialNumber`` is a
deterministic, content-addressed URN — a UUIDv5 over the app name, the version,
the sorted component purls, and the SDK versions (never a random UUID and never
the timestamp) — so re-runs against the same lockfile are byte-identical and
diff cleanly. A ``serialNumber`` is emitted because ``actions/attest`` only
recognizes a document as CycloneDX when ``bomFormat``, ``specVersion`` **and**
``serialNumber`` are all present; omitting it makes the release ``Attest SBOM``
step fail with "Unsupported SBOM format". The only time-varying field is
``metadata.timestamp`` (the build time), overridable via ``--timestamp`` for
reproducible output — mirroring ``gen_release_metadata.py``'s ``--pub-date``.

This module is intentionally pure-stdlib and Flutter-free (mirroring
``gen_release_metadata.py`` / ``gen_release_notes.py``) so it stays reviewable
and unit-testable.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import sys
import uuid
from pathlib import Path

# Identifies this generator in the SBOM's ``metadata.tools`` block.
_TOOL_NAME = "gen_sbom.py"
_TOOL_VERSION = "1.0.0"
_TOOL_VENDOR = "Caller's Compendium"

# Default primary component (the released app) — the workspace member that is
# actually shipped. Overridable via ``--app-name``.
_DEFAULT_APP_NAME = "compendium_app"

# The pub-classification property recorded on each component.
_DEP_TYPE_PROP = "pub:dependency:type"


def _default_timestamp() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _purl(name: str, version: str) -> str:
    """CycloneDX package URL for a pub.dev package."""
    return f"pkg:pub/{name}@{version}"


def _serial_number(
    app_name: str, version: str, components: list[dict], sdk_properties: list[dict]
) -> str:
    """Deterministic, content-addressed CycloneDX ``serialNumber`` URN.

    ``actions/attest`` only recognizes a document as CycloneDX when
    ``bomFormat``, ``specVersion`` **and** ``serialNumber`` are all present, so
    this field is required for the release ``Attest SBOM`` step to succeed. It is
    derived as a UUIDv5 over the app name, version, the (already-sorted) component
    purls, and the SDK versions — never a random UUID and never the timestamp — so
    the same resolved dependency set always yields the same serial and re-runs
    stay byte-identical.
    """
    canonical = "|".join(
        [
            "CycloneDX-SBOM",
            app_name,
            version,
            ";".join(c["purl"] for c in components),
            ";".join(f"{p['name']}={p['value']}" for p in sdk_properties),
        ]
    )
    return f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, canonical)}"


def classify_dependencies(packages: list[dict]) -> dict[str, str]:
    """Map each hosted package name -> ``direct`` / ``dev`` / ``transitive``.

    Classification is derived from the workspace *roots* (``kind == "root"``):

    * ``direct``     = union of roots' ``directDependencies``
    * ``dev``        = union of roots' ``devDependencies`` (minus anything also
                       ``direct`` — a package that is a production dependency of
                       any member is treated as ``direct``)
    * ``transitive`` = every other resolved package

    Only hosted packages end up in the SBOM, but classification is computed over
    all names first so a hosted package that happens to be a direct dep is
    labelled correctly regardless of its top-level ``kind``.
    """
    direct: set[str] = set()
    dev: set[str] = set()
    for pkg in packages:
        if pkg.get("kind") != "root":
            continue
        direct.update(pkg.get("directDependencies", []) or [])
        dev.update(pkg.get("devDependencies", []) or [])
    dev -= direct

    classification: dict[str, str] = {}
    for pkg in packages:
        name = pkg["name"]
        if name in direct:
            classification[name] = "direct"
        elif name in dev:
            classification[name] = "dev"
        else:
            classification[name] = "transitive"
    return classification


def build_sbom(
    deps: dict,
    *,
    version: str,
    app_name: str = _DEFAULT_APP_NAME,
    timestamp: str | None = None,
) -> dict:
    """Build the CycloneDX 1.5 SBOM dict from a ``dart pub deps --json`` dict."""
    packages: list[dict] = deps.get("packages", [])
    classification = classify_dependencies(packages)

    components: list[dict] = []
    for pkg in packages:
        # Only third-party pub packages become components. First-party workspace
        # roots (the app + local path packages) and SDK packages are excluded.
        if pkg.get("source") != "hosted":
            continue
        name = pkg["name"]
        pkg_version = pkg["version"]
        purl = _purl(name, pkg_version)
        components.append(
            {
                "type": "library",
                "bom-ref": purl,
                "name": name,
                "version": pkg_version,
                "purl": purl,
                "properties": [
                    {
                        "name": _DEP_TYPE_PROP,
                        "value": classification.get(name, "transitive"),
                    }
                ],
            }
        )

    # Deterministic ordering so re-runs against the same lockfile diff cleanly.
    components.sort(key=lambda c: c["purl"])

    # Record the real SDK versions (Dart/Flutter) as metadata properties instead
    # of emitting them as 0.0.0 component noise.
    sdk_properties: list[dict] = []
    for sdk in deps.get("sdks", []) or []:
        sdk_name = sdk.get("name")
        sdk_version = sdk.get("version")
        if sdk_name and sdk_version:
            sdk_properties.append(
                {
                    "name": f"pub:sdk:{sdk_name.lower()}",
                    "value": sdk_version,
                }
            )
    sdk_properties.sort(key=lambda p: p["name"])

    app_purl = _purl(app_name, version)
    metadata: dict = {
        "timestamp": timestamp or _default_timestamp(),
        "tools": [
            {
                "vendor": _TOOL_VENDOR,
                "name": _TOOL_NAME,
                "version": _TOOL_VERSION,
            }
        ],
        "component": {
            "type": "application",
            "bom-ref": app_purl,
            "name": app_name,
            "version": version,
            "purl": app_purl,
        },
    }
    if sdk_properties:
        metadata["properties"] = sdk_properties

    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": _serial_number(
            app_name, version, components, sdk_properties
        ),
        "version": 1,
        "metadata": metadata,
        "components": components,
    }


def _read_deps(source: str) -> dict:
    """Load the ``dart pub deps --json`` document from a file or stdin (``-``)."""
    if source == "-":
        text = sys.stdin.read()
    else:
        path = Path(source)
        if not path.is_file():
            raise SystemExit(f"::error::deps file not found: {source}")
        text = path.read_text(encoding="utf-8")
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"::error::invalid JSON from deps input: {exc}") from exc


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--deps",
        required=True,
        help="path to a `dart pub deps --json` file, or '-' for stdin",
    )
    ap.add_argument(
        "--version",
        required=True,
        help="release version (bare SemVer, may include a prerelease suffix)",
    )
    ap.add_argument(
        "--output",
        "-o",
        required=True,
        type=Path,
        help="write the CycloneDX SBOM JSON to this path",
    )
    ap.add_argument(
        "--app-name",
        default=_DEFAULT_APP_NAME,
        help=f"primary component name (default: {_DEFAULT_APP_NAME})",
    )
    ap.add_argument(
        "--timestamp",
        default=None,
        help="RFC3339 UTC metadata.timestamp; default now (set for reproducible "
        "output)",
    )
    args = ap.parse_args(argv)

    deps = _read_deps(args.deps)
    sbom = build_sbom(
        deps,
        version=args.version,
        app_name=args.app_name,
        timestamp=args.timestamp,
    )

    args.output.write_text(
        json.dumps(sbom, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )
    print(
        f"Wrote {args.output} "
        f"({len(sbom['components'])} components, CycloneDX "
        f"{sbom['specVersion']})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
