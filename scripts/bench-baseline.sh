#!/usr/bin/env bash
# Refreshes the checked-in benchmark baseline for package $1 into $2 -- see
# `just bench-baseline` for the recipe that calls this.
set -euo pipefail

pkg="$1"
dest="$2"

mkdir -p "$(dirname "$dest")"
just bench-count "$pkg" 10 | tee "$dest"
