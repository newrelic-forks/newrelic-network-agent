package sinks

import (
	"context"
	"fmt"

	go_metrics "github.com/kentik/go-metrics"
	"github.com/newrelic-forks/newrelic-network-agent"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"

	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/sinks/http"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/sinks/nr"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/sinks/nrmulti"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/sinks/otel"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/sinks/stdout"
)

type SinkImpl interface {
	Init(context.Context, formats.Format, kt.Compression, formats.Formatter) error
	Send(context.Context, *kt.Output)
	Close()
	HttpInfo() map[string]float64
}

type CloudObjectManager interface {
	Init(context.Context, formats.Format, kt.Compression, formats.Formatter) error
	Put(context.Context, string, []byte) error
	Get(context.Context, string) ([]byte, error)
}

type Sink string

const (
	StdOutSink    Sink = "stdout"
	NewRelicSink       = "new_relic"
	NewRelicMulti      = "new_relic_multi"
	OtelSink           = "otel"
	HttpSink           = "http"
	NullSink           = "null"
)

func NewSink(sink Sink, log logger.Underlying, registry go_metrics.Registry, tooBig chan int, logTee chan string, config *networkagent.Config) (SinkImpl, error) {
	switch sink {
	case StdOutSink:
		return stdout.NewSink(log, registry, logTee)
	case NewRelicSink:
		return nr.NewSink(log, registry, tooBig, logTee, config.NewRelicSink)
	case NewRelicMulti:
		return nrmulti.NewSink(log, registry, tooBig, logTee, config.NewRelicSink, config.NewRelicMultiSink)
	case OtelSink:
		return otel.NewSink(log, registry, logTee)
	case HttpSink:
		return http.NewSink(log, registry, config.HTTPSink, logTee)
	case NullSink:
		return newNullSink(log)
	}
	return nil, fmt.Errorf("Unknown sink %v", sink)
}

type nullSink struct{}

func newNullSink(log logger.Underlying) (*nullSink, error) {
	return &nullSink{}, nil
}
func (ns *nullSink) Init(context.Context, formats.Format, kt.Compression, formats.Formatter) error {
	return nil
}
func (ns *nullSink) Send(context.Context, *kt.Output) {
	return
}
func (ns *nullSink) Close() {
	return
}
func (ns *nullSink) HttpInfo() map[string]float64 {
	return map[string]float64{}
}
