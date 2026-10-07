#!/usr/bin/env python3
"""Focused regression tests for local CI-gate selection and availability policy."""

from __future__ import annotations

import contextlib
import importlib.abc
import importlib.machinery
import importlib.util
import io
import re
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path, PurePath

SCRIPT = Path(__file__).resolve().with_name("preflight.py")
ROOT = SCRIPT.parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
SPEC = importlib.util.spec_from_file_location("preflight_under_test", SCRIPT)
assert SPEC and SPEC.loader
preflight = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = preflight
SPEC.loader.exec_module(preflight)

FAST_STEP = preflight.Step("fast", "test fast", (("echo", "fast"),))
SLOW_STEP = preflight.Step("slow", "test slow", (("echo", "slow"),), fast=False)
# Runs for real (`echo` is not an executable on Windows), so the steps whose
# point is the lock around them can actually be executed.
NOOP = (sys.executable, "-c", "pass")
RUNNABLE_SLOW_STEP = preflight.Step("slow", "test slow", (NOOP,), fast=False)
RUNNABLE_FAST_STEP = preflight.Step("fast", "test fast", (NOOP,))
UNAVAILABLE_STEP = preflight.Step(
    "unavailable",
    "test unavailable",
    (("echo", "unavailable"),),
    needs_binary="__preflight_test_missing_binary__",
)


@contextlib.contextmanager
def steps_for_test(*steps):
    previous = preflight.STEPS
    preflight.STEPS = tuple(steps)
    try:
        yield
    finally:
        preflight.STEPS = previous


@contextlib.contextmanager
def private_lock_path():
    """Point the machine-wide lock at a temp file, so tests cannot queue behind
    (or stall) a real preflight running on the same host."""
    previous = preflight.TOOLCHAIN_LOCK
    previous_poll = preflight.LOCK_POLL_SECONDS
    with tempfile.TemporaryDirectory() as directory:
        preflight.TOOLCHAIN_LOCK = Path(directory) / "test-preflight.lock"
        preflight.LOCK_POLL_SECONDS = 0.02
        try:
            yield preflight.TOOLCHAIN_LOCK
        finally:
            preflight.TOOLCHAIN_LOCK = previous
            preflight.LOCK_POLL_SECONDS = previous_poll


def invoke(*argv: str) -> tuple[int, str]:
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        code = preflight.main(list(argv))
    return code, output.getvalue()


def test_fast_only_slow_step_is_invalid() -> None:
    """Regression: this formerly ran and skipped ``slow`` with exit code zero."""
    with steps_for_test(FAST_STEP, SLOW_STEP):
        code, output = invoke("--fast", "--only", "slow")
    assert code == 1
    assert "cannot select non-fast step(s) with --fast: slow" in output


def test_default_skips_unavailable_gate() -> None:
    with steps_for_test(UNAVAILABLE_STEP):
        code, output = invoke()
    assert code == 0
    assert "skip unavailable" in output


def test_require_available_fails_unavailable_gate() -> None:
    with steps_for_test(UNAVAILABLE_STEP):
        code, output = invoke("--require-available")
    assert code == 1
    assert "FAIL unavailable" in output
    assert "not on PATH" in output


def test_toolchain_steps_use_pinned_fvm_commands() -> None:
    toolchain_steps = [step for step in preflight.STEPS if not step.fast]
    assert len(toolchain_steps) == 11
    for step in toolchain_steps:
        assert step.needs_binary == "fvm", step.name
        assert all(command[0] == "fvm" for command in step.commands), step.name


def test_default_test_jobs_halve_cores_capped_at_four() -> None:
    assert preflight.test_jobs({}, 16) == 4
    assert preflight.test_jobs({}, 8) == 4
    assert preflight.test_jobs({}, 4) == 2
    assert preflight.test_jobs({}, 1) == 1
    assert preflight.test_jobs({}, None) == 4


def test_test_jobs_override_is_honoured_and_validated() -> None:
    assert preflight.test_jobs({preflight.TEST_JOBS_ENV: "8"}, 16) == 8
    for bad in ("0", "-1", "", "four", "4.5"):
        try:
            preflight.test_jobs({preflight.TEST_JOBS_ENV: bad}, 16)
        except ValueError:
            continue
        raise AssertionError(f"{bad!r} should be rejected, not silently defaulted")


def test_app_tests_cap_flutter_test_concurrency() -> None:
    """Unbounded, `flutter test` starts one engine per two cores: 5.1 GB here."""
    (step,) = [step for step in preflight.STEPS if step.name == "app-tests"]
    (command,) = step.commands
    assert f"--concurrency={preflight.TEST_JOBS}" in command
    assert preflight.TEST_JOBS <= preflight.MAX_TEST_JOBS


