package merakicloudsnmp

import (
	"context"
	"testing"

	"github.com/gosnmp/gosnmp"
	"github.com/stretchr/testify/assert"

	"github.com/kentik/ktranslate/pkg/eggs/logger"
	lt "github.com/kentik/ktranslate/pkg/eggs/logger/testing"
	"github.com/kentik/ktranslate/pkg/kt"
)

type testWalker struct {
	results []gosnmp.SnmpPDU
	err     error
}

func (w testWalker) WalkAll(oid string) ([]gosnmp.SnmpPDU, error) {
	return w.results, w.err
}

func octetStringPDU(name, value string) gosnmp.SnmpPDU {
	return gosnmp.SnmpPDU{Name: name, Type: gosnmp.OctetString, Value: []byte(value)}
}

func ipAddressPDU(name, value string) gosnmp.SnmpPDU {
	return gosnmp.SnmpPDU{Name: name, Type: gosnmp.IPAddress, Value: value}
}

func TestParseDevTable(t *testing.T) {
	pdus := []gosnmp.SnmpPDU{
		// Row 1: complete -- serial and LAN IP both present.
		octetStringPDU(".1.3.6.1.4.1.29671.1.1.4.1.8.1", "Q2XX-0001-0001"),
		ipAddressPDU(".1.3.6.1.4.1.29671.1.1.4.1.12.1", "10.0.0.1"),
		// Row 2: complete, different device.
		octetStringPDU(".1.3.6.1.4.1.29671.1.1.4.1.8.2", "Q2XX-0002-0002"),
		ipAddressPDU(".1.3.6.1.4.1.29671.1.1.4.1.12.2", "10.0.0.2"),
		// Row 3: serial only, no LAN IP reported -- must be excluded, not guessed.
		octetStringPDU(".1.3.6.1.4.1.29671.1.1.4.1.8.3", "Q2XX-0003-0003"),
		// Row 4: LAN IP only, no serial -- must be excluded.
		ipAddressPDU(".1.3.6.1.4.1.29671.1.1.4.1.12.4", "10.0.0.4"),
		// Unrelated column (devName) for row 1 -- must be ignored, not mistaken for data.
		octetStringPDU(".1.3.6.1.4.1.29671.1.1.4.1.2.1", "some-ap-name"),
		// Malformed/unexpected OID shape -- must not panic.
		{Name: "not-an-oid", Type: gosnmp.OctetString, Value: []byte("garbage")},
	}

	got := parseDevTable(pdus)

	assert.Equal(t, map[string]string{
		"10.0.0.1": "Q2XX-0001-0001",
		"10.0.0.2": "Q2XX-0002-0002",
	}, got)
}

func TestParseDevTableEmpty(t *testing.T) {
	assert.Equal(t, map[string]string{}, parseDevTable(nil))
	assert.Equal(t, map[string]string{}, parseDevTable([]gosnmp.SnmpPDU{}))
}

func testLogger(t *testing.T) logger.ContextL {
	return lt.NewTestContextL(logger.NilContext, t)
}

func TestApplyTags(t *testing.T) {
	log := testLogger(t)

	serialByIP := map[string]string{
		"10.0.0.1": "Q2XX-0001-0001",
		"10.0.0.2": "Q2XX-0002-0002",
	}

	matchedDevice := &kt.SnmpDeviceConfig{DeviceName: "matched", DeviceIP: "10.0.0.1"}
	unmatchedDevice := &kt.SnmpDeviceConfig{DeviceName: "unmatched", DeviceIP: "10.0.0.99"}
	matchedDevice.InitUserTags("ktranslate")
	unmatchedDevice.InitUserTags("ktranslate")

	devices := kt.DeviceMap{
		"matched":   matchedDevice,
		"unmatched": unmatchedDevice,
	}

	matched, total := applyTags(serialByIP, devices, "meraki_serial", log)

	assert.Equal(t, 1, matched)
	assert.Equal(t, 2, total)
	assert.Equal(t, "Q2XX-0001-0001", matchedDevice.GetUserTags()["tags.meraki_serial"])
	assert.NotContains(t, unmatchedDevice.GetUserTags(), "tags.meraki_serial")
}

func TestWalkDevTableUsesTestWalker(t *testing.T) {
	log := testLogger(t)
	want := []gosnmp.SnmpPDU{octetStringPDU(".1.3.6.1.4.1.29671.1.1.4.1.8.1", "Q2XX-0001-0001")}

	target := &kt.SnmpDeviceConfig{DeviceName: "meraki-cloud-snmp", DeviceIP: "snmp.meraki.com"}
	target.SetTestWalker(testWalker{results: want})

	got, err := walkDevTable(target, defaultTimeout, defaultRetries, log)
	assert.NoError(t, err)
	assert.Equal(t, want, got)
}

func TestEnrichSerialsNilConfigIsNoOp(t *testing.T) {
	log := testLogger(t)
	device := &kt.SnmpDeviceConfig{DeviceName: "d1", DeviceIP: "10.0.0.1"}
	device.InitUserTags("ktranslate")
	devices := kt.DeviceMap{"d1": device}

	err := EnrichSerials(context.Background(), &kt.SnmpGlobalConfig{}, devices, log)
	assert.NoError(t, err)
	assert.Empty(t, device.GetUserTags())

	// A nil global config entirely must also be a no-op, not a panic.
	err = EnrichSerials(context.Background(), nil, devices, log)
	assert.NoError(t, err)
}

func TestEnrichSerialsReturnsErrorWithoutPanicking(t *testing.T) {
	log := testLogger(t)
	device := &kt.SnmpDeviceConfig{DeviceName: "d1", DeviceIP: "10.0.0.1"}
	device.InitUserTags("ktranslate")
	devices := kt.DeviceMap{"d1": device}

	// No community and no v3 config set -- InitSNMP rejects this immediately, with no
	// network round trip, exercising the connect-error path deterministically and fast.
	gconf := &kt.SnmpGlobalConfig{
		MerakiCloudSNMP: &kt.MerakiCloudSNMPConfig{
			Host: "snmp.meraki.com",
		},
	}

	err := EnrichSerials(context.Background(), gconf, devices, log)
	assert.Error(t, err)
	assert.Empty(t, device.GetUserTags())
}
