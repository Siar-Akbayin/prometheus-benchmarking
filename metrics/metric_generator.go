package metrics

import (
	"fmt"
	"math/rand"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// Example of creating a gauge with variable cardinality
func createGaugeWithCardinality(baseName string, maxCardinality int) prometheus.GaugeVec {
	labelNames := make([]string, maxCardinality)
	for i := 0; i < maxCardinality; i++ {
		labelNames[i] = fmt.Sprintf("dim%d", i+1)
	}
	return *prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: baseName,
			Help: "A sample gauge metric with variable cardinality",
		},
		labelNames,
	)
}

// Updating metrics with varying cardinality
func updateGauge(gaugeVec prometheus.GaugeVec, maxCardinality int) {
	labelValues := make([]string, maxCardinality)
	for i := 0; i < maxCardinality; i++ {
		labelValues[i] = fmt.Sprintf("%d", i+1)
	}
	gaugeVec.WithLabelValues(labelValues...).Set(rand.Float64() * 100)
}

func main() {
	maxCardinality := 5
	gauge := createGaugeWithCardinality("example_gauge", maxCardinality)

	for {
		updateGauge(gauge, maxCardinality)
		time.Sleep(1 * time.Second)
	}
}
