#!/usr/bin/env python3
"""Offline tests for the device-sync invariant source ratchets."""

from __future__ import annotations

import tempfile
from pathlib import Path

from check_sync_invariants import (
    _certificate_violations,
    _drift_join_violations,
    _drift_write_violations,
    _raw_join_violations,
    _write_violations,
    blank_comments,
    scan,
)


def assert_no(violations) -> None:
    assert not violations, violations


def test_comment_stripping_and_exact_source_roots() -> None:
    source = (
        "/* badCertificateCallback */\n"
        "// normalizeTitle(String value) => value;\n"
        "String normalizeTitle(String value) => value;\n"
    )
    stripped = blank_comments(source)
    assert "badCertificateCallback" not in stripped
    assert "normalizeTitle(String value)" in stripped

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "app/lib/src").mkdir(parents=True)
        (root / "packages/core/lib/src").mkdir(parents=True)
        (root / "app/lib/src/app.dart").write_text(
            "String normalizeTitle(String value) => value;\n"
            "final query = 'SELECT * FROM dances JOIN programs p ON p.id = x "
            "WHERE p.deleted_at IS NULL';\n",
            encoding="utf-8",
        )
        (root / "packages/core/lib/src/core.dart").write_text(
            "final query = 'SELECT * FROM dances JOIN tags t ON t.id = x "
            "WHERE t.deleted_at IS NULL';\n",
            encoding="utf-8",
        )
        result = scan(root)
        assert result.soft_join_candidates == 2
        assert result.normalize_title_definitions == 1
        assert_no(result.violations)


def test_raw_soft_delete_join_requires_parent_filter() -> None:
    compliant = (
        "final q = 'SELECT d.id FROM dance_tags dt JOIN tags t ON t.id = dt.tag_id "
        "WHERE t.deleted_at IS NULL';\n"
    )
    missing = (
        "final q = 'SELECT d.id FROM dance_tags dt JOIN tags t ON t.id = dt.tag_id "
        "WHERE dt.dance_id = ?';\n"
    )
    split = (
        "final q = 'SELECT d.id FROM dance_tags dt JOIN tags t ON t.id = dt.tag_id '\n"
        "  'WHERE t.deleted_at IS NULL';\n"
    )
    assert_no(_raw_join_violations(compliant, "fixture.dart")[0])
    assert _raw_join_violations(missing, "fixture.dart")[0]
    assert_no(_raw_join_violations(split, "fixture.dart")[0])


def test_raw_joined_subquery_requires_parent_filter() -> None:
    compliant = (
        "final q = 'SELECT * FROM dance_tags dt JOIN (SELECT * FROM venues "
        "WHERE deleted_at IS NULL) v ON v.id = dt.venue_id';\n"
    )
    missing = (
        "final q = 'SELECT * FROM dance_tags dt JOIN (SELECT * FROM venues) "
        "v ON v.id = dt.venue_id';\n"
    )
    assert_no(_raw_join_violations(compliant, "fixture.dart")[0])
    assert _raw_join_violations(missing, "fixture.dart")[0]


def test_drift_soft_delete_join_requires_parent_filter() -> None:
    compliant = """
      final rows = await (_db.select(_db.danceTags).join([
        innerJoin(_db.tags, _db.tags.id.equalsExp(_db.danceTags.tagId)),
      ])..where(_db.tags.deletedAt.isNull())).get();
    """
    missing = """
      final rows = await (_db.select(_db.danceTags).join([
        innerJoin(_db.tags, _db.tags.id.equalsExp(_db.danceTags.tagId)),
      ])).get();
    """
    assert_no(_drift_join_violations(compliant, "fixture.dart")[0])
    assert _drift_join_violations(missing, "fixture.dart")[0]


