package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// buildStaticBinary compiles the real network-agent entrypoint the same way every
// shipped build path does post-furious-removal (Makefile's all/windows/arm
// targets, Dockerfile): CGO_ENABLED=0. It exists to catch "the binary doesn't
// even start" regressions, not to exercise features.
func buildStaticBinary(t *testing.T) string {
	t.Helper()

	if out, err := exec.Command("go", "generate", "github.com/newrelic-forks/newrelic-network-agent/pkg/version").CombinedOutput(); err != nil {
		t.Fatalf("go generate ./pkg/version failed: %v\n%s", err, out)
	}

	bin := filepath.Join(t.TempDir(), "network-agent")
	cmd := exec.Command("go", "build", "-o", bin, "github.com/newrelic-forks/newrelic-network-agent/cmd/network-agent")
	cmd.Env = append(os.Environ(),
		"CGO_ENABLED=0",
		"GOOS="+runtime.GOOS,
		"GOARCH="+runtime.GOARCH,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("static build failed: %v\n%s", err, out)
	}

	return bin
}

// TestStaticBuildRunsAndPrintsUsage proves the statically-built binary
// actually executes, rather than just compiling. -h is handled entirely by
// the standard flag package (main.go defines no -h flag of its own), so a
// successful run here also confirms flag registration didn't break.
func TestStaticBuildRunsAndPrintsUsage(t *testing.T) {
	bin := buildStaticBinary(t)

	cmd := exec.Command(bin, "-h")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s -h failed: %v\noutput:\n%s", bin, err, out)
	}

	got := string(out)
	if !strings.Contains(got, "Usage of") {
		t.Errorf("expected usage banner, got:\n%s", got)
	}
	for _, flagName := range []string{"-listen", "-mapping", "-snmp", "-sinks"} {
		if !strings.Contains(got, flagName) {
			t.Errorf("expected %q in usage output, got:\n%s", flagName, got)
		}
	}
}

// TestStaticBuildPrintsVersion exercises -version's early-exit path in
// main() (checked before any config is built or applyFlags runs). Would have
// caught the -version flag's addition breaking applyFlags immediately, on
// every PR, rather than waiting on the path-filtered Tier B benchmark job.
func TestStaticBuildPrintsVersion(t *testing.T) {
	bin := buildStaticBinary(t)

	cmd := exec.Command(bin, "-version")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s -version failed: %v\noutput:\n%s", bin, err, out)
	}

	got := string(out)
	if !strings.Contains(got, "version") {
		t.Errorf("expected version output, got:\n%s", got)
	}
}

// TestStaticBuildGeneratesConfig exercises -generate-config's early-exit
// path in main(), also checked before applyFlags runs.
func TestStaticBuildGeneratesConfig(t *testing.T) {
	bin := buildStaticBinary(t)

	cmd := exec.Command(bin, "-generate-config")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s -generate-config failed: %v\noutput:\n%s", bin, err, out)
	}

	got := string(out)
	if !strings.Contains(got, "127.0.0.1:8081") {
		t.Errorf("expected the default config's listen address in the generated YAML, got:\n%s", got)
	}
}

// TestApplyFlagsHandlesEveryRegisteredFlag is a regression test for a panic
// hit in production: applyFlags's flag.VisitAll loop errors on any flag name
// it has no case for, skipping only flags whose *current* value stringifies
// to "". A bool flag defaulting to false (like -version, added without a
// matching case) stringifies to "false", so it was never skipped -- applyFlags
// returned "unhandled flag version" on every single run, before the binary
// ever looked at its arguments.
//
// An unrecognized mode positional argument reaches applyMode (called right
// after applyFlags) and fails there instead, with an "Invalid mode" message --
// fast, deterministic, and requires no real config or network access. If
// applyFlags panics first, the process instead exits with "unhandled flag
// ...", which this test distinguishes from the expected failure.
func TestApplyFlagsHandlesEveryRegisteredFlag(t *testing.T) {
	bin := buildStaticBinary(t)

	cmd := exec.Command(bin, "definitely-not-a-real-mode")
	out, err := cmd.CombinedOutput()
	got := string(out)

	if err == nil {
		t.Fatalf("expected the bogus mode to fail, got success:\n%s", got)
	}
	if strings.Contains(got, "unhandled flag") {
		t.Fatalf("applyFlags rejected a registered flag before mode dispatch ran:\n%s", got)
	}
	if !strings.Contains(got, "Invalid mode") {
		t.Errorf("expected an \"Invalid mode\" failure from applyMode, got:\n%s", got)
	}
}

// TestStaticBuildHasNoDynamicLinkage confirms CGO_ENABLED=0 actually produced
// a statically linked binary. That's the entire point of removing the
// furious -> gopacket/pcap cgo dependency: a Go binary with no cgo is fully
// static on Linux (ldd/file report no shared library dependencies), which is
// only meaningful to check on Linux -- Darwin and Windows binaries always
// link against OS-provided libraries regardless of CGO_ENABLED.
func TestStaticBuildHasNoDynamicLinkage(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("static linkage is only meaningful/verifiable on linux")
	}

	bin := buildStaticBinary(t)

	out, err := exec.Command("file", bin).CombinedOutput()
	if err != nil {
		t.Fatalf("file failed: %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "statically linked") {
		t.Errorf("expected a statically linked binary, got: %s", out)
	}
}
