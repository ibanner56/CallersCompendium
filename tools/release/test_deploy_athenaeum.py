#!/usr/bin/env python3
"""Drive tools/release/deploy_athenaeum.sh against a local origin and stub docker.

The script runs on the production host, so the properties worth pinning are the
ones that protect it: it builds the commit the tag names (not main), it never
touches the running container if the build fails, it fails when the new server
does not come up, and it rejects arguments that are not a SHA and a release
version before running anything.
"""

import os
import subprocess
import tempfile
from pathlib import Path

from _bash import bash_environ, find_bash

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "release" / "deploy_athenaeum.sh"


def _git(cwd: Path, *args: str) -> str:
    res = subprocess.run(
        ["git", *args], cwd=str(cwd), capture_output=True, text=True, check=True
    )
    return res.stdout.strip()


def _write_stub(path: Path, body: str) -> None:
    path.write_text("#!/bin/sh\n" + body, encoding="utf-8")
    path.chmod(0o755)


def _setup(tmp: Path) -> tuple[Path, str, str]:
    """An origin with a tagged commit, a later main commit, and a host checkout."""
    origin = tmp / "origin.git"
    _git(tmp, "init", "--quiet", "--bare", "-b", "main", str(origin))
    seed = tmp / "seed"
    _git(tmp, "clone", "--quiet", str(origin), str(seed))
    _git(seed, "config", "user.email", "seed@example.com")
    _git(seed, "config", "user.name", "Seed")
    (seed / "marker.txt").write_text("tagged\n", encoding="utf-8")
    _git(seed, "add", "marker.txt")
    _git(seed, "commit", "--quiet", "-m", "tagged")
    tagged = _git(seed, "rev-parse", "HEAD")
    (seed / "marker.txt").write_text("later\n", encoding="utf-8")
    _git(seed, "commit", "--quiet", "-am", "later main commit")
    later = _git(seed, "rev-parse", "HEAD")
    _git(seed, "push", "--quiet", "origin", "HEAD:main")
    host = tmp / "host"
    _git(tmp, "clone", "--quiet", str(origin), str(host))
    return host, tagged, later


def _run(
    tmp: Path,
    host: Path,
    sha: str,
    version: str,
    *,
    docker_fail: str = "",
    heartbeat_ok: bool = True,
    inspect: str | None = None,
    existing_container: bool = True,
    running_image: str = "callers-compendium-athenaeum:2026-10-17",
) -> tuple[subprocess.CompletedProcess, list[str]]:
    stubs = tmp / "stubs"
    stubs.mkdir(exist_ok=True)
    log = tmp / "calls.log"
    log.write_text("", encoding="utf-8")
    _write_stub(stubs / "sudo", '[ "$1" = "-n" ] && shift\nexec "$@"\n')
    # Fed on stdin like the real `ssh ... bash -s`; the docker stub drains stdin,
    # so a script that is not parsed whole loses its tail and fails below.
    # `docker build` also records which commit the checkout was on, so the test
    # can assert the image was built from the tagged tree.
    _write_stub(
        stubs / "docker",
        f"""echo "docker $*" >> '{log}'
cat > /dev/null  # a stdin reader must not swallow the rest of the script
case "$1" in
  build) echo "tree=$(cat marker.txt)" >> '{log}' ;;
  container) [ "{int(existing_container)}" = 1 ] || exit 1 ;;
  inspect) case "$*" in
    *RestartCount*) echo '{inspect if inspect is not None else "true callers-compendium-athenaeum:" + version + " 0"}' ;;
    *) echo '{running_image}' ;;
  esac ;;
esac
[ "$1" = "{docker_fail}" ] && exit 1
exit 0
""",
    )
    _write_stub(stubs / "curl", f'echo "curl $*" >> \'{log}\'\nexit {0 if heartbeat_ok else 22}\n')
    _write_stub(stubs / "sleep", "exit 0\n")
    env = bash_environ()
    env["PATH"] = f"{stubs}{os.pathsep}{env['PATH']}"
    env["ATHENAEUM_REPO_DIR"] = str(host)
    env["ATHENAEUM_HEARTBEAT_ATTEMPTS"] = "3"
    res = subprocess.run(
        [find_bash(), "-s", "--", sha, version],
        stdin=SCRIPT.open("rb"),
        env=env,
        capture_output=True,
        text=True,
    )
    return res, log.read_text(encoding="utf-8").splitlines()


