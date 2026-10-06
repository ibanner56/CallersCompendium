#!/usr/bin/env python3
"""Guard: CI runs the Android JVM unit tests after the Android build.

``app/android/app/src/test`` holds the JVM tests for the share-intake logic
(``IncomingFileStager.kt``: the incoming size cap, the copy and its cleanup,
and cold-start vs warm routing). ``flutter build apk`` compiles none of them and
``flutter test`` is Dart-only, so without a Gradle unit-test step those tests
would never run anywhere (post-audit finding platform-7).

This reads ``.github/workflows/ci.yml``'s ``build`` job and checks that its
step list holds, after the step that runs ``flutter build``, a step that:

- has a ``run`` script line that *is* the Gradle invocation: after any
  trailing ``# comment`` is dropped, the line starts with ``./gradlew`` (or
  ``cd app/android && ./gradlew``) and names ``:app:testDebugUnitTest``. A
  line that only mentions the command (``echo ./gradlew ...``, a comment) does
  not count;
- has an ``if`` that is exactly ``matrix.target == 'android'`` (whitespace,
  quote style and a ``${{ }}`` wrapper may vary). A compound condition that
  merely contains the comparison (``false && ...``, ``... || true``) can run
  the step nowhere or everywhere, so it does not count;
- runs in ``app/android`` (where Flutter writes the Gradle wrapper during the
  build), via ``working-directory`` or a ``cd app/android &&`` prefix.

It also checks that the matrix still has an ``android`` leg, so the condition
cannot be satisfied by a leg that never runs.

Steps are found by indentation: the job body is everything below ``  build:``
until the next two-space key, and a step runs from its ``- `` line until the
next ``- `` at the same indentation. A step's keys are read only at that
step's own level, so a ``run`` string inside another step never counts.

Usage: ``check_android_unit_tests.py`` (no arguments). Exit 0 when the step is
present and ordered, 1 otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = Path(".github/workflows/ci.yml")
JOB = "build"
GRADLE_COMMAND = "./gradlew :app:testDebugUnitTest"
WORKING_DIRECTORY = "app/android"

_JOB_RE = re.compile(r"^  (?P<job>[\w-]+):\s*(?:#.*)?$")
_ANDROID_IF_RE = re.compile(r"""matrix\.target\s*==\s*(['"])android\1""")
_EXPRESSION_RE = re.compile(r"^\$\{\{(?P<inner>.*)\}\}$")
_TRAILING_COMMENT_RE = re.compile(r"(?:^|\s)#.*$")
_GRADLE_LINE_RE = re.compile(
    r"^(?P<cd>cd\s+" + re.escape("app/android") + r"/?\s*&&\s*)?\./gradlew(?:\s|$)"
)
TASK = ":app:testDebugUnitTest"
_ANDROID_LEG_RE = re.compile(r"""^\s*-\s+target:\s*['"]?android['"]?\s*$""")


def job_lines(text: str, job: str) -> list[str]:
    """The lines of ``jobs.<job>``'s body, or ``[]`` when there is no such
    job. The body ends at the next line indented two spaces or less."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        match = _JOB_RE.match(line)
        if not match or match.group("job") != job:
            continue
        body: list[str] = []
        for follow in lines[i + 1 :]:
            stripped = follow.strip()
            if stripped and not stripped.startswith("#"):
                if len(follow) - len(follow.lstrip()) <= 2:
                    break
            body.append(follow)
        return body
    return []


def steps(body: list[str]) -> list[dict[str, str]]:
    """Each step under the job's ``steps:`` key, as a map of its own
    top-level keys to their text (a block scalar's lines joined by
    newlines)."""
    start = None
    for i, line in enumerate(body):
        if line.strip() == "steps:" and len(line) - len(line.lstrip()) == 4:
            start = i + 1
            break
    if start is None:
        return []
    result: list[dict[str, str]] = []
    dash_indent = None
    current: dict[str, str] | None = None
    key = None
    key_indent = None
    for line in body[start:]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            if current is not None and key is not None and stripped == "":
                current[key] += "\n"
            continue
        indent = len(line) - len(line.lstrip())
        if dash_indent is None and stripped.startswith("- "):
            dash_indent = indent
        if dash_indent is None or indent < dash_indent:
            break
        if indent == dash_indent and stripped.startswith("- "):
            current = {}
            result.append(current)
            stripped = stripped[2:].lstrip()
            indent += 2
            key_indent = indent
        if current is None:
            continue
        if indent == key_indent and re.match(r"^[\w-]+:", stripped):
            key, _, value = stripped.partition(":")
            value = value.strip()
            current[key] = "" if value in ("|", ">", "|-", ">-") else value
        elif key is not None and indent > (key_indent or 0):
            current[key] += ("\n" if current[key] else "") + stripped
    return result


def is_android_condition(condition: str) -> bool:
    """True only for exactly ``matrix.target == 'android'``, allowing
    surrounding whitespace, either quote, and one ``${{ }}`` wrapper."""
    text = condition.strip()
    wrapped = _EXPRESSION_RE.match(text)
    if wrapped:
        text = wrapped.group("inner").strip()
    return _ANDROID_IF_RE.fullmatch(text) is not None


def gradle_invocation(run: str) -> str | None:
    """For a ``run`` script that runs the unit-test task, ``"cd"`` when the
    invoking line changes into ``app/android`` itself and ``""`` when it
    relies on the step's working-directory; ``None`` when no line of the
    script runs it."""
    for line in run.splitlines():
        command = _TRAILING_COMMENT_RE.sub("", line).strip()
        match = _GRADLE_LINE_RE.match(command)
        if match and TASK in command.split():
            return "cd" if match.group("cd") else ""
    return None


def check(root: Path = REPO_ROOT) -> list[str]:
    path = root / WORKFLOW
    if not path.is_file():
        return [f"{WORKFLOW}: missing."]
    text = path.read_text(encoding="utf-8")
    body = job_lines(text, JOB)
    if not body:
        return [f"{WORKFLOW}: no '{JOB}' job found."]
    errors: list[str] = []
    if not any(_ANDROID_LEG_RE.match(line) for line in body):
        errors.append(f"{WORKFLOW}: the '{JOB}' matrix has no '- target: android' leg.")
    job_steps = steps(body)
    build_index = next(
        (i for i, s in enumerate(job_steps) if "flutter build" in s.get("run", "")),
        None,
    )
    if build_index is None:
        errors.append(f"{WORKFLOW}: no step in '{JOB}' runs 'flutter build'.")
    gradle = [
        (i, s, form)
        for i, s in enumerate(job_steps)
        if (form := gradle_invocation(s.get("run", ""))) is not None
    ]
    if not gradle:
        errors.append(
            f"{WORKFLOW}: no step in '{JOB}' runs '{GRADLE_COMMAND}', so the "
            "Android JVM unit tests in app/android/app/src/test never run in CI."
        )
        return errors
    for i, step, form in gradle:
        name = step.get("name", f"step {i + 1}")
        if not is_android_condition(step.get("if", "")):
            errors.append(
                f"{WORKFLOW}: '{name}' is not conditioned on exactly "
                "matrix.target == 'android' (got "
                f"'{step.get('if', '')}')."
            )
        if (
            form != "cd"
            and step.get("working-directory", "").strip("'\"") != WORKING_DIRECTORY
        ):
            errors.append(
                f"{WORKFLOW}: '{name}' does not run in '{WORKING_DIRECTORY}'."
            )
        if build_index is not None and i < build_index:
            errors.append(
                f"{WORKFLOW}: '{name}' runs before the 'flutter build' step, "
                "which is what writes the Gradle wrapper and Flutter's Gradle "
                "configuration."
            )
    return errors


def main() -> int:
    errors = check()
    for error in errors:
        print(f"::error::{error}")
    if errors:
        return 1
    print(f"OK: {WORKFLOW} runs '{GRADLE_COMMAND}' on the Android build leg")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
