#!/usr/bin/env bash
# Validates that $2 is a strict SemVer increase over $1 -- real SemVer precedence
# (numeric vs. alphanumeric prerelease identifiers, a release outranking its own
# prerelease, ...), via semver-tool's `compare`, not re-derived by hand (e.g. `sort -V`,
# which isn't SemVer-aware and gets prerelease precedence wrong). See
# `just check-version-increment` for the recipe that calls this.
#
# Assumes `semver` is already on PATH -- see check-semver.sh's header comment for why this
# never shells out to `nix run nixpkgs#semver-tool` itself.
set -euo pipefail

old="$1"
new="$2"

result="$(semver compare "$new" "$old")"
if [ "$result" != "1" ]; then
  echo "error: '$new' is not a strict increase over '$old' (semver compare: $result)" >&2
  exit 1
fi
echo "'$new' > '$old'"
