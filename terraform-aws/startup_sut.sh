#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

# Update and Upgrade the System
sudo apt update
sudo apt upgrade -y

# Install Dependencies for Docker
sudo apt install -y -q apt-transport-https ca-certificates curl software-properties-common

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# Set up the Docker repository
sudo add-apt-repository --yes "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"

# Update apt package index and install Docker CE
sudo apt update
sudo apt install -y -q docker-ce

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Run Prometheus Docker container
echo "Starting Prometheus ..."
sudo docker run -d \
     --name prometheus \
     -p 9090:9090 \
     -v /etc/prometheus:/etc/prometheus \
     -v /prometheus:/prometheus \
     prom/prometheus

echo "Prometheus container started on port 9090"

# Create a file to indicate that the script has finished running
touch /done
