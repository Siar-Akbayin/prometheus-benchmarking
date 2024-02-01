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
)

// Experiment structure
type Experiment struct {
	Queries                  []string `json:"queries"`
	QueryRatePerSecond       int      `json:"queryRatePerSecond"`
	BenchmarkDurationSeconds int      `json:"benchmarkDurationSeconds"`
	NumberOfUsers            int      `json:"numberOfUsers"`
	MaxCardinality           int      `json:"maxCardinality"`
}

// Config structure
type Config struct {
	PrometheusServer string       `json:"prometheusServer"`
	Experiments      []Experiment `json:"experiments"`
}

// queryPrometheus function
func queryPrometheus(query string, prometheusServer string) (float64, error) {
	queryURL := fmt.Sprintf("%s/api/v1/query?query=%s", prometheusServer, query)

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
	return fmt.Sprintf(`sample_gauge_%d{%s}`, cardinality, strings.Join(labelFilters, ","))
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

	for _, experiment := range config.Experiments {
		// Construct the filename based on experiment parameters
		filename := fmt.Sprintf("query_benchmark_results_%dreqs_%dsecs_%dusers_%dcard.csv",
			experiment.QueryRatePerSecond, experiment.BenchmarkDurationSeconds,
			experiment.NumberOfUsers, experiment.MaxCardinality)

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

		// Adjust queries based on cardinality - updated to use new query format
		for i, _ := range experiment.Queries {
			experiment.Queries[i] = constructQueryWithCardinality("sample_gauge", experiment.MaxCardinality)
		}

		// Start benchmark
		stopBenchmark := make(chan struct{})
		go func() {
			time.Sleep(time.Duration(experiment.BenchmarkDurationSeconds) * time.Second)
			close(stopBenchmark)
		}()

		for i := 0; i < experiment.NumberOfUsers; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				var ticker *time.Ticker
				if experiment.QueryRatePerSecond == -1 {
					ticker = time.NewTicker(1 * time.Nanosecond)
				} else {
					ticker = time.NewTicker(time.Second / time.Duration(experiment.QueryRatePerSecond))
				}
				defer ticker.Stop()

				for {
					select {
					case <-ticker.C:
						for _, query := range experiment.Queries {
							startTime := time.Now()
							duration, err := queryPrometheus(query, config.PrometheusServer)
							if err != nil {
								log.Printf("Error querying Prometheus: %s", err)
								continue
							}
							timestamp := startTime.Format(time.RFC3339)
							results <- [3]string{timestamp, strconv.Itoa(experiment.MaxCardinality), fmt.Sprintf("%.0f", duration)}
						}
					case <-stopBenchmark:
						return
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
}
