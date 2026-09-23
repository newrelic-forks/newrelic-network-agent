# Builds the ktranslate binary via buildGoModule directly, not by shelling out to `make`
# (which may go away) -- everything `make all` does is already native here. No
# libpcap/pkg-config needed since the SYN scanner is pure Go (upstream #14).
#
# versionStr comes from the checked-in VERSION file; buildRev (passed in by flake.nix --
# self.rev/dirtyShortRev, pure, no --impure needed) is a commit identifier stamped
# alongside it, so two builds sharing the same VERSION (normal between bumps: VERSION only
# changes on a real release) can still be told apart by their own `-version` output, not
# just by comparing Nix store paths. This does mean the package rebuilds on every commit
# rather than only when VERSION/go.mod/go.sum/*.go change -- accepted deliberately: this is
# documented dev convenience, not the official release path (see flake.nix's Scope
# comment), and nothing else in the repo depends on it staying cache-stable across
# unrelated commits. `root` below is a literal relative path rather than `self` because
# `self` is an attrset, not a Nix `path`, and lib.fileset needs a real path.
#
# `src` is filtered to go.mod/go.sum/VERSION/*.go via lib.fileset, so unrelated changes
# (docs, workflows, etc.) don't force a rebuild on their own -- buildRev changing every
# commit regardless is the actual, unavoidable source of the rebuild-every-commit behavior
# above, not this filtering. Also Tier B's VM test fixture -- see snmp-discovery-bench.nix.
{ pkgs, buildRev }:

let
  root = ../.;
  fs = pkgs.lib.fileset;
  version = pkgs.lib.strings.trim (builtins.readFile (root + "/VERSION"));
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
  ldflags = [
    "-X=github.com/kentik/ktranslate/pkg/version.versionStr=${version}"
    "-X=github.com/kentik/ktranslate/pkg/version.buildStr=${buildRev}"
  ];

  doCheck = false; # only needs to run, not pass go test
}
