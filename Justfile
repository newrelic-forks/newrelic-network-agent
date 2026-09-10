# Dev tooling helpers for this fork. Run inside `nix develop` (flake.nix) to guarantee the
# tools each recipe needs (benchstat via goperf, ...) are present.
#
# Benchmarking recipes below -- see BENCHMARKING_PLAN.md #3.

CURRENT_SYSTEM := `nix eval --impure --raw --expr builtins.currentSystem`

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

# Run the Tier B synthetic SNMP device farm at its small (12-node) scale --
# BENCHMARKING_PLAN.md #2.2. Fast enough for routine local iteration (confirmed
# end-to-end in a few minutes). Defaults to the current host's system -- on Apple
# Silicon this runs the VMs natively via apple-virt/HVF, no linux-builder involved
# (see nix/tests/snmp-discovery-bench.nix); in CI (system=x86_64-linux) it runs
# natively via kvm.
bench-tier-b system=CURRENT_SYSTEM:
    nix build .#checks.{{system}}.snmp-discovery-bench-smoke -L --print-out-paths

# Run the full 40-node/70-20-10 target topology. CI-scale, not laptop-scale: expect
# tens of minutes under any real resource contention -- see snmp-discovery-bench in
# flake.nix's checks output for why this isn't the local default.
bench-tier-b-full system=CURRENT_SYSTEM:
    nix build .#checks.{{system}}.snmp-discovery-bench -L --print-out-paths
