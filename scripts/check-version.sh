#!/usr/bin/env bash
# Validates the checked-in VERSION file itself -- what version-format-check.yml's
# "Validate VERSION is SemVer" step and cut-prerelease.yml's own re-validation both
# actually run. See `just check-version` for the recipe that calls this.
#
# Calls check-semver.sh directly by path rather than recursing through `just` -- no reason
# to spawn a second `just` process just to get back to a script we can already see.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="$(tr -d '[:space:]' < VERSION)"

exec "$script_dir/check-semver.sh" "$version"
