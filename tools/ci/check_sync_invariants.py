#!/usr/bin/env python3
"""CI ratchets for the invariants shared by future device-sync paths.

The checker deliberately covers the production source roots only:
``app/lib/src`` and ``packages/*/lib/src``.  It checks:

* every Drift or raw-SQL join through a soft-deletable parent has a
  ``deleted_at IS NULL`` predicate;
* raw SQL content updates advance ``updated_at`` (I1), and raw SQL updates that
  advance ``updated_at`` also change content or existence state (I2);
* the concrete certificate-validation escape hatches are absent;
* ``normalizeTitle`` has exactly one implementation, and sync title call sites
  import and call that definition; and
* once a ``syncId`` use appears, ``normalizeSyncId`` has exactly one shared
  definition imported and called by both sync client and server units.

The sync-ID check is intentionally dormant while sync code is absent, but it is
not an unconditional pass: the first sync-ID marker activates the definition and
import requirements.  Unsupported source shapes fail closed.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

from check_debug_print import mask_source
from check_settings_marker_reads import extract_sql_literals

REPO_ROOT = Path(__file__).resolve().parents[2]

SOFT_SQL_TABLES = frozenset(
    {
        "dances",
        "programs",
        "choreographers",
        "tags",
        "custom_field_defs",
        "published_sources",
        "venues",
        "settings",
    }
)

SOFT_DRIFT_TABLES = {
    "dances",
    "programs",
    "choreographers",
    "tags",
    "customFieldDefs",
    "publishedSources",
    "venues",
    "settings",
}
SQL_ALIAS_STOP_WORDS = frozenset(
    {"where", "join", "on", "group", "order", "limit", "having", "union"}
)

I1_EXCEPTION_MARKER_RE = re.compile(
    r"sync-invariant-exception:\s*content-derived\b[^\n]*",
    re.IGNORECASE,
)
NON_SYNC_WRITE_EXCLUSION_RE = re.compile(
    r"sync-invariant-exclusion:\s*"
    r"(?:migration-backfill|maintenance-backfill|maintenance-cleanup)\b[^\n]*",
    re.IGNORECASE,
)
SOFT_JOIN_EXCEPTION_RE = re.compile(
    r"sync-invariant-exception:\s*soft-delete-join\b[^\n]*",
    re.IGNORECASE,
)
SUBQUERY_JOIN_RE = re.compile(r"\bJOIN\s*\(\s*SELECT\b", re.IGNORECASE)
DRIFT_MUTATION_ROOT_RE = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*\s*\.\s*(?:update|into)\s*\("
)
DRIFT_BATCH_MUTATION_RE = re.compile(
    r"\b(?!_?db\b)[A-Za-z_][A-Za-z0-9_]*\s*\.\s*"
    r"(?:insert|update|replace|delete)\s*\("
)
DRIFT_MUTATION_METHOD_RE = re.compile(
    r"\.(?:write|insert(?:OnConflictUpdate)?|replace)\s*\("
)

JOIN_RE = re.compile(
    r"\b(?:INNER\s+|LEFT(?:\s+OUTER)?\s+|CROSS\s+)?JOIN\s+"
    r"([a-z_][a-z0-9_]*)(?:\s+(?:AS\s+)?([a-z_][a-z0-9_]*))?",
    re.IGNORECASE,
)
DRIFT_JOIN_RE = re.compile(r"\b(?:innerJoin|leftOuterJoin)\s*\(")
DRIFT_TABLE_RE = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*\.([A-Za-z_][A-Za-z0-9_]*)\b"
)
UPDATE_RE = re.compile(
    r"\bUPDATE\b.*?\bSET\b(?P<set>.*?)(?:\bWHERE\b|$)",
    re.IGNORECASE | re.DOTALL,
)
ASSIGNMENT_RE = re.compile(r"\b([a-z_][a-z0-9_]*)\s*=", re.IGNORECASE)
SERIALIZED_COLUMNS = frozenset(
    {"figures_json", "body", "body_json", "record_json", "canonical_json"}
)

CERTIFICATE_PATTERNS = (
    (
        "badCertificateCallback",
        re.compile(r"\.badCertificateCallback\s*(?:\?\?=|=(?!=))", re.IGNORECASE),
    ),
    (
        "SecurityContext(withTrustedRoots: false)",
        re.compile(
            r"\bSecurityContext\s*\(\s*withTrustedRoots\s*:\s*false\b",
            re.IGNORECASE,
        ),
    ),
    (
        "SecurityContext.setTrustedCertificates",
        re.compile(r"\.setTrustedCertificates\s*\(", re.IGNORECASE),
    ),
    (
        "SecurityContext.setTrustedCertificatesBytes",
        re.compile(r"\.setTrustedCertificatesBytes\s*\(", re.IGNORECASE),
    ),
)

NORMALIZE_TITLE_DEF_RE = re.compile(
    r"^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_<>,? ]*\s+"
    r"normalizeTitle\s*\([^;\n]*\)\s*(?:\{|=>)",
    re.MULTILINE,
)
FUNCTION_DEF_RE = re.compile(
    r"^\s*(?:(?:static|external|abstract)\s+)*"
    r"(?:[A-Za-z_][A-Za-z0-9_<>,?]*\s+)+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*"
    r"\((?P<parameters>[^;\n]*)\)\s*(?P<body>\{|=>)",
    re.MULTILINE,
)
NORMALIZATION_OPERATION_RE = re.compile(
    r"\b(?:trim|toLowerCase|toUpperCase|replaceAll|replaceFirst|"
    r"normalize|normalise|fold|collapse|sanitize|canonicalize)"
    r"[A-Za-z0-9_]*\s*\(",
)
TITLE_NORMALIZER_NAME_RE = re.compile(
    r"(?:normalize|normalise|canonical|sanitize|fold)", re.IGNORECASE
)
TITLE_BEHAVIOR_RE = re.compile(
    r"\b(?:toLowerCase|toUpperCase|replaceAll|replaceFirst|"
    r"normalize|normalise|fold)\s*\(",
)
SYNC_ID_MARKER_RE = re.compile(
    r"\b(?:sync[_-]?id|syncId|syncID)\b",
    re.IGNORECASE,
)
SYNC_ID_DEF_RE = re.compile(
    r"^\s*(?:static\s+)?[A-Za-z_][A-Za-z0-9_<>,? ]*\s+"
    r"normalizeSyncId\s*\([^;\n]*\)\s*(?:\{|=>)",
    re.MULTILINE,
)
SYNC_ID_IMPORT_RE = re.compile(
    r"^\s*import\s+[^;]*(?:normalizeSyncId|sync[_-]?normaliz)",
    re.MULTILINE | re.IGNORECASE,
)
IMPORT_RE = re.compile(
    r"^\s*import\s+['\"](?P<uri>[^'\"]+)['\"](?P<clause>[^;]*)\s*;",
    re.MULTILINE,
)
EXPORT_RE = re.compile(
    r"^\s*export\s+['\"](?P<uri>[^'\"]+)['\"](?P<clause>[^;]*)\s*;",
    re.MULTILINE,
)


@dataclass(frozen=True)
class Violation:
    kind: str
    path: str
    line: int
    detail: str

    def format(self) -> str:
        return f"{self.path}:{self.line}: {self.detail}"


@dataclass(frozen=True)
class ScanResult:
    violations: tuple[Violation, ...]
    soft_join_candidates: int
    normalize_title_definitions: int
    sync_id_activated: bool


def blank_comments(source: str) -> str:
    """Blank comments exactly as the settings classification ratchet does."""

    source = re.sub(
        r"/\*.*?\*/",
        lambda match: re.sub(r"[^\n]", " ", match.group(0)),
        source,
        flags=re.DOTALL,
    )
    return re.sub(
        r"//[^\n]*",
        lambda match: " " * len(match.group(0)),
        source,
    )


def source_roots(root: Path) -> list[Path]:
    """Return ``app/lib/src`` plus every existing ``packages/*/lib/src``."""

    roots: list[Path] = []
    app_root = root / "app" / "lib" / "src"
    if app_root.is_dir():
        roots.append(app_root)
    packages = root / "packages"
    if packages.is_dir():
        for package in sorted(path for path in packages.iterdir() if path.is_dir()):
            package_root = package / "lib" / "src"
            if package_root.is_dir():
                roots.append(package_root)
    return roots


def source_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for source_root in source_roots(root):
        files.extend(sorted(source_root.rglob("*.dart")))
    return files


def _line_number(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def _exception_on_line(
    source: str,
    line: int,
    pattern: re.Pattern[str] = I1_EXCEPTION_MARKER_RE,
) -> bool:
    lines = source.splitlines()
    if line <= 1:
        return False
    value = lines[line - 2]
    if not pattern.search(value):
        return False
    if pattern is I1_EXCEPTION_MARKER_RE:
        normalized = value.lower()
        return "idempotent" in normalized and "divergence" in normalized
    return True


def _statement_for(content: str, offset: int) -> str:
    starts = [
        content.rfind(token, 0, offset)
        for token in ("SELECT", "UPDATE", "DELETE", "INSERT", ";")
    ]
    start = max(starts)
    if start >= 0 and content[start] == ";":
        start += 1
    end = content.find(";", offset)
    return content[start:] if end < 0 else content[start:end]


def _raw_join_violations(source: str, path: str) -> tuple[list[Violation], int]:
    violations: list[Violation] = []
    candidates = 0
    for literal in extract_sql_literals(blank_comments(source)):
        if not literal.parseable:
            if JOIN_RE.search(literal.content) and any(
                re.search(rf"\bJOIN\s+{table}\b", literal.content, re.IGNORECASE)
                for table in SOFT_SQL_TABLES
            ):
                violations.append(
                    Violation(
                        "soft-delete-join-boundary",
                        path,
                        literal.line_no,
                        "cannot verify a soft-delete join in a raw/triple-quoted "
                        "literal; use plain quoted literals or extend the parser",
                    )
                )
            continue
        for match in SUBQUERY_JOIN_RE.finditer(literal.content):
            open_at = literal.content.find("(", match.start())
            end = _balanced_call_end(literal.content, open_at)
            if end is None:
                violations.append(
                    Violation(
                        "soft-delete-join-boundary",
                        path,
                        literal.line_no,
                        "unbalanced joined subquery; cannot verify its parent filter",
                    )
                )
                continue
            subquery = literal.content[open_at + 1 : end]
            references = re.findall(
                r"\b(?:FROM|JOIN)\s+([a-z_][a-z0-9_]*)"
                r"(?:\s+(?:AS\s+)?([a-z_][a-z0-9_]*))?",
                subquery,
                re.IGNORECASE,
            )
            soft_references = [
                (
                    table.lower(),
                    alias.lower()
                    if alias and alias.lower() not in SQL_ALIAS_STOP_WORDS
                    else None,
                )
                for table, alias in references
                if table.lower() in SOFT_SQL_TABLES
            ]
            for table, alias in soft_references:
                candidates += 1
                if len(soft_references) > 1 and alias is None:
                    violations.append(
                        Violation(
                            "soft-delete-join-boundary",
                            path,
                            literal.line_no,
                            f"joined subquery reading {table} has no alias for "
                            "per-parent deleted_at verification",
                        )
                    )
                    continue
                predicate = (
                    rf"\b{re.escape(alias)}\.deleted_at\s+IS\s+NULL\b"
                    if alias
                    else r"\bdeleted_at\s+IS\s+NULL\b"
                )
                if re.search(predicate, subquery, re.IGNORECASE):
                    continue
                violations.append(
                    Violation(
                        "soft-delete-join",
                        path,
                        literal.line_no,
                        f"joined subquery reading {table} must filter "
                        "deleted_at IS NULL",
                    )
                )
        for match in JOIN_RE.finditer(literal.content):
            table = match.group(1).lower()
            if table not in SOFT_SQL_TABLES:
                continue
            candidates += 1
            statement = _statement_for(literal.content, match.start())
            alias = match.group(2)
            if alias and alias.lower() not in {"on", "where", "join"}:
                predicate = re.compile(
                    rf"\b{re.escape(alias)}\.deleted_at\s+IS\s+NULL\b",
                    re.IGNORECASE,
                )
            else:
                predicate = re.compile(r"\bdeleted_at\s+IS\s+NULL\b", re.IGNORECASE)
            if predicate.search(statement) or _predicate_in_call_scope(
                source, literal.line_no, table, predicate
            ):
                continue
            violations.append(
                Violation(
                    "soft-delete-join",
                    path,
                    literal.line_no,
                    f"JOIN {table} must filter its parent with deleted_at IS NULL",
                )
            )
    return violations, candidates


def _predicate_in_call_scope(
    source: str,
    line: int,
    table: str,
    predicate: re.Pattern[str],
) -> bool:
    """Check a raw SQL predicate split by Dart interpolation.

    A customSelect can build one SQL statement from several literal groups with
    an interpolated optional clause between them. The literal parser correctly
    keeps those groups separate; this second, call-scoped check reassembles the
    surrounding customSelect without treating arbitrary source text as SQL.
    """

    line_starts = [0]
    for match in re.finditer("\n", source):
        line_starts.append(match.end())
    search_from = line_starts[min(line - 1, len(line_starts) - 1)]
    join_match = re.search(
        rf"\bJOIN\s+{re.escape(table)}\b",
        source[search_from:],
        re.IGNORECASE,
    )
    if join_match is None:
        return False
    join_at = search_from + join_match.start()
    call_at = source.rfind("customSelect(", 0, join_at)
    if call_at < 0:
        return False
    open_at = source.find("(", call_at)
    if open_at < 0:
        return False
    end = _balanced_call_end(source, open_at)
    return end is not None and predicate.search(source[call_at : end + 1]) is not None


def _balanced_call_end(source: str, open_at: int) -> int | None:
    depth = 0
    for offset in range(open_at, len(source)):
        if source[offset] == "(":
            depth += 1
        elif source[offset] == ")":
            depth -= 1
            if depth == 0:
                return offset
    return None


def _first_call_argument(source: str, open_at: int) -> str:
    depth = 0
    for offset in range(open_at + 1, len(source)):
        char = source[offset]
        if char == "(":
            depth += 1
        elif char == ")":
            if depth == 0:
                return source[open_at + 1 : offset]
            depth -= 1
        elif char == "," and depth == 0:
            return source[open_at + 1 : offset]
    return source[open_at + 1 :]


def _drift_join_violations(source: str, path: str) -> tuple[list[Violation], int]:
    masked = "\n".join(mask_source(source))
    violations: list[Violation] = []
    candidates = 0
    for match in DRIFT_JOIN_RE.finditer(masked):
        end = _balanced_call_end(masked, masked.find("(", match.start()))
        if end is None:
            violations.append(
                Violation(
                    "soft-delete-join-boundary",
                    path,
                    _line_number(source, match.start()),
                    "unbalanced Drift join call; cannot verify its parent filter",
                )
            )
            continue
        call = masked[match.start() : end + 1]
        argument = _first_call_argument(call, call.find("("))
        all_tables = DRIFT_TABLE_RE.findall(argument)
        tables = {
            table
            for table in all_tables
            if table in SOFT_DRIFT_TABLES
        }
        if not tables and not all_tables:
            violations.append(
                Violation(
                    "soft-delete-join-boundary",
                    path,
                    _line_number(source, match.start()),
                    "cannot identify the Drift table in the joined-table "
                    "argument; use a direct table reference",
                )
            )
            continue
        for table in tables:
            candidates += 1
            join_start = masked.rfind(".join(", 0, match.start())
            query_end = masked.find(".get(", end)
            if join_start < 0 or query_end < 0:
                violations.append(
                    Violation(
                        "soft-delete-join-boundary",
                        path,
                        _line_number(source, match.start()),
                        f"cannot identify the query scope for joined {table}",
                    )
                )
                continue
            query = masked[join_start : query_end + 5]
            if re.search(
                rf"\b[A-Za-z_][A-Za-z0-9_]*\.{re.escape(table)}"
                r"\.deletedAt\.isNull\s*\(\s*\)",
                query,
            ):
                continue
            if _exception_on_line(source, _line_number(source, match.start()), SOFT_JOIN_EXCEPTION_RE):
                continue
            violations.append(
                Violation(
                    "soft-delete-join",
                    path,
                    _line_number(source, match.start()),
                    f"Drift join through {table} must filter deletedAt.isNull()",
                )
            )
    return violations, candidates


def _write_violations(source: str, path: str) -> list[Violation]:
    violations: list[Violation] = []
    for literal in extract_sql_literals(blank_comments(source)):
        if not literal.parseable:
            if UPDATE_RE.search(literal.content):
                violations.append(
                    Violation(
                        "write-boundary",
                        path,
                        literal.line_no,
                        "cannot verify I1/I2 in a raw/triple-quoted UPDATE literal",
                    )
                )
            continue
        for update in UPDATE_RE.finditer(literal.content):
            assignments = {
                column.lower() for column in ASSIGNMENT_RE.findall(update.group("set"))
            }
            has_updated = "updated_at" in assignments
            # existence_at orders transitions; deleted_at is the existence state.
            has_existence = "deleted_at" in assignments
            content_columns = assignments & SERIALIZED_COLUMNS
            line = literal.line_no
            if content_columns and not has_updated and not (
                _exception_on_line(source, line)
                or _exception_on_line(source, line, NON_SYNC_WRITE_EXCLUSION_RE)
            ):
                violations.append(
                    Violation(
                        "I1",
                        path,
                        line,
                        "serialized content update must also advance updated_at",
                    )
                )
            if (
                has_updated
                and not content_columns
                and not has_existence
                and not _exception_on_line(source, line, NON_SYNC_WRITE_EXCLUSION_RE)
            ):
                violations.append(
                    Violation(
                        "I2",
                        path,
                        line,
                        "updated_at advance must change body or existence state",
                    )
                )
    return violations


def _drift_write_violations(source: str, path: str) -> list[Violation]:
    """Check direct Drift writes to sync-record tables for I1 and I2."""

    masked = "\n".join(mask_source(source))
    violations: list[Violation] = []
    matches = {
        match.start(): match
        for pattern in (DRIFT_MUTATION_ROOT_RE, DRIFT_BATCH_MUTATION_RE)
        for match in pattern.finditer(masked)
    }
    for match in sorted(matches.values(), key=lambda value: value.start()):
        open_at = masked.find("(", match.start())
        argument = _first_call_argument(masked, open_at)
        if not (
            set(DRIFT_TABLE_RE.findall(argument)) & SOFT_DRIFT_TABLES
        ):
            continue
        statement_end = masked.find(";", match.start())
        if statement_end < 0:
            statement_end = len(masked)
        statement = re.sub(r"\s+", "", masked[match.start() : statement_end])
        is_batch = DRIFT_BATCH_MUTATION_RE.fullmatch(
            masked[match.start() : open_at + 1]
        )
        if not is_batch and not DRIFT_MUTATION_METHOD_RE.search(statement):
            continue
        line = _line_number(source, match.start())
        if not re.search(r"[A-Za-z_][A-Za-z0-9_]*Companion(?:\.insert)?\(", statement):
            violations.append(
                Violation(
                    "typed-write-boundary",
                    path,
                    line,
                    "typed Drift write must use an inline companion so its "
                    "sync fields are inspectable",
                )
            )
            continue
        fields = set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*:", statement))
        has_updated = "updatedAt" in fields or "updated_at" in fields
        has_existence = "deletedAt" in fields or "deleted_at" in fields
        content_fields = fields - {
            "createdAt",
            "created_at",
            "updatedAt",
            "updated_at",
            "deletedAt",
            "deleted_at",
            "existenceAt",
            "existence_at",
        }
        if content_fields and not has_updated:
            violations.append(
                Violation(
                    "typed-I1",
                    path,
                    line,
                    "typed serialized-content write must also provide updatedAt",
                )
            )
        if has_updated and not content_fields and not has_existence:
            violations.append(
                Violation(
                    "typed-I2",
                    path,
                    line,
                    "typed updatedAt write must also change body or existence state",
                )
            )
    return violations


def _certificate_violations(source: str, path: str) -> list[Violation]:
    masked = "\n".join(mask_source(source))
    violations: list[Violation] = []
    for name, pattern in CERTIFICATE_PATTERNS:
        for match in pattern.finditer(masked):
            violations.append(
                Violation(
                    "certificate-hatch",
                    path,
                    _line_number(source, match.start()),
                    f"forbidden certificate-validation escape hatch: {name}",
                )
            )
    return violations


def _definitions(source: str, pattern: re.Pattern[str]) -> list[int]:
    masked = "\n".join(mask_source(source))
    return [match.start() for match in pattern.finditer(masked)]


def _balanced_block_end(source: str, open_at: int) -> int | None:
    depth = 0
    for offset in range(open_at, len(source)):
        if source[offset] == "{":
            depth += 1
        elif source[offset] == "}":
            depth -= 1
            if depth == 0:
                return offset
    return None


def _function_body(source: str, match: re.Match[str]) -> str:
    masked = "\n".join(mask_source(source))
    body_at = match.end() - 1
    if match.group("body") == "=>":
        end = masked.find(";", body_at)
        return masked[body_at:] if end < 0 else masked[body_at:end]
    end = _balanced_block_end(masked, body_at)
    return masked[body_at:] if end is None else masked[body_at : end + 1]


def _alternate_title_definitions(source: str) -> list[int]:
    """Find functions that implement title normalization under another name."""

    masked = "\n".join(mask_source(source))
    definitions: list[int] = []
    for match in FUNCTION_DEF_RE.finditer(masked):
        name = match.group("name")
        if name == "normalizeTitle":
            continue
        signature = match.group("parameters")
        title_relevant = "title" in name.lower() or re.search(
            r"\btitle\b", signature, re.IGNORECASE
        )
        if not title_relevant:
            continue
        body = _function_body(source, match)
        operations = TITLE_BEHAVIOR_RE.findall(body)
        named_normalizer = TITLE_NORMALIZER_NAME_RE.search(name)
        canonical_behavior = len(operations) >= 2 and any(
            operation.rstrip("(")
            in {"toLowerCase", "replaceAll", "replaceFirst", "fold"}
            for operation in operations
        )
        if NORMALIZATION_OPERATION_RE.search(body) and (
            named_normalizer or canonical_behavior
        ):
            definitions.append(match.start())
    return definitions


def _imported_uris(source: str, symbol: str) -> list[tuple[str, int]]:
    """Return imports that make [symbol] available, with their source lines."""

    imports: list[tuple[str, int]] = []
    comments_blank = blank_comments(source)
    for match in IMPORT_RE.finditer(comments_blank):
        clause = match.group("clause")
        show = re.search(r"\bshow\b(?P<names>[\s\S]*)", clause, re.IGNORECASE)
        if show and not re.search(
            rf"\b{re.escape(symbol)}\b", show.group("names")
        ):
            continue
        if re.search(rf"\bhide\s+[^;]*\b{re.escape(symbol)}\b", clause, re.IGNORECASE):
            continue
        imports.append((match.group("uri"), _line_number(source, match.start())))
    return imports


def _exported_uris(source: str, symbol: str) -> list[str]:
    """Return libraries that export [symbol] from this library."""

    exports: list[str] = []
    comments_blank = blank_comments(source)
    for match in EXPORT_RE.finditer(comments_blank):
        clause = match.group("clause")
        show = re.search(r"\bshow\b(?P<names>[\s\S]*)", clause, re.IGNORECASE)
        if show and not re.search(
            rf"\b{re.escape(symbol)}\b", show.group("names")
        ):
            continue
        if re.search(rf"\bhide\s+[^;]*\b{re.escape(symbol)}\b", clause, re.IGNORECASE):
            continue
        exports.append(match.group("uri"))
    return exports


def _resolve_import(root: Path, importer: Path, uri: str) -> Path | None:
    if uri.startswith("dart:"):
        return None
    if uri.startswith("package:"):
        package_uri = uri.removeprefix("package:")
        package, separator, relative = package_uri.partition("/")
        if not separator:
            return None
        candidate = root / "packages" / package / "lib" / relative
    else:
        candidate = importer.parent / uri
    try:
        resolved = candidate.resolve()
        resolved.relative_to(root.resolve())
    except ValueError:
        return None
    return resolved


def _library_exports_definition(
    root: Path,
    library: Path,
    symbol: str,
    definition: Path,
    visited: set[Path],
) -> bool:
    library = library.resolve()
    definition = definition.resolve()
    if library == definition:
        return True
    if library in visited or not library.is_file():
        return False
    visited.add(library)
    try:
        source = library.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return any(
        target is not None
        and _library_exports_definition(
            root, target, symbol, definition, visited
        )
        for uri in _exported_uris(source, symbol)
        for target in [_resolve_import(root, library, uri)]
    )


def _imports_definition(
    root: Path,
    importer: Path,
    source: str,
    symbol: str,
    definition: Path,
) -> bool:
    for uri, _ in _imported_uris(source, symbol):
        target = _resolve_import(root, importer, uri)
        if target is not None and _library_exports_definition(
            root, target, symbol, definition, set()
        ):
            return True
    return False


def _has_function_call(source: str, name: str) -> bool:
    masked = "\n".join(mask_source(source))
    definition_spans = [
        range(match.start("name"), match.end("name"))
        for match in FUNCTION_DEF_RE.finditer(masked)
        if match.group("name") == name
    ]
    return any(
        not any(match.start() in span for span in definition_spans)
        for match in re.finditer(rf"\b{re.escape(name)}\s*\(", masked)
    )


def _sync_unit_kind(relative: str) -> str | None:
    if not _is_sync_source(relative):
        return None
    parts = tuple(part.lower() for part in Path(relative).parts)
    if "client" in parts:
        return "client"
    if "server" in parts:
        return "server"
    stem = Path(relative).stem.lower()
    if "client" in stem:
        return "client"
    if "server" in stem:
        return "server"
    return None


def _is_sync_source(relative: str) -> bool:
    parts = tuple(part.lower() for part in Path(relative).parts)
    stem = Path(relative).stem.lower()
    return "sync" in parts or stem.startswith("sync_") or "_sync" in stem


def scan(root: Path = REPO_ROOT) -> ScanResult:
    files = source_files(root)
    violations: list[Violation] = []
    soft_candidates = 0
    title_definitions = 0
    sync_id_activated = False
    sync_id_definitions: list[tuple[str, int]] = []
    sync_sources: list[tuple[Path, str]] = []
    sync_units: list[tuple[Path, str, str]] = []
    title_definition_paths: list[Path] = []

    for path in files:
        source = path.read_text(encoding="utf-8", errors="replace")
        relative = path.relative_to(root).as_posix()
        raw_violations, raw_candidates = _raw_join_violations(source, relative)
        drift_violations, drift_candidates = _drift_join_violations(source, relative)
        violations.extend(raw_violations)
        violations.extend(drift_violations)
        violations.extend(_write_violations(source, relative))
        violations.extend(_drift_write_violations(source, relative))
        violations.extend(_certificate_violations(source, relative))
        soft_candidates += raw_candidates + drift_candidates

        title_matches = _definitions(source, NORMALIZE_TITLE_DEF_RE)
        title_definitions += len(title_matches)
        if title_matches:
            title_definition_paths.extend([path] * len(title_matches))
        for offset in _alternate_title_definitions(source):
            violations.append(
                Violation(
                    "normalizeTitle",
                    relative,
                    _line_number(source, offset),
                    "title normalization must use the shared normalizeTitle "
                    "definition",
                )
            )
        sync_id_uses = SYNC_ID_MARKER_RE.search("\n".join(mask_source(source)))
        if sync_id_uses:
            sync_id_activated = True
        for offset in _definitions(source, SYNC_ID_DEF_RE):
            sync_id_definitions.append((relative, _line_number(source, offset)))
        if _is_sync_source(relative):
            sync_sources.append((path, source))
        unit_kind = _sync_unit_kind(relative)
        if unit_kind:
            sync_units.append((path, unit_kind, source))

    if not files:
        violations.append(
            Violation("source-scope", ".", 0, "no Dart source files found under src roots")
        )
    if title_definitions != 1:
        violations.append(
            Violation(
                "normalizeTitle",
                "source roots",
                0,
                f"expected exactly one normalizeTitle definition, found "
                f"{title_definitions}",
            )
        )
    elif len(title_definition_paths) == 1:
        title_definition = title_definition_paths[0]
        for path, source in sync_sources:
            if path == title_definition:
                continue
            if not _has_function_call(source, "normalizeTitle"):
                continue
            if not _imports_definition(
                root, path, source, "normalizeTitle", title_definition
            ):
                violations.append(
                    Violation(
                        "normalizeTitle",
                        path.relative_to(root).as_posix(),
                        1,
                        "sync title call sites must import and call the "
                        "shared normalizeTitle definition",
                    )
                )
    if soft_candidates == 0:
        violations.append(
            Violation(
                "soft-delete-join-scope",
                "source roots",
                0,
                "found no soft-delete join candidates; the join detector is vacuous",
            )
        )
    if sync_id_activated:
        if len(sync_id_definitions) != 1:
            violations.append(
                Violation(
                    "sync-ID",
                    "source roots",
                    0,
                    "sync-ID use is present but exactly one normalizeSyncId "
                    f"definition was not found (found {len(sync_id_definitions)})",
                )
            )
        if not any(kind == "client" for _, kind, _ in sync_units):
            violations.append(
                Violation(
                    "sync-ID",
                    "source roots",
                    0,
                    "sync-ID use is present but no sync client unit was found",
                )
            )
        if not any(kind == "server" for _, kind, _ in sync_units):
            violations.append(
                Violation(
                    "sync-ID",
                    "source roots",
                    0,
                    "sync-ID use is present but no sync server unit was found",
                )
            )
        if len(sync_id_definitions) == 1:
            definition = root / sync_id_definitions[0][0]
            for path, kind, source in sync_units:
                relative = path.relative_to(root).as_posix()
                if not _has_function_call(source, "normalizeSyncId") or not _imports_definition(
                    root, path, source, "normalizeSyncId", definition
                ):
                    violations.append(
                        Violation(
                            "sync-ID",
                            relative,
                            1,
                            f"sync {kind} unit must call normalizeSyncId imported "
                            "from the shared normalizer",
                        )
                    )
        for path, kind, source in sync_units:
            relative = path.relative_to(root).as_posix()
            if not SYNC_ID_IMPORT_RE.search(blank_comments(source)):
                # Keep this separate from the resolved-import check so the
                # diagnostic still explains the missing symbol import.
                violations.append(
                    Violation(
                        "sync-ID",
                        relative,
                        1,
                        "sync client/server unit must import normalizeSyncId "
                        "from the shared normalizer",
                    )
                )

    return ScanResult(
        tuple(violations),
        soft_candidates,
        title_definitions,
        sync_id_activated,
    )


def main(root: Path = REPO_ROOT) -> int:
    result = scan(root)
    if result.violations:
        for violation in result.violations:
            print(f"::error::{violation.kind}: {violation.format()}")
        return 1
    sync_status = (
        "active and shared"
        if result.sync_id_activated
        else "not active (no sync-ID use yet)"
    )
    print(
        "OK: sync invariant ratchets passed; "
        f"{result.soft_join_candidates} soft-delete joins checked, "
        "normalizeTitle has one definition, "
        f"sync-ID check is {sync_status}."
    )
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 2:
        print("usage: check_sync_invariants.py [source-root]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1]) if len(sys.argv) == 2 else REPO_ROOT))