def test_toolchain_lock_excludes_a_second_holder() -> None:
    with private_lock_path() as path:
        with preflight.toolchain_lock():
            with open(path, "a+", encoding="utf-8") as rival:
                try:
                    preflight._lock_exclusive(rival)
                except OSError:
                    pass
                else:
                    preflight._unlock(rival)
                    raise AssertionError("a second preflight took the held lock")


def test_toolchain_lock_is_released_after_the_run() -> None:
    with private_lock_path() as path:
        with steps_for_test(RUNNABLE_SLOW_STEP):
            assert invoke()[0] == 0
        with open(path, "a+", encoding="utf-8") as after:
            preflight._lock_exclusive(after)
            preflight._unlock(after)


def test_toolchain_step_queues_behind_a_held_lock() -> None:
    with private_lock_path() as path:
        handle = open(path, "a+", encoding="utf-8")
        preflight._lock_exclusive(handle)
        released = threading.Event()

        def release() -> None:
            time.sleep(0.2)
            released.set()
            preflight._unlock(handle)
            handle.close()

        waiter = threading.Thread(target=release)
        waiter.start()
        try:
            with steps_for_test(RUNNABLE_SLOW_STEP):
                code, output = invoke()
        finally:
            waiter.join()
        assert code == 0
        assert released.is_set(), "the run started before the lock was released"
        assert "wait toolchain" in output


def test_fast_run_does_not_wait_for_the_toolchain_lock() -> None:
    """The Python gates cost megabytes; queueing them behind a Dart run is pure
    latency, and `--fast` exists to be the cheap answer."""
    with private_lock_path():
        with preflight.toolchain_lock():
            with steps_for_test(RUNNABLE_FAST_STEP, SLOW_STEP):
                code, output = invoke("--fast")
        assert code == 0
        assert "wait toolchain" not in output


def test_no_lock_runs_a_toolchain_step_while_the_lock_is_held() -> None:
    with private_lock_path():
        with preflight.toolchain_lock():
            with steps_for_test(RUNNABLE_SLOW_STEP):
                code, output = invoke("--no-lock")
        assert code == 0
        assert "wait toolchain" not in output
        assert "ok   slow" in output


def python_test_files() -> list[str]:
    """Every ``tools/**/test_*.py``, repo-relative, forward slashes."""
    return sorted(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "tools").rglob("test_*.py")
    )


_RUN_BLOCK_SCALARS = ("", "|", "|-", "|+", ">", ">-", ">+")


def run_commands_from_text(workflow_text: str) -> list[str]:
    """Every ``run:`` command body in one workflow file's text.

    A test file only counts as wired in if a ``run:`` step actually invokes
    it -- naming it elsewhere (a comment, a ``paths:`` trigger filter) proves
    nothing about whether it executes. A single-line form (``run: python3
    x.py``) contributes its remainder; a block-scalar form (``run: |``)
    contributes every following line indented past the ``run:`` key itself,
    which is how a multi-command step (several ``python3 ...`` lines under
    one ``run: |``) is written in this repo's workflows. The block ends at
    the first line whose indentation is not deeper (or end of file).
    """
    lines = workflow_text.splitlines()
    commands: list[str] = []
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        if line.lstrip().startswith("#") or "run:" not in line:
            i += 1
            continue
        run_col = line.index("run:")
        rest = line[run_col + len("run:"):].strip()
        i += 1
        if rest not in _RUN_BLOCK_SCALARS:
            commands.append(rest)
            continue
        while i < n:
            cont = lines[i]
            if cont.strip() == "":
                i += 1
                continue
            if len(cont) - len(cont.lstrip()) <= run_col:
                break
            commands.append(cont)
            i += 1
    return commands


def run_commands_text() -> str:
    """Every ``run:`` command body across all workflow files, joined."""
    commands: list[str] = []
    for path in sorted(WORKFLOWS.glob("*.yml")):
        commands.extend(run_commands_from_text(path.read_text(encoding="utf-8")))
    return "\n".join(commands)


def test_every_python_test_file_runs_in_a_workflow() -> None:
    """A test file only ships its guarantee if some workflow executes it.

    Each ``tools/**/test_*.py`` is invoked by name from a ``run:`` line -- there
    is no discovery step -- so a new test file is silent until someone wires
    it. Two were not: ``tools/ci/test_classify_changes.py`` (the test of the
    script that decides which gates run at all) and ``tools/release/test_bash.py``.

    The search is restricted to ``run:`` command bodies, not the whole
    workflow file: a test file's name also appears in a ``paths:`` trigger
    filter in the same repo (``test_compile_changelog_fragments.py`` in
    ``changelog-structure.yml``), and a raw substring search across the
    whole file would call that "run" even if every actual ``run:`` line
    invoking it were deleted (found in review).
    """
    commands = run_commands_text()
    missing = [test for test in python_test_files() if test not in commands]
    assert not missing, f"tools test file(s) not run by any workflow: {missing}"


