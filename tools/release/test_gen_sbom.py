#!/usr/bin/env python3
"""Unit tests for ``gen_sbom.py``.

Pure-stdlib, assert-based (no pytest / no third-party deps), matching the
free/offline tooling constraint. Run directly::

    python3 tools/release/test_gen_sbom.py

Exits non-zero on the first failed assertion (prints a traceback), or prints an
"OK" summary when every case passes.
"""

from __future__ import annotations

import json
import sys
import tempfile
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gen_sbom as g  # noqa: E402

# A compact `dart pub deps --json` fixture mirroring the real pub *workspace*
# shape: three root-kind packages (the workspace umbrella + two members), where
# every non-root package is reported as kind: transitive at the top level, so
# direct/dev classification must come from the roots' dependency lists. Includes
# a hosted direct dep shared by two members, a hosted dev dep, hosted transitive
# deps, and SDK-sourced packages (version 0.0.0) that must be excluded from
# components.
DEPS = {
    "root": "callers_compendium_workspace",
    "packages": [
        {
            "name": "compendium_app",
            "version": "0.1.0+1",
            "kind": "root",
            "source": "root",
            "directDependencies": ["flutter", "compendium_core", "drift", "http"],
            "devDependencies": ["flutter_test", "flutter_lints"],
        },
        {
            "name": "compendium_core",
            "version": "0.1.0",
            "kind": "root",
            "source": "root",
            "directDependencies": ["drift", "meta"],
            "devDependencies": ["build_runner"],
        },
        {
            "name": "callers_compendium_workspace",
            "version": "0.0.0",
            "kind": "root",
            "source": "root",
            "directDependencies": [],
            "devDependencies": [],
        },
        # Hosted: direct (declared by app + core).
        {
            "name": "drift",
            "version": "2.28.2",
            "kind": "transitive",
            "source": "hosted",
        },
        # Hosted: direct (app only).
        {
            "name": "http",
            "version": "1.5.0",
            "kind": "transitive",
            "source": "hosted",
        },
        # Hosted: direct (core only).
        {
            "name": "meta",
            "version": "1.18.0",
            "kind": "transitive",
            "source": "hosted",
        },
        # Hosted: dev (core devDependency).
        {
            "name": "build_runner",
            "version": "2.9.0",
            "kind": "transitive",
            "source": "hosted",
        },
        # Hosted: dev (app devDependency).
        {
            "name": "flutter_lints",
            "version": "6.0.0",
            "kind": "transitive",
            "source": "hosted",
        },
        # Hosted: pure transitive (declared by nobody's direct/dev lists).
        {
            "name": "async",
            "version": "2.13.0",
            "kind": "transitive",
            "source": "hosted",
        },
        # SDK-sourced: must be excluded from components (0.0.0, no pub purl).
        {
            "name": "flutter",
            "version": "0.0.0",
            "kind": "transitive",
            "source": "sdk",
        },
        {
            "name": "flutter_test",
            "version": "0.0.0",
            "kind": "transitive",
            "source": "sdk",
        },
    ],
    "sdks": [
        {"name": "Dart", "version": "3.12.2"},
        {"name": "Flutter", "version": "3.44.6"},
    ],
    "executables": [],
}

FIXED_TS = "2026-07-16T00:00:00Z"


def _by_name(sbom: dict) -> dict[str, dict]:
    return {c["name"]: c for c in sbom["components"]}


