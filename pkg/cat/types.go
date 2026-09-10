package cat

import (
	"database/sql"

	go_metrics "github.com/kentik/go-metrics"
	"github.com/newrelic-forks/newrelic-network-agent"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"

	"github.com/newrelic-forks/newrelic-network-agent/pkg/api"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/cat/auth"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/config"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/filter"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/formats"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/inputs/flow"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/inputs/http"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/inputs/syslog"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/inputs/vpc"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/km"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/maps"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/rollup"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/sinks"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/stitch"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/util/enrich"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/util/gopatricia/patricia"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/util/resolv"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/util/rule"

	model "github.com/newrelic-forks/newrelic-network-agent/pkg/util/kflow2"
)

const (
	HttpHealthCheckPath         = "/check"
	HttpAlertInboundPath        = "/chf"
	HttpInfoPath                = "/service_info"
	HttpCompanyID               = "sid"
	HttpAlertKey                = "key"
	MaxProxyListenerBufferAlloc = 10 * 1024 * 1024 // 10MB
	MSG_KEY_PREFIX              = 80
	HttpSenderID                = "sender_id"
	APP_PROTOCOL_COL            = "app_protocol"
	UDR_TYPE_INT                = "int"
	UDR_TYPE_BIGINT             = "bigint"
	UDR_TYPE_STRING             = "string"
	UDR_TYPE                    = "application_type"
)

type KTranslate struct {
	log          logger.ContextL
	config       *networkagent.Config
	registry     go_metrics.Registry
	metrics      *KKCMetric
	alphaChans   []chan *Flow
	jchfChans    []chan *kt.JCHF
	inputChan    chan []*kt.JCHF
	metricsChan  chan []*kt.JCHF
	mapr         *CustomMapper
	udrMapr      *UDRMapper
	pgdb         *sql.DB
	msgsc        chan *kt.Output
	sinks        map[sinks.Sink]sinks.SinkImpl
	format       formats.Formatter
	formatRollup formats.Formatter
	rollups      []rollup.Roller
	doRollups    bool
	doFilter     bool
	filters      []filter.FilterWrapper
	geo          *patricia.MMMap
	asn          *patricia.MMMap
	resolver     *resolv.Resolver
	auth         *auth.Server
	apic         *api.KentikApi
	tooBig       chan int
	tagMap       maps.TagMapper
	tagMapCity   maps.TagMapper
	tagMapRegion maps.TagMapper
	tagKM        *km.KMMapper
	vpc          vpc.VpcImpl
	nfs          *flow.KentikDriver
	rule         *rule.RuleSet
	syslog       *syslog.KentikSyslog
	http         *http.KentikHttpListener
	enricher     *enrich.Enricher
	logTee       chan string
	logTeeSinks  []chan string
	authConfig   *auth.AuthConfig
	confMgr      config.ConfigManager
	shutdown     func(string)
	objmgr       sinks.CloudObjectManager
	tee          sinks.SinkImpl
	stitcher     *stitch.Stitcher
}

type CustomMapper struct {
	Customs map[uint32]string `json:"customs"`
}

type UDR struct {
	ColumnName      string
	ApplicationName string
	Type            string
}

type UDRMapper struct {
	UDRs     map[int32]map[string]*UDR
	Subtypes map[string]map[string]*UDR
}

type hc struct {
	Flows          float64
	DroppedFlows   float64
	FlowsOut       float64
	Errors         float64
	AlphaQ         int64
	JCHFQ          int64
	AlphaQDrop     float64
	InputQ         float64
	InputQLen      int64
	OutputQLen     int64
	Sinks          map[sinks.Sink]map[string]float64
	SnmpDeviceData map[string]map[string]float64
	Inputs         map[string]map[string]float64
	Stitcher       map[string]float64
}

type Flow struct {
	CompanyId  int
	CHF        model.CHF
	DeviceName string
}

type KKCMetric struct {
	Flows          go_metrics.Meter
	FlowsOut       go_metrics.Meter
	DroppedFlows   go_metrics.Meter
	Errors         go_metrics.Meter
	AlphaQ         go_metrics.Gauge
	JCHFQ          go_metrics.Gauge
	AlphaQDrop     go_metrics.Meter
	InputQ         go_metrics.Meter
	InputQLen      go_metrics.Gauge
	OutputQLen     go_metrics.Gauge
	SnmpDeviceData *kt.SnmpMetricSet
}
