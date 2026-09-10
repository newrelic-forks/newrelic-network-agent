package local

import (
	"context"

	"github.com/newrelic-forks/newrelic-network-agent"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"

	"github.com/fsnotify/fsnotify"
)

type LocalConfig struct {
	logger.ContextL
	currentConfig *networkagent.Config
	watcher       *fsnotify.Watcher
}

func NewConfig(log logger.Underlying, cfg *networkagent.Config) (*LocalConfig, error) {
	lc := LocalConfig{
		ContextL:      logger.NewContextLFromUnderlying(logger.SContext{S: "localConfig"}, log),
		currentConfig: cfg,
	}

	lc.Infof("Monitoring %s for changes", lc.currentConfig.Server.CfgPath)

	// Create new watcher.
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}

	// Add a path.
	err = watcher.Add(lc.currentConfig.Server.CfgPath)
	if err != nil {
		return nil, err
	}

	lc.watcher = watcher

	return &lc, nil
}

func (lc *LocalConfig) Run(ctx context.Context, cb func(*networkagent.Config) error) {
	lc.Infof("config checker running")
	for {
		select {
		case event, ok := <-lc.watcher.Events:
			if !ok {
				return
			}
			if event.Has(fsnotify.Write) {
				err := cb(lc.currentConfig)
				if err != nil {
					lc.Errorf("Cannot update to new config: %v", err)
				}
			}
		case err, ok := <-lc.watcher.Errors:
			if !ok {
				return
			}
			lc.Infof("error:", err)
		case <-ctx.Done():
			lc.Infof("config checker done")
			return
		}
	}
}

func (lc *LocalConfig) DeviceDiscovery(devices kt.DeviceMap) {
	// NOOP
}

func (lc *LocalConfig) Close() {
	lc.watcher.Close()
}
