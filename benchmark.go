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
	"sync"
	"time"
)

type Experiment struct {
	Queries                  []string `json:"queries"`
	QueryRatePerSecond       int      `json:"queryRatePerSecond"`
	BenchmarkDurationSeconds int      `json:"benchmarkDurationSeconds"`
	NumberOfUsers            int      `json:"numberOfUsers"`
	MaxCardinality           int      `json:"maxCardinality"`
	Iterations               int      `json:"iterations"`
}

type Config struct {
	PrometheusServer string       `json:"prometheusServer"`
	Experiments      []Experiment `json:"experiments"`
}

// Queries Prometheus and returns the query duration in milliseconds
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
	return duration * 10000, nil
}

// Constructs a query based on the base metric name and its cardinality
func constructQueryWithCardinality(baseQuery string, cardinality int) string {
	// Directly format the metric name with the cardinality value
	return fmt.Sprintf("%s_%d", baseQuery, cardinality)
}

// Warmup function that performs queries without saving results
func warmup(config Config, experiment Experiment) {
	fmt.Println("Starting warmup period...")
	warmupDuration := 60 // Warmup duration in seconds
	stopWarmup := time.After(time.Duration(warmupDuration) * time.Second)
	var warmupTicker *time.Ticker
	if experiment.QueryRatePerSecond == -1 {
		// Use a very short duration for maximizing the rate
		warmupTicker = time.NewTicker(1 * time.Microsecond)
	} else {
		// Use the specified query rate
		warmupTicker = time.NewTicker(time.Second / time.Duration(experiment.QueryRatePerSecond))
	}
	defer warmupTicker.Stop()

WarmupLoop:
	for {
		select {
		case <-warmupTicker.C:
			for _, query := range experiment.Queries {
				queryWithCardinality := constructQueryWithCardinality(query, experiment.MaxCardinality)
				_, err := queryPrometheus(queryWithCardinality, config.PrometheusServer)
				if err != nil {
					log.Printf("Warmup query error: %s", err)
				}
			}
		case <-stopWarmup:
			break WarmupLoop
		}
	}
	fmt.Println("Warmup complete.")
}

func main() {
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
		// Perform warmup for each experiment
		warmup(config, experiment)

		for iteration := 1; iteration <= experiment.Iterations; iteration++ {
			filename := fmt.Sprintf("query_benchmark_results_%dreqs_%dsecs_%dusers_%dcard_%d.csv",
				experiment.QueryRatePerSecond, experiment.BenchmarkDurationSeconds,
				experiment.NumberOfUsers, experiment.MaxCardinality, iteration)

			file, err := os.Create(filename)
			if err != nil {
				log.Fatalf("Could not create CSV file: %v", err)
			}
			defer file.Close()

			writer := csv.NewWriter(file)
			defer writer.Flush()

			header := []string{"Timestamp", "Cardinality", "Latency (Deci-milliseconds)", "Users", "Duration", "Failure"}
			writer.Write(header)

			results := make(chan [6]string)
			var wg sync.WaitGroup

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
								queryWithCardinality := constructQueryWithCardinality(query, experiment.MaxCardinality)
								startTime := time.Now()
								duration, err := queryPrometheus(queryWithCardinality, config.PrometheusServer)
								failure := "0"
								if err != nil {
									log.Printf("Error querying Prometheus: %s, Number of users: %d, Cardinality: %d", err, experiment.NumberOfUsers, experiment.MaxCardinality)
									failure = "1"
								}
								timestamp := startTime.Format(time.RFC3339)
								results <- [6]string{timestamp, strconv.Itoa(experiment.MaxCardinality), fmt.Sprintf("%.0f", duration), strconv.Itoa(experiment.NumberOfUsers), strconv.Itoa(experiment.BenchmarkDurationSeconds), failure}
							}
						case <-stopBenchmark:
							return
						}
					}
				}()
			}

			go func() {
				wg.Wait()
				close(results)
			}()

			for result := range results {
				writer.Write(result[:])
			}

			fmt.Printf("Query benchmark results for iteration %d saved to %s\n", iteration, filename)
		}
	}

	flagFilePath := "benchmark_complete.flag"
	if _, err := os.Create(flagFilePath); err != nil {
		log.Fatalf("Failed to create benchmark completion flag file: %v", err)
	}
	fmt.Println("Benchmarking complete. Flag file created.")
}
