{
  description = "ktranslate investigation playground -- dev tooling only";

  # Scope (see docs/BENCHMARKING_PLAN.md "Nix usage" section):
  #   - a devShell with the tools needed to develop and benchmark this repo
  #   - packages.*.network-agent (nix/network-agent.nix): a real ktranslate binary, built
  #     directly via buildGoModule's own go build (no dependency on the Makefile, which
  #     is Kentik-era tooling that may go away). This is an additional distribution path
  #     and dev convenience, not a replacement: the Makefile, Dockerfile, and
  #     .github/workflows/ci-build.yml remain the only supported way to produce official
  #     released artifacts, pending a separate future decision to change that.
  #   - a NixOS VM test harness for the Tier B synthetic SNMP farm (checks.*, see
  #     nix/tests/snmp-discovery-bench.nix), which reuses packages.*.network-agent as its
  #     collector VM's binary rather than building its own separate copy. The VM tests
  #     themselves are a separate story: on Darwin they run natively via apple-virt/HVF,
  #     not inside that remote builder -- see snmp-discovery-bench.nix's header comment.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ]; # NixOS VM tests only make sense on Linux
      forLinuxSystems = nixpkgs.lib.genAttrs linuxSystems;

      # Name of the env var the devShell exports below, for interactive
      # `make`/`docker build` -- see `make check-version-env-var`, which
      # fails CI if Dockerfile's ARG ever falls out of sync with it.
      versionEnvVar = "NETWORK_AGENT_VERSION";

      # For the devShell export only -- see nix/network-agent.nix for why the
      # package itself deliberately does *not* consume this (or a matching
      # per-commit date): self.rev is the whole repo's HEAD SHA, so using it
      # to stamp Make/Docker builds is fine (those aren't Nix-cached), but
      # baking it into the package would invalidate that derivation's cache
      # on every commit, including ones that never touch Go source.
      version = self.rev or "0.0.0-${self.dirtyShortRev or "unknown"}";
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go # matches go.mod's `go 1.25.0` (nixos-unstable currently ships 1.25.12)
              goperf # provides `benchstat` (and benchsave/benchfilter) -- see BENCHMARKING_PLAN.md
              go-licence-detector # generates THIRD_PARTY_NOTICES.md -- see `just third-party-notices`
              just
              gopls
              delve
            ];
            # So `make all`/`docker build --build-arg NETWORK_AGENT_VERSION`
            # run from inside this shell get a real commit-based version
            # automatically, instead of falling back to Make's own (still
            # perfectly fine, just differently-formatted) git-describe.
            "${versionEnvVar}" = version;
          };
        });

      packages = forLinuxSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          network-agent = import ./nix/network-agent.nix { inherit pkgs; };
        });

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # The test's guest VMs always run Linux, regardless of whether the host
          # actually executing the test is Darwin (local iteration: runs natively via
          # apple-virt/HVF, no linux-builder VM-inside-VM nesting -- see
          # docs/BENCHMARKING_PLAN.md) or Linux (CI: runs natively via kvm). Match the
          # guest's CPU arch to the host's own so Darwin hosts get an accelerated, not
          # emulated, guest.
          linuxSystem = nixpkgs.lib.replaceStrings [ "-darwin" ] [ "-linux" ] system;
        in
        {
          # Sanity check confirming this system can run a NixOS VM test at all before
          # trusting the real, more complex one below -- see nix/tests/minimal-ping.nix.
          minimal-ping = pkgs.testers.runNixOSTest ./nix/tests/minimal-ping.nix;

          # The real 40-node/70-20-10 target from docs/BENCHMARKING_PLAN.md #2.2. 40
          # concurrent VMs is a lot more than any standard machine's core count: ran
          # well over an hour under heavy CPU contention on a local Mac (vs. ~4 minutes
          # at 12 nodes) and, worse, is now confirmed to almost certainly never fit a
          # standard GitHub-hosted runner (4 vCPU) at all -- see
          # snmp-discovery-bench-ci below for why. Kept as an aspirational/local-only
          # target on beefier hardware, not what CI actually runs.
          snmp-discovery-bench = import ./nix/tests/snmp-discovery-bench.nix {
            inherit pkgs;
            inherit (pkgs) lib;
            collectorBin = self.packages.${linuxSystem}.network-agent;
          };

          # Small topology (matches what was actually iterated on and confirmed working
          # end-to-end locally, ~4-4.5 min) -- fast enough for routine local use on a
          # machine with enough cores to spare. NOT what CI runs -- see
          # snmp-discovery-bench-ci below for why 12 concurrent VMs is already too many
          # for a standard 4-vCPU GitHub runner.
          snmp-discovery-bench-smoke = import ./nix/tests/snmp-discovery-bench.nix {
            inherit pkgs;
            inherit (pkgs) lib;
            collectorBin = self.packages.${linuxSystem}.network-agent;
            deviceCount = 12;
          };

          # Sized for a standard GitHub-hosted runner (4 vCPU/16GB), which
          # snmp-discovery-bench-smoke's 12 concurrent VMs already overwhelmed in
          # practice: the collector VM never became interactive within the NixOS test
          # driver's boot-shell wait, which is a *hardcoded* 10 retries x 30s = 5
          # minutes (nixos/lib/test-driver's connect(), not configurable via any NixOS
          # option) -- confirmed via a real CI run, not assumed. deviceCount=8 with the
          # default 70/20 respond/reject split still hits all four categories
          # (respond/reject/drop/unclaimed) at floor(8*0.7)=5 respond, floor(8*0.2)=1
          # reject, 1 drop, 1 unclaimed -- 8 total concurrent VMs (7 named + collector),
          # closer to (though still slightly above) the runner's 4 physical vCPUs.
          snmp-discovery-bench-ci = import ./nix/tests/snmp-discovery-bench.nix {
            inherit pkgs;
            inherit (pkgs) lib;
            collectorBin = self.packages.${linuxSystem}.network-agent;
            deviceCount = 8;
          };
        });
    };
}
