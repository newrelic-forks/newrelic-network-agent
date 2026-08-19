# Benchmarking Plan — Measuring Before Optimizing

Branch: `investigation`. Companion to `DISCOVERY_PERFORMANCE_PLAN.md`. That document
catalogs suspected bottlenecks with file:line citations (IDs `A1`–`A56` in its Appendix);
this document is the measurement layer that turns "we think X is slow because of Y" into
"here is the before/after number for Y, with statistical confidence." No remediation from
the other plan should be described as done until it has a benchmark result attached.

---

## 0. Principle

Every phase in `DISCOVERY_PERFORMANCE_PLAN.md` §4 gets a benchmark run before the change and
after the change, compared with `benchstat` (§3 below). "It should be faster" is not
evidence; a `benchstat old.txt new.txt` table is.

Two tiers, because "network-bound" and "code-bound" need different treatment:

- **Tier A** — deterministic Go micro-benchmarks that isolate the actual bottleneck *logic*
  (semaphore sizing, serial loops, regex recompilation, channel fan-in) behind an injectable
  fake in place of the real network call. Fast (seconds), zero flakiness, safe to run on
  every PR.
- **Tier B** — a small synthetic SNMP device farm, run as real NixOS virtual machines on a
  real virtual network, driving the actual `Discover()`/`runSnmpPolling` code paths with
  real SNMP/TCP traffic. Slower, has real-world timing variance, run on demand rather than
  gating every PR — but it's the only tier that can faithfully reproduce the *specific*
  network behavior driving the reported symptom (see §2.2).

---

## 1. Nix usage — scope decision (for now)

Nix is being introduced **only** for two things:

1. **Tier B's benchmark harness** — the NixOS VM test that stands up the synthetic device
   farm (§2.2).
2. **A `devShell`** — a reproducible local dev environment (Go toolchain version, `benchstat`,
   lint tools, `libpcap-dev` for cgo — see `.github/workflows/test-on-pr.yml`'s
   `sudo apt-get install make libpcap-dev` step, which a `devShell` should make unnecessary
   to remember/re-run manually) so anyone picking up this repo gets the same tool versions
   without hand-installing things.

Nix is explicitly **not** being adopted for building or packaging the product. The
existing `Makefile` + `Dockerfile` + `.github/workflows/ci-build.yml` remain the only
supported way to build a real ktranslate binary/image. Concretely, this means the Tier B
NixOS test **does not compile ktranslate via Nix** (e.g. no `buildGoModule` of this repo) —
it takes an already-built binary (built the normal way, `make`, exactly as
`test-on-pr.yml` already does) as an input, and only uses Nix to orchestrate the VMs/network
around that binary. This keeps "what compiles the product" singular and keeps Nix's blast
radius limited to test infrastructure, which matters for a team that just inherited this
codebase and doesn't need a second build system to learn on top of Go+Docker.

This scope is intentionally narrow for now. Revisit if/when there's a concrete reason to
consider Nix for build/packaging (e.g. reproducible release artifacts, cross-compilation
pain) — that would be a separate decision with its own tradeoffs, not a side effect of
adopting it for benchmarking.

---

## 2. The two tiers, in detail

### 2.1 Tier A — deterministic micro-benchmarks

Standard `func BenchmarkX(b *testing.B)`, run via `go test -bench=. -benchmem -run=^$`.
No Nix, no new infra — pure Go, same toolchain as the rest of the repo.

