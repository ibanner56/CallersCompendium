#!/usr/bin/env python3
"""Validate and compile pending JSON changelog fragments into release history.

Normal pull requests add one file to ``changelog.d`` rather than concurrently
editing either compiled CHANGELOG. A release invocation validates every
fragment, builds both output files in memory, writes them, and only then removes
the consumed fragments.

Usage:
    compile_changelog_fragments.py --check
    compile_changelog_fragments.py --app-version X.Y.Z --date YYYY-MM-DD --write
    compile_changelog_fragments.py --app-version X.Y.Z --core-version X.Y.Z \
        --date YYYY-MM-DD --write
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

APP_PATH = Path("app/CHANGELOG.md")
APP_PUBSPEC_PATH = Path("app/pubspec.yaml")
CORE_PATH = Path("packages/compendium_core/CHANGELOG.md")
CORE_PUBSPEC_PATH = Path("packages/compendium_core/pubspec.yaml")
FRAGMENTS_PATH = Path("changelog.d")
MARKER = "<!-- release-managed-by: tools/release/compile_changelog_fragments.py -->"
CATEGORIES = ("added", "changed", "fixed", "removed")
APP_CATEGORIES = (*CATEGORIES, "data_migrations")
CATEGORY_HEADINGS = {
    "added": "Added",
    "changed": "Changed",
    "fixed": "Fixed",
    "removed": "Removed",
    "data_migrations": "Data / Migrations",
}
VERSION = re.compile(r"^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SECTION = re.compile(r"^## \[(?P<version>[^\]]+)\](?: - \d{4}-\d{2}-\d{2})?$", re.MULTILINE)
CATEGORY = re.compile(r"^### (?P<category>.+?)\s*$", re.MULTILINE)


class FragmentError(ValueError):
    """A fragment or compilation input violates the release-note contract."""


@dataclass(frozen=True)
class Fragment:
    identifier: str
    user_visible: bool
    app: dict[str, tuple[str, ...]]
    core: dict[str, tuple[str, ...]]


@dataclass(frozen=True)
class ApplyResult:
    app_entries: int
    core_entries: int
    consumed_fragments: int


def _entries(value: object, *, identifier: str, audience: str, category: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        raise FragmentError(f"{identifier}: {audience}.{category} must be a non-empty array")
    if not all(
        isinstance(item, str)
        and item.strip()
        and "\n" not in item
        and "\r" not in item
        for item in value
    ):
        raise FragmentError(
            f"{identifier}: {audience}.{category} entries must be non-empty single-line strings"
        )
    return tuple(item.strip() for item in value)


def _audience(
    value: object, *, identifier: str, audience: str, allowed: tuple[str, ...]
) -> dict[str, tuple[str, ...]]:
    if value is None:
        return {}
    if not isinstance(value, dict) or not value:
        raise FragmentError(f"{identifier}: {audience} must be a non-empty object")
    unknown = set(value) - set(allowed)
    if unknown:
        raise FragmentError(f"{identifier}: unknown {audience} categories: {', '.join(sorted(unknown))}")
    return {
        category: _entries(
            entries, identifier=identifier, audience=audience, category=category
        )
        for category, entries in value.items()
    }


def load_fragments(directory: Path) -> list[Fragment]:
    """Load, fully validate, and return fragments in deterministic ID order."""
    fragments: list[Fragment] = []
    seen: set[str] = set()
    for path in fragment_paths(directory):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise FragmentError(f"{path}: invalid JSON: {error}") from error
        if not isinstance(data, dict):
            raise FragmentError(f"{path}: fragment must be a JSON object")
        if set(data) - {"id", "user_visible", "app", "core"}:
            raise FragmentError(f"{path}: only id, user_visible, app, and core are allowed")
        identifier = data.get("id")
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", identifier):
            raise FragmentError(f"{path}: id must be lowercase letters, digits, and hyphens")
        if identifier != path.stem:
            raise FragmentError(f"{path}: id {identifier!r} must match filename {path.stem!r}")
        if identifier in seen:
            raise FragmentError(f"duplicate fragment id: {identifier}")
        seen.add(identifier)
        user_visible = data.get("user_visible")
        if not isinstance(user_visible, bool):
            raise FragmentError(f"{identifier}: user_visible must be a boolean")
        app = _audience(data.get("app"), identifier=identifier, audience="app", allowed=APP_CATEGORIES)
        core = _audience(data.get("core"), identifier=identifier, audience="core", allowed=CATEGORIES)
        if not app and not core:
            raise FragmentError(f"{identifier}: add an app or core entry")
        if user_visible and not app:
            raise FragmentError(f"{identifier}: user-visible changes require an app entry")
        if not user_visible and app:
            raise FragmentError(f"{identifier}: non-user-visible changes cannot have an app entry")
        fragments.append(
            Fragment(identifier=identifier, user_visible=user_visible, app=app, core=core)
        )
    return fragments


def fragment_paths(directory: Path) -> list[Path]:
    """Return every fragment path, rejecting entries the compiler would ignore."""
    if not directory.is_dir():
        raise FragmentError(f"fragment directory not found: {directory}")
    paths = sorted(directory.iterdir())
    unexpected = [
        path.name
        for path in paths
        if path.name != "README.md" and (not path.is_file() or path.suffix != ".json")
    ]
    if unexpected:
        raise FragmentError(
            f"{directory}: unexpected entries; use only JSON fragments and README.md: "
            + ", ".join(unexpected)
        )
    return [path for path in paths if path.suffix == ".json"]


def _require_managed(changelog: str, path: Path) -> None:
    if not changelog.startswith(MARKER + "\n"):
        raise FragmentError(f"{path}: missing release-managed marker")


def _unreleased_has_content(changelog: str) -> bool:
    start = changelog.find("## [Unreleased]")
    if start < 0:
        raise FragmentError("compiled changelog has no [Unreleased] compatibility section")
    end = changelog.find("\n## ", start + len("## [Unreleased]"))
    section = changelog[start : len(changelog) if end < 0 else end]
    return section.removeprefix("## [Unreleased]").strip() not in {"", "_Nothing yet._"}


def check_pending_state(root: Path) -> None:
    """Reject direct contributor writes to either compiled compatibility section."""
    for relative_path in (APP_PATH, CORE_PATH):
        path = root / relative_path
        try:
            changelog = path.read_text(encoding="utf-8")
        except OSError as error:
            raise FragmentError(f"could not read {relative_path}: {error}") from error
        _require_managed(changelog, relative_path)
        if _unreleased_has_content(changelog):
            raise FragmentError(
                f"{relative_path}: [Unreleased] is release-managed; add a changelog.d fragment instead"
            )


def _section_bounds(changelog: str, version: str) -> tuple[int, int] | None:
    matches = list(SECTION.finditer(changelog))
    selected = [match for match in matches if match.group("version") == version]
    if len(selected) > 1:
        raise FragmentError(f"compiled changelog has duplicate [{version}] sections")
    if not selected:
        return None
    start = selected[0].start()
    following = next((match.start() for match in matches if match.start() > start), len(changelog))
    return start, following


def _render_entries(entries: dict[str, list[str]], categories: tuple[str, ...]) -> str:
    blocks = []
    for category in categories:
        values = entries.get(category, [])
        if values:
            blocks.append(
                f"### {CATEGORY_HEADINGS[category]}\n\n"
                + "".join(f"- {value}\n" for value in values).rstrip()
            )
    return "\n\n".join(blocks)


def _merge_section(existing: str | None, *, version: str, date: str, entries: dict[str, list[str]], categories: tuple[str, ...]) -> str:
    heading = f"## [{version}] - {date}"
    if existing is None:
        body = _render_entries(entries, categories)
        return f"{heading}\n\n{body}\n" if body else f"{heading}\n"

    lines = existing.splitlines()
    if not lines:
        raise FragmentError(f"compiled changelog has empty [{version}] section")
    body = "\n".join(lines[1:]).strip()
    existing_categories = [match.group("category") for match in CATEGORY.finditer(body)]
    if len(existing_categories) != len(set(existing_categories)):
        raise FragmentError(f"compiled changelog has repeated category in [{version}]")
    merged = body
    matches = list(CATEGORY.finditer(merged))
    locations = {match.group("category"): index for index, match in enumerate(matches)}
    missing: dict[str, list[str]] = {}
    # Work backwards so inserting after a category does not invalidate the
    # offsets of an earlier category.
    for category in reversed(categories):
        values = entries.get(category, [])
        category_heading = CATEGORY_HEADINGS[category]
        if not values:
            continue
        index = locations.get(category_heading)
        if index is None:
            missing[category] = values
            continue
        start = matches[index].end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(merged)
        addition = "".join(f"- {value}\n" for value in values).rstrip()
        existing_block = merged[start:end].rstrip()
        merged = f"{merged[:start]}{existing_block}\n{addition}\n\n{merged[end:]}".rstrip()
    appended = _render_entries(missing, categories)
    if appended:
        merged = f"{merged}\n\n{appended}".strip()
    return f"{heading}\n\n{merged}\n" if merged else f"{heading}\n"


def _replace_or_insert(changelog: str, *, version: str, date: str, entries: dict[str, list[str]], categories: tuple[str, ...]) -> str:
    bounds = _section_bounds(changelog, version)
    if bounds is None:
        marker = "## [Unreleased]"
        position = changelog.find(marker)
        if position < 0:
            raise FragmentError("compiled changelog has no [Unreleased] compatibility section")
        next_section = changelog.find("\n## ", position + len(marker))
        insertion = len(changelog) if next_section < 0 else next_section + 1
        section = _merge_section(None, version=version, date=date, entries=entries, categories=categories)
        return changelog[:insertion] + section + "\n" + changelog[insertion:]
    start, end = bounds
    section = _merge_section(
        changelog[start:end], version=version, date=date, entries=entries, categories=categories
    )
    return changelog[:start] + section + "\n" + changelog[end:]


def _collect(fragments: list[Fragment], audience: str, categories: tuple[str, ...]) -> dict[str, list[str]]:
    result = {category: [] for category in categories}
    for fragment in fragments:
        for category, entries in getattr(fragment, audience).items():
            result[category].extend(entries)
    return result


def _pubspec_version(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise FragmentError(f"could not read pubspec: {error}") from error
    match = re.search(r"^version:\s*([^\s#]+)\s*$", text, re.MULTILINE)
    if match is None:
        raise FragmentError(f"{path}: no version field")
    return match.group(1)


def compile_changelogs(
    *,
    app_changelog: str,
    core_changelog: str,
    fragments: list[Fragment],
    app_version: str,
    core_version: str | None,
    release_date: str,
) -> tuple[str, str]:
    """Return both release-managed changelogs without changing files."""
    if not VERSION.fullmatch(app_version) or not DATE.fullmatch(release_date):
        raise FragmentError("app version must be X.Y.Z and date must be YYYY-MM-DD")
    _require_managed(app_changelog, APP_PATH)
    _require_managed(core_changelog, CORE_PATH)
    app_entries = _collect(fragments, "app", APP_CATEGORIES)
    core_entries = _collect(fragments, "core", CATEGORIES)
    if any(core_entries.values()) and (core_version is None or not VERSION.fullmatch(core_version)):
        raise FragmentError("a valid core version is required when pending core entries exist")
    app_result = _replace_or_insert(
        app_changelog, version=app_version, date=release_date, entries=app_entries, categories=APP_CATEGORIES
    )
    core_result = core_changelog
    if any(core_entries.values()):
        core_result = _replace_or_insert(
            core_changelog,
            version=core_version,
            date=release_date,
            entries=core_entries,
            categories=CATEGORIES,
        )
    return app_result, core_result


def apply_release(
    *, root: Path, fragments: list[Fragment], app_version: str, core_version: str | None, release_date: str
) -> ApplyResult:
    """Compile after all inputs validate, then consume the fragments."""
    app_path, core_path = root / APP_PATH, root / CORE_PATH
    check_pending_state(root)
    if _pubspec_version(root / APP_PUBSPEC_PATH) != app_version:
        raise FragmentError("app version must match app/pubspec.yaml before compilation")
    core_entries = sum(
        len(item) for fragment in fragments for item in fragment.core.values()
    )
    if core_entries and _pubspec_version(root / CORE_PUBSPEC_PATH) != core_version:
        raise FragmentError(
            "core version must match packages/compendium_core/pubspec.yaml before compilation"
        )
    app, core = compile_changelogs(
        app_changelog=app_path.read_text(encoding="utf-8"),
        core_changelog=core_path.read_text(encoding="utf-8"),
        fragments=fragments,
        app_version=app_version,
        core_version=core_version,
        release_date=release_date,
    )
    temporary_app, temporary_core = app_path.with_suffix(".md.tmp"), core_path.with_suffix(".md.tmp")
    temporary_app.write_text(app, encoding="utf-8")
    temporary_core.write_text(core, encoding="utf-8")
    temporary_app.replace(app_path)
    temporary_core.replace(core_path)
    for fragment in fragments:
        (root / FRAGMENTS_PATH / f"{fragment.identifier}.json").unlink()
    return ApplyResult(
        app_entries=sum(len(item) for fragment in fragments for item in fragment.app.values()),
        core_entries=core_entries,
        consumed_fragments=len(fragments),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--check", action="store_true", help="validate fragments without writing")
    parser.add_argument("--write", action="store_true", help="compile and consume all pending fragments")
    parser.add_argument("--app-version")
    parser.add_argument("--core-version")
    parser.add_argument("--date", dest="release_date")
    args = parser.parse_args(argv)
    if args.check == args.write:
        parser.error("specify exactly one of --check or --write")
    try:
        fragments = load_fragments(args.root / FRAGMENTS_PATH)
        if args.check:
            check_pending_state(args.root)
            print(f"OK: {len(fragments)} changelog fragment(s) are valid.")
            return 0
        if not args.app_version or not args.release_date:
            raise FragmentError("--write requires --app-version and --date")
        result = apply_release(
            root=args.root,
            fragments=fragments,
            app_version=args.app_version,
            core_version=args.core_version,
            release_date=args.release_date,
        )
    except (OSError, FragmentError) as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    print(
        f"OK: compiled {result.app_entries} app and {result.core_entries} core entries; "
        f"consumed {result.consumed_fragments} fragment(s)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
