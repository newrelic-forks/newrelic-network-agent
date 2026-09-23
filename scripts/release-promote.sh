#!/usr/bin/env bash
# Promotes a tested pre-release to a full release: flips GitHub's "This is a pre-release"
# checkbox off on the v$1 release, which triggers publish-release.yml's `promote` job to
# retag the pre-release's already-pushed newrelic/network-agent:$1-rc image as $1 and
# `latest` -- no rebuild, so what ships is byte-identical to what was tested. See
# `just release-promote` for the recipe that calls this.
set -euo pipefail

version="$1"

command -v gh >/dev/null || {
  echo "error: gh CLI not found -- see https://cli.github.com" >&2
  exit 1
}
tag="v$version"

is_prerelease="$(gh release view "$tag" --json isPrerelease --jq '.isPrerelease' 2>/dev/null)" || {
  echo "error: no GitHub release found for $tag -- cut one first by merging a VERSION bump to $version (see docs/RELEASING.md)." >&2
  exit 1
}
case "$is_prerelease" in
  true) ;;
  false)
    echo "error: $tag is already a full release, not a pre-release -- nothing to promote." >&2
    exit 1
    ;;
  *)
    echo "error: unexpected isPrerelease value '$is_prerelease' for $tag." >&2
    exit 1
    ;;
esac

# Best-effort: confirm the pre-release's own build actually succeeded, so a
# broken/incomplete Docker Hub push doesn't surprise the promote job below. Not a
# hard gate -- gh's run-listing by tag isn't guaranteed exhaustive, and
# publish-release.yml's own promote job is the authoritative, unskippable check.
if ! gh run list --workflow=publish-release.yml --json event,headBranch,conclusion \
  --jq ".[] | select(.event == \"release\" and .headBranch == \"$tag\" and .conclusion == \"success\")" |
  grep -q .; then
  echo "warning: no successful publish-release.yml run found for $tag -- its image may not actually be on Docker Hub yet. The promote job will fail if it isn't." >&2
fi

echo "Promoting $tag to a full release ..."
gh release edit "$tag" --prerelease=false

echo
echo "$tag is no longer marked pre-release. publish-release.yml's promote job will"
echo "retag the existing $version-rc image as $version and latest -- no rebuild."
