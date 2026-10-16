#!/usr/bin/env python3
"""Guard that the Windows release ships the MSVC runtime beside the app.

Pure-stdlib, assert-based (no pytest, matching the rest of
``tools/release/test_*.py``). Run directly::

    python3 tools/release/test_release_windows_crt.py

**Why this file exists** (audit finding platform-4). ``flutter build windows``
links the runner and the plugin DLLs against the dynamic MSVC runtime (``/MD``,
the CMake default; ``app/windows/CMakeLists.txt`` does not override
``MSVC_RUNTIME_LIBRARY``). Flutter's Release folder does not contain that
runtime, so on a Windows PC without the Visual C++ Redistributable the app fails
to start with "VCRUNTIME140_1.dll was not found". The release workflow therefore
copies the three runtime DLLs from the runner's Visual Studio install into the
Release folder before the zip and the installer are built, and then checks that
they reached both downloads.

These tests cannot run Windows. They pin the workflow's *structure*: the
copy step exists, takes the DLLs from the Visual Studio redistributable folder
without a hard-coded version, ships exactly the required set, runs after the
bundle is signed (so Microsoft's own signatures are not replaced with ours) and
before packaging, and a later step checks the zip and the installed tree. The
runner-side assertions in those steps are the behavioural proof.

The Windows leg is one entry of the shared ``build`` matrix, not a job of its
own, so two things keep it alive and are pinned too: the matrix entry itself
(``platform: windows`` on ``os: windows-latest``), and the
``if: matrix.platform == 'windows'`` guard on every Windows-only step (without
it the PowerShell steps would run on the Linux, macOS, Android and iOS legs).
The Windows signing gate (``signing=configured|missing``) and the
``== 'configured'`` condition on Azure Login and both sign steps are pinned
last: the gate script is run under bash with each Azure variable present and
absent.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

from _bash import bash_environ, find_bash

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
JOB_HEADING = re.compile(r"^  [a-z][a-z0-9_]*:\n", re.MULTILINE)

# The DLLs the runner and plugin binaries import on x64 (platform-4). Kept here
# as the test's own expectation, not read back from the workflow.
REQUIRED_DLLS = {"vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll"}

BUILD_STEP = "Build Windows release bundle"
SIGNING_GATE_STEP = "Determine Windows signing availability"
AZURE_LOGIN_STEP = "Azure Login"
SIGN_BUNDLE_STEP = "Sign Windows bundle binaries with Azure Artifact Signing"
STAGE_STEP = "Stage the MSVC runtime beside the app"
PACKAGE_STEP = "Package Windows (zip + installer)"
SIGN_INSTALLER_STEP = "Sign Windows installer with Azure Artifact Signing"
VERIFY_STEP = "Verify the MSVC runtime ships in the zip and the installer"
UPLOAD_STEP = "Upload packaged artifacts"


def job_section(text: str, job: str) -> str:
    match = re.search(rf"^  {re.escape(job)}:\n", text, re.MULTILINE)
    if match is None:
        raise AssertionError(f"missing {job} job")
    next_job = JOB_HEADING.search(text, match.end())
    return text[match.start() : next_job.start() if next_job else len(text)]


def step_index(job: str, step_name: str) -> int:
    marker = f"      - name: {step_name}\n"
    assert marker in job, f"build job has no step named {step_name!r}"
    return job.index(marker)


def step_body(job: str, step_name: str) -> str:
    """The whole step, from its `- name:` line up to the next step."""
    start = step_index(job, step_name)
    following = re.search(r"^      - ", job[start + 1 :], re.MULTILINE)
    end = start + 1 + following.start() if following else len(job)
    return job[start:end]


def run_script(job: str, step_name: str) -> str:
    step = step_body(job, step_name)
    assert "        run: |\n" in step, f"{step_name!r} has no run block"
    _, body = step.split("        run: |\n", 1)
    lines: list[str] = []
    for line in body.splitlines():
        if line and not line.startswith(" " * 10):
            break  # a comment between steps, not part of the script
        lines.append(line[10:] if line else "")
    return "\n".join(lines) + "\n"


def windows_job() -> str:
    return job_section(WORKFLOW.read_text(encoding="utf-8"), "build")


def dll_list_env(job: str) -> set[str]:
    match = re.search(r"^      MSVC_RUNTIME_DLLS: (.+)$", job, re.MULTILINE)
    assert match is not None, "build job must declare env MSVC_RUNTIME_DLLS"
    return {name.lower() for name in match.group(1).split()}


def test_required_dll_set_is_exact() -> None:
    names = dll_list_env(windows_job())
    assert names == REQUIRED_DLLS, (
        f"MSVC_RUNTIME_DLLS is {sorted(names)}, expected exactly {sorted(REQUIRED_DLLS)}"
    )


def test_stage_step_order() -> None:
    job = windows_job()
    assert (
        step_index(job, BUILD_STEP)
        < step_index(job, SIGN_BUNDLE_STEP)
        < step_index(job, STAGE_STEP)
        < step_index(job, PACKAGE_STEP)
    ), (
        "the MSVC runtime must be copied after the bundle is signed (Microsoft's "
        "signatures stay intact) and before the zip and installer are built"
    )


def test_stage_step_locates_redist_without_hardcoded_version() -> None:
    script = run_script(windows_job(), STAGE_STEP)
    assert "vswhere.exe" in script, "locate Visual Studio with vswhere"
    assert "Microsoft.VCRedistVersion.default.txt" in script, (
        "read the redistributable version from Visual Studio, do not hard-code it"
    )
    assert "Microsoft.VC14*.CRT" in script, "glob the CRT folder name"
    assert re.search(r"\.Count -ne 1\)", script), (
        "fail unless the CRT folder glob matches exactly once"
    )
    assert not re.search(r"\\MSVC\\14\.\d", script), "no hard-coded redist version"
    assert "debug_nonredist" not in script.lower()
    assert "$env:MSVC_RUNTIME_DLLS" in script
    assert "Copy-Item" in script


def test_stage_step_ships_no_other_crt_files() -> None:
    script = run_script(windows_job(), STAGE_STEP)
    named = {m.lower() for m in re.findall(r"[A-Za-z0-9_]+\.dll\b", script)}
    extra = named - REQUIRED_DLLS
    assert not extra, f"staging step names DLLs outside the required set: {sorted(extra)}"
    assert not re.search(r"Copy-Item[^\n]*\*", script), "do not copy the CRT folder wholesale"


def test_stage_step_checks_imports_against_the_set() -> None:
    script = run_script(windows_job(), STAGE_STEP)
    assert "dumpbin" in script and "/dependents" in script, (
        "the staging step must check what the bundle actually imports, so a "
        "binary that needs a runtime DLL outside the set fails the job"
    )


def test_verify_step_checks_zip_and_installer() -> None:
    job = windows_job()
    assert (
        step_index(job, PACKAGE_STEP)
        < step_index(job, SIGN_INSTALLER_STEP)
        < step_index(job, VERIFY_STEP)
        < step_index(job, UPLOAD_STEP)
    ), "verify the shipped (signed) installer and zip before uploading them"
    step = step_body(job, VERIFY_STEP)
    assert "        if: matrix.platform == 'windows'\n" in step
    assert "signing" not in step.split("        run:", 1)[0], (
        "the runtime check must run on every Windows release, signed or not"
    )
    script = run_script(job, VERIFY_STEP)
    assert "$env:MSVC_RUNTIME_DLLS" in script
    assert "ZipFile" in script, "open the zip and look for each DLL"
    assert "/VERYSILENT" in script, "install the installer and look for each DLL"
    assert "unins000.exe" in script, "uninstall and check the DLLs are removed"
    assert script.count("throw") >= 3, "each check must fail the job"


WINDOWS_ONLY = "matrix.platform == 'windows'"
WINDOWS_SIGNED = (
    f"{WINDOWS_ONLY} && steps.windows_signing.outputs.signing == 'configured'"
)
AZURE_VARS = (
    "AZURE_CLIENT_ID",
    "AZURE_TENANT_ID",
    "AZURE_SUBSCRIPTION_ID",
    "AZURE_SIGNING_ACCOUNT_NAME",
    "AZURE_CERT_PROFILE_NAME",
)


def step_condition(job: str, step_name: str) -> str:
    """The step's single `if:` expression (steps here keep it on one line)."""
    step = step_body(job, step_name)
    header = re.split(r"^        (?:run|uses):", step, maxsplit=1, flags=re.MULTILINE)[0]
    conditions = re.findall(r"^        if: (.*)$", header, re.MULTILINE)
    assert len(conditions) == 1, (
        f"{step_name!r} must have exactly one single-line `if:`, found {conditions}"
    )
    return conditions[0]


