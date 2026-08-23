#!/usr/bin/env python3
"""Guard compendium_core's resolved graph and source directives against Flutter."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = "compendium_core"
CORE_DIR = Path("packages/compendium_core")
FORBIDDEN = {
    "flutter",
    "flutter_test",
    "flutter_localizations",
    "flutter_web_plugins",
    "flutter_driver",
    "sky_engine",
}
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT = re.compile(r"//.*")
_DIRECTIVE = re.compile(
    r"""^[ \t]*(?:import|export)[ \t]+(['"])package:(flutter[\w]*)/"""
    r"""[^'"\n]*\1[^;\n]*;""",
    re.MULTILINE,
)


def comment_free(source: str) -> str:
    """Remove comments before recognizing actual Dart import/export directives."""
    return _LINE_COMMENT.sub("", _BLOCK_COMMENT.sub("", source))


def reachable_packages(graph: dict[str, object]) -> set[str]:
    raw_packages = graph.get("packages")
    if not isinstance(raw_packages, list):
        raise ValueError("guard could not find a 'packages' list in the package graph")

    packages = {
        package["name"]: package
        for package in raw_packages
        if isinstance(package, dict) and isinstance(package.get("name"), str)
    }
    if CORE not in packages:
        raise ValueError(f"guard could not find '{CORE}' in the package graph")
    seen: set[str] = set()
    stack = [CORE]
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        dependencies = packages.get(name, {}).get("dependencies", [])
        if isinstance(dependencies, list):
            stack.extend(dep for dep in dependencies if isinstance(dep, str))
    seen.discard(CORE)
    return seen


def source_failures(core_dir: Path) -> tuple[list[str], int]:
    failures: list[str] = []
    scanned = 0
    for subdirectory in ("lib", "test", "benchmark"):
        directory = core_dir / subdirectory
        if not directory.is_dir():
            continue
        for dart in directory.rglob("*.dart"):
            scanned += 1
            source = comment_free(dart.read_text(encoding="utf-8"))
            for match in _DIRECTIVE.finditer(source):
                failures.append(
                    f"{dart}: imports package:{match.group(2)} (ADR-001)"
                )
    return failures, scanned


def run(root: Path = REPO_ROOT) -> int:
    result = subprocess.run(
        ["dart", "pub", "deps", "--json"],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        return result.returncode
    try:
        reachable = reachable_packages(json.loads(result.stdout))
    except (json.JSONDecodeError, TypeError, ValueError) as error:
        print(f"::error::{error}")
        return 2

    failures: list[str] = []
    forbidden = sorted(reachable & FORBIDDEN)
    if forbidden:
        failures.append(
            f"transitive Flutter dependency reachable from {CORE}: "
            + ", ".join(forbidden)
        )

    directives, scanned = source_failures(root / CORE_DIR)
    failures.extend(directives)
    if failures:
        for failure in failures:
            print(f"::error::{failure}")
        return 1
    print(
        f"OK: {CORE} is Flutter-free "
        f"(checked {len(reachable)} resolved deps + {scanned} Dart files)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(run())