def _cases() -> None:
    sbom = g.build_sbom(DEPS, version="0.1.0", timestamp=FIXED_TS)

    # 1. Valid CycloneDX 1.5 top-level shape.
    assert sbom["bomFormat"] == "CycloneDX"
    assert sbom["specVersion"] == "1.5"
    assert isinstance(sbom["version"], int)
    assert "metadata" in sbom
    assert isinstance(sbom["components"], list)

    # 2. metadata.component is the released app (application), not a library.
    comp = sbom["metadata"]["component"]
    assert comp["type"] == "application"
    assert comp["name"] == "compendium_app"
    assert comp["version"] == "0.1.0"
    assert comp["purl"] == "pkg:pub/compendium_app@0.1.0"

    # 3. metadata.tools names this generator; timestamp is honoured.
    assert sbom["metadata"]["timestamp"] == FIXED_TS
    tools = sbom["metadata"]["tools"]
    assert any(t.get("name") == "gen_sbom.py" for t in tools)

    # 4. SDK versions recorded in metadata.properties (real versions, not 0.0.0).
    props = {p["name"]: p["value"] for p in sbom["metadata"]["properties"]}
    assert props["pub:sdk:dart"] == "3.12.2"
    assert props["pub:sdk:flutter"] == "3.44.6"

    # 5. Only hosted packages are components; roots + SDK packages excluded.
    names = {c["name"] for c in sbom["components"]}
    assert names == {"drift", "http", "meta", "build_runner", "flutter_lints", "async"}
    assert "flutter" not in names  # sdk
    assert "flutter_test" not in names  # sdk
    assert "compendium_app" not in names  # root
    assert "compendium_core" not in names  # root
    assert "callers_compendium_workspace" not in names  # root

    # 6. Each component has the expected pub purl, bom-ref, and library type.
    by = _by_name(sbom)
    assert by["drift"]["purl"] == "pkg:pub/drift@2.28.2"
    assert by["drift"]["bom-ref"] == "pkg:pub/drift@2.28.2"
    assert by["drift"]["type"] == "library"
    assert by["http"]["purl"] == "pkg:pub/http@1.5.0"

    # 7. direct/dev/transitive classification from the roots' lists.
    def dep_type(name: str) -> str:
        for p in by[name]["properties"]:
            if p["name"] == "pub:dependency:type":
                return p["value"]
        raise AssertionError(f"no dependency-type property on {name}")

    assert dep_type("drift") == "direct"  # direct in both members
    assert dep_type("http") == "direct"  # direct in app
    assert dep_type("meta") == "direct"  # direct in core
    assert dep_type("build_runner") == "dev"  # core devDependency
    assert dep_type("flutter_lints") == "dev"  # app devDependency
    assert dep_type("async") == "transitive"  # nobody's direct/dev

    # 8. Deterministic ordering: components sorted by purl, and repeated builds
    #    are byte-identical.
    purls = [c["purl"] for c in sbom["components"]]
    assert purls == sorted(purls)
    again = g.build_sbom(DEPS, version="0.1.0", timestamp=FIXED_TS)
    assert json.dumps(sbom, sort_keys=True) == json.dumps(again, sort_keys=True)

    # 9. serialNumber is a deterministic, content-addressed URN. It MUST be
    #    present: actions/attest only detects CycloneDX when bomFormat,
    #    specVersion AND serialNumber are all truthy (omitting it made the
    #    release "Attest SBOM" step fail with "Unsupported SBOM format").
    serial = sbom["serialNumber"]
    assert serial.startswith("urn:uuid:"), serial
    # Parses as a real UUID (validates the URN payload).
    uuid.UUID(serial[len("urn:uuid:") :])
    # The attest CycloneDX-detection triad is satisfied.
    assert sbom["bomFormat"] and sbom["specVersion"] and sbom["serialNumber"]
    # Deterministic: same resolved inputs -> identical serial (already covered by
    # the byte-identical check above, asserted explicitly here for clarity).
    assert again["serialNumber"] == serial
    # Content-addressed: a different version yields a different serial.
    other = g.build_sbom(DEPS, version="0.2.0", timestamp=FIXED_TS)
    assert other["serialNumber"] != serial

    # 10. classify_dependencies: a package that is dev in one member but direct
    #     in another is classified direct (production wins). drift is direct in
    #     both; construct a dev-vs-direct clash to prove the precedence.
    clash = {
        "packages": [
            {
                "name": "a",
                "version": "1.0.0",
                "kind": "root",
                "source": "root",
                "directDependencies": ["shared"],
                "devDependencies": [],
            },
            {
                "name": "b",
                "version": "1.0.0",
                "kind": "root",
                "source": "root",
                "directDependencies": [],
                "devDependencies": ["shared"],
            },
            {
                "name": "shared",
                "version": "2.0.0",
                "kind": "transitive",
                "source": "hosted",
            },
        ]
    }
    assert g.classify_dependencies(clash["packages"])["shared"] == "direct"

    # 11. App-name override flows into the primary component + purl.
    renamed = g.build_sbom(
        DEPS, version="1.2.3", app_name="my_app", timestamp=FIXED_TS
    )
    assert renamed["metadata"]["component"]["name"] == "my_app"
    assert renamed["metadata"]["component"]["purl"] == "pkg:pub/my_app@1.2.3"

    # 12. End-to-end via main(): reads deps from a file, writes valid JSON.
    with tempfile.TemporaryDirectory() as td:
        deps_path = Path(td) / "deps.json"
        out_path = Path(td) / "sbom.cdx.json"
        deps_path.write_text(json.dumps(DEPS), encoding="utf-8")
        rc = g.main(
            [
                "--deps",
                str(deps_path),
                "--version",
                "0.1.0",
                "--output",
                str(out_path),
                "--timestamp",
                FIXED_TS,
            ]
        )
        assert rc == 0
        written = json.loads(out_path.read_text(encoding="utf-8"))
        assert written["bomFormat"] == "CycloneDX"
        assert written["specVersion"] == "1.5"
        assert written["serialNumber"].startswith("urn:uuid:")
        # Six pub packages plus the two pdfium builds the desktop releases ship
        # (no --msvc-runtime given, so no MSVC runtime components).
        assert len(written["components"]) == 8
        assert sum(c["name"] == "pdfium" for c in written["components"]) == 2

    # 13. main() also reads deps from stdin when --deps is '-'.
    import io

    with tempfile.TemporaryDirectory() as td:
        out_path = Path(td) / "sbom.cdx.json"
        real_stdin = sys.stdin
        try:
            sys.stdin = io.StringIO(json.dumps(DEPS))
            rc = g.main(
                [
                    "--deps",
                    "-",
                    "--version",
                    "0.1.0",
                    "--output",
                    str(out_path),
                    "--timestamp",
                    FIXED_TS,
                ]
            )
        finally:
            sys.stdin = real_stdin
        assert rc == 0
        assert json.loads(out_path.read_text(encoding="utf-8"))["specVersion"] == "1.5"


