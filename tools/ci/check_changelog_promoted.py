#!/usr/bin/env python3
"""Reject release tags whose fragments are not compiled into CHANGELOG history.

It also holds a release to the schema rule in ``CONTRIBUTING.md`` ("Never bump
``schemaVersion`` in a PATCH release"): see :func:`_schema_step_errors`.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "release"))

from compile_changelog_fragments import FragmentError, fragment_paths

SCHEMA_CONSTANT = "kCompendiumSchemaVersion"
TAXONOMY_CONSTANT = "contraTaxonomyVersion"
# A one-time repair's completion marker, by the naming convention every sweep
# in `CompendiumRepositories.ensureMigrated` follows. A new one means the
# release runs a pass over stored figures or text on upgrade, schema bump or
# not, so the notes must say what it does.
_DONE_MARKER = re.compile(r"'(__[a-z0-9_]+_done__)'")
_CORE = r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
_SELECTED_VERSION = re.compile(rf"^(?P<core>{_CORE})(?:-beta)?$")


# A published release tag: ``v0.3.1``, ``v0.3.1-beta``, ``v0.1.0-beta.7``.
_RELEASE_TAG = re.compile(
    r"^v?(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)(?:-[0-9A-Za-z.-]+)?$"
)


def _release_core(ref: str) -> tuple[int, int, int] | None:
    """``(major, minor, patch)`` of a ``vX.Y.Z[-suffix]`` tag, or None if it is not one."""
    match = _RELEASE_TAG.fullmatch(ref)
    if match is None:
        return None
    return (int(match["major"]), int(match["minor"]), int(match["patch"]))


def _core_version(version: str) -> str:
    match = _SELECTED_VERSION.fullmatch(version)
    if match is None:
        raise ValueError(
            "version must be X.Y.Z or bare beta X.Y.Z-beta with a valid "
            "no-leading-zero core"
        )
    return match.group("core")


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


def _previous_source(ref: str, path: Path) -> str:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path.as_posix()}"],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )
    if result.returncode:
        raise ValueError(f"could not read {path} at previous ref {ref!r}")
    return result.stdout


def _previous_constant_version(ref: str, path: Path, constant: str) -> int | None:
    return _constant_version(_previous_source(ref, path), constant)


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


def _data_migrations(section: str | None) -> str | None:
    if section is None:
        return None
    migration = re.search(
        r"^###[ \t]+Data\s*/\s*Migrations[ \t]*$(.*?)(?=^#{1,3}[ \t]+\S|\Z)",
        section,
        flags=re.IGNORECASE | re.MULTILINE | re.DOTALL,
    )
    return None if migration is None else migration.group(1)


def _migration_reaches(
    section: str | None, target_version: int, keyword: str = "schema"
) -> bool:
    migration = _data_migrations(section)
    if migration is None:
        return False
    ends = re.findall(
        rf"\b{keyword}\b[^\n]*?(?:\bfrom\b[^\n]*?\bto\b|→|->)\s*"
        r"(?:version\s*)?(\d+)\b",
        migration,
        flags=re.IGNORECASE,
    )
    return str(target_version) in ends


def validate(
    *, version: str, changelog_text: str, schema_source: str, previous_ref: str | None,
    database: Path, taxonomy: Path | None = None,
) -> list[str]:
    """Return all compilation/freshness failures for a tagged release."""
    errors: list[str] = []
    core = _core_version(version)
    if _unreleased_has_items(changelog_text):
        errors.append(
            "## [Unreleased] contains list items; remove the direct edit and use "
            "a changelog fragment before compilation."
        )

    heading_count = _core_heading_count(changelog_text, core)
    if heading_count == 0:
        errors.append(
            f"expected exactly one ## [{core}] heading, found 0. "
            "Every stable and bare beta release requires its shared section."
        )
    if heading_count > 1:
        errors.append(
            f"expected exactly one ## [{core}] heading, found {heading_count}. "
            "The bare beta and its stable release share one section: compile "
            "new items into the existing one rather than adding another. "
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
    else:
        errors.extend(
            _schema_step_errors(
                version=version,
                previous_ref=previous_ref,
                previous_schema=previous_schema,
                current_schema=current_schema,
            )
        )
        if previous_schema != current_schema and not _migration_reaches(
            _section(changelog_text, core), current_schema
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
    errors.extend(
        _repair_marker_errors(
            changelog_text=changelog_text,
            core=core,
            schema_source=schema_source,
            previous_source=_previous_source(previous_ref, database),
        )
    )
    return errors


def _schema_step_errors(
    *, version: str, previous_ref: str, previous_schema: int, current_schema: int,
) -> list[str]:
    """Hold a release to ``CONTRIBUTING.md``: never bump the schema in a PATCH release.

    A schema change is a data-format change and rides at least a MINOR version
    bump. A *patch release* is one whose ``X.Y`` is the previous published tag's
    and whose ``Z`` is above zero, ``-beta`` included: ``0.3.0-beta`` ->
    ``0.3.1-beta`` and ``0.3.1-beta`` -> ``0.3.1`` both are, ``0.3.0-beta`` ->
    ``0.4.0-beta`` and a ``0.3.0-beta`` -> ``0.3.0`` promotion are not. The
    schema must also never go down, at any step. Only the release being cut is
    judged; earlier tags that broke the rule are not flagged again.

    An increase against a previous ref that is not a ``vX.Y.Z`` tag cannot be
    classified, and is refused rather than waved through.
    """
    tag = f"v{version}"
    if current_schema < previous_schema:
        return [
            f"{SCHEMA_CONSTANT} went down: {previous_schema} at {previous_ref} -> "
            f"{current_schema} in {tag}. A release never lowers the schema."
        ]
    if current_schema == previous_schema:
        return []
    current = _release_core(_core_version(version))
    previous = _release_core(previous_ref)
    if previous is None or current is None:
        return [
            f"{SCHEMA_CONSTANT} rose ({previous_schema} at {previous_ref} -> "
            f"{current_schema} in {tag}), but {previous_ref!r} is not a vX.Y.Z "
            "release tag, so this cannot be told from a patch release. Pass the "
            "previous published tag as --previous-ref."
        ]
    if current[:2] == previous[:2] and current[2] > 0:
        return [
            f"{tag} is a PATCH release (same {current[0]}.{current[1]} line as "
            f"{previous_ref}) but bumps {SCHEMA_CONSTANT} from {previous_schema} "
            f"({previous_ref}) to {current_schema} ({tag}). Never bump the schema "
            "in a PATCH release: a schema change rides at least a MINOR version "
            "(CONTRIBUTING.md, \"Database schema migrations\"). Move the change "
            "to the next minor release, or cut this release without it."
        ]
    return []


def _repair_marker_errors(
    *, changelog_text: str, core: str, schema_source: str, previous_source: str,
) -> list[str]:
    """A new one-time repair needs a Data / Migrations note.

    Repairs ship as settings markers rather than schema bumps (a PATCH release
    may not bump the schema), so neither version range above notices one. The
    gate cannot judge the prose; it requires the section to exist and to be
    non-empty, and the runbook says what it must describe.
    """
    added = sorted(
        set(_DONE_MARKER.findall(schema_source))
        - set(_DONE_MARKER.findall(previous_source))
    )
    if not added:
        return []
    migration = _data_migrations(_section(changelog_text, core))
    if migration is not None and migration.strip():
        return []
    return [
        f"new one-time repair marker(s) since the previous release "
        f"({', '.join(added)}), but ## [{core}] has no Data / Migrations "
        f"section describing what the pass does to stored data."
    ]


def _pending_fragments(directory: Path) -> list[str]:
    fragments = fragment_paths(directory)
    if not fragments:
        return []
    return [
        "pending changelog fragments remain: "
        + ", ".join(path.name for path in fragments)
    ]


def _taxonomy_errors(
    *, changelog_text: str, core: str, taxonomy: Path | None,
    previous_ref: str,
) -> list[str]:
    """Taxonomy moves are user-visible even though the constant migrates nothing.

    ``contraTaxonomyVersion`` is a documentary marker — nothing reads it at
    runtime — but a bump means dances are categorised or matched differently,
    which users notice. Any pass over stored data that ships with it is gated
    by its own marker, checked by ``_repair_marker_errors``. The runbook requires it in Data / Migrations alongside
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
    parser.add_argument("--fragments", type=Path, default=Path("changelog.d"))
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
        errors.extend(_pending_fragments(args.fragments))
    except (OSError, ValueError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"::error::{error}", file=sys.stderr)
        return 1
    print(
        "OK: CHANGELOG compilation, heading count, and schema/taxonomy/repair "
        "notes are current."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
