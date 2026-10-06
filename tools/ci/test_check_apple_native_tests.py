#!/usr/bin/env python3
"""Unit tests for the native Swift test (RunnerTests) CI guard."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_apple_native_tests as check  # noqa: E402

_WORKFLOW = """\
jobs:
  classify:
    runs-on: ubuntu-latest
    outputs:
      builds_changed: ${{ steps.classify.outputs.builds_changed }}
      apple_native_changed: ${{ steps.classify.outputs.apple_native_changed }}
    steps:
      - id: classify
        run: |
          if [ "$GITHUB_EVENT_NAME" != 'pull_request' ]; then
            {
              echo 'builds_changed=true'
              echo 'apple_native_changed=true'
            } >> "$GITHUB_OUTPUT"
            exit 0
          fi
          if [ -z "$BASE_SHA" ]; then
            exit 1
          fi
          python3 tools/ci/classify_changes.py "$BASE_SHA" "$HEAD_SHA"

  build:
    strategy:
      matrix:
        include:
          - target: macos
            os: macos-latest
          - target: ios
            os: macos-latest
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: flutter build ${{ matrix.build_args }}
      - name: Test native Swift code (iOS)
        if: >-
          matrix.target == 'ios' &&
          needs.classify.outputs.apple_native_changed == 'true'
        working-directory: app/ios
        run: |
          # xcodebuild test in a comment must not count
          set +e
          xcodebuild test \\
            -workspace Runner.xcworkspace \\
            -scheme Runner \\
            -destination "id=$udid" \\
            CODE_SIGNING_ALLOWED=NO \\
            2>&1 | tee "$RUNNER_TEMP/xcodebuild-test.log"
          status="${PIPESTATUS[0]}"
          set -e
          echo "summary" >> "$GITHUB_STEP_SUMMARY"
          exit "$status"
      - name: Test native Swift code (macOS)
        if: matrix.target == 'macos' && needs.classify.outputs.apple_native_changed == 'true'
        working-directory: app/macos
        run: |
          set -o pipefail
          xcodebuild test -workspace Runner.xcworkspace -scheme Runner \\
            -destination 'platform=macOS' | tee "$RUNNER_TEMP/xcodebuild-test.log"

  other:
    runs-on: macos-latest
    steps:
      - if: matrix.target == 'ios'
        run: xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination id=x
