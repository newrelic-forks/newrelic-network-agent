# Builds the real ktranslate binary via Nix -- this fork's own distributable, referred to
# by its name (network-agent) at the flake package level, while the binary itself keeps its
# actual product name (ktranslate) unchanged. `make all` is still the literal build command
# run below (buildPhase just shells out to it) -- Nix's job here is limited to fetching Go
# module deps reproducibly (the standard buildGoModule vendorHash mechanism) and providing
# go/make in the build environment, which is what lets `nix build` transparently dispatch
# the whole thing to a configured remote Linux builder (e.g. nix-darwin's linux-builder)
# when the host system doesn't match the target -- no manual SSH/sudo needed, same as any
# other cross-system Nix build. No libpcap/pkg-config needed since the furious/libpcap-
# dependent SYN scanner was replaced with a pure-Go one (upstream #14, "go static") --
# CGO_ENABLED=0 produces a genuinely static binary now, confirmed by patchelf's own
# "statically linked" notice during fixup.
#
# This is also Tier B's own NixOS VM test fixture (see snmp-discovery-bench.nix) -- one
# definition shared by both uses, rather than the VM test privately building its own copy
# that could silently drift from this one.
{ pkgs, src, versionEnvVar, version ? "nix-build" }:

pkgs.buildGoModule {
  pname = "ktranslate";
  inherit src version;

  vendorHash = "sha256-ZQUnUlWTspAZMO90kEJ6+xukw3gX10+IwTegaCUtEo0=";

  nativeBuildInputs = [ pkgs.gnumake ];

  # versionEnvVar's name is threaded from flake.nix (see its `versionEnvVar`
  # binding) rather than hardcoded here, so the devShell (which exports it
  # too, for `make`/`docker build` run interactively) and this package can't
  # independently drift on the name. Setting it directly (rather than
  # leaving it to Make's own git-describe fallback) matters here specifically
  # because this `src` is a Nix store copy with no `.git` to describe.
  env = { "${versionEnvVar}" = version; };

  buildPhase = ''
    runHook preBuild
    make all
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp bin/ktranslate $out/bin/ktranslate
    runHook postInstall
  '';

  doCheck = false; # this package only needs to run, not pass go test
}
