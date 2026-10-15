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

* ``components[]`` also lists the native binaries the desktop releases ship
  that the pub graph cannot see (audit finding platform-5):

  - **pdfium**, which the ``printing`` plugin bundles into the Linux and
    Windows builds: one component per shipped build (``linux-x64``,
    ``win-x64``) with the pinned version, the SHA-256 of the exact release
    archive, its download URL, and the SHA-256 of the library file that lands
    in the bundle. Read from ``packaging/pdfium/pdfium.cmake`` (the same pin
    the CMake build verifies), via ``pdfium_pin.py``.
  - the **MSVC runtime DLLs** the Windows build ships app-local
    (``vcruntime140.dll``, ``vcruntime140_1.dll``, ``msvcp140.dll``, from
    Visual Studio's redistributable folder). Their version depends on the
    runner image, so the Windows release job records each staged DLL's file
    version and SHA-256 in a small JSON manifest, passed here with
    ``--msvc-runtime``.

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
import re
import sys
import uuid
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))

import pdfium_pin  # noqa: E402

# Identifies this generator in the SBOM's ``metadata.tools`` block.
_TOOL_NAME = "gen_sbom.py"
_TOOL_VERSION = "1.1.0"
_TOOL_VENDOR = "Caller's Compendium"

# Default primary component (the released app) — the workspace member that is
# actually shipped. Overridable via ``--app-name``.
_DEFAULT_APP_NAME = "compendium_app"

# The pub-classification property recorded on each component.
_DEP_TYPE_PROP = "pub:dependency:type"

_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_PDFIUM_PIN = _REPO_ROOT / "packaging" / "pdfium" / "pdfium.cmake"

# The pdfium builds the desktop releases ship (release.yml builds Linux and
# Windows for x64 only), and where each lands in the bundle.
_PDFIUM_RELEASE_TARGETS = {
    "linux-x64": "lib/libpdfium.so",
    "win-x64": "pdfium.dll",
}

_SHA256 = re.compile(r"^[0-9a-f]{64}$")


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


def _pdfium_component(pin: pdfium_pin.PdfiumPin, target: str, shipped: str) -> dict:
    hashes = pin.targets.get(target)
    if hashes is None:
        raise SystemExit(f"::error::no pinned pdfium hashes for {target}")
    url = pdfium_pin.release_url(pin.version, target)
    # ECMA-427 (purl) 5.4 and Annex B: qualifier values are percent-encoded,
    # with ':' left as is, so '/' becomes %2F.
    purl = (
        f"pkg:generic/pdfium@{pin.full_version}"
        f"?checksum=sha256:{hashes.archive_sha256}"
        f"&download_url={quote(url, safe=':')}"
    )
    return {
        "type": "library",
        "bom-ref": purl,
        "supplier": {"name": "bblanchon/pdfium-binaries"},
        "name": "pdfium",
        "version": pin.full_version,
        "purl": purl,
        "hashes": [{"alg": "SHA-256", "content": hashes.archive_sha256}],
        # PDFium's own LICENSE carries BSD-3-Clause and Apache-2.0 texts; the
        # same file then reproduces the notices of the libraries built into it.
        "licenses": [
            {"license": {"id": "BSD-3-Clause"}},
            {"license": {"id": "Apache-2.0"}},
            {"license": {"name": "Bundled third-party notices (LICENSE in the release archive)"}},
        ],
        "externalReferences": [{"type": "distribution", "url": url}],
        "properties": [
            {"name": "compendium:platform", "value": target},
            {"name": "compendium:shipped-file", "value": shipped},
            {"name": "compendium:shipped-file:sha256", "value": hashes.library_sha256},
            {"name": "pdfium-binaries:release", "value": f"chromium/{pin.version}"},
        ],
    }


