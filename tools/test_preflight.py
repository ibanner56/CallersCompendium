#!/usr/bin/env python3
"""Focused regression tests for local CI-gate selection and availability policy."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
import tempfile
import threading
import time
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("preflight.py")
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


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} preflight tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
