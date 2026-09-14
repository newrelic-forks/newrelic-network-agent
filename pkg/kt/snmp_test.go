package kt

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"gopkg.in/yaml.v3"
)

func TestIsPollReady(t *testing.T) {
	// Empty mib always returns true.
	mib := &Mib{}
	assert.True(t, mib.IsPollReady())
	assert.True(t, mib.IsPollReady())
	assert.True(t, mib.IsPollReady())

	// Now, set a poll duration.
	mib.PollDur = time.Duration(10) * time.Second
	assert.True(t, mib.IsPollReady())  // first poll is good.
	assert.False(t, mib.IsPollReady()) // Skip the 2nd.
	assert.False(t, mib.IsPollReady()) // Skip the 2nd.
}

func TestGetName(t *testing.T) {
	mib := &Mib{
		Tag:  "foo",
		Name: "name",
	}
	assert.Equal(t, "foo", mib.GetName())
	mib = nil
	assert.Equal(t, "missing_mib", mib.GetName())
	mib = &Mib{
		Name: "bar",
	}
	assert.Equal(t, "bar", mib.GetName())
}

func TestSNMPV3(t *testing.T) {
	input := []byte(`
user_name: mabel
authentication_protocol: MD5
authentication_passphrase: password123
privacy_protocol: AES
privacy_passphrase: password123
context_engine_id: aaa
context_name: ""
`)

	ms := V3SNMPConfig{}
	err := yaml.Unmarshal(input, &ms)
	assert.NoError(t, err)
	assert.Equal(t, "password123", ms.AuthenticationPassphrase)

	ser, err := yaml.Marshal(&ms)
	assert.NoError(t, err)
	assert.Equal(t, strings.TrimSpace(string(input)), strings.TrimSpace(string(ser)))

	input = []byte(`
user_name: mabel
authentication_protocol: MD5
authentication_passphrase: ${foo}
privacy_protocol: AES
privacy_passphrase: password123
context_engine_id: ${bar}
context_name: ""
`)
	t.Setenv("foo", "password123")
	t.Setenv("bar", "1234")
	err = yaml.Unmarshal(input, &ms)
	assert.NoError(t, err)
	assert.Equal(t, "password123", ms.AuthenticationPassphrase)
	assert.Equal(t, "${foo}", ms.origConf["AuthenticationPassphrase"])

	ser, err = yaml.Marshal(&ms)
	assert.NoError(t, err)
	assert.Equal(t, strings.TrimSpace(string(input)), strings.TrimSpace(string(ser)))

	input = []byte(`${lar}`)
	t.Setenv("lar", `user_name: mabel
authentication_protocol: MD5
authentication_passphrase: password123
privacy_protocol: AES
privacy_passphrase: password123
context_engine_id: aaa
context_name: ""`)
	err = yaml.Unmarshal(input, &ms)
	assert.NoError(t, err)
	assert.Equal(t, "password123", ms.AuthenticationPassphrase)

	ser, err = yaml.Marshal(&ms)
	assert.NoError(t, err)
	assert.Equal(t, strings.TrimSpace(string(input)), strings.TrimSpace(string(ser)))
}

func TestUpdateFromPreservesPollTimeoutSec(t *testing.T) {
	conf := &SnmpConfig{Global: &SnmpGlobalConfig{}}

	// PollTimeoutSec carries over from the old (pre-rediscovery) config when set.
	d := &SnmpDeviceConfig{}
	old := &SnmpDeviceConfig{PollTimeoutSec: 60}
	d.UpdateFrom(old, conf)
	assert.Equal(t, 60, d.PollTimeoutSec)

	// An unset (zero) old value doesn't clobber whatever the new config already has.
	d = &SnmpDeviceConfig{PollTimeoutSec: 45}
	old = &SnmpDeviceConfig{}
	d.UpdateFrom(old, conf)
	assert.Equal(t, 45, d.PollTimeoutSec)
}

func TestMerakiCloudSNMPConfigOptedOutByDefault(t *testing.T) {
	// A global config with no meraki_cloud_snmp key -- i.e. every config that exists today --
	// must leave the new field nil, so the enrichment feature stays off unless opted in.
	input := []byte(`
poll_time_sec: 300
timeout_ms: 3000
`)

	gc := SnmpGlobalConfig{}
	err := yaml.Unmarshal(input, &gc)
	assert.NoError(t, err)
	assert.Nil(t, gc.MerakiCloudSNMP)
}

func TestMerakiCloudSNMPConfigParses(t *testing.T) {
	input := []byte(`
poll_time_sec: 300
meraki_cloud_snmp:
  host: snmp.meraki.com
  port: 161
  snmp_comm: mycommunity
  tag_name: meraki_serial
`)

	gc := SnmpGlobalConfig{}
	err := yaml.Unmarshal(input, &gc)
	assert.NoError(t, err)
	assert.NotNil(t, gc.MerakiCloudSNMP)
	assert.Equal(t, "snmp.meraki.com", gc.MerakiCloudSNMP.Host)
	assert.Equal(t, uint16(161), gc.MerakiCloudSNMP.Port)
	assert.Equal(t, "mycommunity", gc.MerakiCloudSNMP.Community)
	assert.Equal(t, "meraki_serial", gc.MerakiCloudSNMP.TagName)
}

func TestEAPI(t *testing.T) {
	input := []byte(`
host: mabel
username: MD5
password: password123
transport: ""
port: 8080
`)

	ms := EAPIConfig{}
	err := yaml.Unmarshal(input, &ms)
	assert.NoError(t, err)
	assert.Equal(t, "password123", ms.Password)
	assert.Equal(t, 8080, ms.Port)

	ser, err := yaml.Marshal(&ms)
	assert.NoError(t, err)
	assert.Equal(t, strings.TrimSpace(string(input)), strings.TrimSpace(string(ser)))
}
