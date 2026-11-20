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


def changelog(*, unreleased: str, released: str, core: str = "0.1.0") -> str:
    return f"""\
## [Unreleased]

{unreleased}
## [{core}] - 2026-08-07

{released}
"""


FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


sys.path.insert(0, str(HERE))
import check_changelog_promoted as gate  # noqa: E402


def step(previous_ref: str, version: str, before: int, after: int) -> list[str]:
    return gate._schema_step_errors(
        version=version, previous_ref=previous_ref,
        previous_schema=before, current_schema=after,
    )


def patch_release_rule() -> None:
    """The pure rule: no schema bump in a PATCH release, beta included."""
    print("patch-release schema rule:")
    must_fail = [
        # (previous published tag, release version, schema before, after, why)
        ("v0.3.0-beta", "0.3.1-beta", 31, 32, "the issue's case: a beta patch bump"),
        ("v0.3.0-beta", "0.3.1", 31, 32, "a stable patch bump"),
        ("v0.3.0", "0.3.1", 31, 32, "stable to stable patch bump"),
        ("v0.3.1-beta", "0.3.1", 31, 32, "stable promotion of a patch beta still bumping"),
        ("v0.3.0-beta", "0.3.5-beta", 31, 35, "a larger Z"),
        ("v0.10.0-beta", "0.10.1-beta", 41, 42, "two-digit minor"),
        ("v0.1.0-beta.7", "0.1.1-beta", 31, 32, "a counter-suffixed previous tag"),
        ("0.3.0-beta", "0.3.1-beta", 31, 32, "a previous ref without the v prefix"),
        ("v0.3.1-beta", "0.3.2", 33, 32, "a decrease inside a patch line"),
        ("v0.3.0", "0.4.0", 33, 32, "a decrease at a minor step"),
        ("v0.3.0", "1.0.0", 33, 32, "a decrease at a major step"),
        ("abc1234", "0.3.1", 31, 32, "a rise against a ref that is not a release tag"),
        ("v٣.0.0", "0.3.1", 31, 32, "a tag with non-ASCII digits is not a release tag"),
        ("v01.2.3", "0.3.1", 31, 32, "a tag with a leading zero is not a release tag"),
    ]
    for previous, version, before, after, why in must_fail:
        errors = step(previous, version, before, after)
        check(f"fails: {why} ({previous} -> {version}, {before}->{after})",
              len(errors) == 1, str(errors))
    must_pass = [
        ("v0.3.0-beta", "0.4.0-beta", 31, 32, "a minor step with a bump"),
        ("v0.3.0", "1.0.0", 31, 32, "a major step with a bump"),
        ("v0.3.0-beta", "0.3.0", 31, 32, "promoting a minor's beta (Z is 0)"),
        ("v0.3.0", "0.3.1", 32, 32, "a patch with no schema change"),
        ("v0.3.0-beta", "0.3.1-beta", 32, 32, "a beta patch with no schema change"),
        ("v0.9.2-beta", "0.10.1-beta", 31, 32, "0.9 -> 0.10 is a minor step (when 0.10.0 was never published)"),
        ("v0.3.0", "0.4.1", 31, 32, "a minor step that also has a Z"),
        ("abc1234", "0.3.1", 32, 32, "an unclassifiable ref with no schema change"),
    ]
    for previous, version, before, after, why in must_pass:
        errors = step(previous, version, before, after)
        check(f"passes: {why} ({previous} -> {version}, {before}->{after})",
              errors == [], str(errors))

    (message,) = step("v0.3.0-beta", "0.3.1-beta", 31, 32)
    check("the failure names both tags", "v0.3.0-beta" in message and "v0.3.1-beta" in message, message)
    check("the failure names both schema values", "31" in message and "32" in message, message)
    check("the failure names the constant and the rule", "kCompendiumSchemaVersion" in message and "PATCH" in message, message)
    (down,) = step("v0.3.0", "0.4.0", 33, 32)
    check("a decrease names both tags and values", all(x in down for x in ("v0.3.0", "v0.4.0", "33", "32")), down)