def test_windows_leg_is_in_the_build_matrix() -> None:
    # The Windows leg is a matrix entry of the shared `build` job. Dropping it,
    # or pointing it at another OS, ships a release with no Windows assets and
    # is otherwise only noticed when publish_draft fails to download
    # `native-components-windows` on a real tag.
    job = windows_job()
    assert re.search(
        r"^          - platform: windows\n"
        r"            arch: x64\n"
        r"            os: windows-latest\n",
        job,
        re.MULTILINE,
    ), "the build matrix must contain `platform: windows` / `os: windows-latest`"
    assert "    runs-on: ${{ matrix.os }}\n" in job, "each leg must run on its matrix OS"


def test_windows_only_steps_are_guarded_to_the_windows_leg() -> None:
    # Every step below is PowerShell or Windows-specific. The matrix is shared,
    # so without the guard it would run (and fail) on the other four legs.
    job = windows_job()
    for step_name in (
        SIGNING_GATE_STEP,
        BUILD_STEP,
        STAGE_STEP,
        PACKAGE_STEP,
        UPLOAD_NATIVE_STEP,
        VERIFY_STEP,
    ):
        assert step_condition(job, step_name) == WINDOWS_ONLY, (
            f"{step_name!r} must be `if: {WINDOWS_ONLY}`"
        )


