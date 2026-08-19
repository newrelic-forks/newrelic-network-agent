package nrm

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSanitizeMetricsUTF8(t *testing.T) {
	assert := assert.New(t)

	metrics := []NRMetric{
		{
			Value: "bad\xffvalue",
			Attributes: map[string]any{
				"mac_address": "bad\xffattr",
				"count":       int64(3),
				"ok":          "fine",
			},
		},
		{
			Value:      float64(42),
			Attributes: nil,
		},
	}

	sanitizeMetricsUTF8(metrics)

	assert.Equal("626164ff76616c7565", metrics[0].Value)
	assert.Equal("626164ff61747472", metrics[0].Attributes["mac_address"])
	assert.Equal(int64(3), metrics[0].Attributes["count"])
	assert.Equal("fine", metrics[0].Attributes["ok"])
	assert.Equal(float64(42), metrics[1].Value)
	assert.Nil(metrics[1].Attributes)
}