| Benchmark target | Bottleneck ref | File to fake | What's measured | Status |
|---|---|---|---|---|
| Pre-scan fan-out | `A7`, `A52`-`A56` (`disco.go:157-163`; vendored `furious/scan/scan-device.go:37-132`) | Fake probe with configurable latency, gated by a shared `osCeiling` semaphore modeling the finite OS resource a real dial contends for | `BenchmarkPreScanFanOut` (`disco_bench_test.go`): unbounded vs. bounded pool, at 65,536 addresses / ~7.6% live | Done |
| Verification loop `doubleCheckHost` | `A8`, `A9`, `A12`-`A14` (`disco.go:172,176-181,244-390`) | Fake probe, same latency model | `BenchmarkVerificationLoop` (`disco_bench_test.go`): `threads=4` (shipped default, `A49`/`A50`) vs. 64/256 | Done |
| CIDR serialization | `A6` (`disco.go:141`) | Same fake prober | `BenchmarkCIDRSerialization` (`disco_bench_test.go`): serial (current) vs. parallel across 4 CIDRs | Done |
| Restart storm / device (re)init | `A23`-`A27` (`snmp.go:176,205,226,231,310,316`) | **No fake needed** — calls the real `snmp_util.InitSNMP` (confirmed network-free: `gosnmp.Connect()` only opens a local UDP socket) and the real, no-op `apic.EnsureDevice`; does *not* call the real `launchSnmp`, which would leak background goroutines each waiting out a real multi-second SNMP timeout | `BenchmarkDeviceInitLoop` (`snmp_bench_test.go`): devices/sec at fleet sizes 100/1,000/5,000 | Done |
| Regex/profile matching | `A36` (`mibs/profile.go:302-337`, lines 305/322) | None — use real loaded profiles | `BenchmarkFindProfile_MatchesList`, `BenchmarkFindProfile_FleetParse` (`mibs/profile_bench_test.go`) | Done |
| Consumer/backpressure | `A38`, `A40`-`A45` (`kkc.go:226,229,777-786,556-576,511-553`) | Fake per-batch cost in place of real `handleInput` work (constructing a real `*KTranslate` fixture wasn't worth it just for this) | `BenchmarkConsumerThroughput` (`kkc_bench_test.go`): `consumers=1` (shipped default, `A46`) vs. 4/16, at producer counts 100/1,000/5,000 | Done |

All four files exist now:

```
pkg/inputs/snmp/disco_bench_test.go        # pre-scan fan-out, doubleCheckHost, CIDR serialization
pkg/inputs/snmp/snmp_bench_test.go         # restart-storm / device (re)init loop
pkg/inputs/snmp/mibs/profile_bench_test.go # FindProfile / checkMatch
pkg/cat/kkc_bench_test.go                  # consumer throughput / backpressure
```

A first version of the pre-scan fan-out benchmark modeled the probe as a bare
`time.Sleep`, with no shared resource constraint — and found "unbounded" *faster*
than any bounded pool, which would have been a misleading result to leave standing.
`time.Sleep` costs nothing in real OS resources, so Go's scheduler handles tens of
thousands of concurrent sleepers for free; a real dial doesn't get that deal. The
`osCeiling` semaphore in the final version applies the same finite-resource
constraint to every variant, which flips the result to the honest, defensible one:
unbounded fan-out buys no throughput over a correctly-sized pool, only extra
`B/op`/`allocs/op` for goroutines that never needed to exist. Worth remembering when
writing the next Tier A fake — a fake that's *too* free-lunch can quietly measure the
wrong thing.

`benchmarks/baseline.txt` covers all of the above, captured inside the Nix devShell
with `-count=5` (not 10, to keep the combined run under a few minutes — the earlier
`-count=10` run across just the mibs package took ~2 minutes; across all three
packages it exceeded 5). `-count=5` is enough to store as a reference baseline, but
`benchstat` will report `± ∞` (needs ≥6 samples for a confidence interval) — any real
before/after comparison should re-run both sides with `-count=10`+ for statistical
confidence, per §3.

### 2.2 Tier B — NixOS VM synthetic device farm

**Why not just fake the network in Go for this too:** the dominant real-world cost
identified in the other plan (§2.1/§2.2 there) hinges on a distinction a Go-level fake on
loopback cannot reproduce — a **silently dropped** packet (firewalled/filtered, the common
enterprise case, forces the full `timeout_ms` wait) vs. an **actively rejected** one
(closed port, fast RST/ICMP-unreachable). On loopback, "nothing is listening" always fails
fast — you cannot get the slow case without a real kernel and a real drop rule. NixOS VM
tests give you both, on a real virtual network, reproducibly.

**Topology:**
- One `collector` node: runs the pre-built ktranslate binary (see §1 — built by `make`, not
  by Nix) against the farm's address range, using a real `snmp.yml` discovery config that
  mirrors the shipped defaults (`config/snmp-base.yaml`, `deployment/docker/snmp-base-nr.yaml`
  — same `threads`, `timeout_ms`, `retries`, `check_all_ips` values, so the benchmark is
  measuring the actual shipped configuration, not a hypothetical one).
- N `device` nodes: run real `net-snmp`'s `snmpd` (packaged in nixpkgs) with a minimal MIB
  config, each on its own address in the farm's virtual subnet.
- A configurable subset of addresses are **silent**: either no node at all (just an
  unclaimed address on the virtual network — a real "nothing there" case) or a node with an
  explicit `networking.firewall`/`iptables -j DROP` rule on UDP/161 and TCP/1 (the "actively
  firewalled" case). Another subset is **rejecting** (node up, nothing listening on those
  ports — fast RST). The rest **respond** (real `snmpd`).
- Node/address counts and the respond:reject:drop ratio are parameters (generate `nodes`
  attrs programmatically via `builtins.listToAttrs (map ... (lib.range 1 N))`), so the same
  test file can be run at different scales.

**Mechanics (`pkgs.testers.runNixOSTest`):**
```nix
# sketch — not final, illustrates the shape described above
testers.runNixOSTest {
  name = "snmp-discovery-bench";
  nodes = {
    collector = { ... }: { /* runs the pre-built ktranslate binary against the farm */ };
  } // (generated device/reject/drop nodes);
  testScript = ''
    # start all nodes, wait for snmpd units on "respond" nodes
    # run collector's discovery, capture start/end timestamps from its log
    # copy the report out via machine.copy_from_vm / a shared store path
  '';
}
```
Run via `nix build .#checks.x86_64-linux.snmp-discovery-bench` (or `nix flake check`).

**Scale ceiling:** each node is a full VM — RAM/CPU bound, not something you scale to
5,000 or 65,000 on a shared CI runner. Realistic target: tens to a few hundred nodes with a
representative drop/reject/respond mix. That's enough to get a *real, trustworthy* IPs/sec
and devices/sec number to compare against the field report and against post-fix runs — it's
a calibration point, not a literal full-scale replica. See §5 for how this combines with
Tier A to reason about full scale.

**CI feasibility (verified, not assumed):** the official Nix tutorial for this feature
(nix.dev, "Integration testing with NixOS virtual machines") notes hardware acceleration is
required and many CIs lack it, pointing at `cachix/install-nix-action`'s guidance for
GitHub Actions specifically. Checking that action's current README directly: it lists
*"Enables KVM on supported machines: run VMs and NixOS tests with full
hardware-acceleration"* as a feature, `enable_kvm: true` is the **default**, and its FAQ
gives the exact recipe:
```yaml
- uses: cachix/install-nix-action@v31
  with:
    enable_kvm: true
    extra_nix_config: "system-features = nixos-test benchmark big-parallel kvm"
```
So on standard GitHub-hosted `ubuntu-latest` runners this runs with real KVM acceleration,
not a slow software-emulation fallback.

---

## 3. Tooling and reporting

- `go test -bench=. -benchmem -run=^$ ./...` — Tier A. `-run=^$` skips normal tests so only
  benchmarks execute.
- `benchstat` (`golang.org/x/perf/cmd/benchstat`, not currently installed — confirmed via
  `which benchstat`) turns two benchmark runs into a statistical diff (mean, variance,
  percent change with confidence), which is what makes a claim like "Phase 1 made
  verification 40% faster" defensible rather than anecdotal. Workflow for any change:
  1. On the pre-change code, run benchmarks, save `old.txt`.
  2. Make the change.
  3. Run benchmarks again, save `new.txt`.
  4. `benchstat old.txt new.txt` → paste the table into the PR description as evidence.
- Tier B's report is simpler (one real number per run, not a statistical distribution over
  many fast iterations): timestamp, node count, drop:reject:respond ratio, elapsed time,
  IPs/sec, devices/sec found. Append each run to a tracked file (`benchmarks/history.md` or
  `.csv`) so there's a trend line across changes over time, rather than a single
  point-in-time claim.

