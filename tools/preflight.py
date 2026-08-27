#!/usr/bin/env python3
"""One local entry point for the gates CI runs.

A failure found by CI costs a wait, a log fetch, and a full re-reason at the
current prompt size; the same failure found locally costs one line. Several of
this repository's gates are also invisible to the obvious local command --
`dart test` does not run the figure-fixture ratchet over the real suites, and
`flutter test` does not run any of the Python ratchets -- so "the tests passed"
locally has never implied "CI will be green".

Usage:

    python3 tools/preflight.py            # everything available in this checkout
    python3 tools/preflight.py --list     # what would run, and why
    python3 tools/preflight.py --fast     # only the Python gates, no Dart/Flutter (seconds)
    python3 tools/preflight.py --only privacy fixtures
    python3 tools/preflight.py --require-available

Output is one line per step. On failure the last few lines of that step's output
are shown and the rest is discarded: a red run should tell you what to fix, not
hand you the whole log.

Missing toolchains are visibly skipped by default, so cloud and local sessions
without Flutter still run every applicable Python gate. Pass --require-available
to make a selected unavailable gate fail instead.

Exit codes: 0 = every selected step passed or was skipped, 1 = invalid selection
or a selected step failed / was unavailable under --require-available.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parent.parent
FAIL_TAIL_LINES = 12


@dataclass(frozen=True)
class Step:
    name: str
    why: str
    commands: tuple[tuple[str, ...], ...]
    cwd: Path = ROOT
    # True when the step needs no Dart/Flutter toolchain, so `--fast` can run
    # it in seconds. Not the same as pure-stdlib: `release-tooling` is a fast
    # step that needs the `cryptography` wheel, and reports SKIP without it.
    fast: bool = True
    # Executable that must be on PATH, or an import that must resolve, for this
    # step to mean anything. A missing one is reported as SKIP with the reason,
    # never as a pass: a step that silently no-ops is worse than one that fails.
    needs_binary: str | None = None
    needs_import: str | None = None


def py(*args: str) -> tuple[str, ...]:
    return (sys.executable, *args)


STEPS: tuple[Step, ...] = (
    Step(
        "preflight",
        "the local CI-gate selector and availability policy",
        (py("tools/test_preflight.py"),),
    ),
    Step(
        "agent-context",
        "resident agent instructions stay within their byte budget",
        (
            py("tools/ci/test_check_agent_context_budget.py"),
            py("tools/ci/check_agent_context_budget.py"),
        ),
    ),
    Step(
        "pr-gates",
        "the merge-readiness gate script itself still works",
        (py("tools/ci/test_check_pr_review_gates.py"),),
    ),
    Step(
        "comment-weight",
        "the comment-weight reporter's own logic (the report itself is on demand)",
        (py("tools/ci/test_report_comment_weight.py"),),
    ),
    Step(
        "app-version",
        "the app release-version format and kAppVersion match app/pubspec.yaml",
        (
            py("tools/ci/test_check_app_version.py"),
            py("tools/ci/check_app_version.py"),
        ),
    ),
    Step(
        "debug-print",
        "no unguarded debugPrint reaches a release build",
        (
            py("tools/ci/test_check_debug_print.py"),
            py("tools/ci/check_debug_print.py"),
        ),
    ),
    Step(
        "caught-errors",
        "every caught user-facing error reaches the diagnostic log",
        (
            py("tools/ci/test_check_caught_error_logged.py"),
            py("tools/ci/check_caught_error_logged.py"),
        ),
    ),
    Step(
        "settings-reads",
        "raw settings reads filter deleted_at IS NULL",
        (
            py("tools/ci/test_check_settings_marker_reads.py"),
            py("tools/ci/check_settings_marker_reads.py"),
        ),
    ),
    Step(
        "schema-gate",
        "the schema-bump gate's own logic",
        (py("tools/ci/test_check_schema_migration.py"),),
    ),
    Step(
        "version-history",
        "the version-ledger gate's own logic (the gate itself is PR-only)",
        (py("tools/ci/test_check_version_history.py"),),
    ),
    Step(
        "changelog-gate",
        "the CHANGELOG promotion gate's own logic",
        (py("tools/ci/test_check_changelog_promoted.py"),),
    ),
    Step(
        "changelog-structure",
        "both CHANGELOGs: version sections in order, no category repeated in one",
        (
            py("tools/ci/test_check_changelog_structure.py"),
            py("tools/ci/check_changelog_structure.py"),
        ),
    ),
    Step(
        "l10n",
        "translation ARBs: parity, freshness, content safety, full coverage",
        (
            py("tools/ci/test_arb_translate.py"),
            py("tools/ci/arb_translate.py", "validate", "--all"),
            py("tools/ci/test_check_arb_translation_coverage.py"),
            py("tools/ci/check_arb_translation_coverage.py"),
        ),
    ),
    Step(
        "user-docs",
        "docs/user is the single source of the in-app bundle, and guides render",
        (
            py("tools/ci/test_sync_user_docs.py"),
            py("tools/ci/sync_user_docs.py", "--check"),
            py("tools/site/test_markdown_to_html.py"),
            py("tools/site/test_render_user_docs.py"),
            py("tools/site/render_user_docs.py", "--check"),
        ),
    ),
    Step(
        "release-tooling",
        "release identity / SBOM / metadata / notes / Pages publishing",
        (
            py("tools/release/test_android_version_code.py"),
            py("tools/release/test_check_beta_prerelease_history.py"),
            py("tools/release/test_gen_sbom.py"),
            py("tools/release/test_gen_release_metadata.py"),
            py("tools/release/test_gen_release_notes.py"),
            py("tools/release/test_gen_recovery_provenance.py"),
            py("tools/release/test_release_workflow_recovery.py"),
            py("tools/release/test_publish_pages_manifest.py"),
            py("tools/release/test_publish_pages_site.py"),
            py("tools/release/test_check_pages_signature_files.py"),
        ),
        needs_import="cryptography",
    ),
    Step(
        "core-flutter-free-tests",
        "the Flutter-free core guard's comment-safe source and graph logic",
        (py("tools/ci/test_check_core_flutter_free.py"),),
    ),
    Step(
        "core-coverage-tests",
        "the Flutter-free core coverage-floor calculation",
        (py("tools/ci/test_check_core_coverage.py"),),
    ),
    Step(
        "format",
        "dart format",
        (("dart", "format", "--output=none", "--set-exit-if-changed", "."),),
        fast=False,
        needs_binary="dart",
    ),
    Step(
        "flutter-version",
        "the installed Flutter SDK matches .fvmrc",
        (py("tools/ci/check_flutter_version.py"),),
        fast=False,
        needs_binary="flutter",
    ),
    Step(
        "analyze",
        "flutter analyze --fatal-infos",
        (("flutter", "analyze", "--fatal-infos"),),
        fast=False,
        needs_binary="flutter",
    ),
    Step(
        "l10n-drift",
        "committed localizations match the current ARB-generated output",
        (py("tools/ci/check_l10n_drift.py"),),
        fast=False,
        needs_binary="flutter",
    ),
    Step(
        "core-flutter-free",
        "compendium_core's dependency closure and source directives exclude Flutter",
        (py("tools/ci/check_core_flutter_free.py"),),
        fast=False,
        needs_binary="dart",
    ),
    Step(
        "fixtures",
        "figure fixtures are valid under the taxonomy -- `dart test` does NOT check this",
        (("dart", "run", "tool/check_fixture_validity.dart"),),
        cwd=ROOT / "packages" / "compendium_core",
        fast=False,
        needs_binary="dart",
    ),
    Step(
        "core-tests",
        "compendium_core suite with CI-equivalent LCOV generation",
        (py("tools/ci/run_core_tests_with_coverage.py"),),
        fast=False,
        needs_binary="dart",
    ),
    Step(
        "core-coverage",
        "compendium_core's generated-source-excluded 80% coverage floor",
        (py("tools/ci/check_core_coverage.py"),),
        fast=False,
        needs_binary="dart",
    ),
    Step(
        "benchmark",
        "compendium_core search benchmark",
        (("dart", "run", "benchmark/search_benchmark.dart"),),
        cwd=ROOT / "packages" / "compendium_core",
        fast=False,
        needs_binary="dart",
    ),
    Step(
        "app-tests",
        "app suite (includes the privacy classification ratchets)",
        (("flutter", "test"),),
        cwd=ROOT / "app",
        fast=False,
        needs_binary="flutter",
    ),
)


def _unavailable(step: Step) -> str | None:
    if step.needs_binary and shutil.which(step.needs_binary) is None:
        return f"{step.needs_binary} is not on PATH"
    if step.needs_import:
        try:
            __import__(step.needs_import)
        except ImportError:
            return f"python module {step.needs_import!r} is not installed"
    return None


def _tail(text: str) -> list[str]:
    lines = [line for line in text.splitlines() if line.strip()]
    return lines[-FAIL_TAIL_LINES:]


def run_step(step: Step) -> tuple[str, str]:
    """Return (status, detail) where status is one of ok / FAIL / skip."""
    unavailable = _unavailable(step)
    if unavailable:
        return "skip", unavailable

    started = time.monotonic()
    for command in step.commands:
        result = subprocess.run(
            command,
            cwd=step.cwd,
            check=False,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
        )
        if result.returncode != 0:
            detail = "\n".join(_tail(result.stdout + result.stderr))
            return "FAIL", f"{' '.join(command)}\n{detail}"
    return "ok", f"{time.monotonic() - started:.1f}s"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--list", action="store_true", help="show the steps and exit")
    parser.add_argument(
        "--fast",
        action="store_true",
        help="only the Python gates (skips the Dart/Flutter toolchain)",
    )
    parser.add_argument(
        "--only",
        nargs="+",
        metavar="STEP",
        help="run only these steps (see --list)",
    )
    parser.add_argument(
        "--require-available",
        action="store_true",
        help="fail instead of skipping a selected gate with a missing toolchain",
    )
    args = parser.parse_args(argv)

    if args.only:
        unknown = sorted(set(args.only) - {s.name for s in STEPS})
        if unknown:
            print(f"unknown step(s): {', '.join(unknown)}")
            return 1
        not_fast = sorted(
            step.name for step in STEPS if step.name in args.only and not step.fast
        )
        if args.fast and not_fast:
            print(
                "cannot select non-fast step(s) with --fast: "
                + ", ".join(not_fast)
            )
            return 1
        steps = [s for s in STEPS if s.name in args.only]
    else:
        steps = [s for s in STEPS if not args.fast or s.fast]

    if args.list:
        for step in steps:
            print(f"{step.name:16} {step.why}")
        return 0

    failures: list[str] = []
    skipped = 0
    for step in steps:
        status, detail = run_step(step)
        if status == "ok":
            print(f"ok   {step.name:16} {detail}")
        elif status == "skip":
            if args.require_available:
                failures.append(step.name)
                print(f"FAIL {step.name:16} unavailable: {detail}")
            else:
                skipped += 1
                print(f"skip {step.name:16} {detail}")
        else:
            failures.append(step.name)
            print(f"FAIL {step.name:16} {detail}")

    ran = len(steps) - skipped - len(failures)
    if failures:
        print(f"FAIL: {', '.join(failures)} ({ran} passed, {skipped} skipped)")
        return 1
    print(f"OK: {ran} step(s) passed, {skipped} skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
