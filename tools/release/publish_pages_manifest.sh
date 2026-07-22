#!/usr/bin/env bash
# Publish ONE channel's update manifest (`stable.json` / `beta.json`) to the
# persistent `gh-pages` branch so it serves at the site root
# (`https://ibanner56.github.io/CallersCompendium/<channel>.json`, the fixed URL
# the in-app update client reads — see app/lib/src/update/update_config.dart and
# docs/adr/002-distribution-and-update-channels.md §1/§2).
#
# WHY a branch (not actions/deploy-pages): the GitHub-Actions Pages flow replaces
# the WHOLE site each deploy, so a stable release would clobber `beta.json` and
# vice-versa. This script instead starts from the EXISTING gh-pages content and
# overwrites ONLY the current channel's file — the other channel is preserved by
# construction. It is deliberately parameterized (REMOTE/BRANCH/WORKTREE/PAGES_*)
# so it can be exercised offline against local bare repos by
# tools/release/test_publish_pages_manifest.py (no network, no third-party
# action, nothing new to SHA-pin).
#
# Usage:
#   publish_pages_manifest.sh --manifest <path> --channel <stable|beta> --tag <vX.Y.Z> [--signature <path>]
#
# When --signature is given (issue #431), its file is published alongside the
# manifest as `<channel>.json.sig` (the detached Ed25519 signature the in-app
# client verifies against the pinned public key). When omitted the behaviour is
# byte-identical to before (manifest only) so an unsigned release stays green.
#
# Environment overrides (defaults target the real release):
#   REMOTE            git remote to push to           (default: origin)
#   BRANCH            branch to publish to             (default: gh-pages)
#   WORKTREE          scratch worktree dir             (default: $RUNNER_TEMP/gh-pages or ./.gh-pages-site)
#   PAGES_USER_NAME   commit author/committer name     (default: github-actions[bot])
#   PAGES_USER_EMAIL  commit author/committer email    (default: the bot no-reply)
#   PUSH_RETRIES      non-fast-forward retry attempts   (default: 5)
set -euo pipefail

manifest=""
channel=""
tag=""
signature=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest) [ "$#" -ge 2 ] || { echo "::error::--manifest requires a value" >&2; exit 2; }; manifest="$2"; shift 2 ;;
    --channel)  [ "$#" -ge 2 ] || { echo "::error::--channel requires a value" >&2; exit 2; };  channel="$2";  shift 2 ;;
    --tag)      [ "$#" -ge 2 ] || { echo "::error::--tag requires a value" >&2; exit 2; };      tag="$2";      shift 2 ;;
    --signature) [ "$#" -ge 2 ] || { echo "::error::--signature requires a value" >&2; exit 2; }; signature="$2"; shift 2 ;;
    *) echo "::error::unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$manifest" ] || { echo "::error::--manifest is required" >&2; exit 2; }
[ -n "$channel" ]  || { echo "::error::--channel is required" >&2; exit 2; }
[ -n "$tag" ]      || { echo "::error::--tag is required" >&2; exit 2; }
case "$channel" in
  stable|beta) ;;
  *) echo "::error::--channel must be 'stable' or 'beta', got: $channel" >&2; exit 2 ;;
esac
[ -f "$manifest" ] || { echo "::error::manifest file not found: $manifest" >&2; exit 2; }
if [ -n "$signature" ]; then
  [ -f "$signature" ] || { echo "::error::signature file not found: $signature" >&2; exit 2; }
fi

remote="${REMOTE:-origin}"
branch="${BRANCH:-gh-pages}"
worktree="${WORKTREE:-${RUNNER_TEMP:-.}/gh-pages-site}"
user_name="${PAGES_USER_NAME:-github-actions[bot]}"
user_email="${PAGES_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
retries="${PUSH_RETRIES:-5}"

# Absolute path so the copy survives the `cd` into the worktree.
manifest_abs="$(cd "$(dirname "$manifest")" && pwd)/$(basename "$manifest")"
dest="${channel}.json"
sig_abs=""
sig_dest="${channel}.json.sig"
if [ -n "$signature" ]; then
  sig_abs="$(cd "$(dirname "$signature")" && pwd)/$(basename "$signature")"
fi

cleanup() { git worktree remove --force "$worktree" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Stage the current channel's manifest into a gh-pages worktree, preserving every
# other file already on the branch. Returns with $worktree checked out to $branch.
prepare_worktree() {
  git worktree remove --force "$worktree" >/dev/null 2>&1 || true
  rm -rf "$worktree"

  if git ls-remote --exit-code --heads "$remote" "$branch" >/dev/null 2>&1; then
    # Branch exists: base the worktree on the latest remote tip so the OTHER
    # channel's file (and anything else already published) is carried forward.
    git fetch --no-tags --depth=1 "$remote" "$branch"
    git worktree add --force -B "$branch" "$worktree" FETCH_HEAD
  else
    # First-ever publish: an orphan branch with no history and nothing to clobber.
    # `checkout --orphan` stages HEAD's files onto an unborn branch; `git rm -rf .`
    # then `clean -fdx` empty the tree so gh-pages starts with only our manifest.
    git worktree add --force --detach "$worktree" HEAD
    git -C "$worktree" checkout --orphan "$branch"
    git -C "$worktree" rm -rf . >/dev/null 2>&1 || true
    git -C "$worktree" clean -fdx >/dev/null 2>&1 || true
  fi
}

commit_manifest() {
  cp "$manifest_abs" "$worktree/$dest"
  touch "$worktree/.nojekyll"   # serve JSON verbatim; skip Jekyll processing.

  git -C "$worktree" add "$dest" .nojekyll

  # Publish the detached signature next to the manifest when provided so the
  # in-app client can fetch <channel>.json.sig and verify it (issue #431).
  if [ -n "$sig_abs" ]; then
    cp "$sig_abs" "$worktree/$sig_dest"
    git -C "$worktree" add "$sig_dest"
  fi

  if git -C "$worktree" diff --cached --quiet; then
    echo "No change to $dest for $tag; gh-pages already up to date (no-op)."
    return 1
  fi
  # Set the identity per-commit (`-c`) rather than `git config`, which would
  # persist into the shared repo config and change a local maintainer's commit
  # identity as a surprising side effect.
  git -C "$worktree" \
    -c "user.name=$user_name" \
    -c "user.email=$user_email" \
    commit -m "release: publish $dest for $tag" >/dev/null
  return 0
}

prepare_worktree
if ! commit_manifest; then
  exit 0
fi

# Push with bounded retry: a concurrent stable+beta release could advance the
# branch between our fetch and push. On rejection we re-stage our single file
# onto the new tip (never discarding the other channel) and retry.
attempt=0
while :; do
  if git -C "$worktree" push "$remote" "HEAD:$branch"; then
    echo "Published $dest to $remote/$branch for $tag."
    echo "Live at https://ibanner56.github.io/CallersCompendium/$dest once Pages is enabled."
    break
  fi
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$retries" ]; then
    echo "::error::failed to push $dest to $remote/$branch after $retries attempts" >&2
    exit 1
  fi
  echo "Push rejected (branch advanced); re-staging $dest and retrying ($attempt/$retries)..."
  prepare_worktree
  if ! commit_manifest; then
    # Someone else already published identical content for this channel.
    exit 0
  fi
done
