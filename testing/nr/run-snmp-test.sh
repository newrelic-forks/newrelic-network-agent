#!/usr/bin/env bash
# testing/nr/run-snmp-test.sh
#
# Manual/local harness for running this fork's ktranslate against real SNMP
# devices and a real New Relic account -- used while iterating on NR-612348.
# See testing/nr/README.md for one-time setup (secretspec + 1Password)
# before running this.
#
# Usage:
#   secretspec run -- testing/nr/run-snmp-test.sh up   --site NAME --cidr CIDR --nr-account-id ID \
#       [--nr-region REGION] [--image upstream|<local-tag>] [--profiles-dir DIR]
#   secretspec run -- testing/nr/run-snmp-test.sh down --site NAME
#
# --image upstream pulls the public kentik/ktranslate:v2 image. Anything
# else is used as-is as a local image reference -- e.g. ntranslate:main,
# ntranslate:develop, or ntranslate:<scratch-branch>, built with
# ./build-fork-image.sh <git-ref>. No pull is attempted for these; build (or
# rebuild) them yourself first.
#
# NEW_RELIC_API_KEY and SNMP_COMMUNITY must already be in the environment --
# `secretspec run --` is what puts them there. Never hardcode either, and
# never add a command here that would print them (no `env`, no dumping the
# rendered config, no `set -x`).

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_ROOT="$DIR/state"

usage() {
  cat <<'USAGE' >&2
Usage:
  run-snmp-test.sh up   --site NAME --cidr CIDR --nr-account-id ID [--nr-region REGION] [--image upstream|<local-tag>] [--profiles-dir DIR]
  run-snmp-test.sh down --site NAME

Always run via: secretspec run -- testing/nr/run-snmp-test.sh ...
USAGE
  exit 1
}

# Escapes a value for safe use as a sed replacement with a `|` delimiter.
sed_escape() {
  printf '%s' "$1" | sed -e 's/[\&|]/\\&/g'
}

[ $# -ge 1 ] || usage
action="$1"; shift

site=""
cidr=""
nr_account_id=""
nr_region="us_stage"
image="upstream"
profiles_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --site) site="$2"; shift 2 ;;
    --cidr) cidr="$2"; shift 2 ;;
    --nr-account-id) nr_account_id="$2"; shift 2 ;;
    --nr-region) nr_region="$2"; shift 2 ;;
    --image) image="$2"; shift 2 ;;
    --profiles-dir) profiles_dir="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[ -n "$site" ] || { echo "--site is required" >&2; usage; }

container="ktranslate-snmp-${site}"
site_state_dir="$STATE_ROOT/$site"
snmp_config="$site_state_dir/snmp.yaml"

case "$action" in
  down)
    if docker ps -aq --filter "name=^${container}\$" | grep -q .; then
      docker stop "$container" >/dev/null
      docker rm "$container" >/dev/null
      echo "Stopped and removed $container"
    else
      echo "$container is not running -- nothing to do"
    fi
    exit 0
    ;;
  up) ;;
  *) usage ;;
esac

[ -n "$cidr" ] || { echo "--cidr is required for 'up'" >&2; usage; }
[ -n "$nr_account_id" ] || { echo "--nr-account-id is required for 'up'" >&2; usage; }

: "${NEW_RELIC_API_KEY:?NEW_RELIC_API_KEY is not set -- run this via 'secretspec run --'}"
: "${SNMP_COMMUNITY:?SNMP_COMMUNITY is not set -- run this via 'secretspec run --'}"

if docker ps -aq --filter "name=^${container}\$" | grep -q .; then
  echo "$container already exists -- run 'down --site $site' first" >&2
  exit 1
fi

mkdir -p "$site_state_dir"

if [ -f "$snmp_config" ]; then
  echo "Reusing existing discovered state at $snmp_config (delete it to force a fresh rediscovery)"
else
  echo "No existing state for site '$site' -- rendering a fresh discovery-only config"
  sed \
    -e "s|__SITE_CIDR__|$(sed_escape "$cidr")|" \
    -e "s|__SITE_COMMUNITY__|$(sed_escape "$SNMP_COMMUNITY")|" \
    "$DIR/snmp-template.yaml" > "$snmp_config"
fi

if [ "$image" = "upstream" ]; then
  docker_image="kentik/ktranslate:v2"
  pull_flag=(--pull=always)
else
  docker_image="$image"
  pull_flag=()
fi

volume_flags=(-v "$snmp_config:/snmp-base.yaml")
if [ -n "$profiles_dir" ]; then
  volume_flags+=(-v "$profiles_dir:/etc/ktranslate/profiles:ro")
fi

docker run -d --name "$container" --restart unless-stopped "${pull_flag[@]}" \
  -p 162:1620/udp \
  "${volume_flags[@]}" \
  -e NEW_RELIC_API_KEY="$NEW_RELIC_API_KEY" \
  "$docker_image" \
  -snmp /snmp-base.yaml \
  -snmp_discovery_on_start=true \
  -nr_account_id="$nr_account_id" \
  -service_name=snmp \
  -snmp_discovery_min=180 \
  -nr_region="$nr_region" \
  -sinks=new_relic \
  -format=new_relic_metric \
  -log_level debug \
  -tee_logs=true

echo "Started $container ($docker_image) for site '$site' -- state at $snmp_config"