### CI wiring

This repo's CI on `investigation` is deliberately manual/opt-in
(`.github/workflows/test-on-pr.yml` is `workflow_dispatch`-only; auto-triggers were
disabled per `PLAYGROUND.md`; `.github/workflows/ci-build.yml` runs on
`push: [investigation]` + `pull_request`). A new benchmark workflow should match that
convention rather than gate every push:

- New `.github/workflows/benchmark.yml`, `workflow_dispatch` (+ optionally
  `push: [investigation]` like `ci-build.yml`).
- **Tier A job**: checkout → `actions/setup-go` → `go install golang.org/x/perf/cmd/benchstat@latest`
  → run benchmarks → if a baseline (`benchmarks/baseline.txt`) is checked in, diff with
  `benchstat` and write the table to `$GITHUB_STEP_SUMMARY` (shows directly in the Actions
  run, no artifact download needed) → upload raw `.txt` files as artifacts too.
- **Tier B job**: separate (slower, noisier) job — checkout → `cachix/install-nix-action@v31`
  (`enable_kvm: true`) → `make` (build the real binary the normal way, per §1) →
  `nix build .#checks.x86_64-linux.snmp-discovery-bench` (or `nix flake check`) → append
  the result to `benchmarks/history.md` and upload as an artifact. Consider a `schedule`
  (nightly) trigger in addition to manual, since it's the one that tracks drift over time
  without needing someone to remember to run it.
