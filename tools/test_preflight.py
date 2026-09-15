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


def test_toolchain_steps_use_pinned_fvm_commands() -> None:
    toolchain_steps = [step for step in preflight.STEPS if not step.fast]
    assert len(toolchain_steps) == 12
    for step in toolchain_steps:
        assert step.needs_binary == "fvm", step.name
        assert all(command[0] == "fvm" for command in step.commands), step.name


def test_rubric_tests_are_wired_end_to_end() -> None:
    rubric = next(step for step in preflight.STEPS if step.name == "rubric-tests")
    assert rubric.cwd == preflight.ROOT / "packages" / "compendium_rubric"
    assert rubric.commands == (
        preflight.fvm("dart", "analyze"),
        preflight.fvm("dart", "test"),
    )

    ci = (preflight.ROOT / ".github" / "workflows" / "ci.yml").read_text()
    checks = (
        preflight.ROOT / ".github" / "workflows" / "_checks.yml"
    ).read_text()
    assert "echo 'rubric_tests_changed=true'" in ci
    classifier = ci.split("rubric_tests_changed = validation_changed and any(", 1)[1]
    classifier = classifier.split("app_tests_changed =", 1)[0]
    assert "path.startswith(b'packages/compendium_rubric/')" in classifier
    assert "path.startswith(b'packages/compendium_core/')" in classifier
    assert "path in shared_runtime_paths" in classifier
    assert (
        "run_rubric_tests: "
        "${{ needs.classify.outputs.rubric_tests_changed == 'true' }}"
    ) in ci

    assert "run_rubric_tests:" in checks
    rubric_job = checks.split("\n  rubric-tests:\n", 1)[1]
    rubric_job = rubric_job.split("\n  app-tests:\n", 1)[0]
    assert "if: inputs.run_rubric_tests" in rubric_job
    assert "working-directory: packages/compendium_rubric" in rubric_job
    assert "run: dart analyze" in rubric_job
    assert "run: dart test" in rubric_job


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} preflight tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
