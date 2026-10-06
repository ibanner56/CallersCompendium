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
    "apple_native_changed": False,
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
    # The Android leg of `build` is the only place the Kotlin JVM unit tests
    # run (./gradlew :app:testDebugUnitTest), so a native-only Android change
    # -- test or source -- must reach the build matrix (platform-7).
    expect(
        "native Android test alone",
        (
            b"app/android/app/src/test/kotlin/org/callerscompendium/"
            b"compendiumApp/IncomingFileStagerTest.kt",
        ),
        validation_changed=True,
        app_tests_changed=True,
        builds_changed=True,
    )
    expect(
        "native Android Gradle script alone",
        (b"app/android/app/build.gradle.kts",),
        validation_changed=True,
        app_tests_changed=True,
        builds_changed=True,
    )
    # server/ path-depends on compendium_core (server/pubspec.yaml) and every
    # server library imports the core barrel, so a core change reaches the
    # server suite. Compile breaks were already caught by validate's
    # workspace-root analyze; a *behavioural* regression in a shared wire
    # model or the privacy registry passed analyze and failed only on the
    # post-merge push to main, where ci.yml runs every suite -- attributed to
    # whatever merged next. 117 of 300 recent main commits had this shape.
    expect(
        "packages/compendium_core/ path",
        (b"packages/compendium_core/lib/src/privacy/field_registry.dart",),
        validation_changed=True,
        core_tests_changed=True,
        app_tests_changed=True,
        server_tests_changed=True,
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
        # The Flutter version decides the engine framework the Swift tests link.
        apple_native_changed=True,
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


def test_test_input_paths_reach_the_suite_that_reads_them() -> None:
    print("files that are inputs to an app test route to the app suite:")
    # THIRD_PARTY_NOTICES.md is Markdown, so alone it used to set nothing at
    # all -- and app/test/licenses_notice_test.dart, the only guard that the
    # fmptools notice is still carried in full, never ran for the PR that
    # trimmed it. Worse, ci.yml's push path filter ignores '**.md', so the
    # trimmed notice was never checked on main either: it failed on the next
    # unrelated PR that happened to set app_tests_changed. Same shape as
    # GENERATED_MARKDOWN_PATHS: Markdown that is really an input to code.
    expect(
        "THIRD_PARTY_NOTICES.md alone",
        (b"THIRD_PARTY_NOTICES.md",),
        validation_changed=True,
        app_tests_changed=True,
    )
    # release.yml is read by app/test/application_name_test.dart. Not
    # Markdown, so validation already ran for it; the app suite did not.
    expect(
        "release.yml alone",
        (b".github/workflows/release.yml",),
        validation_changed=True,
        app_tests_changed=True,
    )
    # A test input cannot break a platform build, so it does not light up
    # builds_changed -- unlike an app/ path, where the two move together.
    # (expect() asserts every unnamed output is False, so both cases above
    # already pin builds_changed=False; this one adds the Markdown sibling.)
    expect(
        "a test input plus an unrelated markdown file still skips builds",
        (b"THIRD_PARTY_NOTICES.md", b"README.md"),
        validation_changed=True,
        app_tests_changed=True,
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


def test_apple_native_paths_run_the_swift_tests() -> None:
    print("Apple native paths run the Swift RunnerTests, other app paths do not:")
    for path in (
        b"app/ios/Runner/IncomingFilesPlugin.swift",
        b"app/ios/RunnerTests/RunnerTests.swift",
        b"app/ios/Runner.xcodeproj/project.pbxproj",
        b"app/ios/ShareExtension/ShareViewController.swift",
        b"app/macos/Runner/MainFlutterWindow.swift",
        b"app/macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme",
    ):
        expect(
            path.decode(),
            (path,),
            validation_changed=True,
            app_tests_changed=True,
            builds_changed=True,
            apple_native_changed=True,
        )
    # Dart-only, Android-only and other-desktop changes build but must not pay
    # for two macOS xcodebuild test runs.
    for path in (
        b"app/lib/main.dart",
        b"app/android/app/src/main/kotlin/MainActivity.kt",
        b"app/windows/runner/main.cpp",
        b"packages/compendium_core/lib/src/privacy/field_registry.dart",
        b"packaging/linux/AppRun",
    ):
        outcome = classify((path,))
        check(
            f"{path.decode()} does not run the Swift tests",
            outcome["builds_changed"] and not outcome["apple_native_changed"],
            str(outcome),
        )
    # A Markdown note inside app/ios is not validated, so no build job runs to
    # hold the test step: apple_native_changed must imply builds_changed.
    expect("an all-Markdown app/ios diff", (b"app/ios/README.md",))


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
    # Caught by Copilot review on #1324: docs-bundle-gate and
    # changelog-structure-gate are now DEFINED inside ci.yml (not only in the
    # standalone workflows), so an edit to those job definitions has to be
    # self-validating the same way the standalone workflows self-trigger on
    # their own YAML changing.
    expect(
        "editing ci.yml itself re-triggers both required gates",
        (b".github/workflows/ci.yml",),
        validation_changed=True,
        docs_bundle_changed=True,
        changelog_changed=True,
    )


def main() -> int:
    test_ordinary_markdown_only_skips_everything()
    test_generated_classification_doc_forces_core_tests()
    test_non_markdown_paths_route_to_their_suites()
    test_test_input_paths_reach_the_suite_that_reads_them()
    test_packaging_paths_trigger_builds_independently()
    test_apple_native_paths_run_the_swift_tests()
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
