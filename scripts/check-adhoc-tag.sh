#!/usr/bin/env bash
# Rejects $1 if it's valid SemVer or is literally "latest" -- both are reserved for the
# real release pipeline (VERSION bump -> cut-prerelease.yml -> publish-release.yml), never
# for push-adhoc-image.yml's workflow_dispatch input. See `just check-adhoc-tag` for the
# recipe that calls this.
#
# Calls check-semver.sh directly by path rather than through `just` -- same reason as
# check-version.sh.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tag="$1"

case "$(printf '%s' "$tag" | tr '[:upper:]' '[:lower:]')" in
  latest)
    echo "error: 'latest' is reserved for the release pipeline -- pick a different ad-hoc tag." >&2
    exit 1
    ;;
esac

if "$script_dir/check-semver.sh" "$tag" >/dev/null 2>&1; then
  echo "error: '$tag' is valid SemVer, which is reserved for the release pipeline (VERSION bump -> cut-prerelease.yml) -- an ad-hoc tag must not be confusable with a real release. Pick something clearly not a version number." >&2
  exit 1
fi
echo "'$tag' is a valid ad-hoc image tag."
