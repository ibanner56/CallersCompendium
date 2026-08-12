#!/usr/bin/env python3
"""Reject release tags whose CHANGELOG entries have not been promoted."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SCHEMA_CONSTANT = "kCompendiumSchemaVersion"
TAXONOMY_CONSTANT = "contraTaxonomyVersion"


def _core_version(version: str) -> str:
    return re.split(r"[-+]", version.strip(), maxsplit=1)[0]


def _section(changelog: str, heading: str, level: int = 2) -> str | None:
    pattern = re.compile(rf"^{'#' * level}[ \t]+\[{re.escape(heading)}\][^\n]*$")
    lines = changelog.splitlines()
    for start, line in enumerate(lines):
        if pattern.match(line):
            body: list[str] = []
            for candidate in lines[start + 1 :]:
                if re.match(rf"^#{{1,{level}}}[ \t]+\S", candidate):
                    break
                body.append(candidate)
            return "\n".join(body)
    return None


def _constant_version(source: str, constant: str) -> int | None:
    match = re.search(
        rf"\bconst\s+int\s+{constant}\s*=\s*(\d+)\s*;", source
    )
    return int(match.group(1)) if match else None


def _schema_version(source: str) -> int | None:
    return _constant_version(source, SCHEMA_CONSTANT)


def _previous_constant_version(ref: str, path: Path, constant: str) -> int | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path.as_posix()}"],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )
    if result.returncode:
        raise ValueError(f"could not read {path} at previous ref {ref!r}")
    return _constant_version(result.stdout, constant)


def _previous_schema_version(ref: str, database: Path) -> int | None:
    return _previous_constant_version(ref, database, SCHEMA_CONSTANT)


def _core_heading_count(changelog: str, core: str) -> int:
    pattern = re.compile(
        rf"^##[ \t]+\[{re.escape(core)}\][^\n]*$", flags=re.MULTILINE
    )
    return len(pattern.findall(changelog))


def _unreleased_has_items(changelog: str) -> bool:
    section = _section(changelog, "Unreleased")
    if section is None:
        return False
    return any(
        re.match(r"^\s*(?:[-*+]\s+\S|\d+[.)]\s+\S)", line)
        for line in section.splitlines()
    )


def _migration_reaches(
    section: str | None, target_version: int, keyword: str = "schema"
) -> bool:
    if section is None:
        return False
    migration = re.search(
        r"^###[ \t]+Data\s*/\s*Migrations[ \t]*$(.*?)(?=^#{1,3}[ \t]+\S|\Z)",
        section,
        flags=re.IGNORECASE | re.MULTILINE | re.DOTALL,
    )
    if migration is None:
        return False
    ends = re.findall(
        rf"\b{keyword}\b[^\n]*?(?:\bfrom\b[^\n]*?\bto\b|→|->)\s*"
        r"(?:version\s*)?(\d+)\b",
        migration.group(1),
        flags=re.IGNORECASE,
    )
    return str(target_version) in ends


def validate(
    *, version: str, changelog_text: str, schema_source: str, previous_ref: str | None,
    database: Path, taxonomy: Path | None = None,
) -> list[str]:
    """Return all promotion/freshness failures for a tagged release."""
    errors: list[str] = []
    core = _core_version(version)
    if _unreleased_has_items(changelog_text):
        errors.append(
            "## [Unreleased] contains list items; promote them before tagging."
        )

    heading_count = _core_heading_count(changelog_text, core)
    if heading_count > 1:
        errors.append(
            f"expected exactly one ## [{core}] heading, found {heading_count}. "
            "Successive prereleases in a line share one section: merge the "
            "promoted items into the existing one rather than adding another. "
            "Release notes render from the first section, so the later "
            "duplicate is silently orphaned."
        )

    current_schema = _schema_version(schema_source)
    if current_schema is None:
        errors.append(f"could not read {SCHEMA_CONSTANT} from {database}.")
        return errors
    if previous_ref is None:
        return errors

    previous_schema = _previous_schema_version(previous_ref, database)
    if previous_schema is None:
        errors.append(
            f"could not read {SCHEMA_CONSTANT} from {database} at {previous_ref!r}."
        )
    elif previous_schema != current_schema and not _migration_reaches(
        _section(changelog_text, _core_version(version)), current_schema
    ):
        errors.append(
            f"schema changed ({previous_schema} -> {current_schema}), but "
            f"## [{core}]'s Data / Migrations section does "
            f"not contain a schema range ending at {current_schema}."
        )

    errors.extend(
        _taxonomy_errors(
            changelog_text=changelog_text,
            core=core,
            taxonomy=taxonomy,
            previous_ref=previous_ref,
        )
    )
    return errors


def _taxonomy_errors(
    *, changelog_text: str, core: str, taxonomy: Path | None,
    previous_ref: str | None,
) -> list[str]:
    """Taxonomy moves are user-visible even though nothing migrates.

    ``contraTaxonomyVersion`` is a documentary marker — nothing reads it at
    runtime — but a bump means dances are categorised or matched differently,
    which users notice. The runbook requires it in Data / Migrations alongside
    the schema range.
    """
    if taxonomy is None or not taxonomy.exists():
        return []
    current = _constant_version(
        taxonomy.read_text(encoding="utf-8"), TAXONOMY_CONSTANT
    )
    if current is None:
        return [f"could not read {TAXONOMY_CONSTANT} from {taxonomy}."]
    previous = _previous_constant_version(previous_ref, taxonomy, TAXONOMY_CONSTANT)
    if previous is None:
        return [
            f"could not read {TAXONOMY_CONSTANT} from {taxonomy} "
            f"at {previous_ref!r}."
        ]
    if previous == current:
        return []
    if _migration_reaches(_section(changelog_text, core), current, "taxonomy"):
        return []
    return [
        f"taxonomy changed ({previous} -> {current}), but ## [{core}]'s "
        f"Data / Migrations section does not contain a taxonomy range ending "
        f"at {current}."
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--changelog", type=Path, default=Path("app/CHANGELOG.md"))
    parser.add_argument(
        "--database",
        type=Path,
        default=Path("packages/compendium_core/lib/src/storage/database.dart"),
    )
    parser.add_argument(
        "--taxonomy",
        type=Path,
        default=Path(
            "packages/compendium_core/lib/src/taxonomy/contra_taxonomy.dart"
        ),
    )
    parser.add_argument(
        "--previous-ref",
        help="previous release tag/ref; omit for the first release",
    )
    args = parser.parse_args(argv)

    try:
        errors = validate(
            version=args.version,
            changelog_text=args.changelog.read_text(encoding="utf-8"),
            schema_source=args.database.read_text(encoding="utf-8"),
            previous_ref=args.previous_ref,
            database=args.database,
            taxonomy=args.taxonomy,
        )
    except (OSError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"::error::{error}", file=sys.stderr)
        return 1
    print(
        "OK: CHANGELOG promotion, heading count, and schema/taxonomy notes "
        "are current."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
