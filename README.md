
# Benchmarking Tool for Prometheus Metrics

This benchmarking tool is designed to evaluate the performance of Prometheus under various query loads. It dynamically generates queries based on configured parameters, measures query response times, and aggregates the results into CSV files for analysis.

## Overview

The tool conducts a series of experiments defined in a configuration file (`config.json`). Each experiment can specify different parameters, such as the rate of queries per second, the duration of the benchmark, the number of concurrent users, and the cardinality of the queries. The tool includes a warm-up phase to ensure that the Prometheus server is ready for the benchmark.

## Configuration

The benchmarking tool is configured via a `config.json` file, which specifies the Prometheus server to query and details of each experiment. Here's a sample configuration structure:

```json
{
  "prometheusServer": "http://localhost:9090",
  "experiments": [
    {
      "queries": ["sample_query"],
      "queryRatePerSecond": 10,
      "benchmarkDurationSeconds": 300,
      "numberOfUsers": 5,
      "maxCardinality": 100,
      "iterations": 2
    }
  ]
}
```

Each experiment within the `experiments` array can have the following properties:
- `queries`: An array of base queries to be benchmarked.
- `queryRatePerSecond`: The rate at which queries will be sent to Prometheus. -1 means that the queries will be sent as fast as possible.
- `benchmarkDurationSeconds`: The total duration of each experiment in seconds.
- `numberOfUsers`: The number of concurrent users sending queries.
- `maxCardinality`: The dimensions number for the queries.
- `iterations`: The number of times the experiment will be repeated.

## Usage

This tool tailored to be used with Terraform. The usage steps are describe here: 