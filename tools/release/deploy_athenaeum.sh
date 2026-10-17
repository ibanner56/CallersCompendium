#!/usr/bin/env bash
# Deploy the Athenaeum sync server for one release. This script runs ON the
# server host: release.yml's `deploy_server` job pipes it over SSH
# (`ssh ... bash -s -- <sha> <version> < tools/release/deploy_athenaeum.sh`), so
# the exact commands that run are the ones in the tagged commit.
#
# Usage:
#   deploy_athenaeum.sh <40-hex-commit-sha> <release-version>
#
#   <sha>      the commit the release tag points at; it is checked out detached,
#              never a branch tip, so a push to main mid-release cannot change
#              what is built.
#   <version>  the tag without its `v` (`0.7.0-beta`); it becomes the image tag
#              callers-compendium-athenaeum:<version>.
#
# Any failure exits non-zero, which fails the release before the mobile uploads
# and the update manifest. The image is built BEFORE the running container is
# touched, so a broken build leaves the previous release serving. A failure after
# that point (the new container will not start or never answers /heartbeat) leaves
# the new container in place for inspection; the previous image is still on the
# host, and docs/dev/athenaeum-operations.md says how to roll back to it.
#
# Environment overrides (defaults target the real host; the test sets them):
#   ATHENAEUM_REPO_DIR            checkout to build from         (default: /opt/CallersCompendium)
#   ATHENAEUM_HEARTBEAT_URL       readiness probe                (default: http://127.0.0.1:33333/heartbeat)
#   ATHENAEUM_HEARTBEAT_ATTEMPTS  one-second probe attempts      (default: 30)
set -euo pipefail

sha="${1:?usage: deploy_athenaeum.sh <40-hex-commit-sha> <release-version>}"
version="${2:?usage: deploy_athenaeum.sh <40-hex-commit-sha> <release-version>}"

# The release workflow has already validated both, but this runs as a privileged
# user on a production host and the values reach docker and git, so check again.
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::'$sha' is not a full 40-character lowercase commit SHA" >&2
  exit 1
fi
core_re='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
if [[ ! "$version" =~ ^${core_re}(-beta)?$ ]]; then
  echo "::error::'$version' is not an X.Y.Z or X.Y.Z-beta release version" >&2
  exit 1
fi

repo_dir="${ATHENAEUM_REPO_DIR:-/opt/CallersCompendium}"
heartbeat_url="${ATHENAEUM_HEARTBEAT_URL:-http://127.0.0.1:33333/heartbeat}"
heartbeat_attempts="${ATHENAEUM_HEARTBEAT_ATTEMPTS:-30}"
container=athenaeum
image="callers-compendium-athenaeum:${version}"

# Everything below sits in one brace group. This script arrives on stdin
# (`bash -s`), and bash reads a stdin script a line at a time, so a command that
# reads stdin (git over an ssh remote does) would swallow the rest of the script
# and the deploy would exit 0 half done. A brace group is parsed whole before it
# runs, and the `exit` after it means bash never reads stdin again.
{
echo "Deploying Athenaeum ${version} from ${sha}"

cd "$repo_dir"
# Fetch the commit itself rather than a branch: the tag may sit on a commit
# main has since moved past, and GitHub serves reachable commits by SHA.
git fetch origin "$sha"
git checkout --detach "$sha"
if [ "$(git rev-parse HEAD)" != "$sha" ]; then
  echo "::error::checkout is at $(git rev-parse HEAD), expected $sha" >&2
  exit 1
fi

sudo -n docker build \
  --file server/Dockerfile \
  --tag "$image" \
  .

if sudo -n docker container inspect "$container" >/dev/null 2>&1; then
  sudo -n docker stop "$container"
  sudo -n docker rm "$container"
fi

sudo -n docker run --detach \
  --name "$container" \
  --network host \
  --restart unless-stopped \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --mount type=bind,src=/var/lib/athenaeum,dst=/var/lib/athenaeum \
  --env-file /root/athenaeum.env \
  "$image"

# `docker run --detach` succeeds as soon as the container exists, so a server
# that crashes on start (a bad migration, a missing pepper) would otherwise pass.
# Wait for the credential-free liveness endpoint, then confirm the container is
# the one just started and has not been restarting.
ready=false
for ((attempt = 1; attempt <= heartbeat_attempts; attempt++)); do
  if curl --fail --silent --show-error --max-time 5 --output /dev/null "$heartbeat_url"; then
    ready=true
    break
  fi
  sleep 1
done
if [ "$ready" != true ]; then
  echo "::error::${container} did not answer ${heartbeat_url} within ${heartbeat_attempts}s" >&2
  exit 1
fi

state="$(sudo -n docker inspect --format '{{.State.Running}} {{.Config.Image}} {{.RestartCount}}' "$container")"
if [ "$state" != "true ${image} 0" ]; then
  echo "::error::${container} is not the fresh ${image} container (running/image/restarts: ${state})" >&2
  exit 1
fi

echo "Athenaeum ${version} (${sha}) is serving."
}
exit $?
