#!/usr/bin/env python3
"""Reject release tags whose CHANGELOG entries have not been promoted."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

SCHEMA_CONSTANT = "kCompendiumSchemaVersion"


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


def _schema_version(source: str) -> int | None:
    match = re.search(
        rf"\bconst\s+int\s+{SCHEMA_CONSTANT}\s*=\s*(\d+)\s*;", source
    )
    return int(match.group(1)) if match else None


def _previous_schema_version(ref: str, database: Path) -> int | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{database.as_posix()}"],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )
    if result.returncode:
        raise ValueError(f"could not read {database} at previous ref {ref!r}")
    return _schema_version(result.stdout)


def _unreleased_has_items(changelog: str) -> bool:
    section = _section(changelog, "Unreleased")
    if section is None:
        return False
    return any(
        re.match(r"^\s*(?:[-*+]\s+\S|\d+[.)]\s+\S)", line)
        for line in section.splitlines()
    )


def _migration_reaches(section: str | None, schema_version: int) -> bool:
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
        r"\bschema\b[^\n]*?(?:\bfrom\b[^\n]*?\bto\b|→|->)\s*"
        r"(?:version\s*)?(\d+)\b",
        migration.group(1),
        flags=re.IGNORECASE,
    )
    return str(schema_version) in ends


def validate(
    *, version: str, changelog_text: str, schema_source: str, previous_ref: str | None,
    database: Path,
) -> list[str]:
    """Return all promotion/freshness failures for a tagged release."""
    errors: list[str] = []
    if _unreleased_has_items(changelog_text):
        errors.append(
            "## [Unreleased] contains list items; promote them before tagging."
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
            f"## [{_core_version(version)}]'s Data / Migrations section does "
            f"not contain a schema range ending at {current_schema}."
        )
    return errors


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
        )
    except (OSError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"::error::{error}", file=sys.stderr)
        return 1
    print("OK: CHANGELOG promotion and schema migration notes are current.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
