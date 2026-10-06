#!/usr/bin/env python3
"""Guard: CI runs the native Swift tests (RunnerTests) on the iOS and macOS legs.

``app/ios/RunnerTests`` and ``app/macos/RunnerTests`` hold XCTest suites for the
Swift code that Dart tests cannot reach: the share-extension URL queue, bounded
staging of incoming files, and the macOS termination handshake. ``flutter
build`` does not compile test targets, so until post-audit finding platform-7
nothing in CI ever built or ran them; they could stop compiling, or start
failing, unnoticed.

``ci.yml``'s ``build`` job now runs ``xcodebuild test`` for the ``Runner``
scheme on its ``ios`` and ``macos`` legs, gated by ``classify``'s
``apple_native_changed`` output so a Dart-only PR does not pay for it (pushes to
main set every output true, so main stays proven). This guard fails when either
half of that goes away:

- each of the ``ios`` and ``macos`` legs has a step in the ``build`` job whose
  ``if:`` selects that leg and requires ``apple_native_changed``, whose
  ``run:`` calls ``xcodebuild test`` against ``Runner.xcworkspace`` with
  ``-scheme Runner`` and a destination for that platform, and which is not
  ``continue-on-error`` (a test step whose failure cannot fail the job proves
  nothing);
- ``classify`` declares the ``apple_native_changed`` output, its push branch
  sets it true, and ``classify_changes.py`` emits it and sets it for a change
  under ``app/ios/`` and ``app/macos/``.

The workflow is read with a small indentation walker rather than a YAML
library (the tools here are stdlib-only): the ``build`` job runs to the next
line at its own two-space indentation, each step starts at a six-space ``- ``,
and a step key's value runs until the next line at that key's indentation.

Usage: ``check_apple_native_tests.py`` (no arguments). Exit 0 when the wiring is
present, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CI_WORKFLOW = Path(".github/workflows/ci.yml")
OUTPUT = "apple_native_changed"

# Leg name -> regex its xcodebuild -destination value must match.
LEGS = {
    "ios": re.compile(r"""-destination\s+["']?(?:id=|platform=iOS Simulator)"""),
    "macos": re.compile(r"""-destination\s+["']?platform=macOS"""),
}

# A path under each native tree that the classifier must route to OUTPUT.
NATIVE_SAMPLE_PATHS = {
    "ios": b"app/ios/Runner/AppDelegate.swift",
    "macos": b"app/macos/Runner/AppDelegate.swift",
}


def job_block(text: str, job: str) -> list[str]:
    """The lines of ``jobs.<job>``, header excluded; ``[]`` when absent."""
    lines = text.splitlines()
    header = re.compile(rf"^  {re.escape(job)}:\s*(?:#.*)?$")
    for i, line in enumerate(lines):
        if header.match(line):
            body: list[str] = []
            for follow in lines[i + 1 :]:
                stripped = follow.strip()
                if stripped and not stripped.startswith("#"):
                    if len(follow) - len(follow.lstrip()) <= 2:
                        break
                body.append(follow)
            return body
    return []


def steps(job_lines: list[str]) -> list[list[str]]:
    """Splits a job body's ``steps:`` list into one line list per step."""
    result: list[list[str]] = []
    in_steps = False
    for line in job_lines:
        if re.match(r"^    steps:\s*$", line):
            in_steps = True
            continue
        if not in_steps:
            continue
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if stripped and not stripped.startswith("#") and indent <= 4:
            break
        if re.match(r"^      - ", line):
            result.append([line])
        elif result:
            result[-1].append(line)
    return result


def step_value(step: list[str], key: str) -> str:
    """The value of ``key`` in one step, block scalars joined with newlines.

    The key sits at eight spaces, or directly after the step's ``- ``. Its
    value is the rest of that line plus every following line indented deeper
    than eight spaces, stopping at the next key of the step."""
    key_re = re.compile(rf"^(?:      - |        ){re.escape(key)}:(?P<rest>.*)$")
    for i, line in enumerate(step):
        match = key_re.match(line)
        if not match:
            continue
        parts = [match.group("rest").strip()]
        for follow in step[i + 1 :]:
            stripped = follow.strip()
            indent = len(follow) - len(follow.lstrip())
            if stripped and indent <= 8:
                break
            parts.append(follow.strip())
        # A folded scalar (">", ">-") is one line to YAML; a literal ("|")
        # keeps its newlines.
        joiner = " " if parts[0].startswith(">") else "\n"
        return joiner.join(parts[1:] if parts[0][:1] in (">", "|") else parts).strip()
    return ""


