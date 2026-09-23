package cat

import (
	"github.com/newrelic-forks/newrelic-network-agent"
)

// Callback for when theres a config managment service which detects a change.
func (kc *NetworkAgent) newConfig(newC *networkagent.Config) error {
	kc.log.Warnf("Write detected on %s, shutting down", newC.Server.CfgPath)
	kc.shutdown("Config file changed")
	return nil
}