def _msvc_components(manifest: dict) -> list[dict]:
    redist = manifest.get("redist_version")
    crt_folder = manifest.get("crt_folder")
    dlls = manifest.get("dlls")
    if not isinstance(redist, str) or not redist:
        raise SystemExit("::error::MSVC runtime manifest has no redist_version")
    if not isinstance(crt_folder, str) or not crt_folder:
        raise SystemExit("::error::MSVC runtime manifest has no crt_folder")
    if not isinstance(dlls, list) or not dlls:
        raise SystemExit("::error::MSVC runtime manifest lists no DLLs")
    components: list[dict] = []
    seen: set[str] = set()
    for entry in dlls:
        name = str(entry.get("name", "")).lower()
        version = entry.get("file_version")
        sha256 = str(entry.get("sha256", "")).lower()
        if not name.endswith(".dll") or name in seen:
            raise SystemExit(f"::error::MSVC runtime manifest: bad or repeated DLL {name!r}")
        if not isinstance(version, str) or not version:
            raise SystemExit(f"::error::MSVC runtime manifest: no file_version for {name}")
        if not _SHA256.match(sha256):
            raise SystemExit(f"::error::MSVC runtime manifest: bad sha256 for {name}")
        seen.add(name)
        purl = f"pkg:generic/microsoft/{name}@{version}"
        components.append(
            {
                "type": "library",
                "bom-ref": purl,
                "supplier": {"name": "Microsoft Corporation"},
                "name": name,
                "version": version,
                "purl": purl,
                "hashes": [{"alg": "SHA-256", "content": sha256}],
                "licenses": [
                    {"license": {"name": "Microsoft Visual Studio redistributable (Distributable Code)"}}
                ],
                "properties": [
                    {"name": "compendium:platform", "value": "win-x64"},
                    {"name": "compendium:shipped-file", "value": name},
                    {"name": "msvc:redist-version", "value": redist},
                    {"name": "msvc:crt-folder", "value": crt_folder},
                ],
            }
        )
    return components


def native_components(
    pin: pdfium_pin.PdfiumPin, *, msvc_runtime: dict | None = None
) -> list[dict]:
    """Components for the native binaries the desktop releases ship.

    pdfium comes from the in-repo pin. The MSVC runtime comes from the manifest
    the Windows release job writes; without one it is left out (a local run),
    and ``release.yml`` always passes it.
    """
    components = [
        _pdfium_component(pin, target, shipped)
        for target, shipped in _PDFIUM_RELEASE_TARGETS.items()
    ]
    if msvc_runtime is not None:
        components.extend(_msvc_components(msvc_runtime))
    return components


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
    native: list[dict] | None = None,
) -> dict:
    """Build the CycloneDX 1.5 SBOM dict from a ``dart pub deps --json`` dict.

    ``native`` (from :func:`native_components`) is appended to the pub
    packages before sorting.
    """
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

    components.extend(native or [])

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
    ap.add_argument(
        "--pdfium-pin",
        type=Path,
        default=_DEFAULT_PDFIUM_PIN,
        help="the pdfium pin to list (default: packaging/pdfium/pdfium.cmake)",
    )
    ap.add_argument(
        "--msvc-runtime",
        type=Path,
        default=None,
        help="JSON manifest of the MSVC runtime DLLs the Windows build staged "
        "(written by release.yml); omit to leave them out",
    )
    args = ap.parse_args(argv)

    deps = _read_deps(args.deps)
    msvc = None
    if args.msvc_runtime is not None:
        if not args.msvc_runtime.is_file():
            raise SystemExit(f"::error::MSVC runtime manifest not found: {args.msvc_runtime}")
        try:
            msvc = json.loads(args.msvc_runtime.read_text(encoding="utf-8-sig"))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"::error::invalid MSVC runtime manifest: {exc}") from exc
    native = native_components(pdfium_pin.read(args.pdfium_pin), msvc_runtime=msvc)
    sbom = build_sbom(
        deps,
        version=args.version,
        app_name=args.app_name,
        timestamp=args.timestamp,
        native=native,
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