def test_signing_steps_need_windows_and_a_configured_gate() -> None:
    # With the Azure variables absent the leg must stay a clean unsigned build:
    # logging in or signing then fails the release leg.
    job = windows_job()
    for step_name in (AZURE_LOGIN_STEP, SIGN_BUNDLE_STEP, SIGN_INSTALLER_STEP):
        assert step_condition(job, step_name) == WINDOWS_SIGNED, (
            f"{step_name!r} must be `if: {WINDOWS_SIGNED}`"
        )
    assert (
        step_index(job, SIGNING_GATE_STEP)
        < step_index(job, AZURE_LOGIN_STEP)
        < step_index(job, SIGN_BUNDLE_STEP)
    ), "the gate must be decided before anything reads its output"
    assert "        id: windows_signing\n" in step_body(job, SIGNING_GATE_STEP), (
        "the gate step id is what the `steps.windows_signing` conditions read"
    )


def run_signing_gate(present: set[str], empty: set[str]) -> str:
    """Run the gate script under bash; return the `signing` step output.

    Variables in `present` are set to a value, those in `empty` are set to the
    empty string (what `${{ vars.X }}` yields for an unset variable), the rest
    are not exported at all.
    """
    script = run_script(windows_job(), SIGNING_GATE_STEP)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        output = root / "github_output"
        environment = bash_environ()
        for name in AZURE_VARS:
            environment.pop(name, None)
        environment["GITHUB_OUTPUT"] = str(output)
        environment.update({name: "value" for name in present})
        environment.update({name: "" for name in empty})
        result = subprocess.run(
            [find_bash(), "-c", script],
            cwd=root,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, (
            f"the gate script must never fail the leg: {result.stderr}"
        )
        values = [
            line.split("=", 1)[1]
            for line in output.read_text(encoding="utf-8").splitlines()
            if line.startswith("signing=")
        ]
        assert len(values) == 1, f"expected exactly one signing= output, got {values}"
        return values[0]


def test_signing_gate_reads_the_five_azure_variables() -> None:
    step = step_body(windows_job(), SIGNING_GATE_STEP)
    for name in AZURE_VARS:
        assert f"          {name}: ${{{{ vars.{name} }}}}\n" in step, (
            f"the gate must read {name} from the repository variable of that name"
        )


def test_signing_gate_is_configured_only_when_every_variable_is_set() -> None:
    every = set(AZURE_VARS)
    assert run_signing_gate(every, set()) == "configured"
    assert run_signing_gate(set(), set()) == "missing", "no variables at all"
    assert run_signing_gate(set(), every) == "missing", "variables set but empty"
    for name in AZURE_VARS:
        assert run_signing_gate(every - {name}, set()) == "missing", (
            f"{name} unset must leave the gate at `missing`"
        )
        assert run_signing_gate(every - {name}, {name}) == "missing", (
            f"{name} empty must leave the gate at `missing`"
        )


NATIVE_ARTIFACT = "native-components-windows"
UPLOAD_NATIVE_STEP = "Upload the MSVC runtime manifest for the SBOM"
SBOM_STEP = "Generate CycloneDX SBOM"


def test_stage_step_records_what_it_shipped_for_the_sbom() -> None:
    # platform-5: the SBOM lists the MSVC runtime, but it is generated on
    # Linux in publish_draft, so the Windows job records the staged DLLs.
    script = run_script(windows_job(), STAGE_STEP)
    assert "msvc-runtime.json" in script, "write the MSVC runtime manifest"
    assert "Get-FileHash" in script and "SHA256" in script, "hash each staged DLL"
    assert "FileMajorPart" in script, "record each DLL's file version"
    assert "$redistVersion" in script.split("msvc-runtime.json")[0], (
        "record the redistributable version the DLLs came from"
    )


def test_manifest_is_uploaded_outside_the_dist_namespace() -> None:
    job = windows_job()
    step = step_body(job, UPLOAD_NATIVE_STEP)
    assert "actions/upload-artifact@" in step
    assert f"name: {NATIVE_ARTIFACT}" in step, (
        "not a dist-* artifact: it must not be merged into the release assets"
    )
    assert "if-no-files-found: error" in step
    assert step_index(job, STAGE_STEP) < step_index(job, UPLOAD_NATIVE_STEP)


def test_publish_draft_feeds_the_manifest_to_the_sbom() -> None:
    job = job_section(WORKFLOW.read_text(encoding="utf-8"), "publish_draft")
    assert f"name: {NATIVE_ARTIFACT}" in job, "publish_draft must download the manifest"
    download = job.index(f"name: {NATIVE_ARTIFACT}")
    sbom = run_script(job, SBOM_STEP)
    assert "--msvc-runtime" in sbom, "gen_sbom.py must be given the MSVC runtime manifest"
    assert "msvc-runtime.json" in sbom
    assert download < step_index(job, SBOM_STEP)


def main() -> int:
    tests = [(name, fn) for name, fn in globals().items() if name.startswith("test_")]
    failures = 0
    for name, fn in tests:
        try:
            fn()
        except AssertionError as error:
            failures += 1
            print(f"FAIL {name}: {error}")
        else:
            print(f"ok   {name}")
    if failures:
        print(f"{failures} of {len(tests)} failed")
        return 1
    print(f"all {len(tests)} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
