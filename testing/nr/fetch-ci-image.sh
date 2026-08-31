#!/usr/bin/env bash
# testing/nr/fetch-ci-image.sh
#
# Fetches an ntranslate image built by .github/workflows/ci-build.yml in
# GitHub Actions, instead of building locally with build-fork-image.sh --
# useful when the local build hits the corporate-TLS-interception blocker
# documented in docs/PLAYGROUND.md (CI is unaffected by that).
#
# By default, dispatches a fresh ci-build.yml run for the given ref, waits
# for it, downloads the resulting image artifact, docker-loads it, and
# retags it as ntranslate:<tag>. Pass --latest to skip the dispatch and just
# grab the most recent successful run's artifact instead (faster, but not
# guaranteed to match the ref's current tip).
#
# Only works for refs that already have .github/workflows/ci-build.yml --
# confirmed present on `develop` (and anything branched from it), NOT on
# `main` (which stays a faithful copy of upstream kentik/ktranslate).
#
# Usage:
#   ./fetch-ci-image.sh <git-ref> [image-tag] [--platform linux/amd64|linux/arm64] [--latest] [--repo owner/name]
#
# Examples:
#   ./fetch-ci-image.sh develop                  # dispatch + wait -> ntranslate:develop
#   ./fetch-ci-image.sh develop --latest          # grab latest successful run's artifact instead
#
# Requires: `gh`, already authenticated (gh auth status) against github.com.

set -euo pipefail

repo="DavSanchez/ntranslate"
platform=""
latest=false

usage() {
  echo "Usage: $0 <git-ref> [image-tag] [--platform linux/amd64|linux/arm64] [--latest] [--repo owner/name]" >&2
  exit 1
}

[ $# -ge 1 ] || usage
ref="$1"; shift

tag=""
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  tag="$1"; shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --platform) platform="$2"; shift 2 ;;
    --latest) latest=true; shift ;;
    --repo) repo="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[ -n "$tag" ] || tag="$(printf '%s' "$ref" | tr -c 'a-zA-Z0-9_.-' '-')"

if [ -z "$platform" ]; then
  case "$(uname -m)" in
    arm64|aarch64) platform="linux/arm64" ;;
    *) platform="linux/amd64" ;;
  esac
fi

run_id=""

if [ "$latest" = true ]; then
  echo "Looking up the most recent successful ci-build.yml run for '$ref' (not dispatching a new one)"
  run_id="$(gh run list --repo "$repo" --workflow=ci-build.yml --branch "$ref" --status=success --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
  [ -n "$run_id" ] || { echo "No successful ci-build.yml run found for '$ref'" >&2; exit 1; }
else
  echo "Dispatching a fresh ci-build.yml run for '$ref' (platform: $platform)"
  before="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  gh workflow run ci-build.yml --repo "$repo" --ref "$ref" -f "platform=$platform"

  for _ in $(seq 1 30); do
    run_id="$(gh run list --repo "$repo" --workflow=ci-build.yml --branch "$ref" \
      --json databaseId,createdAt --jq "[.[] | select(.createdAt > \"$before\")] | sort_by(.createdAt) | last | .databaseId // empty")"
    [ -n "$run_id" ] && break
    sleep 2
  done
  [ -n "$run_id" ] || { echo "Timed out waiting for the dispatched run to appear -- check https://github.com/$repo/actions/workflows/ci-build.yml" >&2; exit 1; }

  echo "Watching run $run_id (this waits for the full CI build -- several minutes)"
  gh run watch "$run_id" --repo "$repo" --exit-status
fi

artifact_name="$(gh api "repos/$repo/actions/runs/$run_id/artifacts" --jq '.artifacts[] | select(.name | startswith("ntranslate-image-")) | .name' | head -1)"
[ -n "$artifact_name" ] || { echo "Run $run_id has no ntranslate-image-* artifact (did it fail before upload?)" >&2; exit 1; }

download_dir="$(mktemp -d "${TMPDIR:-/tmp}/ntranslate-ci-image.XXXXXX")"
cleanup() { rm -rf "$download_dir"; }
trap cleanup EXIT

echo "Downloading artifact '$artifact_name' from run $run_id"
gh run download "$run_id" --repo "$repo" --name "$artifact_name" --dir "$download_dir"

docker load -i "$download_dir/ntranslate-image.tar"
docker tag ntranslate:ci "ntranslate:$tag"

echo "Loaded ntranslate:$tag from CI run $run_id -- use it with: run-snmp-test.sh up --image ntranslate:$tag ..."
