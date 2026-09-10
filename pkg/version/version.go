package version

import (
	"runtime"

	"github.com/kentik/ktranslate/pkg/eggs/version"
)

// versionStr and dateStr are overridden at link time, e.g.:
//   -ldflags "-X github.com/kentik/ktranslate/pkg/version.versionStr=v2.5.0 \
//             -X github.com/kentik/ktranslate/pkg/version.dateStr=2026-09-09"
// See the Makefile's NETWORK_AGENT_VERSION-derived LDFLAGS.
var (
	versionStr = "dev"
	dateStr    = "unknown"
)

var Version = version.VersionInfo{
	Version: versionStr,
	Date:    dateStr,
	// Derived at runtime rather than baked in at build time -- correct even
	// for cross-compiled builds (e.g. `make arm` from a Darwin host).
	Platform: runtime.GOOS + "/" + runtime.GOARCH,
	Distro:   runtime.Version(),
}
