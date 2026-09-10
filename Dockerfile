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
#
# Downloaded and cached by the calling workflow (see ci-build.yml / publish-release.yml),
# via actions/cache -- not inside this build at all, since a BuildKit `--mount=type=cache`
# doesn't survive across CI runs (each job gets a fresh BuildKit daemon) and isn't included
# in `--cache-from`/`--cache-to` exports, so it can never actually persist here. This stage
# just stages the already-downloaded files from the build context for the COPY below.
# Building locally: run `just maxmind-dbs` first to populate maxmind-dbs/.
FROM scratch AS maxmind
COPY maxmind-dbs/GeoLite2-Country.mmdb /GeoLite2-Country.mmdb
COPY maxmind-dbs/GeoLite2-ASN.mmdb /GeoLite2-ASN.mmdb

# snmp profiles
FROM alpine:latest AS snmp
ARG NR_SNMP_PROFILE_REPO
RUN apk add -U git

# Both the upstream default and newrelic-forks/snmp-profiles are public repos, so this
# clones anonymously -- no token/auth needed.
RUN if [ -z "${NR_SNMP_PROFILE_REPO}" ]; then \
        git clone https://github.com/newrelic-forks/snmp-profiles /snmp; \
    else \
        echo "picking repo ${NR_SNMP_PROFILE_REPO} for snmp profiles"; \
        git clone ${NR_SNMP_PROFILE_REPO} /snmp; \
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
