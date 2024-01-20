provider "aws" {
  region = "us-east-2"
}

terraform {
  required_providers {
    aws = {
      version = "~>5.0"
      source  = "hashicorp/aws"
    }
  }
}

# TLS Private Key Resource
#resource "tls_private_key" "terrafrom_generated_private_key" {
#  algorithm = "RSA"
#  rsa_bits  = 4096
#}

# AWS Key Pair Resource
#resource "aws_key_pair" "generated_key" {
#  key_name   = "aws_key_pair"
#  public_key = tls_private_key.terrafrom_generated_private_key.public_key_openssh
#
#  provisioner "local-exec" {
#    command = <<-EOT
#      echo '${tls_private_key.terrafrom_generated_private_key.private_key_pem}' > aws_key_pair.pem
#      echo '${tls_private_key.terrafrom_generated_private_key.public_key_openssh}' > aws_key_pair.pem
#      chmod 400 aws_key_pair.pem
#    EOT
#  }
#}

resource "aws_key_pair" "deployer" {
  key_name   = "aws"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDKVcO6lwQXlMyGqAWmKOfp0xc5v7UZSB5rLdzx+m9s8DuYB8vGCzXRF/lu6gA2LlXNeQoZoppoOi6IzMUAsszLOq8Q8NXIb3S5yDqVwK//FoNWOroU5SI9WsXYpvoZLe6PEgKjRIpj1+STWSEht6CMRCCu5GxqGlCkuGuDKjwkFxK+VafJBk9VK/9+GIdTNDcHwfjsiCQ+9VPPPAz0gMZjcGx5oT7TNzHWQsw/I2FI+jsXvg7y4JUE1MBUDKWu9wraFoKiCfCO3cbDnqhLz2Y7rNHXST1beWex43oQDVPEr+XQttUi+l0SBxz/W2sV7QaRh0kO2Vxi7QPW/wypNV3v0ixsFfqrtHKWIFBA/83BNFVLbkLrdplakfyrXg1Xcowr34Y575TyfmvvBHlgJftXOiKmkxjYsBawt3ptx4y7sqz0FhJLCdnx7J8gwNboWo7N9IdesQLsgE09HyaQ2DE4CcO7LQm74jt51eKICveG7bN2lN/U7qLuu5q0ponqBBQxicW2dcLC2Qz4UleimJAwqOqTVO8o5Bo/XJshh1Bf7NdZm/lDGYyqa0jIKetTXzRNAtsUk43LMyM7Jm1qhh/5e7svKqt7qvuxQIrVAL85zOO7zH3qSmK6XMmyG0BJTy/oDgUjt9Ob+ErxEkN1rrFbYXW7cFkz7T65mZm83VoAww== Siar@MacBook-Pro-929.fritz.box"
}

# Create a new VPC
#resource "aws_vpc" "example_vpc" {
#  cidr_block = "10.0.0.0/16"
#  enable_dns_hostnames = true
#}

# Create an internet gateway
#resource "aws_internet_gateway" "example_igw" {
#  vpc_id = "vpc-0ecaaa86c9a76e267"
#}

# Fetch the latest Amazon Linux AMI for x86_64 architecture
#data "aws_ami" "this" {
#  most_recent = true
#  owners      = ["amazon"]
#
#  filter {
#    name   = "architecture"
#    values = ["x86_64"]
#  }
#
#  filter {
#    name   = "name"
#    values = ["al2023-ami-2023*"]
#  }
#}

# Create a subnet
#resource "aws_subnet" "example_subnet" {
#  vpc_id     = "vpc-0ecaaa86c9a76e267"
#  cidr_block = "172.31.16.0/20"
#  map_public_ip_on_launch = true # Enable public IP
#}

# Create a security group
resource "aws_security_group" "my-security-group-csb" {
  name   = "my-security-group"
  vpc_id = "vpc-0ecaaa86c9a76e267"

  # Allow inbound SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound for Prometheus and custom metrics
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "benchmark_client" {
  ami           = "ami-0ec3d9efceafb89e0" # Debian 12 x86, username: admin
  instance_type = "t3.large"
  subnet_id     = "subnet-034cd218e2b28c58a"
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "Benchmarking Client"
  }
}

#resource "terraform_data" "add_ip_to_script" {
#  provisioner "local-exec" {
#    interpreter = ["bash", "-exc"]
#    command = <<-EOT
#      awk 'NR==2 {sub(/localhost/, ${aws_instance.benchmark_client.public_ip})}1' startup_sut.sh > temp_file && mv temp_file startup_sut.sh
#    EOT
#  }
#  depends_on = [aws_instance.benchmark_client]
#}

resource "local_file" "startup_sut" {
  file_permission = "0666"
  content = <<-EOT
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

  # Append Prometheus configuration to the file
  echo "global:" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "  scrape_interval: 15s" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "scrape_configs:" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "  - job_name: 'prometheus'" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "    static_configs:" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "      - targets: ['localhost:9090']" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "  - job_name: 'benchmarking_client'" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "    static_configs:" | sudo tee -a /etc/prometheus/prometheus.yml
  echo "      - targets: ['${aws_instance.benchmark_client.public_ip}:8081']" | sudo tee -a /etc/prometheus/prometheus.yml

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

    EOT
  filename = "${path.module}/startup_sut.sh"

  depends_on = [aws_instance.benchmark_client]

}


# Create EC2 instance and deploy Prometheus on it
resource "aws_instance" "prometheus_server" {
  ami           = "ami-0ec3d9efceafb89e0" # Debian 12 x86, username: admin
  instance_type = "t3.medium"
  subnet_id     = "subnet-034cd218e2b28c58a"
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  user_data = local_file.startup_sut.content

  tags = {
    Name = "Prometheus Server"
  }
  depends_on = [aws_instance.benchmark_client]
}

#resource "aws_instance" "metrics_exposer" {
#  ami           = "ami-0ec3d9efceafb89e0" # Debian 12 x86, username: admin
#  instance_type = "t3.medium"
#  subnet_id     = "subnet-034cd218e2b28c58a"
#  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
#  key_name = aws_key_pair.deployer.key_name
#
#  tags = {
#    Name = "Metrics Exposer"
#  }
#}


