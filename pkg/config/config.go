package config

/**
Interface to manage configs.
*/

import (
	"context"
	"flag"
	"fmt"

	"github.com/newrelic-forks/newrelic-network-agent"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/config/local"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/config/nr"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"
)

type ConfigManager interface {
	Run(context.Context, func(*networkagent.Config) error) // Run takes a context and a callback function to call whenever there is a new update to process
	DeviceDiscovery(kt.DeviceMap)                          // called whenever there is a new snmp device discovery to parse.
	Close()                                                // Called on shutdown of ktrans.
}

type ConfigProvider string

const (
	NewRelicConfig ConfigProvider = "new_relic"
	LocalConfig    ConfigProvider = "local"
	NoConfig       ConfigProvider = ""
)

var (
	configProvider string
)

func init() {
	flag.StringVar(&configProvider, "config_provider", "", "Implementation of which provider controls the config process. Can be one of (new_relic,local)")
}

func NewConfig(prov ConfigProvider, log logger.Underlying, config *networkagent.Config) (ConfigManager, error) {
	switch prov {
	case NewRelicConfig:
		return nr.NewConfig(log, config)
	case LocalConfig:
		return local.NewConfig(log, config)
	case NoConfig:
		return nil, nil
	default:
		return nil, fmt.Errorf("Unknown config provider %v", prov)
	}
}