"""

FAILURES: list[str] = []


def expect(name: str, condition: bool, detail: object = "") -> None:
    if condition:
        print(f"  ok   {name}")
    else:
        FAILURES.append(name)
        print(f"  FAIL {name}: {detail}")


def leg_errors(text: str) -> list[str]:
    return [e for leg in check.LEGS for e in check.leg_test_step_errors(text, leg)]


def _mutated(name: str, old: str, new: str, leg_word: str, *, count: int = 1) -> None:
    assert _WORKFLOW.count(old) == count, f"{name}: fixture has {_WORKFLOW.count(old)} of {old!r}"
    text = _WORKFLOW.replace(old, new)
    errors = leg_errors(text) + check.classify_wiring_errors(text)
    expect(name, any(leg_word in e for e in errors), errors)


def test_fixture() -> None:
    print("a correctly wired workflow passes:")
    expect("both legs run the tests", leg_errors(_WORKFLOW) == [], leg_errors(_WORKFLOW))
    expect(
        "classify wiring present",
        check.classify_wiring_errors(_WORKFLOW) == [],
        check.classify_wiring_errors(_WORKFLOW),
    )


def test_mutations() -> None:
    print("each mutation of the wiring is caught:")
    _mutated(
        "build-for-testing only (compiles, never runs)",
        "xcodebuild test -workspace Runner.xcworkspace -scheme Runner \\\n",
        "xcodebuild build-for-testing -workspace Runner.xcworkspace -scheme Runner \\\n",
        "macos leg",
    )
    _mutated(
        "iOS command commented out (only the decoy comment says xcodebuild test)",
        "          xcodebuild test \\\n",
        "          # xcodebuild test \\\n",
        "ios leg",
    )
    _mutated(
        "wrong scheme",
        "-scheme Runner \\\n            -destination 'platform=macOS'",
        "-scheme ShareExtension \\\n            -destination 'platform=macOS'",
        "macos leg",
    )
    _mutated(
        "macOS step aimed at an iOS destination",
        "'platform=macOS'",
        "'platform=iOS Simulator,name=iPhone 16'",
        "macos leg",
    )
    _mutated(
        "iOS step not gated on apple_native_changed",
        "          matrix.target == 'ios' &&\n"
        "          needs.classify.outputs.apple_native_changed == 'true'\n",
        "          matrix.target == 'ios'\n",
        "ios leg",
    )
    _mutated(
        "macOS step made continue-on-error",
        "        working-directory: app/macos\n",
        "        working-directory: app/macos\n        continue-on-error: true\n",
        "macos leg",
    )
    # The only remaining iOS test step is in another job: it must not count.
    _mutated(
        "iOS step selects no leg (decoy in another job does not count)",
        "matrix.target == 'ios' &&",
        "matrix.target == 'android' &&",
        "ios leg",
    )
    # Copilot review on #1710: GitHub's default `bash -e` has no pipefail, so
    # `xcodebuild test | tee` takes tee's status and a failing run goes green.
    _mutated(
        "iOS tee'd xcodebuild with its PIPESTATUS handling removed",
        '          status="${PIPESTATUS[0]}"\n',
        "",
        "ios leg",
    )
    _mutated(
        "macOS tee'd xcodebuild with set -o pipefail removed",
        "          set -o pipefail\n",
        "",
        "macos leg",
    )
    _mutated(
        "macOS pipefail set only after the xcodebuild pipeline",
        "          set -o pipefail\n"
        "          xcodebuild test -workspace Runner.xcworkspace -scheme Runner \\\n"
        "            -destination 'platform=macOS' | tee \"$RUNNER_TEMP/xcodebuild-test.log\"\n",
        "          xcodebuild test -workspace Runner.xcworkspace -scheme Runner \\\n"
        "            -destination 'platform=macOS' | tee \"$RUNNER_TEMP/xcodebuild-test.log\"\n"
        "          set -o pipefail\n",
        "macos leg",
    )
    # A test step for a leg the matrix no longer builds never runs.
    _mutated(
        "ios leg removed from the build matrix",
        "          - target: ios\n            os: macos-latest\n",
        "",
        "ios leg",
    )
    _mutated(
        "macos leg removed from the build matrix",
        "          - target: macos\n            os: macos-latest\n",
        "",
        "macos leg",
    )
    # The echo must be on the push path; on the PR path it would force the
    # tests on every PR and leave pushes to the classifier.
    _mutated(
        "apple_native_changed echo moved into the PR path",
        "              echo 'apple_native_changed=true'\n"
        "            } >> \"$GITHUB_OUTPUT\"\n"
        "            exit 0\n"
        "          fi\n",
        "            } >> \"$GITHUB_OUTPUT\"\n"
        "            exit 0\n"
        "          fi\n"
        "          echo 'apple_native_changed=true' >> \"$GITHUB_OUTPUT\"\n",
        "push branch",
    )
    _mutated(
        "classify output undeclared",
        "      apple_native_changed: ${{ steps.classify.outputs.apple_native_changed }}\n",
        "",
        "declare",
    )
    _mutated(
        "push branch leaves the output unset",
        "              echo 'apple_native_changed=true'\n",
        "",
        "push branch",
    )


def test_mutated_repo_workflow() -> None:
    # The real ci.yml with its test command neutralised: the guard must fail
    # for both legs, not only for a fixture.
    print("the real ci.yml, mutated, fails:")
    real = (check.REPO_ROOT / check.CI_WORKFLOW).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        dest = root / check.CI_WORKFLOW
        dest.parent.mkdir(parents=True)
        dest.write_text(real.replace("xcodebuild test", "xcodebuild build-for-testing"))
        errors = check.check(root, include_classifier=False)
        for leg in check.LEGS:
            expect(
                f"real ci.yml without 'xcodebuild test' fails the {leg} leg",
                any(f"{leg} leg" in e for e in errors),
                errors,
            )
        # And with the pipe-status handling stripped: the shape that let a
        # failing xcodebuild pass behind `| tee` (Copilot review on #1710).
        assert real.count('status="${PIPESTATUS[0]}"') == 2, "expected one per leg"
        assert real.count("set -o pipefail") == 2, "expected one per leg"
        dest.write_text(
            real.replace('status="${PIPESTATUS[0]}"', 'status=0').replace(
                "set -o pipefail", "true"
            )
        )
        errors = check.check(root, include_classifier=False)
        for leg in check.LEGS:
            expect(
                f"real ci.yml without pipefail/PIPESTATUS fails the {leg} leg",
                any(f"{leg} leg" in e and "piped" in e for e in errors),
                errors,
            )


def test_repo() -> None:
    # The assertion that is red on a tree where nothing runs xcodebuild test.
    print("the repository is wired:")
    errors = check.check()
    expect("ci.yml and classify_changes.py run the native tests", errors == [], "\n".join(errors))


def main() -> int:
    test_fixture()
    test_mutations()
    test_mutated_repo_workflow()
    test_repo()
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("\nOK: all native Swift test guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