def _docker_verbs(calls: list[str]) -> list[str]:
    return [c.split()[1] for c in calls if c.startswith("docker ")]


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        host, tagged, later = _setup(tmp)

        # Happy path: builds the TAGGED commit (not main's later one), tags the
        # image with the release version, then swaps the container.
        res, calls = _run(tmp, host, tagged, "0.7.0-beta")
        out = res.stdout + res.stderr
        assert res.returncode == 0, out
        assert _git(host, "rev-parse", "HEAD") == tagged
        assert "tree=tagged" in calls, calls
        assert any(
            c.startswith("docker build ")
            and "--tag callers-compendium-athenaeum:0.7.0-beta" in c
            and "--file server/Dockerfile" in c
            for c in calls
        ), calls
        verbs = _docker_verbs(calls)
        assert verbs.index("build") < verbs.index("stop") < verbs.index("rm") < verbs.index("run"), verbs
        run_call = next(c for c in calls if c.startswith("docker run "))
        for flag in (
            "--name athenaeum", "--network host", "--restart unless-stopped",
            "--read-only", "--env-file /root/athenaeum.env",
            "callers-compendium-athenaeum:0.7.0-beta",
        ):
            assert flag in run_call, (flag, run_call)
        assert any(c.startswith("curl ") for c in calls), calls

        # A first deploy has no container to stop; that must not be an error.
        res, calls = _run(tmp, host, tagged, "0.7.0", existing_container=False)
        assert res.returncode == 0, res.stdout + res.stderr
        assert "stop" not in _docker_verbs(calls) and "run" in _docker_verbs(calls), calls

        # A failed build must leave the running container alone.
        res, calls = _run(tmp, host, tagged, "0.7.0-beta", docker_fail="build")
        assert res.returncode != 0
        assert not {"stop", "rm", "run"} & set(_docker_verbs(calls)), calls

        # A failed `docker run` fails the deploy.
        res, _ = _run(tmp, host, tagged, "0.7.0-beta", docker_fail="run")
        assert res.returncode != 0

        # A server that never answers /heartbeat fails the deploy.
        res, _ = _run(tmp, host, tagged, "0.7.0-beta", heartbeat_ok=False)
        assert res.returncode != 0 and "did not answer" in res.stdout + res.stderr

        # A container that is answering but is restarting, or is not the new
        # image, fails the deploy.
        for state in ("true callers-compendium-athenaeum:0.7.0-beta 2",
                      "true callers-compendium-athenaeum:0.6.0-beta 0",
                      "false callers-compendium-athenaeum:0.7.0-beta 0"):
            res, _ = _run(tmp, host, tagged, "0.7.0-beta", inspect=state)
            assert res.returncode != 0 and "is not the fresh" in res.stdout + res.stderr, state

        # The server is never downgraded: an older (or beta-of-the-same-core)
        # release is refused before anything is fetched or built, while the same
        # version, a newer one, and a legacy date-tagged container proceed.
        image = "callers-compendium-athenaeum:"
        for running, new_version, allowed in (
            ("0.8.0-beta", "0.7.0-beta", False),
            ("0.7.0", "0.7.0-beta", False),
            ("0.10.0", "0.9.0", False),
            ("0.7.0-beta", "0.7.0-beta", True),
            ("0.7.0-beta", "0.7.0", True),
            ("0.7.0", "0.10.0", True),
            ("2026-10-17", "0.7.0-beta", True),
        ):
            res, calls = _run(
                tmp, host, tagged, new_version, running_image=image + running
            )
            if allowed:
                assert res.returncode == 0, (running, new_version, res.stdout, res.stderr)
            else:
                assert res.returncode != 0 and "refusing to downgrade" in (
                    res.stdout + res.stderr
                ), (running, new_version)
                assert not {"build", "stop", "rm", "run"} & set(_docker_verbs(calls)), calls

        # A commit origin does not have fails before anything is built or replaced.
        missing = "0" * 40
        res, calls = _run(tmp, host, missing, "0.7.0-beta")
        assert res.returncode != 0, res.stdout + res.stderr
        assert not {"build", "stop", "rm", "run"} & set(_docker_verbs(calls)), calls

        # Malformed arguments are rejected before git or docker run.
        for sha, version in (
            ("main", "0.7.0-beta"),
            (tagged[:12], "0.7.0-beta"),
            (tagged.upper(), "0.7.0-beta"),
            (tagged, "v0.7.0-beta"),
            (tagged, "0.7.0-rc.1"),
            (tagged, "0.7.0; touch pwned"),
            (tagged, "01.7.0"),
        ):
            res, calls = _run(tmp, host, sha, version)
            assert res.returncode != 0, (sha, version, res.stdout, res.stderr)
            assert not calls, (sha, version, calls)
        assert not (host / "pwned").exists()

    print("deploy_athenaeum.sh guards: OK")


if __name__ == "__main__":
    main()
