package util

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"
	lt "github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger/testing"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"
)

func TestInitSNMPMaxRepetitions(t *testing.T) {
	l := lt.NewTestContextL(logger.NilContext, t)

	tests := []struct {
		name     string
		device   uint32
		global   uint32
		expected uint32
	}{
		{"unset leaves the gosnmp default", 0, 0, 0},
		{"global value applies", 0, 25, 25},
		{"device value wins over global", 10, 25, 10},
		{"device value applies without global", 10, 0, 10},
		{"device value at the limit applies", 50, 0, 50},
		{"device value above the limit falls back to global", 100, 25, 25},
		{"global value above the limit uses the gosnmp default", 0, 100, 0},
		{"both above the limit use the gosnmp default", 100, 100, 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// A UDP connect doesn't send anything, so no SNMP agent needs to be listening.
			device := &kt.SnmpDeviceConfig{
				DeviceName:     "test",
				DeviceIP:       "127.0.0.1",
				Community:      "public",
				MaxRepetitions: tt.device,
			}
			server, err := InitSNMP(device, time.Second, 0, tt.global, "", l)
			assert.NoError(t, err)
			assert.Equal(t, tt.expected, server.MaxRepetitions)
			server.Conn.Close()
		})
	}
}
