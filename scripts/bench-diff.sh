#!/usr/bin/env bash
# Compares package $1's current benchmarks against the checked-in baseline $2 -- see
# `just bench-diff` for the recipe that calls this.
set -euo pipefail

pkg="$1"
baseline="$2"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
just bench-count "$pkg" 10 > "$tmp"

# -ignore cpu: benchmarks/baseline.txt is captured on linux/amd64 CI hardware, which
# varies between runs (see BENCHMARKING_PLAN.md) -- and on a Mac this is also a real
# goos/goarch mismatch, so don't expect a meaningful `vs base` delta from this locally,
# only from CI's own comparison.
benchstat -ignore cpu "$baseline" "$tmp"