def test_run_commands_from_text_ignores_non_run_mentions() -> None:
    """A test file named only in a ``paths:`` filter is not "run".

    The naive implementation searched the whole workflow file (minus
    full-line comments), so a script mentioned only in a trigger filter --
    or reinstated there after its ``run:`` line was deleted -- would still
    read as wired in. This pins that the extraction is scoped to ``run:``
    command bodies specifically.
    """
    workflow = (
        "on:\n"
        "  push:\n"
        "    paths:\n"
        "      - 'tools/ci/test_only_in_paths_filter.py'\n"
        "jobs:\n"
        "  checks:\n"
        "    steps:\n"
        "      # tools/ci/test_only_in_comment.py described here\n"
        "      - run: python3 tools/ci/test_single_line.py\n"
        "      - run: |\n"
        "          python3 tools/ci/test_block_first.py\n"
        "          python3 tools/ci/test_block_second.py\n"
        "      - name: next step\n"
        "        run: python3 tools/ci/test_after_block.py\n"
    )
    commands = run_commands_from_text(workflow)
    joined = "\n".join(commands)

    assert "tools/ci/test_only_in_paths_filter.py" not in joined
    assert "tools/ci/test_only_in_comment.py" not in joined
    assert "tools/ci/test_single_line.py" in joined
    assert "tools/ci/test_block_first.py" in joined
    assert "tools/ci/test_block_second.py" in joined
    assert "tools/ci/test_after_block.py" in joined


_TEST_RUNNER = re.compile(r"\b(?:dart|flutter)\s+test\b")
_TEST_CONCURRENCY = re.compile(r"(?:^|\s)(?:-j\s*\d+|--concurrency[= ]\d+)(?=\s|$)")


def unbounded_test_commands(commands_text: str) -> list[str]:
    """``dart test`` / ``flutter test`` commands with no explicit concurrency."""
    return [
        line.strip()
        for line in commands_text.splitlines()
        if _TEST_RUNNER.search(line) and not _TEST_CONCURRENCY.search(line)
    ]


def test_workflow_test_commands_set_explicit_concurrency() -> None:
    """Left to the default, `flutter test` runs nproc/2 processes (2 on the
    4-core runner) and `dart test` its own default; CI pins both."""
    unbounded = unbounded_test_commands(run_commands_text())
    assert not unbounded, f"dart/flutter test without -j/--concurrency: {unbounded}"


def test_unbounded_test_commands_flags_missing_concurrency() -> None:
    workflow = (
        "      - run: flutter test\n"
        "      - run: dart test test\n"
        "      - run: flutter test --concurrency=4\n"
        "      - run: dart test -j 4\n"
        "      - run: python3 tools/ci/run_core_tests_with_coverage.py\n"
    )
    commands = "\n".join(run_commands_from_text(workflow))
    assert unbounded_test_commands(commands) == ["flutter test", "dart test test"]


class _Panic(BaseException):
    """Stands in for pyo3's PanicException, which is not an Exception."""


@contextlib.contextmanager
def broken_submodule_package(name: str):
    """A package that imports, whose submodule import panics."""
    import types

    package = types.ModuleType(name)
    package.__path__ = []  # type: ignore[attr-defined]
    submodule = f"{name}.sub"

    class Finder:
        def find_spec(self, fullname, path=None, target=None):
            if fullname != submodule:
                return None
            loader = importlib.abc.Loader()
            loader.create_module = lambda spec: None  # type: ignore[method-assign]

            def exec_module(module):
                raise _Panic("simulated pyo3 panic")

            loader.exec_module = exec_module  # type: ignore[method-assign]
            return importlib.machinery.ModuleSpec(fullname, loader)

    finder = Finder()
    sys.modules[name] = package
    sys.meta_path.insert(0, finder)
    try:
        yield submodule
    finally:
        sys.meta_path.remove(finder)
        sys.modules.pop(name, None)
        sys.modules.pop(submodule, None)


def test_broken_import_probe_reports_unavailable_not_fail() -> None:
    with broken_submodule_package("preflight_stub_pkg") as submodule:
        step = preflight.Step(
            "stub", "test stub", (NOOP,), needs_import=submodule
        )
        reason = preflight._unavailable(step)
    assert reason is not None
    assert "_Panic" in reason


