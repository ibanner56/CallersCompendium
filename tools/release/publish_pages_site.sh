#!/usr/bin/env bash
# Publish the static landing page (`site/`) to the persistent `gh-pages` branch
# that also hosts the in-app update manifests
# (`https://ibanner56.github.io/CallersCompendium/`).
#
# WHY a branch (not actions/deploy-pages): the GitHub-Actions Pages flow replaces
# the WHOLE site each deploy, which would clobber `beta.json` / `stable.json`
# published by tools/release/publish_pages_manifest.sh. This script instead starts
# from the EXISTING gh-pages content and rewrites ONLY the site files, PRESERVING
# the channel manifests (and `.nojekyll`) by construction — the mirror image of
# the manifest publisher, which preserves the site. The two therefore coexist on
# one branch without ever erasing each other.
#
# It is deliberately parameterized (REMOTE/BRANCH/WORKTREE/PAGES_*) so it can be
# exercised offline against local bare repos by
# tools/release/test_publish_pages_site.py (no network, no third-party action,
# nothing new to SHA-pin).
#
# Usage:
#   publish_pages_site.sh [--site <dir>]      (default: site)
#
# Environment overrides (defaults target the real deploy):
#   REMOTE            git remote to push to           (default: origin)
#   BRANCH            branch to publish to             (default: gh-pages)
#   WORKTREE          scratch worktree dir             (default: $RUNNER_TEMP/gh-pages-site or ./.gh-pages-site)
#   PAGES_USER_NAME   commit author/committer name     (default: github-actions[bot])
#   PAGES_USER_EMAIL  commit author/committer email    (default: the bot no-reply)
#   PUSH_RETRIES      non-fast-forward retry attempts   (default: 5)
#   SOURCE_REF        label recorded in the commit msg (default: current git short SHA)
set -euo pipefail

site_dir="site"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --site) [ "$#" -ge 2 ] || { echo "::error::--site requires a value" >&2; exit 2; }; site_dir="$2"; shift 2 ;;
    *) echo "::error::unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -d "$site_dir" ]            || { echo "::error::site dir not found: $site_dir" >&2; exit 2; }
[ -f "$site_dir/index.html" ] || { echo "::error::$site_dir/index.html not found" >&2; exit 2; }

# Absolute path so the copy survives the `cd`/worktree operations below.
site_abs="$(cd "$site_dir" && pwd)"

remote="${REMOTE:-origin}"
branch="${BRANCH:-gh-pages}"
worktree="${WORKTREE:-${RUNNER_TEMP:-.}/gh-pages-site}"
user_name="${PAGES_USER_NAME:-github-actions[bot]}"
user_email="${PAGES_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
retries="${PUSH_RETRIES:-5}"
source_ref="${SOURCE_REF:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}"

# Files on gh-pages that belong to OTHER writers and must never be touched here.
# Anything else at the branch root is considered "site output" we own.
#
# The channel manifests AND their detached signatures (`<channel>.json.sig`, added
# in #431) are published by tools/release/publish_pages_manifest.sh and must be
# preserved TOGETHER: a manifest without its signature is as broken as the reverse
# — the in-app update client fetches `<channel>.json.sig`, and a missing signature
# makes it fail closed and silently stop offering updates (issue #607).
#
# Preserved BY PATTERN, not by enumerated channel name (issue #640): `*.json` and
# `*.json.sig` cover every current and future channel manifest + signature (e.g. a
# new `alpha.json`/`alpha.json.sig`) without ever needing an edit here. Each glob
# is matched by `find -name` against the *basename only* of top-level gh-pages
# entries (`-mindepth 1 -maxdepth 1` below), so it can't be widened by slashes or
# path traversal in a crafted name, and `site/` ships no `*.json` of its own today
# (verified: only html/css/js/svg), so this can't accidentally preserve a stale
# site file instead of replacing it.
#
# `CNAME` holds the Pages custom domain. With the Pages source set to "deploy from
# a branch", GitHub reads the domain from this file at the branch root: delete it
# and the custom-domain setting is silently CLEARED. Before it was preserved here,
# every site publish erased it, so the domain had to be re-entered by hand.
#
# Belt and braces, and the two layers have a deliberate precedence:
#   * `site/CNAME` is the SOURCE OF TRUTH — it is copied in below (after the prune),
#     so a checked-in value always wins.
#   * this preserve entry is the safety net for a staged site that lacks the file,
#     so a publish can never clear the domain as a side effect.
# To RETIRE the custom domain, delete `site/CNAME` *and* drop "CNAME" here —
# otherwise the stale value is carried forward indefinitely.
preserve=(".git" ".nojekyll" "CNAME" "*.json" "*.json.sig")

cleanup() { git worktree remove --force "$worktree" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Check out gh-pages into a scratch worktree, carrying forward whatever is already
# published (the channel manifests in particular). Returns with $worktree on $branch.
prepare_worktree() {
  git worktree remove --force "$worktree" >/dev/null 2>&1 || true
  rm -rf "$worktree"

  if git ls-remote --exit-code --heads "$remote" "$branch" >/dev/null 2>&1; then
    git fetch --no-tags --depth=1 "$remote" "$branch"
    git worktree add --force -B "$branch" "$worktree" FETCH_HEAD
  else
    # First-ever publish: an orphan branch with nothing to clobber.
    git worktree add --force --detach "$worktree" HEAD
    git -C "$worktree" checkout --orphan "$branch"
    git -C "$worktree" rm -rf . >/dev/null 2>&1 || true
    git -C "$worktree" clean -fdx >/dev/null 2>&1 || true
  fi
}

# Replace the site output in the worktree with the current `site/` tree, leaving
# the preserved manifest files exactly as they were on the branch.
sync_site() {
  # Remove previously-published site files (top-level entries we don't preserve).
  # `--` guards against any gh-pages entry whose name begins with `-`.
  local keep_expr=()
  local name
  for name in "${preserve[@]}"; do keep_expr+=(! -name "$name"); done
  find "$worktree" -mindepth 1 -maxdepth 1 "${keep_expr[@]}" -exec rm -rf -- {} +

  # Copy the fresh site tree in (contents of site/, not the directory itself).
  cp -R "$site_abs"/. "$worktree"/

  # Keep the Jekyll bypass marker so assets/JSON are served verbatim.
  touch "$worktree/.nojekyll"

  git -C "$worktree" add -A
}

commit_site() {
  sync_site
  if git -C "$worktree" diff --cached --quiet; then
    echo "No change to the landing page; gh-pages already up to date (no-op)."
    return 1
  fi
  # Per-commit identity (`-c`) so we never mutate the shared repo config.
  git -C "$worktree" \
    -c "user.name=$user_name" \
    -c "user.email=$user_email" \
    commit -m "site: publish landing page (${source_ref})" >/dev/null
  return 0
}

prepare_worktree
if ! commit_site; then
  exit 0
fi

# Push with bounded retry: a concurrent release could advance the branch (e.g. a
# manifest publish) between our fetch and push. On rejection we re-sync onto the
# new tip — which still preserves the manifests — and retry.
attempt=0
while :; do
  if git -C "$worktree" push "$remote" "HEAD:$branch"; then
    echo "Published landing page to $remote/$branch (${source_ref})."
    echo "Live at https://ibanner56.github.io/CallersCompendium/ once Pages is enabled."
    break
  fi
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$retries" ]; then
    echo "::error::failed to push the landing page to $remote/$branch after $retries attempts" >&2
    exit 1
  fi
  echo "Push rejected (branch advanced); re-syncing and retrying ($attempt/$retries)..."
  prepare_worktree
  if ! commit_site; then
    exit 0
  fi
done
