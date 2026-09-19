#!/usr/bin/env python3
"""Guard the existing-tag recovery path in the release workflow."""

import os
import re
import base64
import subprocess
import sys
import tempfile
from pathlib import Path

from _bash import find_bash


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
CHECKS_WORKFLOW = ROOT / ".github" / "workflows" / "_checks.yml"
JOB_HEADING = re.compile(r"^  [a-z][a-z0-9_]*:\n", re.MULTILINE)


def _section(text: str, start: str, end: str) -> str:
    start_index = text.index(start)
    end_index = text.index(end, start_index)
    return text[start_index:end_index]


def _job_section(text: str, job: str) -> str:
    match = re.search(rf"^  {re.escape(job)}:\n", text, re.MULTILINE)
    if match is None:
        raise AssertionError(f"missing {job} job")
    next_job = JOB_HEADING.search(text, match.end())
    return text[match.start() : next_job.start() if next_job else len(text)]


def _publish_script(text: str) -> str:
    publish_step = _section(
        text,
        "      - name: Create or update the DRAFT release\n",
        "  # Close the supply-chain loop (#300):",
    )
    run_marker = "        run: |\n"
    _, body = publish_step.split(run_marker, 1)
    lines: list[str] = []
    for line in body.splitlines():
        if line and not line.startswith("          "):
            break
        lines.append(line[10:] if line else "")
    return "\n".join(lines) + "\n"


def _step_script(job: str, step_name: str) -> str:
    """Return the dedented `run:` body of the named step within a job section."""
    marker = f"      - name: {step_name}\n"
    start = job.index(marker) + len(marker)
    following = re.search(r"^      (?:- |# )", job[start:], re.MULTILINE)
    end = start + following.start() if following else len(job)
    step = job[start:end]
    if "        run: |\n" not in step:
        return step.split("        run: ", 1)[1]
    _, body = step.split("        run: |\n", 1)
    return "\n".join(line[10:] if line else "" for line in body.splitlines()) + "\n"


def _step_index(job: str, step_name: str) -> int:
    return job.index(f"      - name: {step_name}\n")


def _concurrency_group(text: str, event: str, ref: str, ref_type: str, tag: str) -> str:
    """Evaluate the workflow's concurrency-group expression for one trigger.

    Supports only the `&&` / `||` / `==` / `!=` / `format('<p>{0}', x)` subset the
    expression uses; anything else fails the sanity regex instead of being
    silently mis-evaluated. This is a local re-implementation, not GitHub's
    evaluator.
    """
    match = re.search(r"^  group: release-\$\{\{ (.+) \}\}$", text, re.MULTILINE)
    assert match is not None, "missing release concurrency group"
    expression = re.sub(
        r"format\('([^'{]*)\{0\}', ([a-z_.]+)\)", r"('\1' + \2)", match.group(1)
    )
    contexts = {
        "github.event_name": event,
        "github.ref_type": ref_type,
        "github.ref_name": ref.rsplit("/", 1)[-1],
        "github.ref": ref,
        "inputs.release_tag": tag,
    }
    for name in sorted(contexts, key=len, reverse=True):
        expression = expression.replace(name, repr(contexts[name]))
    expression = expression.replace("&&", " and ").replace("||", " or ")
    leftover = re.sub(r"'[^']*'", "", expression)
    assert re.fullmatch(r"[\s+=!()]*(?:(?:and|or)[\s+=!()]*)*", leftover), expression
    return "release-" + str(eval(expression, {"__builtins__": {}}))  # noqa: S307


