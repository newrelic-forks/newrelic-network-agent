#!/usr/bin/env bash
# Downloads the MaxMind GeoLite2 databases into $1, for a local `docker build` --
# see `just maxmind-dbs` for the recipe that calls this.
set -euo pipefail

dest="$1"

if [ -z "${MM_DOWNLOAD_KEY:-}" ]; then
  echo "MM_DOWNLOAD_KEY (MaxMind license key) not set" >&2
  exit 1
fi

mkdir -p "$dest"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -sfL -o "$tmp/country.tar.gz" -u "${MM_ACCOUNT_ID:-}:$MM_DOWNLOAD_KEY" "https://download.maxmind.com/geoip/databases/GeoLite2-Country/download?suffix=tar.gz"
tar zxf "$tmp/country.tar.gz" --strip-components 1 -C "$dest"
curl -sfL -o "$tmp/asn.tar.gz" -u "${MM_ACCOUNT_ID:-}:$MM_DOWNLOAD_KEY" "https://download.maxmind.com/geoip/databases/GeoLite2-ASN/download?suffix=tar.gz"
tar zxf "$tmp/asn.tar.gz" --strip-components 1 -C "$dest"
