MODULE := github.com/kentik/ktranslate

# NETWORK_AGENT_VERSION: set by the nix devShell (matches the network-agent
# flake package's own version), a Docker --build-arg, or CI. Falls back to
# git describe for a plain checkout with none of those. See
# `check-version-env-var` below for the one place this name must also match.
NETWORK_AGENT_VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -X '$(MODULE)/pkg/version.versionStr=$(NETWORK_AGENT_VERSION)' -X '$(MODULE)/pkg/version.dateStr=$(shell date -u +%Y-%m-%dT%H:%M:%SZ)'

.PHONY: all
all:
	CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o bin/ktranslate ./cmd/ktranslate

.PHONY: windows
windows:
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags "$(LDFLAGS)" -o bin/ktranslate.exe ./cmd/ktranslate

.PHONY: arm
arm:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags "-s -w $(LDFLAGS)" -o bin/ktranslate ./cmd/ktranslate

.PHONY: print-version-env-var
print-version-env-var:
	@echo NETWORK_AGENT_VERSION

.PHONY: check-version-env-var
check-version-env-var:
	@grep -qx "ARG $$(make -s print-version-env-var)" Dockerfile || \
	  { echo "Dockerfile's ARG doesn't match Makefile's version env var" >&2; exit 1; }

.PHONY: test
test: check-version-env-var
	go test ./cmd/... ./pkg/...

.PHONY: bench
bench:
	go test -bench=. ./cmd/... ./pkg/...

.PHONY: ktranslate
ktranslate:
	go install ./cmd/ktranslate

.PHONY: clean
clean:
	rm -f bin/ktranslate

.PHONY: generate
generate:
	go generate ./...

.PHONY: install
install:
	mkdir -p $(DESTDIR)/usr/local/bin
	install -m 0755 bin/ktranslate $(DESTDIR)/usr/local/bin

.PHONY: docker
docker: all
	docker pull ubuntu:20.04
	docker build -t ktranslate:v2 -f Dockerfile .
