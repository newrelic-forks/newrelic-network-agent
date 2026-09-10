package formats

import (
	"context"
	"fmt"

	"github.com/newrelic-forks/newrelic-network-agent"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"

	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/avro"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/carbon"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/elasticsearch"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/influx"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/json"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/kflow"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/netflow"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/nrm"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/otel"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/prom"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/redis"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats/snmp"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/rollup"

	go_metrics "github.com/kentik/go-metrics"
)

type Formatter interface {
	To([]*kt.JCHF, []byte) (*kt.Output, error)
	From(*kt.Output) ([]map[string]interface{}, error)
	Rollup([]rollup.Rollup) (*kt.Output, error)
}

type Format string

const (
	FORMAT_AVRO          Format = "avro"
	FORMAT_ELASTICSEARCH        = "elasticsearch"
	FORMAT_JSON                 = "json"
	FORMAT_JSON_FLAT            = "flat_json"
	FORMAT_NETFLOW              = "netflow"
	FORMAT_INFLUX               = "influx"
	FORMAT_CARBON               = "carbon"
	FORMAT_PROM                 = "prometheus"
	FORMAT_PROM_REMOTE          = "prometheus_remote"
	FORMAT_NR                   = "new_relic"
	FORMAT_NRM                  = "new_relic_metric"
	FORMAT_KFLOW                = "kflow"
	FORMAT_OTEL                 = "otel"
	FORMAT_SNMP                 = "snmp"
	FORMAT_REDIS                = "redis"
)

func NewFormat(ctx context.Context, format Format, log logger.Underlying, registry go_metrics.Registry, compression kt.Compression, cfg *networkagent.Config, logTee chan string) (Formatter, error) {
	switch format {
	case FORMAT_AVRO:
		return avro.NewFormat(log, compression)
	case FORMAT_ELASTICSEARCH:
		return elasticsearch.NewFormat(log, compression, cfg.ElasticFormat)
	case FORMAT_JSON:
		return json.NewFormat(log, compression, false)
	case FORMAT_NETFLOW:
		return netflow.NewFormat(log, compression, cfg.NetflowFormat)
	case FORMAT_INFLUX:
		return influx.NewFormat(log, registry, compression, cfg.InfluxDBFormat)
	case FORMAT_CARBON:
		return carbon.NewFormat(log, compression)
	case FORMAT_PROM:
		return prom.NewFormat(log, compression, cfg.PrometheusFormat)
	case FORMAT_NR, FORMAT_JSON_FLAT:
		return json.NewFormat(log, compression, true)
	case FORMAT_NRM:
		return nrm.NewFormat(log, compression, cfg.NRMFormat)
	case FORMAT_KFLOW:
		return kflow.NewFormat(log, compression)
	case FORMAT_PROM_REMOTE:
		return prom.NewRemoteFormat(log, compression, cfg.PrometheusFormat)
	case FORMAT_OTEL:
		return otel.NewFormat(ctx, log, cfg.OtelFormat, logTee, registry)
	case FORMAT_SNMP:
		return snmp.NewFormat(log, cfg.SnmpFormat)
	case FORMAT_REDIS:
		return redis.NewFormat(ctx, log, cfg.RedisFormat)
	default:
		return nil, fmt.Errorf("You used an unsupported format: %v.", format)
	}
}
