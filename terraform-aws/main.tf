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

resource "aws_key_pair" "deployer" {
  key_name   = "aws"
  public_key = file("${path.module}/aws.pem.pub")
}

# Create a security group
resource "aws_security_group" "my-security-group-csb" {
  name   = "my-security-group-csb"
  vpc_id = var.vpc_id

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

  # Allow inbound for metrics generator
  ingress {
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound for benchmarking tool
  ingress {
    from_port   = 8081
    to_port     = 8081
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

resource "aws_instance" "metrics_generator" {
  ami           = "ami-0c758b376a9cf7862" # Debian 12 64-bit (Arm), username: admin
  instance_type = "m7g.medium"
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  user_data = <<-EOT
    #!/bin/bash

    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo mkdir -p /app  # Create a directory on the instance (if not already present)
    sudo chown -R admin:admin /app  # Change ownership to the desired user (replace 'admin' with the actual username)

    # Pull the Docker image from the registry
    sudo docker pull ghcr.io/siar-akbayin/metricsgenerator:latest


    # Build and run Docker container
    sudo docker run -d -p 8082:8082 --name metricsgenerator ghcr.io/siar-akbayin/metricsgenerator:latest
    EOT
  tags = {
    Name = "Metrics Generator"
  }
}

resource "aws_instance" "benchmark_client" {
  ami           = "ami-0c758b376a9cf7862" # Debian 12 64-bit (Arm), username: admin
  instance_type = "t4g.2xlarge"
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "Benchmarking Client"
  }
}

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
    echo "  - job_name: 'metrics_generator'" | sudo tee -a /etc/prometheus/prometheus.yml
    echo "    static_configs:" | sudo tee -a /etc/prometheus/prometheus.yml
    echo "      - targets: ['${aws_instance.metrics_generator.public_ip}:8082']" | sudo tee -a /etc/prometheus/prometheus.yml

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

  depends_on = [aws_instance.benchmark_client, aws_instance.metrics_generator]

}

# Creates EC2 instance and deploys Prometheus on it
resource "aws_instance" "prometheus_server" {
  ami           = "ami-0c758b376a9cf7862" # Debian 12 64-bit (Arm), username: admin
  instance_type = "m7g.large"
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  user_data = local_file.startup_sut.content

  tags = {
    Name = "Prometheus Server"
  }
  depends_on = [aws_instance.benchmark_client]
}

# Waiting time to let instances set up completely
resource "terraform_data" "wait" {
  provisioner "local-exec" {
    command = "sleep 60"
  }
  depends_on = [aws_instance.prometheus_server]
}

resource "terraform_data" "add_ip_to_config_json" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command = "awk -v ip=${aws_instance.prometheus_server.public_ip} 'NR==2 {sub(/localhost/, ip)}1' ../config.json > temp_file && mv temp_file ../config.json"
  }
  depends_on = [terraform_data.wait]
}

# Build and push benchmarking client image
resource "terraform_data" "build_and_push_image" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command = "echo ${var.sudo_pw} | sudo -S docker build -t ${var.container_registry_link}prombench:latest ../ &&  sudo -S docker push ${var.container_registry_link}prombench:latest"
  }
  depends_on = [terraform_data.add_ip_to_config_json]
}

# ssh into Prometheus instance and set target to itself (port 9090) to scape own performance metrics
resource "terraform_data" "prometheus_setup" {
  provisioner "local-exec" {
    command = <<-EOT
        ssh -o StrictHostKeyChecking=no -i ${aws_key_pair.deployer.key_name}.pem admin@${aws_instance.prometheus_server.public_ip} 'bash -s' <<EOF
        echo "  - job_name: 'prometheus'" | sudo tee -a /etc/prometheus/prometheus.yml
        echo "    static_configs:" | sudo tee -a /etc/prometheus/prometheus.yml
        echo "      - targets: ['${aws_instance.prometheus_server.public_ip}:9090']" | sudo tee -a /etc/prometheus/prometheus.yml
        echo "" | sudo tee -a /etc/prometheus/prometheus.yml
        sudo docker restart prometheus
        EOF
    EOT
  }
  depends_on = [terraform_data.build_and_push_image]
}


resource "terraform_data" "benchmarking_client_setup" {
  provisioner "remote-exec" {
    inline = [
      "ulimit -n 10000",
      "sudo apt update",
      "sudo apt install -y apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sudo sh get-docker.sh",
      "sudo usermod -aG docker $USER",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo mkdir -p /app",  # Creates a directory on the instance (if not already present)
      "sudo chown -R admin:admin /app",  # Changes ownership to the desired user

      # Pull the Docker image from the registry
      "sudo docker pull ${var.container_registry_link}prombench:latest",

      # Wait for pull
      "sleep 20",

      # Build and run Docker container
      "sudo docker run -d -p 8081:8081 --name benchmark_instance ${var.container_registry_link}prombench:latest",

      # Restart container
      "sudo docker restart benchmark_instance"
    ]

    connection {
      type        = "ssh"
      user        = "admin"  # SSH user https://alestic.com/2014/01/ec2-ssh-username/
      private_key = file("${path.module}/${aws_key_pair.deployer.key_name}.pem")
      host        = aws_instance.benchmark_client.public_ip
    }
  }

  depends_on = [terraform_data.wait, aws_instance.prometheus_server, terraform_data.prometheus_setup, terraform_data.build_and_push_image]
}

resource "terraform_data" "retrieve_results" {
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p ~/csvfiles",
      "sudo chown $(whoami) ~/csvfiles",
      "sudo chmod 755 ~/csvfiles",
      "container_id=$(sudo docker ps -aqf 'name=benchmark_instance')",
      "until sudo docker exec $container_id ls /app/benchmark_complete.flag ; do sleep 60; done",
      "sudo docker exec $container_id sh -c 'tar -cvf - /app/*.csv' | tar -xvf - -C ~/csvfiles/"
    ]

    connection {
      type        = "ssh"
      user        = "admin"  # SSH user https://alestic.com/2014/01/ec2-ssh-username/
      private_key = file("${path.module}/${aws_key_pair.deployer.key_name}.pem")
      host        = aws_instance.benchmark_client.public_ip
    }
  }

  depends_on = [terraform_data.benchmarking_client_setup]
}

# ssh into Prometheus instance and set target to itself to scape own performance
resource "terraform_data" "retrieve_csv_files" {
  provisioner "local-exec" {
    command    = "mkdir -p ./results && scp -o StrictHostKeyChecking=no -i ${aws_key_pair.deployer.key_name}.pem admin@${aws_instance.benchmark_client.public_ip}:'~/csvfiles/app/*' ./results"
  }
  depends_on = [terraform_data.retrieve_results]
}
