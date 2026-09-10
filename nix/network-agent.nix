{ pkgs, buildRev }:
let
  root = ../.;
  fs = pkgs.lib.fileset;
  versionFile = root + "/VERSION";
  version = pkgs.lib.strings.trim (builtins.readFile versionFile);
  goSrc = fs.toSource {
    inherit root;
    fileset = fs.unions [
      (root + "/go.mod")
      (root + "/go.sum")
      versionFile
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
    "-X=github.com/newrelic-forks/newrelic-network-agent/pkg/version.versionStr=${version}"
    "-X=github.com/newrelic-forks/newrelic-network-agent/pkg/version.buildStr=${buildRev}"
  ];

  doCheck = false; # only needs to run, not pass go test
}
