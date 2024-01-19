#!/bin/bash

# Install Docker
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo systemctl start docker
sudo systemctl enable docker

# Create Prometheus configuration file
sudo mkdir -p /etc/prometheus
sudo touch /etc/prometheus/prometheus.yml

# Add minimal configuration to the Prometheus configuration file
echo "global:" | sudo tee -a /etc/prometheus/prometheus.yml
echo "  scrape_interval: 15s" | sudo tee -a /etc/prometheus/prometheus.yml
echo "" | sudo tee -a /etc/prometheus/prometheus.yml
echo "scrape_configs:" | sudo tee -a /etc/prometheus/prometheus.yml
echo "  - job_name: 'prometheus'" | sudo tee -a /etc/prometheus/prometheus.yml
echo "    static_configs:" | sudo tee -a /etc/prometheus/prometheus.yml
echo "      - targets: ['localhost:9090']" | sudo tee -a /etc/prometheus/prometheus.yml

# Run Prometheus container
sudo docker run -d \
     --name prometheus \
     -p 9090:9090 \
     -v /etc/prometheus:/etc/prometheus \
     -v /prometheus:/prometheus \
     prom/prometheus

# Adjust permissions
sudo chmod -R 777 /prometheus

# Restart Prometheus container
sudo docker restart prometheus

echo "Prometheus setup completed successfully!"
