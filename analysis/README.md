# Analysis

This directory contains the analysis scripts for aggregating and plotting the results of the Prometheus benchmarking. This means that this directory is only useful if you have already run the Prometheus benchmarking tool and have the results.
Go [here](https://github.com/Siar-Akbayin/prometheus-benchmarking/tree/main/terraform-aws) for the Prometheus benchmarking tool.

## Quick Start
run:
```bash 
pip install -r requirements.txt
``` 
to install the required packages.

Then run the latency.py script to generate the latency aggregation data and plots of the experiments with 300s and 600s duration:
```bash
python latency.py
```
Add additional duration arguments to the latency.py script to generate the latency aggregation data and plots for other experiment durations.

Do the same for the throughput.

The results are getting stored in the corresponding directories.