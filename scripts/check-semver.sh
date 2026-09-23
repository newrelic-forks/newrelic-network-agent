#!/usr/bin/env bash
# Validates that $1 is SemVer (MAJOR.MINOR.PATCH, optionally -prerelease) -- and,
# specifically, rejects +build-metadata even though semver-tool itself accepts it: this
# repo doesn't use SemVer's +build suffix anywhere (NETWORK_AGENT_BUILD covers that
# separately), so a version string carrying one is never actually valid here. See
# `just check-semver` for the recipe that calls this.
#
# Assumes `semver` is already on PATH -- run through the devShell (`nix develop`, or `nix
# develop --command just check-semver ...` from CI), never a bare `nix run
# nixpkgs#semver-tool`, which would resolve against the global flake registry's nixpkgs
# instead of this repo's own pinned one.
set -euo pipefail

s="$1"

case "$s" in
  *+*)
    echo "error: '$s' has build metadata -- this repo doesn't use SemVer's +build suffix" >&2
    exit 1
    ;;
esac

result="$(semver validate "$s")"
if [ "$result" != "valid" ]; then
  echo "error: '$s' is not a valid SemVer version (expected MAJOR.MINOR.PATCH, optionally -prerelease): $result" >&2
  exit 1
fi
echo "'$s' is valid SemVer"
