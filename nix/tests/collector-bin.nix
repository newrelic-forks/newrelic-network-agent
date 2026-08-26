# Builds a throwaway ktranslate binary for Tier B's own NixOS VM test fixture --
# NOT the release/product build. That stays make/Dockerfile/ci-build.yml (see
# flake.nix's header comment). `make all` is still the literal build command run
# below (buildPhase just shells out to it) -- Nix's job here is limited to fetching Go
# module deps reproducibly (the standard buildGoModule vendorHash mechanism) and
# providing go/make in the build environment, which is what lets `nix build`
# transparently dispatch the whole thing to a configured remote Linux builder (e.g.
# nix-darwin's linux-builder) when the host system doesn't match the target -- no
# manual SSH/sudo needed, same as any other cross-system Nix build. No
# libpcap/pkg-config needed since the furious/libpcap-dependent SYN scanner was
# replaced with a pure-Go one (upstream #14, "go static") -- CGO_ENABLED=0 produces a
# genuinely static binary now, confirmed by patchelf's own "statically linked" notice
# during fixup.
{ pkgs, src }:

pkgs.buildGoModule {
  pname = "ktranslate-tier-b-fixture";
  version = "0-test-fixture";
  inherit src;

  vendorHash = "sha256-zaAtFYFOY71xVW0Vh8nTwdfT+Lk7C0S1EKKKYca2QsI=";

  nativeBuildInputs = [ pkgs.gnumake ];

  env.KENTIK_KTRANSLATE_VERSION = "tier-b-fixture"; # skips version.sh's git calls, see scripts/version.sh:4-9

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

  doCheck = false; # this fixture only needs to run, not pass go test
}
