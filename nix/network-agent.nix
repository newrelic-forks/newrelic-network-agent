# Builds the real ktranslate binary via Nix -- this fork's own distributable, referred to
# by its name (network-agent) at the flake package level, while the binary itself keeps its
# actual product name (ktranslate) unchanged. Built directly via buildGoModule's own `go
# build` + `ldflags` machinery, not by shelling out to `make` -- the Makefile is Kentik-era
# tooling that may go away, and everything `make all` does (a plain CGO_ENABLED=0 `go build`
# with two `-X` ldflags) is already native to buildGoModule, so there's nothing to gain by
# depending on it here. No libpcap/pkg-config needed since the furious/libpcap-dependent SYN
# scanner was replaced with a pure-Go one (upstream #14, "go static") -- CGO_ENABLED=0
# produces a genuinely static binary.
#
# Deliberately does not stamp a commit-specific version/date into the binary via ldflags
# (pkg/version/version.go's own "dev"/"unknown" defaults stand as built). self.rev is the
# whole repo's HEAD SHA, so using it here would change this derivation's build inputs --
# and invalidate its Nix cache entry -- on every commit to the repo, including ones that
# never touch Go source at all. Nix's own provenance (the derivation hash, the flake lock)
# already records exactly what was built; a baked-in string would be strictly weaker and
# cost cache reuse across unrelated history for no benefit. Make/Docker builds don't have
# this tension (see Makefile), so they still stamp NETWORK_AGENT_VERSION/-DATE freely.
#
# This is also Tier B's own NixOS VM test fixture (see snmp-discovery-bench.nix) -- one
# definition shared by both uses, rather than the VM test privately building its own copy
# that could silently drift from this one.
#
# The source is filtered down to just go.mod/go.sum plus every *.go file, via lib.fileset,
# so that a change to anything else in the repo (docs, workflows, other nix files,
# benchmark fixtures) doesn't invalidate this derivation's build inputs and force an
# unnecessary rebuild -- only an actual change to the Go module (source or dependencies)
# does that, which is exactly the set this package cares about. The root for this is a
# literal relative path (`../.`), not flake.nix's `self`: self's Nix type is an attrset
# (`typeOf self == "set"`, verified directly), not a `path`, and lib.fileset requires a
# real path -- a plain relative path written here resolves to one, pointing at the same
# already-fetched flake source, no separate copy or impurity involved.
{ pkgs }:

let
  root = ../.;
  fs = pkgs.lib.fileset;
  goSrc = fs.toSource {
    inherit root;
    fileset = fs.unions [
      (root + "/go.mod")
      (root + "/go.sum")
      (fs.fileFilter (file: file.hasExt "go") root)
    ];
  };
in

pkgs.buildGoModule {
  pname = "ktranslate";
  src = goSrc;
  version = "unstable";

  vendorHash = "sha256-ZQUnUlWTspAZMO90kEJ6+xukw3gX10+IwTegaCUtEo0=";

  subPackages = [ "cmd/ktranslate" ];

  env.CGO_ENABLED = "0";

  doCheck = false; # this package only needs to run, not pass go test
}
