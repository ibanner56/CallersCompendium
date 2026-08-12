#!/usr/bin/env python3
"""Offline tests for ``check_changelog_promoted.py``."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "check_changelog_promoted.py"
DATABASE = Path("packages/compendium_core/lib/src/storage/database.dart")
TAXONOMY = Path("packages/compendium_core/lib/src/taxonomy/contra_taxonomy.dart")


def run(*args: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        cwd=cwd,
        check=False,
        capture_output=True,
        encoding="utf-8",
    )


def write(repo: Path, path: Path, contents: str) -> None:
    destination = repo / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(contents, encoding="utf-8")


def database(version: int) -> str:
    return f"const int kCompendiumSchemaVersion = {version};\n"


def taxonomy(version: int) -> str:
    return f"const int contraTaxonomyVersion = {version};\n"


def changelog(*, unreleased: str, released: str) -> str:
    return f"""\
## [Unreleased]

{unreleased}
## [0.1.0] - 2026-08-07

{released}
"""


FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def main() -> int:
    FAILURES.clear()
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.invalid"],
                       cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "Test"], cwd=repo,
                       check=True)
        write(repo, DATABASE, database(20))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="",
            released="### Added\n\n- Previous release.\n",
        ))
        subprocess.run(["git", "add", "."], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-qm", "previous release"], cwd=repo,
                       check=True)
        subprocess.run(["git", "tag", "v0.1.0-beta.6"], cwd=repo, check=True)

        # This mirrors the stale beta.6 section plus populated Unreleased that
        # previously passed gen_release_notes.py --check for beta.7.
        write(repo, DATABASE, database(24))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n- New beta work.\n",
            released=(
                "> Upgrading rewrites stored figures (schema 15 → 20).\n\n"
                "### Data / Migrations\n\n"
                "- Schema advances from version 15 to 20.\n"
            ),
        ))
        stale = run("--version", "0.1.0-beta.7", "--previous-ref",
                    "v0.1.0-beta.6", cwd=repo)
        check("stale beta section is rejected", stale.returncode == 1,
              stale.stderr)
        check("unpromoted entries are named", "Unreleased" in stale.stderr,
              stale.stderr)
        check("stale schema range is named", "20" in stale.stderr,
              stale.stderr)

        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n### Fixed\n",
            released=(
                "### Data / Migrations\n\n"
                "- Schema advances from version 20 to 24.\n"
            ),
        ))
        promoted = run("--version", "0.1.0-beta.7", "--previous-ref",
                       "v0.1.0-beta.6", cwd=repo)
        check("promoted beta with current migration endpoint passes",
              promoted.returncode == 0, promoted.stderr)

        write(repo, DATABASE, database(20))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n",
            released="### Added\n\n- No schema migration.\n",
        ))
        unchanged = run("--version", "0.1.0", "--previous-ref",
                        "v0.1.0-beta.6", cwd=repo)
        check("unchanged schema needs no migration section",
              unchanged.returncode == 0, unchanged.stderr)

        # A promotion that inserts a second `## [0.1.0]` heading instead of
        # merging into the existing one. This shipped as a real release branch:
        # the gate passed, and gen_release_notes rendered the correct body from
        # the first section, so the orphaned older section was invisible.
        write(repo, Path("app/CHANGELOG.md"), (
            "## [Unreleased]\n\n"
            "## [0.1.0] - 2026-08-11\n\n"
            "### Added\n\n- New beta work.\n\n"
            "## [0.1.0] - 2026-08-01\n\n"
            "### Added\n\n- Previous release.\n"
        ))
        duplicated = run("--version", "0.1.0-beta.7", "--previous-ref",
                         "v0.1.0-beta.6", cwd=repo)
        check("a second [0.1.0] heading is rejected",
              duplicated.returncode == 1, duplicated.stderr)
        check("the duplicate error names the count",
              "found 2" in duplicated.stderr, duplicated.stderr)

        # Taxonomy moves are only checked when the taxonomy source exists.
        write(repo, DATABASE, database(20))
        write(repo, TAXONOMY, taxonomy(23))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="",
            released="### Added\n\n- Previous release.\n",
        ))
        subprocess.run(["git", "add", "."], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-qm", "taxonomy baseline"], cwd=repo,
                       check=True)
        subprocess.run(["git", "tag", "v0.1.0-beta.7"], cwd=repo, check=True)

        write(repo, TAXONOMY, taxonomy(27))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n",
            released=(
                "### Data / Migrations\n\n"
                "- Schema unchanged.\n"
            ),
        ))
        taxonomy_missing = run("--version", "0.1.0-beta.8", "--previous-ref",
                               "v0.1.0-beta.7", cwd=repo)
        check("taxonomy move without a note is rejected",
              taxonomy_missing.returncode == 1, taxonomy_missing.stderr)
        check("the taxonomy error names the range",
              "23 -> 27" in taxonomy_missing.stderr, taxonomy_missing.stderr)

        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n",
            released=(
                "### Data / Migrations\n\n"
                "- Taxonomy advances from version 23 to 27.\n"
            ),
        ))
        taxonomy_noted = run("--version", "0.1.0-beta.8", "--previous-ref",
                             "v0.1.0-beta.7", cwd=repo)
        check("taxonomy move with a note passes",
              taxonomy_noted.returncode == 0, taxonomy_noted.stderr)

        write(repo, TAXONOMY, taxonomy(23))
        unchanged_taxonomy = run("--version", "0.1.0-beta.8", "--previous-ref",
                                 "v0.1.0-beta.7", cwd=repo)
        check("unchanged taxonomy needs no note",
              unchanged_taxonomy.returncode == 0, unchanged_taxonomy.stderr)

    if FAILURES:
        for failure in FAILURES:
            print(f"::error::{failure}")
        print(f"{len(FAILURES)} check(s) failed")
        return 1
    print("OK: all CHANGELOG promotion gate tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
