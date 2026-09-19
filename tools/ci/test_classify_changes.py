#!/usr/bin/env python3
"""Offline tests for ``classify_changes.py``'s pure decision function.

Pure-stdlib, assert-based (no pytest / no third-party deps, matching the rest of
``tools/*/test_*.py``). Run directly::

    python3 tools/ci/test_classify_changes.py

``classify()`` is a pure function of a changed-path tuple, so these tests drive
it directly with representative path sets rather than building a throwaway git
repository (contrast ``test_check_schema_migration.py``, which must exercise
real git history because its gate reads file contents at two refs).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from classify_changes import classify  # noqa: E402

FAILURES: list[str] = []

ALL_FALSE = {
    "validation_changed": False,
    "core_tests_changed": False,
    "app_tests_changed": False,
    "server_tests_changed": False,
    "builds_changed": False,
    "docs_bundle_changed": False,
    "changelog_changed": False,
}


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    FAILURES.append(f"{name}{': ' + detail if detail else ''}")
    print(f"  FAIL {name}{': ' + detail if detail else ''}")


def expect(name: str, paths: tuple[bytes, ...], **expected: bool) -> None:
    outcome = classify(paths)
    wanted = dict(ALL_FALSE, **expected)
    check(name, outcome == wanted, f"paths={paths!r} -> {outcome}, want {wanted}")


def test_ordinary_markdown_only_skips_everything() -> None:
    print("ordinary markdown-only diffs skip validation:")
    expect("single README edit", (b"README.md",))
    expect(
        "multiple unrelated markdown files",
        (b"docs/dev/README.md", b"docs/adr/003-linux-native-distribution-channel.md"),
    )


def test_generated_classification_doc_forces_core_tests() -> None:
    print("the generated data-classification doc is validation-relevant:")
    expect(
        "doc alone",
        (b"docs/dev/data-classification.md",),
        validation_changed=True,
        core_tests_changed=True,
    )
    expect(
        "doc plus an unrelated markdown file",
        (b"docs/dev/data-classification.md", b"README.md"),
        validation_changed=True,
        core_tests_changed=True,
    )
    # Only this one generated path is special-cased; every other markdown file
    # under docs/dev/ still skips validation on its own.
    expect(
        "a different docs/dev markdown file is not swept in",
        (b"docs/dev/releasing.md",),
    )


def test_non_markdown_paths_route_to_their_suites() -> None:
    print("non-markdown paths route to the suites that cover them:")
    expect(
        "app/ path",
        (b"app/lib/main.dart",),
        validation_changed=True,
        app_tests_changed=True,
        builds_changed=True,
    )
    expect(
        "packages/compendium_core/ path",
        (b"packages/compendium_core/lib/src/privacy/field_registry.dart",),
        validation_changed=True,
        core_tests_changed=True,
        app_tests_changed=True,
        builds_changed=True,
    )
    expect(
        "server/ path",
        (b"server/lib/main.dart",),
        validation_changed=True,
        server_tests_changed=True,
    )
    expect(
        "shared runtime path (.fvmrc) reaches every suite",
        (b".fvmrc",),
        validation_changed=True,
        core_tests_changed=True,
        app_tests_changed=True,
        server_tests_changed=True,
        builds_changed=True,
    )
    expect(
        "core test driver path reaches only core",
        (b"tools/ci/check_core_coverage.py",),
        validation_changed=True,
        core_tests_changed=True,
    )
    expect(
        "unrelated non-markdown path (e.g. a tool script) still runs validation only",
        (b"tools/brand/generate_icons.py",),
        validation_changed=True,
    )


def test_packaging_paths_trigger_builds_independently() -> None:
    print("packaging-only diffs still build:")
    expect(
        "linux packaging asset alone",
        (b"packaging/linux/AppRun",),
        validation_changed=True,
        builds_changed=True,
    )
    expect(
        "windows packaging script alone",
        (b"packaging/windows/CallersCompendium.iss",),
        validation_changed=True,
        builds_changed=True,
    )
    # Packaging-only changes have no app/core code in the diff, so they must
    # not falsely light up app_tests_changed -- builds_changed has to be an
    # independent predicate, not just a wider app_tests_changed.
    expect(
        "packaging alone does not imply app_tests_changed",
        (b"packaging/linux/AppRun",),
        validation_changed=True,
        builds_changed=True,
        app_tests_changed=False,
    )
    expect(
        "packaging plus an app change still builds (no interaction bug)",
        (b"packaging/linux/AppRun", b"app/lib/main.dart"),
        validation_changed=True,
        app_tests_changed=True,
        builds_changed=True,
    )
    # Caught by Copilot review on #1322: builds_changed must never be true
    # while validation_changed is false. ci.yml's `build` job requires
    # needs.checks.result == 'success', and `checks` is skipped outright when
    # validation_changed is false -- so a packaging-only .md diff (an
    # all-Markdown diff is exactly what makes validation_changed false) would
    # set builds_changed=true with no way for `build` to ever run, and
    # merge-gate's `require_success 'Platform builds'` would fail closed
    # forever. builds_changed must imply validation_changed.
    expect(
        "an all-Markdown packaging diff does not set builds_changed",
        (b"packaging/README.md",),
    )


def test_docs_bundle_and_changelog_gates_run_on_markdown_only_diffs() -> None:
    print("docs-bundle and changelog gates are not gated on validation_changed:")
    expect(
        "docs/user markdown alone (no other code) still flags docs_bundle_changed",
        (b"docs/user/getting-started.md",),
        docs_bundle_changed=True,
    )
    expect(
        "app/assets/docs bundle path",
        (b"app/assets/docs/getting-started.md",),
        docs_bundle_changed=True,
    )
    expect(
        "site/ path",
        (b"site/index.html",),
        # Not markdown, so validation_changed is already true independent of
        # this predicate -- included for path-prefix coverage, not to test
        # the validation_changed independence claim (see the .md cases above
        # and below for that).
        validation_changed=True,
        docs_bundle_changed=True,
    )
    expect(
        "the sync tool script itself",
        (b"tools/ci/sync_user_docs.py",),
        validation_changed=True,
        docs_bundle_changed=True,
    )
    expect(
        "app CHANGELOG.md alone still flags changelog_changed",
        (b"app/CHANGELOG.md",),
        changelog_changed=True,
    )
    expect(
        # Ends in .md and isn't in GENERATED_MARKDOWN_PATHS, so
        # validation_changed stays false -- exactly the case this predicate
        # exists to still catch independently.
        "core package CHANGELOG.md alone",
        (b"packages/compendium_core/CHANGELOG.md",),
        changelog_changed=True,
    )
    expect(
        "a changelog.d fragment",
        (b"changelog.d/1234.added.json",),
        validation_changed=True,
        changelog_changed=True,
    )
    expect(
        "unrelated markdown diff sets neither",
        (b"README.md",),
    )


def main() -> int:
    test_ordinary_markdown_only_skips_everything()
    test_generated_classification_doc_forces_core_tests()
    test_non_markdown_paths_route_to_their_suites()
    test_packaging_paths_trigger_builds_independently()
    test_docs_bundle_and_changelog_gates_run_on_markdown_only_diffs()

    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("\nAll classify_changes tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