def main() -> int:
    FAILURES.clear()
    patch_release_rule()
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, check=True)
        (repo / "changelog.d").mkdir()
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
        subprocess.run(["git", "tag", "v0.1.0-beta"], cwd=repo, check=True)

        # This mirrors a stale beta section plus populated Unreleased.
        write(repo, DATABASE, database(24))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n- New beta work.\n",
            released=(
                "> Upgrading rewrites stored figures (schema 15 → 20).\n\n"
                "### Data / Migrations\n\n"
                "- Schema advances from version 15 to 20.\n"
            ),
        ))
        stale = run("--version", "0.1.0-beta", "--previous-ref",
                    "v0.1.0-beta", cwd=repo)
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
        promoted = run("--version", "0.1.0-beta", "--previous-ref",
                       "v0.1.0-beta", cwd=repo)
        check("promoted beta with current migration endpoint passes",
              promoted.returncode == 0, promoted.stderr)

        write(repo, Path("changelog.d/pending.json"), "{}")
        pending = run("--version", "0.1.0-beta", "--previous-ref",
                      "v0.1.0-beta", cwd=repo)
        check("pending fragments reject a tag", pending.returncode == 1,
              pending.stderr)
        check("pending fragment is named", "pending.json" in pending.stderr,
              pending.stderr)
        (repo / "changelog.d/pending.json").unlink()

        write(repo, DATABASE, database(20))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n",
            released="### Added\n\n- No schema migration.\n",
        ))
        unchanged = run("--version", "0.1.0", "--previous-ref",
                        "v0.1.0-beta", cwd=repo)
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
        duplicated = run("--version", "0.1.0-beta", "--previous-ref",
                         "v0.1.0-beta", cwd=repo)
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
        subprocess.run(["git", "tag", "v0.2.0-beta"], cwd=repo, check=True)

        write(repo, TAXONOMY, taxonomy(27))
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n",
            released=(
                "### Data / Migrations\n\n"
                "- Schema unchanged.\n"
            ),
            core="0.2.0",
        ))
        taxonomy_missing = run("--version", "0.2.0-beta", "--previous-ref",
                               "v0.2.0-beta", cwd=repo)
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
            core="0.2.0",
        ))
        taxonomy_noted = run("--version", "0.2.0-beta", "--previous-ref",
                             "v0.2.0-beta", cwd=repo)
        check("taxonomy move with a note passes",
              taxonomy_noted.returncode == 0, taxonomy_noted.stderr)

        write(repo, TAXONOMY, taxonomy(23))
        unchanged_taxonomy = run("--version", "0.2.0-beta", "--previous-ref",
                                 "v0.2.0-beta", cwd=repo)
        check("unchanged taxonomy needs no note",
              unchanged_taxonomy.returncode == 0, unchanged_taxonomy.stderr)

        # A new one-time repair marker, with neither version moving: a PATCH
        # release shipping a repair as a settings marker.
        marker = "const String k = '__example_repair_done__';\n"
        write(repo, DATABASE, database(20) + marker)
        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n",
            released="### Fixed\n\n- A repair.\n",
            core="0.2.0",
        ))
        marker_missing = run("--version", "0.2.0-beta", "--previous-ref",
                             "v0.2.0-beta", cwd=repo)
        check("a new repair marker without a note is rejected",
              marker_missing.returncode == 1, marker_missing.stderr)
        check("the repair error names the marker",
              "__example_repair_done__" in marker_missing.stderr,
              marker_missing.stderr)

        write(repo, Path("app/CHANGELOG.md"), changelog(
            unreleased="### Added\n\n",
            released=(
                "### Data / Migrations\n\n"
                "- A one-time pass rewrites stored figures on first launch.\n"
            ),
            core="0.2.0",
        ))
        marker_noted = run("--version", "0.2.0-beta", "--previous-ref",
                           "v0.2.0-beta", cwd=repo)
        check("a new repair marker with a note passes",
              marker_noted.returncode == 0, marker_noted.stderr)
        write(repo, DATABASE, database(20))

        invalid_beta = run("--version", "0.2.0-beta.1", cwd=repo)
        check("beta counters are rejected", invalid_beta.returncode != 0,
              invalid_beta.stderr)

    patch_release_end_to_end()

    if FAILURES:
        for failure in FAILURES:
            print(f"::error::{failure}")
        print(f"{len(FAILURES)} check(s) failed")
        return 1
    print("OK: all CHANGELOG promotion gate tests passed")
    return 0


