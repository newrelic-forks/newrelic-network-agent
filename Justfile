# Dev tooling helpers for this fork. Run inside `nix develop` (flake.nix) to guarantee the
# tools each recipe needs (benchstat via goperf, go-licence-detector, ...) are present.
#
# Recipes with real logic delegate to a same-named script in scripts/ rather than an inline
# #!/usr/bin/env bash body, specifically so shellcheck (via an editor integration, a git
# hook, whatever) can actually see them -- it can't lint a script embedded in a Justfile
# recipe.
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
    ./scripts/maxmind-dbs.sh "{{dest}}"

# Run Tier A benchmarks for a package (default: everything).
bench pkg="./...":
    go test {{pkg}} -bench=. -benchmem -run=^$

# Run a package's benchmarks `count` times -- enough samples for benchstat to compare.
bench-count pkg count="10":
    go test {{pkg}} -bench=. -benchmem -run=^$ -count={{count}}

# Refresh the checked-in baseline for a package.
bench-baseline pkg dest="benchmarks/baseline.txt":
    ./scripts/bench-baseline.sh "{{pkg}}" "{{dest}}"

# Compare the current code's benchmarks against the checked-in baseline.
bench-diff pkg baseline="benchmarks/baseline.txt":
    ./scripts/bench-diff.sh "{{pkg}}" "{{baseline}}"

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
    ./scripts/third-party-notices-check.sh

# --- SemVer helpers -----------------------------------------------------------
#
# Deliberately here, not in flake.nix: these are thin wrappers around semver-tool
# (fsaintjacques/semver-tool) plus this repo's own release policy (no +build metadata in
# VERSION, no bare-vs-prerelease suffix rules, ...) -- not packages, not a devShell, and
# not complex enough to need Nix's own build/VM machinery the way the checks in flake.nix
# do. They assume semver-tool is already on PATH rather than shelling out to `nix run
# nixpkgs#semver-tool` themselves -- that would resolve against whatever nixpkgs the
# *global* flake registry currently points at, not this repo's own flake.lock-pinned
# nixpkgs, silently bypassing the pin. So every caller, human or CI, is expected to run
# these via the devShell (`nix develop` -- interactively, or `nix develop --command just
# <recipe>` from CI; see cut-prerelease.yml/version-format-check.yml/push-adhoc-image.yml),
# never a bare `nix run nixpkgs#just -- <recipe>`.

# Validates that `s` is SemVer (MAJOR.MINOR.PATCH, optionally -prerelease) -- and,
# specifically, rejects +build-metadata even though semver-tool itself accepts it: this
# repo doesn't use SemVer's +build suffix anywhere (NETWORK_AGENT_BUILD covers that
# separately), so a version string carrying one is never actually valid here.
check-semver s:
    ./scripts/check-semver.sh "{{s}}"

# Validates that `new` is a strict SemVer increase over `old` -- real SemVer precedence
# (numeric vs. alphanumeric prerelease identifiers, a release outranking its own
# prerelease, ...), via semver-tool's `compare`, not re-derived by hand (e.g. `sort -V`,
# which isn't SemVer-aware and gets prerelease precedence wrong).
check-version-increment old new:
    ./scripts/check-version-increment.sh "{{old}}" "{{new}}"

# Validates the checked-in VERSION file itself -- what version-format-check.yml's "Validate
# VERSION is SemVer" step and cut-prerelease.yml's own re-validation both actually run.
check-version:
    ./scripts/check-version.sh

# Rejects `tag` if it's valid SemVer or is literally "latest" -- both are reserved for the
# real release pipeline (VERSION bump -> cut-prerelease.yml -> publish-release.yml), never
# for push-adhoc-image.yml's workflow_dispatch input. This is release *policy* (which tags
# are reserved), so it lives here too, calling into check-semver.sh for the actual "is this
# valid SemVer" primitive.
check-adhoc-tag tag:
    ./scripts/check-adhoc-tag.sh "{{tag}}"

# --- Release helpers ---------------------------------------------------------
#
# Cutting a pre-release is cut-prerelease.yml's job, triggered by a VERSION-bumping commit
# landing on main -- see docs/RELEASING.md for the full pipeline. This recipe covers the one
# manual step: promoting a tested pre-release to a full release. Needs `gh` authenticated
# (`gh auth login`).

# Promote a tested pre-release to a full release: flips GitHub's "This is a pre-release"
# checkbox off on the v<version> release, which triggers publish-release.yml's `promote`
# job to retag the pre-release's already-pushed newrelic/network-agent:<version>-rc image
# as <version> and `latest` -- no rebuild, so what ships is byte-identical to what was
# tested.
release-promote version:
    ./scripts/release-promote.sh "{{version}}"
