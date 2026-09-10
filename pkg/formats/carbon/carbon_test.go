package carbon

import (
	"strings"
	"testing"

	"github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger"
	lt "github.com/newrelic-forks/newrelic-network-agent/pkg/eggs/logger/testing"
	"github.com/newrelic-forks/newrelic-network-agent/pkg/kt"

	"github.com/stretchr/testify/assert"
)

func TestSeriToCarbon(t *testing.T) {
	serBuf := make([]byte, 0)
	assert := assert.New(t)
	l := lt.NewTestContextL(logger.NilContext, t).GetLogger().GetUnderlyingLogger()

	f, err := NewFormat(l, kt.CompressionNone)
	assert.NoError(err)

	res, err := f.To(kt.InputTesting, serBuf)
	assert.NoError(err)
	assert.NotNil(res)

	pts := strings.Split(string(res.Body), "\n")
	// with the carbon formatter each field (in_bytes, etc) is an individual metric
	expected := 10
	assert.Equal(len(pts), expected)
}
