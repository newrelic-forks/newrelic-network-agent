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
# `version`/`date` are plain strings, not env vars: unlike Make/Docker (which read
# NETWORK_AGENT_VERSION from the environment, since a human or CI sets it), this derivation
# is always built with an explicit, already-resolved value from flake.nix -- no impure
# `builtins.getEnv` needed anywhere in this file or its caller. Nix's own `self.rev`
# (flake.nix) already gives a fully deterministic version per commit, so there's no
# override path to plumb through: a release is just building the tagged commit, and the
# commit SHA is sufficient provenance (`git tag --points-at <sha>` recovers the tag name
# if ever needed) -- see flake.nix for exactly what's passed in.
#
# This is also Tier B's own NixOS VM test fixture (see snmp-discovery-bench.nix) -- one
# definition shared by both uses, rather than the VM test privately building its own copy
# that could silently drift from this one.
{ pkgs, src, version, date }:

pkgs.buildGoModule {
  pname = "ktranslate";
  inherit src version;

  vendorHash = "sha256-ZQUnUlWTspAZMO90kEJ6+xukw3gX10+IwTegaCUtEo0=";

  subPackages = [ "cmd/ktranslate" ];

  env.CGO_ENABLED = "0";

  ldflags = [
    "-X=github.com/kentik/ktranslate/pkg/version.versionStr=${version}"
    "-X=github.com/kentik/ktranslate/pkg/version.dateStr=${date}"
  ];

  doCheck = false; # this package only needs to run, not pass go test
}
