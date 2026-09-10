package elasticsearch

import (
	"testing"

	"github.com/newrelic-forks/newrelic-network-agent"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"
	lt "github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger/testing"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"
	"github.com/stretchr/testify/assert"
)

func TestSerializeElasticsearch(t *testing.T) {
	serBuf := make([]byte, 0)
	assert := assert.New(t)
	l := lt.NewTestContextL(logger.NilContext, t).GetLogger().GetUnderlyingLogger()

	f, err := NewFormat(l, kt.CompressionNone, &networkagent.ElasticFormatConfig{Action: "index"})
	assert.NoError(err)

	res, err := f.To(kt.InputTesting, serBuf)
	assert.NoError(err)
	assert.NotNil(res)

	out, err := f.From(res)
	assert.NoError(err)
	assert.Equal(len(kt.InputTesting), len(out))
	for i, _ := range out {
		assert.Equal(kt.InputTesting[i].SrcAddr, out[i]["src_addr"])
	}
}

func TestSerializeElasticsearchGzip(t *testing.T) {
	serBuf := make([]byte, 0)
	assert := assert.New(t)
	l := lt.NewTestContextL(logger.NilContext, t).GetLogger().GetUnderlyingLogger()
	f, err := NewFormat(l, kt.CompressionGzip, &networkagent.ElasticFormatConfig{Action: "index"})
	assert.NoError(err)
	res, err := f.To(kt.InputTesting, serBuf)
	assert.NoError(err)
	assert.NotNil(res)
	out, err := f.From(res)
	assert.NoError(err)
	assert.Equal(len(kt.InputTesting), len(out))
	for i, _ := range out {
		assert.Equal(kt.InputTesting[i].SrcAddr, out[i]["src_addr"])
	}
}
