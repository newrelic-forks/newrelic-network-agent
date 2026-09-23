package kt

import (
	"encoding/binary"
	"net"
	"os"
	"strconv"
	"strings"
)

func LookupEnvString(key string, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok {
		return val
	}
	return defaultVal
}

func LookupEnvInt(key string, defaultVal int) int {
	if val, ok := os.LookupEnv(key); ok {
		if ival, err := strconv.Atoi(val); err == nil {
			return ival
		} else {
			return defaultVal
		}
	}
	return defaultVal
}

func LookupEnvBool(key string, defaultVal bool) bool {
	if val, ok := os.LookupEnv(key); ok {
		return strings.ToLower(val) == "true"
	}
	return defaultVal
}

// LookupEnvStringDeprecated checks newKey first, then falls back to the deprecated oldKey,
// then defaultVal. Use this to rename an env var without breaking deployments that still
// set the old name -- oldKey keeps working until it's removed in a later release.
func LookupEnvStringDeprecated(newKey, oldKey, defaultVal string) string {
	if val, ok := os.LookupEnv(newKey); ok {
		return val
	}
	return LookupEnvString(oldKey, defaultVal)
}

// LookupEnvIntDeprecated is LookupEnvStringDeprecated for int-valued env vars.
func LookupEnvIntDeprecated(newKey, oldKey string, defaultVal int) int {
	if val, ok := os.LookupEnv(newKey); ok {
		if ival, err := strconv.Atoi(val); err == nil {
			return ival
		}
		return defaultVal
	}
	return LookupEnvInt(oldKey, defaultVal)
}

func FixupName(name string) string {
	name = strings.ToLower(strings.ReplaceAll(name, " ", "_"))
	return name
}

func Int2ip(nn uint32) net.IP {
	ip := make(net.IP, 4)
	binary.BigEndian.PutUint32(ip, nn)
	return ip
}
