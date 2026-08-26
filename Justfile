# Dev tooling helpers for this fork. Run inside `nix develop` (flake.nix) to guarantee the
# tools each recipe needs (benchstat via goperf, go-licence-detector, ...) are present.
#
# Benchmarking recipes below -- see BENCHMARKING_PLAN.md #3.

default:
    @just --list

# Run Tier A benchmarks for a package (default: everything).
bench pkg="./...":
    go test {{pkg}} -bench=. -benchmem -run=^$

# Run a package's benchmarks `count` times -- enough samples for benchstat to compare.
bench-count pkg count="10":
    go test {{pkg}} -bench=. -benchmem -run=^$ -count={{count}}

# Refresh the checked-in baseline for a package.
bench-baseline pkg dest="benchmarks/baseline.txt":
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "$(dirname {{dest}})"
    just bench-count {{pkg}} 10 | tee {{dest}}

# Compare the current code's benchmarks against the checked-in baseline.
bench-diff pkg baseline="benchmarks/baseline.txt":
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    just bench-count {{pkg}} 10 > "$tmp"
    # -ignore cpu: benchmarks/baseline.txt is captured on linux/amd64 CI hardware,
    # which varies between runs (see BENCHMARKING_PLAN.md) -- and on a Mac this is
    # also a real goos/goarch mismatch, so don't expect a meaningful `vs base` delta
    # from this locally, only from CI's own comparison.
    benchstat -ignore cpu {{baseline}} "$tmp"

# Regenerate THIRD_PARTY_NOTICES.md from go.mod (direct + indirect deps).
third-party-notices out="THIRD_PARTY_NOTICES.md":
    # go-licence-detector reads LICENSE files out of the local module cache -- it doesn't
    # fetch them itself, so on a cold cache (e.g. a fresh CI runner) it silently produces
    # a notices file with zero package entries instead of erroring.
    go mod download all
    go list -mod=mod -m -json all | go-licence-detector \
        -includeIndirect \
        -rules assets/licence/rules.json \
        -overrides assets/licence/overrides.json \
        -noticeTemplate assets/licence/THIRD_PARTY_NOTICES.md.tmpl \
        -noticeOut {{out}}

# Verify THIRD_PARTY_NOTICES.md is up to date with go.mod.
third-party-notices-check:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    just third-party-notices "$tmp"
    diff "$tmp" THIRD_PARTY_NOTICES.md
