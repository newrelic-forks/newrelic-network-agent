#!/usr/bin/env bash
# Verifies THIRD_PARTY_NOTICES.md is up to date with go.mod -- see
# `just third-party-notices-check` for the recipe that calls this.
set -euo pipefail

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
just third-party-notices "$tmp"
diff "$tmp" THIRD_PARTY_NOTICES.md