def _run_guard_script(
    script: str, is_draft: str, curl_ok: bool
) -> tuple[subprocess.CompletedProcess[str], list[str]]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        calls = root / "calls"
        (fake_bin / "gh").write_text(
            '#!/usr/bin/env bash\n'
            'printf "gh %s\\n" "$*" >> "$CALLS"\n'
            'printf "%s\\n" "$IS_DRAFT"\n',
            encoding="utf-8",
        )
        (fake_bin / "curl").write_text(
            '#!/usr/bin/env bash\n'
            'printf "curl token=%s %s\\n" "${GH_TOKEN:-unset}" "$*" >> "$CALLS"\n'
            '[ "$CURL_OK" = "1" ]\n',
            encoding="utf-8",
        )
        for name in ("gh", "curl"):
            (fake_bin / name).chmod(0o755)
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{fake_bin}{os.pathsep}{environment.get('PATH', '')}",
                "CALLS": str(calls),
                "IS_DRAFT": is_draft,
                "CURL_OK": "1" if curl_ok else "0",
                "GH_TOKEN": "secret-token",
                "CHANNELS": "stable beta",
                "TAG": "v0.1.0",
                "GITHUB_REPOSITORY": "ibanner56/CallersCompendium",
            }
        )
        result = subprocess.run(
            [find_bash(), "-c", script],
            cwd=root,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        recorded = calls.read_text(encoding="utf-8").splitlines() if calls.exists() else []
        return result, recorded


def _assert_verifier_rejects_tampered_manifest() -> None:
    """Run the real pre-publish verifier on a valid, then tampered, manifest."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    key = Ed25519PrivateKey.generate()
    raw_public = key.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    script = ROOT / "tools" / "release" / "check_pages_signature_files.py"
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        key_source = root / "key.dart"
        key_source.write_text(
            "const String kUpdateManifestPublicKey =\n    '"
            + base64.b64encode(raw_public).decode()
            + "';\n",
            encoding="utf-8",
        )
        manifest = root / "manifest" / "stable.json"
        manifest.parent.mkdir()
        manifest.write_bytes(b'{"version":"1.0.0"}')
        (manifest.parent / "stable.json.sig").write_text(
            base64.b64encode(key.sign(manifest.read_bytes())).decode(),
            encoding="utf-8",
        )
        args = [sys.executable, str(script), str(manifest.parent), "--key-source", str(key_source)]
        ok = subprocess.run(args, capture_output=True, text=True, check=False)
        assert ok.returncode == 0, (ok.stdout, ok.stderr)
        manifest.write_bytes(b'{"version":"9.9.9"}')
        bad = subprocess.run(args, capture_output=True, text=True, check=False)
        assert bad.returncode == 1, (bad.stdout, bad.stderr)


def _run_publish_script(
    script: str, release_state: str
) -> tuple[subprocess.CompletedProcess[str], list[str], list[str]]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        fake_bin = root / "bin"
        fake_bin.mkdir()
        calls_path = root / "calls"
        actions_path = root / "actions"
        fake_gh = fake_bin / "gh"
        fake_gh.write_text(
            """#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
if [ "$1" != "release" ]; then
  exit 2
fi
case "$2" in
  view)
    if [ "$RELEASE_STATE" = "missing" ]; then
      exit 1
    fi
    if [ "$RELEASE_STATE" = "draft" ]; then
      printf 'true\n'
    else
      printf 'false\n'
    fi
    ;;
  upload)
    printf 'upload\n' >> "$GH_ACTIONS"
    ;;
  create)
    printf 'create\n' >> "$GH_ACTIONS"
    ;;
  *)
    exit 2
    ;;