ROOT = Path(__file__).resolve().parents[2]
PIN_FILE = ROOT / "packaging" / "pdfium" / "pdfium.cmake"

# What the Windows release job writes after staging the MSVC runtime
# (release.yml, "Stage the MSVC runtime beside the app").
MSVC_MANIFEST = {
    "redist_version": "14.44.35112",
    "crt_folder": "Microsoft.VC143.CRT",
    "dlls": [
        {"name": "vcruntime140.dll", "file_version": "14.44.35112.1", "sha256": "a" * 64},
        {"name": "vcruntime140_1.dll", "file_version": "14.44.35112.1", "sha256": "b" * 64},
        {"name": "msvcp140.dll", "file_version": "14.44.35112.1", "sha256": "c" * 64},
    ],
}


def _prop(component: dict, name: str) -> str:
    for p in component.get("properties", []):
        if p["name"] == name:
            return p["value"]
    raise AssertionError(f"no {name} property on {component['bom-ref']}")


def _native_cases() -> None:
    """Native components the pub graph cannot see (audit finding platform-5)."""
    import pdfium_pin

    pin = pdfium_pin.read(PIN_FILE)

    # 14. pdfium: one component per shipped desktop build, carrying the pinned
    #     version and the SHA-256 of the exact release archive.
    native = g.native_components(pin)
    pdfium = {_prop(c, "compendium:platform"): c for c in native if c["name"] == "pdfium"}
    assert set(pdfium) == {"linux-x64", "win-x64"}, sorted(pdfium)
    for target, comp in pdfium.items():
        entry = pin.targets[target]
        url = (
            "https://github.com/bblanchon/pdfium-binaries/releases/download/"
            f"chromium/{pin.version}/pdfium-{target}.tgz"
        )
        assert comp["type"] == "library"
        assert comp["version"] == pin.full_version
        assert comp["hashes"] == [{"alg": "SHA-256", "content": entry.archive_sha256}]
        assert {"type": "distribution", "url": url} in comp["externalReferences"]
        assert comp["purl"].startswith(f"pkg:generic/pdfium@{pin.full_version}?")
        assert f"checksum=sha256:{entry.archive_sha256}" in comp["purl"]
        # ECMA-427 (purl) 5.4 / Annex B: a download_url value is
        # percent-encoded; ':' stays as is, '/' becomes %2F.
        encoded = url.replace("/", "%2F")
        assert comp["purl"].endswith(f"&download_url={encoded}"), comp["purl"]
        assert comp["purl"].startswith("pkg:generic/pdfium@") and "https:%2F%2Fgithub.com" in comp["purl"]
        assert comp["bom-ref"] == comp["purl"]
        assert _prop(comp, "compendium:shipped-file:sha256") == entry.library_sha256
        assert _prop(comp, "pdfium-binaries:release") == f"chromium/{pin.version}"
        ids = {l["license"].get("id") for l in comp["licenses"]}
        assert "BSD-3-Clause" in ids, comp["licenses"]
    assert pdfium["linux-x64"]["purl"] != pdfium["win-x64"]["purl"]
    assert _prop(pdfium["linux-x64"], "compendium:shipped-file") == "lib/libpdfium.so"
    assert _prop(pdfium["win-x64"], "compendium:shipped-file") == "pdfium.dll"

    # 15. MSVC runtime: one component per DLL the Windows build staged, with
    #     the file version and SHA-256 recorded on the runner.
    native = g.native_components(pin, msvc_runtime=MSVC_MANIFEST)
    msvc = {c["name"]: c for c in native if c["name"].endswith(".dll")}
    assert set(msvc) == {"vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll"}
    for entry in MSVC_MANIFEST["dlls"]:
        comp = msvc[entry["name"]]
        assert comp["version"] == entry["file_version"]
        assert comp["hashes"] == [{"alg": "SHA-256", "content": entry["sha256"]}]
        assert comp["supplier"] == {"name": "Microsoft Corporation"}
        assert comp["purl"] == f"pkg:generic/microsoft/{entry['name']}@{entry['file_version']}"
        assert _prop(comp, "compendium:platform") == "win-x64"
        assert _prop(comp, "msvc:redist-version") == "14.44.35112"

    # 16. A malformed manifest fails loudly instead of yielding a thin SBOM.
    bad_manifests = [
        {**MSVC_MANIFEST, "dlls": []},
        {**MSVC_MANIFEST, "redist_version": ""},
        {**MSVC_MANIFEST, "dlls": [{**MSVC_MANIFEST["dlls"][0], "sha256": "xyz"}]},
        {**MSVC_MANIFEST, "dlls": [{**MSVC_MANIFEST["dlls"][0], "file_version": ""}]},
        {**MSVC_MANIFEST, "dlls": [MSVC_MANIFEST["dlls"][0], MSVC_MANIFEST["dlls"][0]]},
    ]
    for bad in bad_manifests:
        try:
            g.native_components(pin, msvc_runtime=bad)
        except SystemExit:
            continue
        raise AssertionError(f"accepted a malformed MSVC manifest: {bad}")

    # 17. End to end: main() reads the pin from the repo and the manifest from
    #     --msvc-runtime; components stay sorted and the serial covers them.
    with tempfile.TemporaryDirectory() as td:
        deps_path = Path(td) / "deps.json"
        manifest_path = Path(td) / "msvc-runtime.json"
        out_path = Path(td) / "sbom.cdx.json"
        deps_path.write_text(json.dumps(DEPS), encoding="utf-8")
        manifest_path.write_text(json.dumps(MSVC_MANIFEST), encoding="utf-8")
        args = ["--deps", str(deps_path), "--version", "0.1.0", "--output", str(out_path),
                "--timestamp", FIXED_TS]
        assert g.main(args + ["--msvc-runtime", str(manifest_path)]) == 0
        written = json.loads(out_path.read_text(encoding="utf-8"))
        names = [c["name"] for c in written["components"]]
        assert names.count("pdfium") == 2
        assert {"vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll"} <= set(names)
        assert len(names) == 6 + 2 + 3
        purls = [c["purl"] for c in written["components"]]
        assert purls == sorted(purls)
        with_msvc = written["serialNumber"]
        assert g.main(args) == 0
        without = json.loads(out_path.read_text(encoding="utf-8"))
        assert without["serialNumber"] != with_msvc


def main() -> int:
    _cases()
    _native_cases()
    print("OK: all gen_sbom tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