def patch_release_end_to_end() -> None:
    """The same rule through the CLI, against real tags in a throwaway repository."""
    print("patch-release schema rule, end to end:")
    with tempfile.TemporaryDirectory() as temp:
        repo = Path(temp)
        git = lambda *args: subprocess.run(["git", *args], cwd=repo, check=True)  # noqa: E731
        git("init", "-q", "-b", "main")
        git("config", "user.email", "test@example.invalid")
        git("config", "user.name", "Test")
        (repo / "changelog.d").mkdir()

        def notes(core: str, schema_from: int | None = None, schema_to: int | None = None) -> str:
            migration = (
                f"### Data / Migrations\n\n- Schema advances from version {schema_from} to {schema_to}.\n"
                if schema_from is not None else "### Added\n\n- Something.\n"
            )
            return f"## [Unreleased]\n\n## [{core}] - 2026-08-07\n\n{migration}"

        write(repo, DATABASE, database(31))
        write(repo, Path("app/CHANGELOG.md"), notes("0.3.0"))
        git("add", ".")
        git("commit", "-qm", "v0.3.0-beta")
        git("tag", "v0.3.0-beta")

        # The red case from the issue: 0.3.0-beta -> 0.3.1-beta with schema 31 -> 32,
        # even though its Data / Migrations note is present and correct.
        write(repo, DATABASE, database(32))
        write(repo, Path("app/CHANGELOG.md"), notes("0.3.1", 31, 32))
        red = run("--version", "0.3.1-beta", "--previous-ref", "v0.3.0-beta", cwd=repo)
        check("a beta patch release that bumps the schema is rejected", red.returncode == 1, red.stderr)
        check("the error names both tags and both values",
              all(x in red.stderr for x in ("v0.3.0-beta", "v0.3.1-beta", "31", "32")), red.stderr)
        check("the error says why", "PATCH release" in red.stderr, red.stderr)

        stable = run("--version", "0.3.1", "--previous-ref", "v0.3.0-beta", cwd=repo)
        check("the same bump in a stable patch release is rejected too", stable.returncode == 1, stable.stderr)

        # The same schema change as a minor release passes.
        write(repo, Path("app/CHANGELOG.md"), notes("0.4.0", 31, 32))
        minor = run("--version", "0.4.0-beta", "--previous-ref", "v0.3.0-beta", cwd=repo)
        check("the same bump in a minor release passes", minor.returncode == 0, minor.stderr)

        # A patch with no schema change passes.
        write(repo, DATABASE, database(31))
        write(repo, Path("app/CHANGELOG.md"), notes("0.3.1"))
        quiet = run("--version", "0.3.1-beta", "--previous-ref", "v0.3.0-beta", cwd=repo)
        check("a patch release with no schema change passes", quiet.returncode == 0, quiet.stderr)

        # A decrease fails at any step.
        write(repo, DATABASE, database(30))
        write(repo, Path("app/CHANGELOG.md"), notes("0.4.0", 31, 30))
        down = run("--version", "0.4.0-beta", "--previous-ref", "v0.3.0-beta", cwd=repo)
        check("a schema decrease is rejected", down.returncode == 1 and "went down" in down.stderr, down.stderr)

        # A previous ref that is not a release tag: a rise cannot be classified.
        write(repo, DATABASE, database(32))
        write(repo, Path("app/CHANGELOG.md"), notes("0.3.1", 31, 32))
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, check=True,
                             capture_output=True, encoding="utf-8").stdout.strip()
        odd = run("--version", "0.3.1-beta", "--previous-ref", sha, cwd=repo)
        check("a rise against a commit ref is refused, not passed",
              odd.returncode == 1 and "not a vX.Y.Z release tag" in odd.stderr, odd.stderr)

        # Errors stack: a patch bump with no Data / Migrations note reports both.
        write(repo, Path("app/CHANGELOG.md"), notes("0.3.1"))
        both = run("--version", "0.3.1-beta", "--previous-ref", "v0.3.0-beta", cwd=repo)
        check("a patch bump without a migration note reports both problems",
              both.returncode == 1 and "PATCH release" in both.stderr
              and "schema range" in both.stderr, both.stderr)

        # No previous published tag: the existing handling, no new failure.
        write(repo, DATABASE, database(32))
        write(repo, Path("app/CHANGELOG.md"), notes("0.3.1", 31, 32))
        first = run("--version", "0.3.1-beta", cwd=repo)
        check("with no previous tag the rule does not apply", first.returncode == 0, first.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
