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
			v:    VersionInfo{Version: "0.0.1"},
			want: "version 0.0.1",
		},
		{
			name: "with build identifier",
			v:    VersionInfo{Version: "0.0.1", Build: "42c0e64"},
			want: "version 0.0.1 (build 42c0e64)",
		},
		{
			// Date is deliberately never part of the output -- set here to guard
			// against it creeping back in by accident, not because it should matter.
			name: "date is set but never shown",
			v:    VersionInfo{Version: "0.0.1", Date: "2026-09-23", Build: "42c0e64"},
			want: "version 0.0.1 (build 42c0e64)",
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