- Regression policy: start by just reporting the diff for humans to judge (this is an
  investigation branch, not a release pipeline) rather than failing the build on a
  threshold. Tighten later once the numbers are trusted.
- Caching: nixpkgs' own packages (the NixOS base system, `net-snmp`) come from the public
  `cache.nixos.org` substituter by default — no project-specific binary cache (e.g. Cachix)
  is needed to get a fast *base* system. Only worth adding a project cache later if the test
  derivation itself grows expensive to rebuild across runs.

---

## 4. Proposed file layout

```
flake.nix                                   # devShell + Tier B check, nothing else
flake.lock
nix/devshell.nix                            # Go toolchain, benchstat, lint tools, libpcap
nix/tests/snmp-discovery-bench.nix          # the runNixOSTest definition (§2.2)
pkg/inputs/snmp/disco_bench_test.go         # Tier A
pkg/inputs/snmp/snmp_bench_test.go          # Tier A
pkg/inputs/snmp/mibs/profile_bench_test.go  # Tier A
pkg/cat/kkc_bench_test.go                   # Tier A
benchmarks/baseline.txt                     # Tier A baseline for benchstat diffing
benchmarks/history.md                       # Tier B run history (append-only)
.github/workflows/benchmark.yml
```

---

## 5. How Tier A and Tier B combine to reason about full scale

Tier B gives a real, small-scale (tens–hundreds of nodes) throughput number with faithful
network behavior. Tier A gives a cheap, large-scale (thousands of synthetic addresses/
devices) number with faked network behavior but the *same* concurrency-cap/serialization
logic as production. Use Tier B to confirm Tier A's fake is calibrated correctly (e.g. "at
80 nodes with a realistic drop ratio, Tier B says X seconds; does Tier A's fake-latency
model predict something close to X when configured with the same node count and ratio?")
— once that calibration checks out, trust Tier A's extrapolation to 5,000 devices / 65,000
IPs, since literally running that many VMs isn't practical in CI.

---

## 6. Validating the benchmarks themselves

- Tier A: run each benchmark with `-count=10` and check `benchstat`'s own variance output
  before trusting a single run — Go benchmarks can be noisy on shared CI runners; a change
  claimed as "faster" should show up as a statistically significant delta, not just a
  different single sample.
- Tier B: run the same topology twice before changing anything, to establish the run-to-run
  variance baseline for a real network/VM test (expect more variance than Tier A — real
  timeouts, real scheduler jitter) before treating any single before/after pair as
  conclusive.

---

## 7. Open questions / follow-ups before implementation

- Exact mechanism for getting the pre-built ktranslate binary into the `collector` VM
  (shared Nix store path vs. a virtiofs/9p mount vs. baking it into a throwaway NixOS image
  at test-build time via `pkgs.runCommand` that just copies in an externally-provided path —
  functionally equivalent, pick whichever is least fiddly once someone's hands-on with it;
  none of these options involve Nix *compiling* the binary, consistent with §1).
  This is genuinely just an implementation detail; not decision-worthy up front.
- Where the `benchmarks/baseline.txt` Tier A baseline comes from initially (a checked-in
  snapshot from current `main`/`investigation` HEAD before any Phase 1-5 change lands).
- Whether `benchmarks/history.md` should be git-committed (simple, visible in PR diffs) or
  kept as a rolling CI artifact only (avoids repo churn from every run) — leaning
  git-committed since it's low-frequency (manual/nightly) and the trend-over-time value
  depends on it being durable and diffable.

---

## Appendix — cross-reference to `DISCOVERY_PERFORMANCE_PLAN.md`

This document deliberately does not repeat the bottleneck citations (`A1`-`A56`) already
recorded there — see that file's Appendix for the exact `file:line` source of every
bottleneck a Tier A or Tier B benchmark in this document is designed to measure.
