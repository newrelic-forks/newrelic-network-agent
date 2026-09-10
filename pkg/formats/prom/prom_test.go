package prom

import (
	"testing"

	"github.com/newrelic-forks/newrelic-network-agent"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"
	lt "github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger/testing"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"

	"github.com/stretchr/testify/assert"
)

func TestSeriToInflux(t *testing.T) {
	cfg := networkagent.DefaultConfig().PrometheusFormat
	serBuf := make([]byte, 0)
	assert := assert.New(t)
	l := lt.NewTestContextL(logger.NilContext, t).GetLogger().GetUnderlyingLogger()

	f, err := NewFormat(l, kt.CompressionNone, cfg)
	assert.NoError(err)

	res, err := f.To(kt.InputTesting, serBuf)
	assert.NoError(err)
	assert.Nil(res)

	res, err = f.To(kt.InputTestingSynth, serBuf)
	assert.NoError(err)
	assert.Nil(res)

	res, err = f.To(kt.InputTestingSnmp, serBuf)
	assert.NoError(err)
	assert.Nil(res)
}