def test_i1_and_i2_write_paths_are_independent() -> None:
    compliant = (
        "final q = 'UPDATE dances SET figures_json = ?, updated_at = ? "
        "WHERE id = ?';\n"
    )
    i1_missing = "final q = 'UPDATE dances SET figures_json = ? WHERE id = ?';\n"
    i2_missing = "final q = 'UPDATE dances SET updated_at = ? WHERE id = ?';\n"
    existence_stamp_only = (
        "final q = 'UPDATE dances SET updated_at = ?, existence_at = ? "
        "WHERE id = ?';\n"
    )
    existence_change = (
        "final q = 'UPDATE dances SET updated_at = ?, deleted_at = ? "
        "WHERE id = ?';\n"
    )
    exception = (
        "// sync-invariant-exception: content-derived normalization is idempotent; "
        "divergence is surfaced\n"
        + i1_missing
    )
    exception_without_idempotence = (
        "// sync-invariant-exception: content-derived normalization; "
        "divergence is surfaced\n"
        + i1_missing
    )
    exception_without_divergence_surface = (
        "// sync-invariant-exception: content-derived normalization is idempotent\n"
        + i1_missing
    )
    migration = (
        "// sync-invariant-exclusion: migration-backfill is idempotent; "
        "not a sync record edit\n"
        "final q = 'UPDATE dances SET updated_at = ?, existence_at = ? "
        "WHERE id = ?';\n"
    )
    assert_no(_write_violations(compliant, "fixture.dart"))
    assert any(v.kind == "I1" for v in _write_violations(i1_missing, "fixture.dart"))
    assert any(v.kind == "I2" for v in _write_violations(i2_missing, "fixture.dart"))
    assert any(v.kind == "I2" for v in _write_violations(existence_stamp_only, "fixture.dart"))
    assert_no(_write_violations(existence_change, "fixture.dart"))
    assert_no(_write_violations(exception, "fixture.dart"))
    assert any(v.kind == "I1" for v in _write_violations(exception_without_idempotence, "fixture.dart"))
    assert any(
        v.kind == "I1"
        for v in _write_violations(exception_without_divergence_surface, "fixture.dart")
    )
    assert_no(_write_violations(migration, "fixture.dart"))
    assert any(
        v.kind == "I2"
        for v in _write_violations(
            exception
            + "final q = 'UPDATE dances SET updated_at = ? WHERE id = ?';\n",
            "fixture.dart",
        )
    )


def test_typed_drift_writes_fail_closed() -> None:
    compliant = "await db.update(db.dances).write(companion);\n"
    assert _drift_write_violations(compliant, "fixture.dart")
    assert_no(_drift_write_violations("// await db.update(db.dances).write(x);", "fixture.dart"))


def test_certificate_scan_catches_each_concrete_escape_hatch() -> None:
    source = """
      client.badCertificateCallback = (_, __, ___) => true;
      client.badCertificateCallback ??= (_, __, ___) => true;
      final a = SecurityContext(withTrustedRoots: false);
      context.setTrustedCertificates('/tmp/root.pem');
      context.setTrustedCertificatesBytes(bytes);
    """
    violations = _certificate_violations(source, "fixture.dart")
    assert len(violations) == 5
    assert_no(
        _certificate_violations(
            "// client.badCertificateCallback = true;\n"
            "/* context.setTrustedCertificatesBytes(bytes); */\n",
            "fixture.dart",
        )
    )
    assert_no(_certificate_violations("final context = SecurityContext();", "fixture.dart"))


def test_sync_id_activation_requires_one_shared_definition_and_imports() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        client = root / "packages/core/lib/src/sync/client.dart"
        server = root / "packages/core/lib/src/sync/server.dart"
        shared = root / "packages/core/lib/src/sync/normalization.dart"
        for path in (client, server, shared):
            path.parent.mkdir(parents=True, exist_ok=True)
        (root / "app/lib/src/title.dart").parent.mkdir(parents=True)
        (root / "app/lib/src/title.dart").write_text(
            "String normalizeTitle(String value) => value;\n"
            "final q = 'SELECT * FROM dance_tags JOIN tags t ON t.id = x "
            "WHERE t.deleted_at IS NULL';\n",
            encoding="utf-8",
        )
        shared.write_text(
            "String normalizeSyncId(String value) => value.trim();\n",
            encoding="utf-8",
        )
        client.write_text(
            "import 'normalization.dart' show normalizeSyncId;\n"
            "String send(String syncId) => normalizeSyncId(syncId);\n",
            encoding="utf-8",
        )
        server.write_text(
            "import 'normalization.dart' show normalizeSyncId;\n"
            "String accept(String syncId) => normalizeSyncId(syncId);\n",
            encoding="utf-8",
        )
        result = scan(root)
        assert result.sync_id_activated
        assert_no(result.violations)

        duplicate = root / "packages/core/lib/src/sync/duplicate.dart"
        duplicate.write_text(
            "String normalizeTitle(String value) => value;\n",
            encoding="utf-8",
        )
        result = scan(root)
        assert any(v.kind == "normalizeTitle" for v in result.violations)
        duplicate.unlink()

        server.write_text(
            "String accept(String syncId) => syncId.trim();\n", encoding="utf-8"
        )
        result = scan(root)
        assert any(v.kind == "sync-ID" for v in result.violations)


def test_repository_scan_is_not_vacuous() -> None:
    result = scan(Path(__file__).resolve().parents[2])
    assert result.soft_join_candidates > 0
    assert result.normalize_title_definitions == 1
    assert_no(result.violations)


def main() -> int:
    tests = [
        value
        for name, value in sorted(globals().items())
        if name.startswith("test_")
    ]
    for test in tests:
        test()
    print(f"OK: {len(tests)} sync invariant tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
