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
# Version comes from the checked-in VERSION file (repo root) -- a plain semver string,
# bumped by a human only when it actually means something, which is exactly why it's safe
# to stamp here without costing cache reuse: unlike flake.nix's self.rev (the whole repo's
# HEAD SHA) or self.lastModifiedDate, VERSION doesn't change on every commit, only on an
# actual version bump. Make/Docker/CI read the same file by default -- see Makefile -- so
# all three build paths agree on one semver source of truth. No per-commit date is stamped
# here at all (pkg/version/version.go's "unknown" default stands as built) -- a real
# timestamp only exists at the whole-repo/commit granularity, which would reintroduce the
# exact cache cost VERSION is designed to avoid.
#
# This is also Tier B's own NixOS VM test fixture (see snmp-discovery-bench.nix) -- one
# definition shared by both uses, rather than the VM test privately building its own copy
# that could silently drift from this one.
#
# The source is filtered down to just go.mod/go.sum/VERSION plus every *.go file, via
# lib.fileset, so that a change to anything else in the repo (docs, workflows, other nix
# files, benchmark fixtures) doesn't invalidate this derivation's build inputs and force
# an unnecessary rebuild -- only an actual change to the Go module (source, dependencies,
# or the version itself) does that. The root for this is a literal relative path (`../.`),
# not flake.nix's `self`: self's Nix type is an attrset (`typeOf self == "set"`, verified
# directly), not a `path`, and lib.fileset requires a real path -- a plain relative path
# written here resolves to one, pointing at the same already-fetched flake source, no
# separate copy or impurity involved.
{ pkgs }:

let
  root = ../.;
  fs = pkgs.lib.fileset;
  version = import ./version.nix { inherit (pkgs) lib; inherit root; };
  goSrc = fs.toSource {
    inherit root;
    fileset = fs.unions [
      (root + "/go.mod")
      (root + "/go.sum")
      (root + "/VERSION")
      (fs.fileFilter (file: file.hasExt "go") root)
    ];
  };
in

pkgs.buildGoModule {
  pname = "ktranslate";
  src = goSrc;
  inherit version;

  vendorHash = "sha256-ZQUnUlWTspAZMO90kEJ6+xukw3gX10+IwTegaCUtEo0=";

  subPackages = [ "cmd/ktranslate" ];

  env.CGO_ENABLED = "0";

  ldflags = [ "-X=github.com/kentik/ktranslate/pkg/version.versionStr=${version}" ];

  doCheck = false; # this package only needs to run, not pass go test
}