def test_import_probe_does_not_swallow_keyboard_interrupt() -> None:
    class Finder:
        def find_spec(self, fullname, path=None, target=None):
            if fullname == "preflight_stub_interrupt":
                raise KeyboardInterrupt
            return None

    finder = Finder()
    sys.meta_path.insert(0, finder)
    try:
        step = preflight.Step(
            "stub", "test stub", (NOOP,), needs_import="preflight_stub_interrupt"
        )
        try:
            preflight._unavailable(step)
        except KeyboardInterrupt:
            return
        raise AssertionError("KeyboardInterrupt must propagate")
    finally:
        sys.meta_path.remove(finder)


def test_release_tooling_probes_the_ed25519_submodule() -> None:
    (step,) = [step for step in preflight.STEPS if step.name == "release-tooling"]
    assert step.needs_import == "cryptography.hazmat.primitives.asymmetric.ed25519"


def test_pdfium_pin_tests_are_split_across_two_steps() -> None:
    """The cmake -P half must SKIP without cmake, not crash release-tooling,
    and the two halves together must still run the whole file."""
    steps = {step.name: step for step in preflight.STEPS}
    pin = "tools/release/test_pdfium_pin.py"

    def flags(name: str) -> list[tuple[str, ...]]:
        return [c[c.index(pin) + 1 :] for c in steps[name].commands if pin in c]

    assert flags("release-tooling") == [("--without-cmake",)]
    assert flags("pdfium-verifier") == [("--cmake-only",)]
    assert steps["pdfium-verifier"].needs_binary == "cmake"


def test_core_tests_step_passes_preflight_jobs() -> None:
    (step,) = [step for step in preflight.STEPS if step.name == "core-tests"]
    (command,) = step.commands
    assert command[-2:] == ("-j", str(preflight.TEST_JOBS))


def test_every_python_test_file_is_a_preflight_step() -> None:
    """docs/dev/README.md calls preflight the local mirror of CI, and the
    mirror had holes in both directions: the changelog-fragment compiler's
    test and ``test_resolve_release_codename.py`` ran only in CI, so a
    malformed ``changelog.d`` fragment passed ``--fast`` and failed on the PR.
    """
    commands = {
        PurePath(part).as_posix()
        for step in preflight.STEPS
        for command in step.commands
        for part in command
    }
    missing = [test for test in python_test_files() if test not in commands]
    assert not missing, f"tools test file(s) with no preflight step: {missing}"


def test_unavailable_toolchain_step_does_not_take_the_lock() -> None:
    unavailable_slow = preflight.Step(
        "slow",
        "test slow",
        (NOOP,),
        fast=False,
        needs_binary="__preflight_test_missing_binary__",
    )
    with private_lock_path():
        with preflight.toolchain_lock():
            with steps_for_test(unavailable_slow):
                code, output = invoke()
        assert code == 0
        assert "wait toolchain" not in output
        assert "skip slow" in output


def _core_coverage_driver():
    spec = importlib.util.spec_from_file_location(
        "run_core_tests_with_coverage",
        Path(__file__).resolve().parent / "ci" / "run_core_tests_with_coverage.py",
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_core_coverage_driver_forwards_jobs_to_dart_test() -> None:
    """CI runs the core suite through this driver with no `-j` of its own
    (`_checks.yml`), so the driver's own `-j` is what pins core-test
    concurrency there (CS-09 T1). Dropping it left every test green."""
    driver = _core_coverage_driver()
    commands: list[list[str]] = []

    class _Done:
        returncode = 0

    def fake_run(command, **_kwargs):
        commands.append(list(command))
        return _Done()

    # driver.subprocess is the process-wide module: restore it, or every later
    # test that really runs a subprocess would get this fake instead.
    real_run = driver.subprocess.run
    driver.subprocess.run = fake_run
    try:
        with tempfile.TemporaryDirectory() as tmp:
            core = Path(tmp)
            (core / "test").mkdir()
            (core / "test" / "a_test.dart").write_text("", encoding="utf-8")
            assert driver.run(core, jobs=3) == 0
    finally:
        driver.subprocess.run = real_run
    assert subprocess.run is real_run
    (command,) = commands
    jobs_at = command.index("-j")
    assert command[jobs_at + 1] == "3", command

    seen: list[int] = []
    driver.run = lambda core_dir=None, jobs=None: seen.append(jobs) or 0
    assert driver.main([]) == 0
    assert seen == [driver.DEFAULT_JOBS]


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} preflight tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