def _shell_commands(run: str) -> list[str]:
    """``run`` with comments dropped and backslash continuations joined."""
    kept = [line for line in run.splitlines() if not line.lstrip().startswith("#")]
    return re.sub(r"\\\n\s*", " ", "\n".join(kept)).splitlines()


def _selects_leg(condition: str, leg: str) -> bool:
    return re.search(rf"""matrix\.target\s*==\s*['"]{leg}['"]""", condition) is not None


def _requires_output(condition: str) -> bool:
    return (
        re.search(
            rf"""needs\.classify\.outputs\.{OUTPUT}\s*==\s*['"]true['"]""", condition
        )
        is not None
    )


def leg_test_step_errors(text: str, leg: str) -> list[str]:
    """Why no step of ``build`` runs the Runner tests for ``leg``; ``[]`` if one does."""
    build = job_block(text, "build")
    if not build:
        return ["no 'build' job found."]
    candidates = [s for s in steps(build) if _selects_leg(step_value(s, "if"), leg)]
    reasons: list[str] = []
    for step in candidates:
        name = step_value(step, "name") or "(unnamed step)"
        commands = [
            c for c in _shell_commands(step_value(step, "run"))
            if re.search(r"\bxcodebuild\b.*\btest\b", c)
        ]
        problems: list[str] = []
        if not commands:
            problems.append("its run: does not call 'xcodebuild test'")
        elif not any(
            re.search(r"-workspace\s+[\"']?Runner\.xcworkspace\b", c)
            and re.search(r"-scheme\s+[\"']?Runner\b", c)
            and LEGS[leg].search(c)
            for c in commands
        ):
            problems.append(
                "no 'xcodebuild test' there names -workspace Runner.xcworkspace, "
                f"-scheme Runner and a {leg} -destination together"
            )
        if not _requires_output(step_value(step, "if")):
            problems.append(f"its if: does not require needs.classify.outputs.{OUTPUT}")
        if step_value(step, "continue-on-error").strip("'\"").lower() not in ("", "false"):
            problems.append("it is continue-on-error, so a failing test cannot fail the job")
        if not problems:
            return []
        reasons.append(f"step '{name}': " + "; ".join(problems))
    if not candidates:
        reasons.append(f"no step's if: selects matrix.target == '{leg}'")
    return [
        f"the build job's {leg} leg does not run the native Runner tests: "
        + " / ".join(reasons)
    ]


def classify_wiring_errors(text: str) -> list[str]:
    errors: list[str] = []
    classify = "\n".join(job_block(text, "classify"))
    if not classify:
        return ["no 'classify' job found."]
    if not re.search(
        rf"^\s+{OUTPUT}:\s*\$\{{\{{\s*steps\.classify\.outputs\.{OUTPUT}\s*\}}\}}\s*$",
        classify,
        re.MULTILINE,
    ):
        errors.append(f"the classify job does not declare the '{OUTPUT}' output.")
    if not re.search(rf"echo\s+['\"]?{OUTPUT}=true", classify):
        errors.append(
            f"the classify job's push branch does not set {OUTPUT}=true, so pushes "
            "to main would skip the native tests."
        )
    return errors


def classifier_errors() -> list[str]:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import classify_changes  # noqa: PLC0415

    if OUTPUT not in classify_changes.OUTPUT_KEYS:
        return [f"classify_changes.py does not emit '{OUTPUT}' (OUTPUT_KEYS)."]
    errors: list[str] = []
    for leg, path in NATIVE_SAMPLE_PATHS.items():
        if not classify_changes.classify((path,)).get(OUTPUT):
            errors.append(
                f"classify_changes.py does not set {OUTPUT} for {path.decode()}, "
                f"so a {leg} native change would not run its tests."
            )
    return errors


def check(root: Path = REPO_ROOT, *, include_classifier: bool = True) -> list[str]:
    path = root / CI_WORKFLOW
    if not path.is_file():
        return [f"{CI_WORKFLOW}: missing."]
    text = path.read_text(encoding="utf-8")
    errors = [f"{CI_WORKFLOW}: {e}" for leg in LEGS for e in leg_test_step_errors(text, leg)]
    errors += [f"{CI_WORKFLOW}: {e}" for e in classify_wiring_errors(text)]
    if include_classifier:
        errors += classifier_errors()
    return errors


def main() -> int:
    errors = check()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print("OK: the ios and macos build legs run the native Runner tests when Apple native code changes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
