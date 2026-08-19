{
  description = "ktranslate investigation playground -- dev tooling only";

  # Scope, deliberately narrow (see BENCHMARKING_PLAN.md "Nix usage" section):
  #   - a devShell with the tools needed to develop and benchmark this repo
  #   - (elsewhere) a NixOS VM test harness for the Tier B synthetic SNMP farm
  # This flake does NOT build or package ktranslate itself -- the Makefile,
  # Dockerfile, and .github/workflows/ci-build.yml remain the only supported
  # way to produce a real binary/image.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
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
              just
              gopls
              delve
              libpcap # cgo dependency -- mirrors `apt-get install libpcap-dev` in test-on-pr.yml
              pkg-config
            ];
          };
        });
    };
}
