# build ktranslate
FROM golang:1.25-alpine AS build
RUN apk add -U make bash libcap
ENV CGO_ENABLED=0
COPY . /src
WORKDIR /src
ARG NETWORK_AGENT_VERSION
RUN make

# maxmind dbs
FROM alpine:latest AS maxmind
RUN apk add -U curl tar
ENV GEOLITE2_COUNTRY_FILE=GeoLite2-Country.mmdb
ENV GEOLITE2_ASN_FILE=GeoLite2-ASN.mmdb
# MaxMind account id + license key come from BuildKit secrets (never build-args), so the
# values never appear in build logs, image layers, or `docker history` -- even if a step
# fails (build-args get expanded into the printed RUN command; secret files do not).
RUN --mount=type=secret,id=mm_account_id --mount=type=secret,id=mm_license_key \
    set -eu; \
    ACCT="$(cat /run/secrets/mm_account_id 2>/dev/null || true)"; \
    KEY="$(cat /run/secrets/mm_license_key 2>/dev/null || true)"; \
    if [ -z "$KEY" ]; then echo "maxmind license key secret (mm_license_key) not provided"; exit 1; fi; \
    curl -sfL -o /tmp/country.tar.gz -u "$ACCT:$KEY" "https://download.maxmind.com/geoip/databases/GeoLite2-Country/download?suffix=tar.gz"; \
    tar zxf /tmp/country.tar.gz --strip-components 1 -C /; \
    curl -sfL -o /tmp/asn.tar.gz -u "$ACCT:$KEY" "https://download.maxmind.com/geoip/databases/GeoLite2-ASN/download?suffix=tar.gz"; \
    tar zxf /tmp/asn.tar.gz --strip-components 1 -C /

# snmp profiles
FROM alpine:latest AS snmp
ARG KENTIK_SNMP_PROFILE_REPO
RUN apk add -U git

# Opt-in auth: when a `github_token` BuildKit secret is provided (a GitHub token with read
# access to the repo), transparently authenticate GitHub HTTPS clones. This is a complete
# no-op when the secret is absent, so the override/clone logic below is unchanged from
# upstream. The token lives only in this throwaway stage (only /snmp/profiles is copied on).
RUN --mount=type=secret,id=github_token \
    if [ -s /run/secrets/github_token ]; then \
        git config --global url."https://x-access-token:$(cat /run/secrets/github_token)@github.com/".insteadOf "https://github.com/"; \
    fi

# If there is a branch of snmp-profiles to use, switch over here now.
RUN if [ -z "${KENTIK_SNMP_PROFILE_REPO}" ]; then \
    git clone https://github.com/kentik/snmp-profiles /snmp; \
else \
    echo "picking repo ${KENTIK_SNMP_PROFILE_REPO} for snmp profiles"; \
    git clone ${KENTIK_SNMP_PROFILE_REPO} /snmp; \
fi

# main image
FROM alpine:3.23.3
RUN apk add -U --no-cache ca-certificates
RUN addgroup -g 1000 ktranslate && \
	adduser -D -u 1000 -G ktranslate -H -h /etc/ktranslate ktranslate
#RUN set -eux; \
#	groupadd --gid 1000 ktranslate; \
#	useradd --home-dir /etc/ktranslate --gid ktranslate --no-create-home --uid 1000 ktranslate

# Some people want to specify an alternative config dir. This lets them override with --build-arg CONFIG-DIR=my-new-dir
ARG CONFIG_DIR=config
COPY --chown=ktranslate:ktranslate ${CONFIG_DIR}/ /etc/ktranslate/

# maxmind db
COPY --from=maxmind /GeoLite2-Country.mmdb /etc/ktranslate/
COPY --from=maxmind /GeoLite2-ASN.mmdb /etc/ktranslate/
# snmp
COPY --from=snmp /snmp/profiles /etc/ktranslate/profiles

# add backwards compatibility symlinks for folks using an snmp.yml from the older image (and "ls" to verify the symlinks are correct and working)
RUN ls -lah /etc/ktranslate ; ln -sv /etc/ktranslate /etc/profiles ; ls -lah /etc/profiles/
RUN ln -sv /etc/ktranslate/mibs.db /etc/mib.db ; ls -lah /etc/mib.db/

COPY --from=build /src/bin/ktranslate /usr/local/bin/ktranslate
COPY --from=build /usr/sbin/setcap /usr/sbin/setcap
COPY --from=build /usr/lib/libcap.so.2 /usr/lib/libcap.so.2
RUN setcap cap_net_raw=+ep /usr/local/bin/ktranslate

COPY --from=build /src/THIRD_PARTY_NOTICES.md /usr/share/doc/ktranslate/THIRD_PARTY_NOTICES.md

EXPOSE 8082

USER ktranslate
ENTRYPOINT ["ktranslate", "-listen", "off", "-mapping", "/etc/ktranslate/config.json", "-geo", "/etc/ktranslate/GeoLite2-Country.mmdb", "-udrs", "/etc/ktranslate/udr.csv", "-api_devices", "/etc/ktranslate/devices.json", "-asn", "/etc/ktranslate/GeoLite2-ASN.mmdb", "-log_level", "info", "-geo_region_map", "/etc/ktranslate/ch_region_mapping.csv.gz", "-geo_city_map", "/etc/ktranslate/ch_city_mapping.csv.gz"]