esac
""",
            encoding="utf-8",
        )
        fake_gh.chmod(0o755)

        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{fake_bin}{os.pathsep}{environment.get('PATH', '')}",
                "GH_CALLS": str(calls_path),
                "GH_ACTIONS": str(actions_path),
                "RELEASE_STATE": release_state,
                "TAG": "v0.1.0",
                "VERSION": "0.1.0",
                "CHANNELS": "stable beta",
                "PRERELEASE": "true",
                "CODENAME": "v0.1.0",
                "GITHUB_REPOSITORY": "ibanner56/CallersCompendium",
            }
        )
        result = subprocess.run(
            [find_bash(), "-c", script],
            cwd=root,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )
        calls = (
            calls_path.read_text(encoding="utf-8").splitlines()
            if calls_path.exists()
            else []
        )
        actions = (
            actions_path.read_text(encoding="utf-8").splitlines()
            if actions_path.exists()
            else []
        )
        return result, calls, actions


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")

    assert "release_tag:" in text, "workflow_dispatch must accept a recovery tag"
    assert "is_release: ${{ steps.resolve.outputs.is_release }}" in text
    assert "recovery: ${{ steps.resolve.outputs.recovery }}" in text
    assert "release_ref: ${{ steps.resolve.outputs.release_ref }}" in text
    assert "source_sha: ${{ steps.resolve.outputs.source_sha }}" in text
    assert "codename: ${{ steps.resolve.outputs.codename }}" in text
    assert "resolve_release_codename.py --tag-message" in text
    assert 'tag_object_type="$(git cat-file -t "$release_ref")"' in text
    assert "codename_required=false" in text
    assert "codename_required=true" in text
    assert '--title "$CODENAME"' in text
    assert 'if [ "$GITHUB_REF" != "refs/heads/main" ]; then' in text
    assert "::error::existing-tag recovery must be dispatched from main" in text

    metadata_step = _section(
        text,
        "      - name: Generate SHA256SUMS + channel manifests",
        "      # The manifest signature is a publication gate.",
    )
    assert "          RELEASE_CODENAME: ${{ needs.meta.outputs.codename }}" in metadata_step
    assert "metadata_args=(" in metadata_step
    assert "gen_release_metadata.py --help" in metadata_step
    assert 'metadata_args+=(--codename "$RELEASE_CODENAME")' in metadata_step
    assert 'gen_release_metadata.py "${metadata_args[@]}"' in metadata_step
    assert '--codename "$RELEASE_CODENAME"' in metadata_step
    assert '--codename "${{ needs.meta.outputs.codename }}"' not in metadata_step

    codename_define = (
        '--dart-define=CALLERS_COMPENDIUM_RELEASE_CODENAME="$CODENAME"'
    )
    assert text.count(codename_define) == 6

    build_job = _job_section(text, "build")
    assert "      CODENAME: ${{ needs.meta.outputs.codename }}" in build_job
    build_windows_job = _job_section(text, "build_windows")
    assert "      CODENAME: ${{ needs.meta.outputs.codename }}" in build_windows_job

    # Every source checkout must pin the resolved commit, not the mutable tag
    # ref, so a tag moved mid-run cannot make assurance validate one commit while
    # build/publish ship another. release_ref is retained only where the tag NAME
    # is required (e.g. the recovery provenance predicate), never as a checkout.
    # Match the checkout step's own indentation so the checks job's
    # `checkout_ref:` pass-through (which also ends in "ref:") is not counted.
    assert text.count("\n          ref: ${{ needs.meta.outputs.source_sha }}") == 4, (
        "build, Windows, publish, and Pages jobs must all check out the resolved "
        "source SHA"
    )
    assert text.count("\n          ref: ${{ needs.meta.outputs.release_ref }}") == 0, (
        "no job may check out the mutable release_ref; the tag name is passed via "
        "meta outputs where needed, not as a checkout ref"
    )

    # The reusable assurance checks must run against the SAME resolved commit as
    # the build/publish jobs, not the dispatch ref. On a recovery dispatch (which
    # must be launched from main) a ref-less reusable checkout validated main
    # while the build packaged the tagged commit. The checks job therefore has to
    # depend on meta and pass the resolved commit down into _checks.yml.
    checks_job = _job_section(text, "checks")
    assert "uses: ./.github/workflows/_checks.yml" in checks_job, (
        "the release checks job must delegate to the reusable checks workflow"
    )
    assert re.search(r"^    needs:\s*(meta\b|\[[^\]]*\bmeta\b[^\]]*\])", checks_job, re.MULTILINE), (
        "the checks job must depend on meta so the resolved commit is available"
    )
    assert "checkout_ref: ${{ needs.meta.outputs.source_sha }}" in checks_job, (
        "the checks job must pin the reusable checks to the resolved release commit"
    )

    # And _checks.yml must actually honour that input in every job's checkout,
    # while defaulting to the triggering ref so the PR gate (ci.yml passes no
    # checkout_ref) is unaffected.
    checks_text = CHECKS_WORKFLOW.read_text(encoding="utf-8")
    assert re.search(
        r"^      checkout_ref:\n(?:.*\n)*?        default:\s*''\n",
        checks_text,
        re.MULTILINE,
    ), "_checks.yml must declare a checkout_ref input defaulting to the triggering ref"
    assert checks_text.count("ref: ${{ inputs.checkout_ref }}") == 4, (
        "every _checks.yml job (validate, core, app, server) must check out "
        "the passed-in ref"
    )
    assert text.count("needs.meta.outputs.is_release == 'true'") == 4, (
        "draft, mobile, provenance verification, and Pages must share the release guard"
    )

    ios_gate = _section(
        text,
        "      - name: Determine iOS signing availability",
        "      - name: Install Linux desktop dependencies",
    )
    assert 'if [ "$RECOVERY" = "true" ]; then' in ios_gate
    assert "signing=skipped-recovery" in ios_gate

    ios_build = _section(
        text,
        "      - name: Build signed iOS .ipa (App Store archive)",
        "      - name: Clean up iOS signing material",
    )
    assert "Upload iOS build to TestFlight" not in ios_build
    assert "ios-testflight-status" in ios_build

    publish_draft = _job_section(text, "publish_draft")
    assert "runs-on: ubuntu-latest" in publish_draft
    assert "environment: release-signing" not in publish_draft
    assert "      - name: Create or update the DRAFT release" in publish_draft
    assert 'TARGET_SHA: ${{ needs.meta.outputs.source_sha }}' not in publish_draft
    assert '--target "$TARGET_SHA"' not in publish_draft

    publish_script = _publish_script(text)
    published_result, published_calls, published_actions = _run_publish_script(
        publish_script, "published"
    )
    published_output = published_result.stdout + published_result.stderr
    assert published_result.returncode != 0, published_output
    assert (
        "::error::Release v0.1.0 is already published; refusing to overwrite assets."
        in published_output
    ), published_output
    assert not any(call.startswith("release upload ") for call in published_calls), (
        published_calls,
        published_actions,
    )
    assert 'gh release view "$TAG" --json isDraft --jq \'.isDraft\'' in publish_draft
    assert 'if [ "$is_draft" != "true" ]; then' in publish_draft

    draft_result, draft_calls, draft_actions = _run_publish_script(
        publish_script, "draft"
    )
    assert draft_result.returncode == 0, (
        draft_result.stdout,
        draft_result.stderr,
    )
    assert any(
        call.startswith("release view v0.1.0 --json isDraft --jq .isDraft")
        for call in draft_calls
    ), draft_calls
    assert any(
        call.startswith("release upload ") and "--clobber" in call
        for call in draft_calls
    ), draft_calls
    assert "upload" in draft_actions, draft_actions

    missing_result, missing_calls, missing_actions = _run_publish_script(
        publish_script, "missing"
    )
    assert missing_result.returncode == 0, (
        missing_result.stdout,
        missing_result.stderr,
    )
    assert any(
        call.startswith("release create ") and "--draft" in call
        for call in missing_calls
    ), missing_calls
    assert "create" in missing_actions, missing_actions

    publish_mobile = _job_section(text, "publish_mobile")
    assert "runs-on: macos-latest" in publish_mobile
    assert "environment: release-publication" in publish_mobile
    needs_match = re.search(r"^\s*needs:\s*\[([^\]]+)\]\s*$", publish_mobile, re.MULTILINE)
    assert needs_match is not None and {"meta", "verify"}.issubset(
        {item.strip() for item in needs_match.group(1).split(",")}
    )
    assert "needs.meta.outputs.recovery != 'true'" in publish_mobile
    assert "name: ios-testflight-status" in publish_mobile
    assert "      - name: Upload iOS build to TestFlight" in publish_mobile
    assert "EVENT_NAME: ${{ github.event_name }}" in publish_mobile
    assert '[[ "$REF" == refs/tags/v* ]]' in publish_mobile

    provenance = _section(
        text,
        "      # A recovery run's workflow comes from main",
        "      # Attest the SBOM",
    )
    assert "      - name: Check out recovery provenance helper" in provenance
    assert "path: workflow-tools" in provenance
    assert "ref: ${{ github.sha }}" in provenance
    assert "python3 workflow-tools/tools/release/gen_recovery_provenance.py" in provenance
    assert "REPOSITORY_ID: ${{ github.repository_id }}" in provenance
    assert "REPOSITORY_OWNER_ID: ${{ github.repository_owner_id }}" in provenance
    assert "RUNNER_ENVIRONMENT: ${{ runner.environment }}" in provenance
    assert '--repository-id "$REPOSITORY_ID"' in provenance
    assert '--repository-owner-id "$REPOSITORY_OWNER_ID"' in provenance
    assert '--runner-environment "$RUNNER_ENVIRONMENT"' in provenance
    assert provenance.count("actions/attest-build-provenance@") == 2
    assert "needs.meta.outputs.recovery != 'true'" in provenance
    assert "needs.meta.outputs.recovery == 'true'" in provenance
    assert "predicate-path: recovery-provenance.json" in provenance

    # Issue 07: every run targeting one tag shares a concurrency group, whether
    # it began as a tag push or a main-dispatched recovery.
    tag_push = _concurrency_group(text, "push", "refs/tags/v0.1.0", "tag", "")
    recovery = _concurrency_group(
        text, "workflow_dispatch", "refs/heads/main", "branch", "v0.1.0"
    )
    dry_run = _concurrency_group(text, "workflow_dispatch", "refs/heads/main", "branch", "")
    branch_like_tag = _concurrency_group(
        text, "workflow_dispatch", "refs/heads/v0.1.0", "branch", ""
    )
    other_tag = _concurrency_group(text, "push", "refs/tags/v0.2.0", "tag", "")
    assert tag_push == recovery, (tag_push, recovery)
    assert len({tag_push, dry_run, branch_like_tag, other_tag}) == 4, (
        tag_push,
        dry_run,
        branch_like_tag,
        other_tag,
    )
    assert "  cancel-in-progress: false" in text

    # Issues 04/05/06: public metadata is the last side effect of a release.
    pages_job = _job_section(text, "pages")
    pages_needs = re.search(r"^    needs:\s*\[([^\]]+)\]\s*$", pages_job, re.MULTILINE)
    assert pages_needs is not None and {"meta", "publish_draft", "verify"}.issubset(
        {item.strip() for item in pages_needs.group(1).split(",")}
    ), "pages must wait for provenance verification"
    assert "    environment: release-publication\n" in pages_job, (
        "pages must sit behind the post-publication approval"
    )
    public_step = "Require a public release with downloadable manifests"
    install_step = "Install Ed25519 verification dependency"
    verify_step = "Verify manifest signatures before publishing"
    publish_step = "Publish signed manifests to gh-pages"
    assert (
        _step_index(pages_job, public_step)
        < _step_index(pages_job, install_step)
        < _step_index(pages_job, verify_step)
        < _step_index(pages_job, publish_step)
    ), "pages must check publicity and signatures before it publishes"
    assert (
        "python3 tools/release/check_pages_signature_files.py manifest"
        in _step_script(pages_job, verify_step)
    )
    assert "publish_pages_manifest.sh" not in pages_job[: _step_index(pages_job, publish_step)]

    guard = _step_script(pages_job, public_step)
    result, calls = _run_guard_script(guard, "false", True)
    assert result.returncode == 0, (result.stdout, result.stderr)
    curls = [call for call in calls if call.startswith("curl ")]
    assert len(curls) == 2 and all("token=unset" in call for call in curls), calls
    assert any(call.endswith("/v0.1.0/stable.json") for call in curls), calls
    result, calls = _run_guard_script(guard, "true", True)
    assert result.returncode != 0 and "still a draft" in result.stdout + result.stderr
    assert not any(call.startswith("curl ") for call in calls), calls
    result, _ = _run_guard_script(guard, "false", False)
    assert result.returncode != 0 and "not publicly downloadable" in (
        result.stdout + result.stderr
    )

    # The pre-publish verifier itself must reject a tampered manifest.
    _assert_verifier_rejects_tampered_manifest()

    print("release workflow recovery guards: OK")


if __name__ == "__main__":
    main()
