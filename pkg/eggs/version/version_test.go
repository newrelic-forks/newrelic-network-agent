package version

import "testing"

func TestVersionInfoString(t *testing.T) {
	cases := []struct {
		name string
		v    VersionInfo
		want string
	}{
		{
			name: "no build identifier",
			v:    VersionInfo{Version: "0.0.1", Date: "2026-09-23"},
			want: "version 0.0.1 built on 2026-09-23",
		},
		{
			name: "with build identifier",
			v:    VersionInfo{Version: "0.0.1", Date: "2026-09-23", Build: "42c0e64"},
			want: "version 0.0.1 built on 2026-09-23 (build 42c0e64)",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := c.v.String(); got != c.want {
				t.Errorf("String() = %q, want %q", got, c.want)
			}
		})
	}
}
