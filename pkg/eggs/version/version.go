package version

import "fmt"

type VersionInfo struct {
	Version  string
	Date     string
	Build    string // optional: identifies which build produced this binary, e.g. a CI run
	Platform string
	Distro   string
}

func (v VersionInfo) String() string {
	if v.Build != "" {
		return fmt.Sprintf("version %s (build %s)", v.Version, v.Build)
	}
	return fmt.Sprintf("version %s", v.Version)
}
