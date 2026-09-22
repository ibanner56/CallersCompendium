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
without FVM still run every applicable Python gate. Pass --require-available
to make a selected unavailable gate fail instead.

The Dart/Flutter steps hold a machine-wide lock, because their cost is measured
in gigabytes rather than seconds: on a 16-thread, 16 GB Windows host `app-tests`
alone peaked at 5.1 GB resident (eight `flutter_tester` processes plus the tool
and its compiler) and drove system commit to 18.46 GB of an 18.8 GB limit. Two
preflights at once therefore do not fit, and the failure is not a red gate --
the second run is killed by whatever reaps processes when the host runs out of
memory, which reads as an infrastructure flake and buys a retry that fails the
same way. Runs now queue instead: the lock is taken before the first Dart step
that will actually run and released at the end, so `--fast` runs and the Python
gates of a full run never wait for it. Pass --no-lock to opt out.

Exit codes: 0 = every selected step passed or was skipped, 1 = invalid selection
or a selected step failed / was unavailable under --require-available.
"""

from __future__ import annotations

import argparse
import contextlib
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterator, Mapping
from dataclasses import dataclass
from pathlib import Path, PurePath
from typing import IO, Sequence

ROOT = Path(__file__).resolve().parent.parent
FAIL_TAIL_LINES = 12

# One lock per machine, not per checkout: the constraint is the host's memory,
# and the sessions that collide are in *different* worktrees. The per-user temp
# directory is the right home for it -- every session here runs as the same user,
# and a lock that vanishes on reboot is a lock that cannot go stale across one.
TOOLCHAIN_LOCK = Path(tempfile.gettempdir()) / "callers-compendium-preflight.lock"
LOCK_POLL_SECONDS = 2.0

# Half the cores, capped at 4. `flutter test` otherwise defaults to
# `numberOfProcessors / 2` test processes -- 8 here -- and each holds a full
# engine: measured 5.1 GB peak at 8 against 3.3 GB at 4, for 196s against
# 208-235s over three capped runs. Half a minute is worth 1.8 GB on a host whose
# spare commit is ~5 GB. The cap does not reach CI, which runs a 4-core runner
# and so lands on 2 by itself.
MAX_TEST_JOBS = 4
TEST_JOBS_ENV = "PREFLIGHT_TEST_JOBS"


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
    needs_path: Path | None = None


def test_jobs(environ: Mapping[str, str], cpu_count: int | None) -> int:
    """Concurrency for the Flutter test step: see MAX_TEST_JOBS.

    Raises ValueError for an unusable override rather than falling back to the
    default: a typo in the variable that is there to bound memory should say so,
    not silently restore the 8-process run it was set to prevent.
    """
    override = environ.get(TEST_JOBS_ENV)
    if override is not None:
        try:
            jobs = int(override)
        except ValueError:
            raise ValueError(f"{TEST_JOBS_ENV}={override!r} is not an integer") from None
        if jobs < 1:
            raise ValueError(f"{TEST_JOBS_ENV}={override!r} must be at least 1")
        return jobs
    return max(1, min(MAX_TEST_JOBS, (cpu_count or 2 * MAX_TEST_JOBS) // 2))


try:
    TEST_JOBS = test_jobs(os.environ, os.cpu_count())
except ValueError as error:
    sys.exit(f"preflight: {error}")


def _lock_exclusive(handle: IO[str]) -> None:
    """Take a whole-file advisory lock, or raise OSError if another run holds it.

    Both implementations are tied to the open file, so the OS drops the lock when
    this process exits however it exits -- including the low-memory kill this
    lock exists to prevent. That is why there is no PID file and no staleness
    check: a lock that outlives its holder would need one, and this cannot.
    """
    if os.name == "nt":
        import msvcrt

        msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
    else:
        import fcntl

        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)


def _unlock(handle: IO[str]) -> None:
    if os.name == "nt":
        import msvcrt

        msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        import fcntl

        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


@contextlib.contextmanager
def toolchain_lock() -> Iterator[None]:
    """Serialize the Dart/Flutter steps against every other preflight on the host."""
    with open(TOOLCHAIN_LOCK, "a+", encoding="utf-8") as handle:
        announced = False
        while True:
            try:
                _lock_exclusive(handle)
                break
            except OSError:
                if not announced:
                    print(
                        f"wait {'toolchain':16} another preflight holds "
                        f"{TOOLCHAIN_LOCK.name}; queued behind it",
                        flush=True,
                    )
                    announced = True
                time.sleep(LOCK_POLL_SECONDS)
        try:
            yield
        finally:
            _unlock(handle)


def py(*args: str) -> tuple[str, ...]:
    if not args:
        return (sys.executable,)

    # Automatically switch separators based on the host OS
    normalized_script = str(PurePath(args[0]))
    remaining_args = args[1:]

    return (sys.executable, normalized_script, *remaining_args)


def fvm(*args: str) -> tuple[str, ...]:
    return ("fvm", *args)


def fvm_py(*args: str) -> tuple[str, ...]:
    return fvm("exec", *py(*args))


STEPS: tuple[Step, ...] = (
    Step(
        "preflight",
        "the local CI-gate selector and availability policy",
        (py("tools/test_preflight.py"),),
    ),
    Step(
        "classify-gate",
        "the CI path-classification gate's own logic (routes changes to their guards)",
        (py("tools/ci/test_classify_changes.py"),),
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
        "device-sync-tracking",
        "ADR-004 work units, dependencies, evidence, and Project projection",
        (
            py("tools/tracking/test_validate.py"),
            py("tools/tracking/test_validate_pr.py"),
            py("tools/tracking/test_sync_project.py"),
            py("tools/tracking/test_workflow_integration.py"),
            py("tools/tracking/validate.py"),
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
        "sync-invariants",
        "soft-delete joins, sync writes, certificate hatches, and normalizers",
        (
            py("tools/ci/test_check_sync_invariants.py"),
            py("tools/ci/check_sync_invariants.py"),
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
            py("tools/site/test_privacy_policy.py"),
            py("tools/site/render_user_docs.py", "--check"),
        ),
    ),
    Step(
        "release-tooling",
        "release identity / SBOM / metadata / notes / Pages publishing",
        (
            py("tools/release/test_bash.py"),
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
        (fvm("dart", "format", "--output=none", "--set-exit-if-changed", "."),),
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "flutter-version",
        "the installed Flutter SDK matches .fvmrc",
        (fvm_py("tools/ci/check_flutter_version.py"),),
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "analyze",
        "flutter analyze --fatal-infos",
        (fvm("flutter", "analyze", "--fatal-infos"),),
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "l10n-drift",
        "committed localizations match the current ARB-generated output",
        (fvm_py("tools/ci/check_l10n_drift.py"),),
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "core-flutter-free",
        "compendium_core's dependency closure and source directives exclude Flutter",
        (fvm_py("tools/ci/check_core_flutter_free.py"),),
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "fixtures",
        "figure fixtures are valid under the taxonomy -- `dart test` does NOT check this",
        (fvm("dart", "run", "tool/check_fixture_validity.dart"),),
        cwd=ROOT / "packages" / "compendium_core",
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "core-tests",
        "compendium_core suite with CI-equivalent LCOV generation",
        (fvm_py("tools/ci/run_core_tests_with_coverage.py"),),
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "core-coverage",
        "compendium_core's generated-source-excluded 80% coverage floor",
        (fvm_py("tools/ci/check_core_coverage.py"),),
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "benchmark",
        "compendium_core search benchmark",
        (fvm("dart", "run", "benchmark/search_benchmark.dart"),),
        cwd=ROOT / "packages" / "compendium_core",
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "app-tests",
        "app suite (includes the privacy classification ratchets)",
        (fvm("flutter", "test", f"--concurrency={TEST_JOBS}"),),
        cwd=ROOT / "app",
        fast=False,
        needs_binary="fvm",
    ),
    Step(
        "server-tests",
        "Athenaeum server analyzer and endpoint suite",
        (
            fvm("dart", "analyze", "server"),
            fvm("dart", "test", "server/test"),
        ),
        fast=False,
        needs_binary="fvm",
        needs_path=ROOT / "server" / "pubspec.yaml",
    ),
)


def _unavailable(step: Step) -> str | None:
    if step.needs_path and not step.needs_path.is_file():
        return f"{step.needs_path.relative_to(ROOT)} is not present"
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
    parser.add_argument(
        "--no-lock",
        action="store_true",
        help="run the Dart/Flutter steps without the machine-wide memory lock",
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
    with contextlib.ExitStack() as lock:
        held = args.no_lock
        for step in steps:
            # Lazily, and only for a step that will really run: an unavailable
            # Dart step costs no memory, and a run that took the lock to skip
            # eleven of them would stall the run that needs it. Held from there
            # to the end of the run rather than per step, so two runs do not
            # trade the lock back and forth and pay both their compile costs.
            if not held and not step.fast and _unavailable(step) is None:
                lock.enter_context(toolchain_lock())
                held = True
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
