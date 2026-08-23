#!/usr/bin/env python3
"""Focused regression tests for local CI-gate selection and availability policy."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("preflight.py")
SPEC = importlib.util.spec_from_file_location("preflight_under_test", SCRIPT)
assert SPEC and SPEC.loader
preflight = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = preflight
SPEC.loader.exec_module(preflight)

FAST_STEP = preflight.Step("fast", "test fast", (("echo", "fast"),))
SLOW_STEP = preflight.Step("slow", "test slow", (("echo", "slow"),), fast=False)
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


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} preflight tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
