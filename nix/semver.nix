# Minimal SemVer 2.0.0 "core version" matcher: MAJOR.MINOR.PATCH (no leading zeros,
# aside from a lone "0"), plus an optional -prerelease suffix. Deliberately drops
# SemVer's +build-metadata suffix: this repo already has a separate, non-semver build
# identifier (NETWORK_AGENT_BUILD -- see Makefile/flake.nix), so encoding one inside the
# version string too would just be a second, redundant place for the same concept.
#
# Each dot-separated prerelease identifier gets the same "numeric identifiers MUST NOT
# include leading zeroes" rule SemVer 2.0.0 spells out (spec item 9): identifierPart
# below is "0", or a leading-zero-free numeric run, or -- since the no-leading-zero rule
# only applies to *purely* numeric identifiers -- any run containing at least one
# letter/hyphen (where leading zeros are fine, e.g. "rc01" or "0a"). Without this split,
# "1.2.3-01" would wrongly validate: [0-9A-Za-z-]+ alone doesn't know "01" is numeric.
#
# `pattern` is POSIX ERE (no \d, no non-capturing groups) and deliberately unanchored,
# since it's shared, unmodified, between two different regex engines:
#   - flake.nix's checks.<system>.version-is-semver, via Nix's builtins.match, which
#     already requires a full-string match (no anchors needed/wanted there).
#   - apps.<system>.check-semver (a plain bash script), via `[[ =~ ]]`, which does need
#     explicit ^...$ anchors -- added by that script itself, not baked in here.
{ }:
rec {
  identifierPart = "(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)";

  pattern = "(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-${identifierPart}(\\.${identifierPart})*)?";

  isValid = s: builtins.match pattern s != null;
}
