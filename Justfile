# Dev tooling helpers for this fork. Run inside `nix develop` (flake.nix) to guarantee the
# tools each recipe needs (benchstat via goperf, go-licence-detector, ...) are present.
#
# Benchmarking recipes below -- see BENCHMARKING_PLAN.md #3.

CURRENT_SYSTEM := `nix eval --impure --raw --expr builtins.currentSystem`

default:
    @just --list

# Download the MaxMind GeoLite2 databases into maxmind-dbs/, for a local `docker build`
# (see Dockerfile's maxmind stage -- CI/release builds get these from actions/cache
# instead, via ci-build.yml/publish-release.yml). Needs MM_ACCOUNT_ID/MM_DOWNLOAD_KEY in
# the environment -- the same names those workflows read from repo secrets. A free
# GeoLite2 account works: https://www.maxmind.com
maxmind-dbs dest="maxmind-dbs":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${MM_DOWNLOAD_KEY:-}" ]; then
        echo "MM_DOWNLOAD_KEY (MaxMind license key) not set" >&2
        exit 1
    fi
    mkdir -p {{dest}}
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -sfL -o "$tmp/country.tar.gz" -u "${MM_ACCOUNT_ID:-}:$MM_DOWNLOAD_KEY" "https://download.maxmind.com/geoip/databases/GeoLite2-Country/download?suffix=tar.gz"
    tar zxf "$tmp/country.tar.gz" --strip-components 1 -C {{dest}}
    curl -sfL -o "$tmp/asn.tar.gz" -u "${MM_ACCOUNT_ID:-}:$MM_DOWNLOAD_KEY" "https://download.maxmind.com/geoip/databases/GeoLite2-ASN/download?suffix=tar.gz"
    tar zxf "$tmp/asn.tar.gz" --strip-components 1 -C {{dest}}

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

# --- Release helpers ---------------------------------------------------------
#
# Cutting a pre-release is fully automated: cut-prerelease.yml tags and publishes a
# GitHub pre-release the moment a VERSION-bumping commit merges to main, at that exact
# commit -- see docs/RELEASING.md. There's no `just release-rc`, deliberately: the checked-in
# VERSION file is the one source of truth for what's tagged, so a manual, VERSION-file-free
# way to cut a release would let the two drift.
#
# Promoting a tested pre-release to a full release is the one deliberately manual step left
# -- this just wraps that in one command instead of the GitHub UI, plus the same pre-flight
# checks publish-release.yml's own `promote` job would otherwise fail on. Needs `gh`
# authenticated (`gh auth login`).

# Promote a tested pre-release to a full release: flips GitHub's "This is a pre-release"
# checkbox off on the *existing* v<version> release -- never creates a new tag or release,
# since under this repo's model there's only ever one release object per version. That edit
# triggers publish-release.yml's `promote` job (behind the docker-hub-release environment)
# to retag the pre-release's already-pushed newrelic/network-agent:sha-<commit> image as
# <version> and `latest` -- no rebuild, so what ships is byte-identical to what was tested.
release-promote version:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v gh >/dev/null || { echo "error: gh CLI not found -- see https://cli.github.com" >&2; exit 1; }
    tag="v{{version}}"

    is_prerelease="$(gh release view "$tag" --json isPrerelease --jq '.isPrerelease' 2>/dev/null)" || {
      echo "error: no GitHub release found for $tag -- cut one first by merging a VERSION bump to {{version}} (see docs/RELEASING.md)." >&2
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
         --jq ".[] | select(.event == \"release\" and .headBranch == \"$tag\" and .conclusion == \"success\")" \
         | grep -q .; then
      echo "warning: no successful publish-release.yml run found for $tag -- its image may not actually be on Docker Hub yet. The promote job will fail if it isn't." >&2
    fi

    echo "Promoting $tag to a full release ..."
    gh release edit "$tag" --prerelease=false

    echo
    echo "$tag is no longer marked pre-release. publish-release.yml's promote job (once"
    echo "approved in the docker-hub-release environment) will retag the existing"
    echo "sha-tagged image as {{version}} and latest -- no rebuild."
