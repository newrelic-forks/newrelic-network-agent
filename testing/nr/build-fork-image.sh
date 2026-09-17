#!/usr/bin/env bash
# testing/nr/build-fork-image.sh
#
# Builds this fork's Dockerfile from an arbitrary git ref (branch, tag, or
# commit) into a local image, so run-snmp-test.sh's --image flag can switch
# between the official upstream image, this fork's main/develop, or any
# scratch branch you're iterating on.
#
# The ref is checked out into a throwaway `git worktree` -- your current
# branch and working tree are never touched, and it works even if you have
# uncommitted changes checked out right now.
#
# This follows docs/PLAYGROUND.md's "Local build (colima)" recipe exactly
# (same nix-provided standalone buildx, same BuildKit secret mounts, same
# known TLS-interception caveat) -- see that doc if this fails outright.
#
# Usage:
#   ./build-fork-image.sh <git-ref> [image-tag]
#
# Examples:
#   ./build-fork-image.sh develop                # -> ntranslate:develop
#   ./build-fork-image.sh main                    # -> ntranslate:main
#   ./build-fork-image.sh my-scratch-branch        # -> ntranslate:my-scratch-branch
#   ./build-fork-image.sh my-scratch-branch scratch # -> ntranslate:scratch
#
# Requires (same as docs/PLAYGROUND.md, NOT secretspec -- this is the
# existing build-secrets convention, kept separate on purpose):
#   MM_ACCOUNT_ID, MM_DOWNLOAD_KEY  -- source ./.envrc for these
#   GH_TOKEN                       -- falls back to `gh auth token` if unset
#
# Override the buildx builder (defaults to "colima", per PLAYGROUND.md's
# documented setup) with BUILDX_BUILDER=<name>.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
BUILDER="${BUILDX_BUILDER:-colima}"

usage() {
  echo "Usage: $0 <git-ref> [image-tag]" >&2
  exit 1
}

[ $# -ge 1 ] || usage
ref="$1"
tag="${2:-$(printf '%s' "$ref" | tr -c 'a-zA-Z0-9_.-' '-')}"

: "${MM_ACCOUNT_ID:?MM_ACCOUNT_ID is not set -- source .envrc first (see docs/PLAYGROUND.md)}"
: "${MM_DOWNLOAD_KEY:?MM_DOWNLOAD_KEY is not set -- source .envrc first (see docs/PLAYGROUND.md)}"
GH_TOKEN="${GH_TOKEN:-$(gh auth token)}"
export GH_TOKEN

worktree_dir="$(mktemp -d "${TMPDIR:-/tmp}/ntranslate-build-${tag}.XXXXXX")"
cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$worktree_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Checking out '$ref' into a throwaway worktree at $worktree_dir"
git -C "$REPO_ROOT" worktree add --detach "$worktree_dir" "$ref"

echo "Resolving a standalone buildx (this docker CLI has no buildx plugin -- see PLAYGROUND.md)"
buildx_out="$(nix --extra-experimental-features 'nix-command flakes' \
  build --no-link --print-out-paths nixpkgs#docker-buildx | head -1)"
BUILDX="$buildx_out/libexec/docker/cli-plugins/docker-buildx"

echo "Building ntranslate:$tag from '$ref' (builder: $BUILDER)"
"$BUILDX" build --builder "$BUILDER" \
  --secret id=github_token,env=GH_TOKEN \
  --secret id=mm_account_id,env=MM_ACCOUNT_ID \
  --secret id=mm_license_key,env=MM_DOWNLOAD_KEY \
  --build-arg KENTIK_KTRANSLATE_VERSION="$tag" \
  --build-arg KENTIK_SNMP_PROFILE_REPO=https://github.com/DavSanchez/snmp-profiles \
  -t "ntranslate:$tag" --load "$worktree_dir"

echo "Built ntranslate:$tag -- use it with: run-snmp-test.sh up --image ntranslate:$tag ..."
