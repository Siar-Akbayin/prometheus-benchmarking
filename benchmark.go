package main

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	metrics "github.com/Siar-Akbayin/prometheus-metrics-generator"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Config structure
type Config struct {
	PrometheusServer         string   `json:"prometheusServer"`
	Queries                  []string `json:"queries"`
	QueryRatePerSecond       int      `json:"queryRatePerSecond"`
	BenchmarkDurationSeconds int      `json:"benchmarkDurationSeconds"`
	NumberOfUsers            int      `json:"numberOfUsers"`
	MaxCardinality           int      `json:"maxCardinality"`
}

var (
	gaugeVec       prometheus.GaugeVec
	cardinalityVec prometheus.GaugeVec
)

// initializeMetrics function
func initializeMetrics(maxCardinality int) (prometheus.GaugeVec, prometheus.GaugeVec) {
	gaugeVec := metrics.CreateGaugeWithCardinality("sample_gauge", maxCardinality)
	cardinalityVec := metrics.CreateGaugeWithCardinality("cardinality_gauge", maxCardinality)
	return gaugeVec, cardinalityVec
}

// queryPrometheus function
func queryPrometheus(query string, prometheusServer string) (float64, error) {
	queryURL := prometheusServer + "/api/v1/query?query=" + query

	startTime := time.Now()
	response, err := http.Get(queryURL)
	if err != nil {
		return 0, err
	}
	defer response.Body.Close()
	_, err = io.ReadAll(response.Body)
	if err != nil {
		return 0, err
	}
	duration := time.Since(startTime).Seconds()

	return duration * 1000, nil
}

// constructQueryWithCardinality function
func constructQueryWithCardinality(baseQuery string, cardinality int) string {
	var labelFilters []string
	for i := 0; i < cardinality; i++ {
		labelFilter := fmt.Sprintf(`dim%d="%d"`, i+1, i+1)
		labelFilters = append(labelFilters, labelFilter)
	}
	return fmt.Sprintf(`%s{%s}`, baseQuery, strings.Join(labelFilters, ","))
}

func main() {
	// Read configuration
	configFile, err := os.Open("config.json")
	if err != nil {
		log.Fatal("Could not open config file", err)
	}
	defer configFile.Close()

	var config Config
	decoder := json.NewDecoder(configFile)
	err = decoder.Decode(&config)
	if err != nil {
		log.Fatal("Could not decode config file", err)
	}

	// Initialize and register Prometheus gauge metrics
	gaugeVec, cardinalityVec = initializeMetrics(config.MaxCardinality)
	prometheus.MustRegister(gaugeVec)
	prometheus.MustRegister(cardinalityVec)

	// Start Prometheus HTTP server for metric scraping
	go func() {
		http.Handle("/metrics", promhttp.Handler())
		log.Fatal(http.ListenAndServe(":8081", nil))
	}()

	// Construct the filename with the number of requests per second and benchmark duration
	filename := fmt.Sprintf("query_benchmark_results_%dreqs_%dsecs.csv", config.QueryRatePerSecond, config.BenchmarkDurationSeconds)

	// Open file for writing
	file, err := os.Create(filename)
	if err != nil {
		log.Fatal("Could not create CSV file", err)
	}
	defer file.Close()

	// Write CSV header
	writer := csv.NewWriter(file)
	defer writer.Flush()
	header := []string{"Timestamp", "Cardinality", "Duration (Milliseconds)"}
	writer.Write(header)

	// Channel and WaitGroup for goroutines
	results := make(chan [3]string)
	var wg sync.WaitGroup

	// Adjust queries based on cardinality
	for i, query := range config.Queries {
		config.Queries[i] = constructQueryWithCardinality(query, config.MaxCardinality)
	}

	// Check if running in maximum throughput mode
	maxThroughputMode := config.QueryRatePerSecond == -1

	// Start benchmark
	for i := 0; i < config.NumberOfUsers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var ticker *time.Ticker
			if maxThroughputMode {
				// In maximum throughput mode, create a ticker with a very short duration
				ticker = time.NewTicker(1 * time.Nanosecond)
			} else {
				ticker = time.NewTicker(time.Second / time.Duration(config.QueryRatePerSecond))
			}
			defer ticker.Stop()
			for range ticker.C {
				// Update Prometheus gauge metrics
				metrics.UpdateGauge(gaugeVec, config.MaxCardinality)
				metrics.UpdateGauge(cardinalityVec, config.MaxCardinality)

				for _, query := range config.Queries {
					startTime := time.Now()
					duration, err := queryPrometheus(query, config.PrometheusServer)
					if err != nil {
						log.Printf("Error querying Prometheus: %s", err)
						continue
					}
					timestamp := startTime.Format(time.RFC3339)
					results <- [3]string{timestamp, strconv.Itoa(config.MaxCardinality), fmt.Sprintf("%.0f", duration)}
				}
			}
		}()
	}

	// Collecting results
	go func() {
		wg.Wait()
		close(results)
	}()

	// Write results to CSV
	for result := range results {
		writer.Write(result[:])
	}

	fmt.Printf("Query benchmark results saved to %s\n", filename)
}
