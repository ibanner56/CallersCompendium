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

    # 9. No random serialNumber (would break reproducibility).
    assert "serialNumber" not in sbom

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
        assert len(written["components"]) == 6

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


def main() -> int:
    _cases()
    print("OK: all gen_sbom tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
