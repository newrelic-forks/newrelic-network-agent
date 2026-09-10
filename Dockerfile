# build newrelic-network-agent
FROM golang:1.25-alpine AS build
RUN apk add -U make bash libcap
ENV CGO_ENABLED=0
COPY . /src
WORKDIR /src
ARG NETWORK_AGENT_VERSION
ARG NETWORK_AGENT_BUILD
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
RUN addgroup -g 1000 newrelic-network-agent && \
	adduser -D -u 1000 -G newrelic-network-agent -H -h /etc/newrelic-network-agent newrelic-network-agent
#RUN set -eux; \
#	groupadd --gid 1000 newrelic-network-agent; \
#	useradd --home-dir /etc/newrelic-network-agent --gid newrelic-network-agent --no-create-home --uid 1000 newrelic-network-agent

# Some people want to specify an alternative config dir. This lets them override with --build-arg CONFIG-DIR=my-new-dir
ARG CONFIG_DIR=config
COPY --chown=newrelic-network-agent:newrelic-network-agent ${CONFIG_DIR}/ /etc/newrelic-network-agent/

# maxmind db
COPY --from=maxmind /GeoLite2-Country.mmdb /etc/newrelic-network-agent/
COPY --from=maxmind /GeoLite2-ASN.mmdb /etc/newrelic-network-agent/
# snmp
COPY --from=snmp /snmp/profiles /etc/newrelic-network-agent/profiles

# add backwards compatibility symlinks for folks using an snmp.yml from the older image (and "ls" to verify the symlinks are correct and working)
RUN ls -lah /etc/newrelic-network-agent ; ln -sv /etc/newrelic-network-agent /etc/profiles ; ls -lah /etc/profiles/
RUN ln -sv /etc/newrelic-network-agent/mibs.db /etc/mib.db ; ls -lah /etc/mib.db/

COPY --from=build /src/bin/newrelic-network-agent /usr/local/bin/newrelic-network-agent
COPY --from=build /usr/sbin/setcap /usr/sbin/setcap
COPY --from=build /usr/lib/libcap.so.2 /usr/lib/libcap.so.2
RUN setcap cap_net_raw=+ep /usr/local/bin/newrelic-network-agent

COPY --from=build /src/THIRD_PARTY_NOTICES.md /usr/share/doc/newrelic-network-agent/THIRD_PARTY_NOTICES.md

EXPOSE 8082

USER newrelic-network-agent
ENTRYPOINT ["newrelic-network-agent", "-listen", "off", "-mapping", "/etc/newrelic-network-agent/config.json", "-geo", "/etc/newrelic-network-agent/GeoLite2-Country.mmdb", "-udrs", "/etc/newrelic-network-agent/udr.csv", "-api_devices", "/etc/newrelic-network-agent/devices.json", "-asn", "/etc/newrelic-network-agent/GeoLite2-ASN.mmdb", "-log_level", "info", "-geo_region_map", "/etc/newrelic-network-agent/ch_region_mapping.csv.gz", "-geo_city_map", "/etc/newrelic-network-agent/ch_city_mapping.csv.gz"]
