// Package merakicloudsnmp enriches locally-polled SNMP devices with their Meraki serial
// number, sourced from a single bootstrap-time SNMP walk against Meraki's org-wide "cloud
// SNMP" endpoint (snmp.meraki.com), rather than local per-device SNMP -- which doesn't
// expose the serial on most Meraki gear.
package merakicloudsnmp

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gosnmp/gosnmp"

	"github.com/kentik/ktranslate/pkg/eggs/logger"
	snmp_util "github.com/kentik/ktranslate/pkg/inputs/snmp/util"
	"github.com/kentik/ktranslate/pkg/kt"
)

const (
	// devTableOID is MERAKI-CLOUD-CONTROLLER-MIB::devTable, indexed by devMac.
	devTableOID = ".1.3.6.1.4.1.29671.1.1.4"
	// devSerialCol and devLanIpCol are columns within devTable's devEntry row.
	devSerialCol = ".1.3.6.1.4.1.29671.1.1.4.1.8."
	devLanIpCol  = ".1.3.6.1.4.1.29671.1.1.4.1.12."

	DefaultHost    = "snmp.meraki.com"
	DefaultPort    = uint16(161)
	DefaultTagName = "meraki_serial"

	defaultTimeout = 5 * time.Second
	defaultRetries = 2
)

// EnrichSerials walks Meraki's org-wide cloud SNMP endpoint (if configured via
// gconf.MerakiCloudSNMP) once, and tags any locally-configured device whose DeviceIP
// matches a devLanIp reported there with its Meraki serial number, via AddUserTag. This
// must be called before any per-device polling goroutine starts reading tags via
// SetUserTags, since SnmpDeviceConfig's tag map isn't synchronized for concurrent access.
//
// A nil gconf.MerakiCloudSNMP (the default -- this feature is opt-in) is a no-op. Any
// connect/walk error is returned to the caller rather than retried indefinitely; callers
// should treat it as non-fatal so a broken or unreachable cloud SNMP endpoint never blocks
// normal device polling from starting.
func EnrichSerials(ctx context.Context, gconf *kt.SnmpGlobalConfig, devices kt.DeviceMap, log logger.ContextL) error {
	if gconf == nil || gconf.MerakiCloudSNMP == nil {
		return nil
	}
	cfg := gconf.MerakiCloudSNMP

	host := cfg.Host
	if host == "" {
		host = DefaultHost
	}
	port := cfg.Port
	if port == 0 {
		port = DefaultPort
	}
	tagName := cfg.TagName
	if tagName == "" {
		tagName = DefaultTagName
	}
	timeout := defaultTimeout
	if cfg.TimeoutMS > 0 {
		timeout = time.Duration(cfg.TimeoutMS) * time.Millisecond
	}
	retries := defaultRetries
	if cfg.Retries > 0 {
		retries = cfg.Retries
	}

	target := &kt.SnmpDeviceConfig{
		DeviceName: "meraki-cloud-snmp",
		DeviceIP:   host,
		Port:       port,
		Community:  cfg.Community,
		V3:         cfg.V3,
	}

	pdus, err := walkDevTable(target, timeout, retries, log)
	if err != nil {
		return fmt.Errorf("meraki cloud snmp walk of %s:%d failed: %w", host, port, err)
	}

	serialByIP := parseDevTable(pdus)
	matched, total := applyTags(serialByIP, devices, tagName, log)
	log.Infof("Meraki cloud SNMP serial enrichment: matched %d of %d configured device(s) against %d device(s) reported by %s.",
		matched, total, len(serialByIP), host)

	return nil
}

// walkDevTable fetches devTable from target, honoring a test walker if one has been set
// on target via SetTestWalker (see kt.SnmpDeviceConfig), so tests don't need real network.
func walkDevTable(target *kt.SnmpDeviceConfig, timeout time.Duration, retries int, log logger.ContextL) ([]gosnmp.SnmpPDU, error) {
	if walker := target.GetTestWalker(); walker != nil {
		return walker.WalkAll(devTableOID)
	}

	server, err := snmp_util.InitSNMP(target, timeout, retries, "meraki-cloud-snmp", log)
	if err != nil {
		return nil, err
	}
	defer server.Close()

	return server.BulkWalkAll(devTableOID)
}

// parseDevTable groups devTable PDUs by row and returns a devLanIp -> devSerial map. Rows
// missing either column (partial/malformed responses) are silently excluded rather than
// causing an error -- this is best-effort enrichment, not a source of truth.
func parseDevTable(pdus []gosnmp.SnmpPDU) map[string]string {
	serialByIdx := map[string]string{}
	ipByIdx := map[string]string{}

	for _, pdu := range pdus {
		name := pdu.Name
		if !strings.HasPrefix(name, ".") {
			name = "." + name
		}

		switch {
		case strings.HasPrefix(name, devSerialCol):
			idx := strings.TrimPrefix(name, devSerialCol)
			if s, ok := readString(pdu); ok && s != "" {
				serialByIdx[idx] = s
			}
		case strings.HasPrefix(name, devLanIpCol):
			idx := strings.TrimPrefix(name, devLanIpCol)
			if s, ok := readString(pdu); ok && s != "" {
				ipByIdx[idx] = s
			}
		}
	}

	serialByIP := map[string]string{}
	for idx, ip := range ipByIdx {
		if serial, ok := serialByIdx[idx]; ok && serial != "" {
			serialByIP[ip] = serial
		}
	}
	return serialByIP
}

// readString pulls a string out of a devTable column PDU, whether the agent typed it as
// an OctetString (DisplayString columns, e.g. devSerial) or an IpAddress (devLanIp).
func readString(pdu gosnmp.SnmpPDU) (string, bool) {
	switch pdu.Type {
	case gosnmp.OctetString:
		return snmp_util.ReadOctetString(pdu, true)
	case gosnmp.IPAddress:
		s, ok := pdu.Value.(string)
		return s, ok
	default:
		return "", false
	}
}

// applyTags tags every device in devices whose DeviceIP matches an entry in serialByIP,
// via AddUserTag(tagName, serial) -- which every existing metric-emission path already
// merges into outgoing metrics via SetUserTags, with no further wiring needed. Devices
// with no match are left untouched. Returns how many devices were matched, out of how
// many were considered.
func applyTags(serialByIP map[string]string, devices kt.DeviceMap, tagName string, log logger.ContextL) (matched, total int) {
	for _, device := range devices {
		total++
		serial, ok := serialByIP[device.DeviceIP]
		if !ok || serial == "" {
			continue
		}
		device.AddUserTag(tagName, serial)
		matched++
		log.Debugf("Meraki cloud SNMP: tagged device %s (%s) with serial %s.", device.DeviceName, device.DeviceIP, serial)
	}
	return matched, total
}
