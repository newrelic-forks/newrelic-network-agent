# Single source of truth for reading VERSION (the checked-in semver string at the repo
# root), so flake.nix's devShell export and network-agent.nix's package build can't
# independently drift on how it's parsed (e.g. one trimming whitespace differently than
# the other).
{ lib, root }:
lib.strings.trim (builtins.readFile (root + "/VERSION"))
