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
  public_key = var.public_key
}

# Create a new VPC
#resource "aws_vpc" "example_vpc" {
#  cidr_block = "10.0.0.0/16"
#  enable_dns_hostnames = true
#}

# Create a subnet
#resource "aws_subnet" "example_subnet" {
#  vpc_id     = "vpc-0ecaaa86c9a76e267"
#  cidr_block = "172.31.16.0/20"
#  map_public_ip_on_launch = true # Enable public IP
#}

# Create a security group
resource "aws_security_group" "my-security-group-csb" {
  name   = "my-security-group-csb"
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
  instance_type = "m7g.large"
  subnet_id     = "subnet-034cd218e2b28c58a"
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
  instance_type = "m7g.large"
  subnet_id     = "subnet-034cd218e2b28c58a"
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  user_data = <<-EOT
    #!/bin/bash

    # Install Docker
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    sudo systemctl start docker
    sudo systemctl enable docker

    # Copy Dockerfile to the instance
    cat <<EOF > Dockerfile
    FROM golang:1.21.5

    # Set the working directory inside the container
    WORKDIR /app

    # Copy only the necessary files to the container
    COPY benchmark.go .
    COPY config.json .
    COPY go.mod .
    COPY go.sum .

    # Download and install Go module dependencies
    RUN go mod download

    # Build the Go application
    RUN go build -o benchmark

    # Expose the port your application listens on
    EXPOSE 8081

    # Run the binary built above
    CMD ["./benchmark"]
    EOF

    # Build and run the Docker image
    sudo docker build -t prombench .
    sudo docker run -d -p 8081:8081 --name benchmark_instance prombench
    EOT
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

# Create EC2 instance and deploy Prometheus on it
resource "aws_instance" "prometheus_server" {
  ami           = "ami-0c758b376a9cf7862" # Debian 12 64-bit (Arm), username: admin
  instance_type = "m7g.large"
  subnet_id     = "subnet-034cd218e2b28c58a"
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

# build and push benchmarking client image
resource "terraform_data" "build_and_push_image" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command = "echo ${var.sudo_pw} | sudo -S docker build -t ghcr.io/siar-akbayin/prombench:latest ../ &&  sudo -S docker push ghcr.io/siar-akbayin/prombench:latest"
  }
  depends_on = [terraform_data.add_ip_to_config_json]
}

# ssh into Prometheus instance and set target to itself to scape own performance
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
      "sudo apt update",
      "sudo apt install -y apt-transport-https ca-certificates curl software-properties-common",
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sudo sh get-docker.sh",
      "sudo usermod -aG docker $USER",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo mkdir -p /app",  # Create a directory on the instance (if not already present)
      "sudo chown -R admin:admin /app",  # Change ownership to the desired user (replace 'admin' with the actual username)

      # Pull the Docker image from the registry
      "sudo docker pull ghcr.io/siar-akbayin/prombench:latest",

      # Wait for pull
      "sleep 20",

      # Build and run Docker container
      "sudo docker run -d -p 8081:8081 --name benchmark_instance ghcr.io/siar-akbayin/prombench:latest",

      # Restart container
      "sudo docker restart benchmark_instance"
    ]

    connection {
      type        = "ssh"
      user        = "admin"  # SSH user https://alestic.com/2014/01/ec2-ssh-username/
      private_key = file("${path.module}/${aws_key_pair.deployer.key_name}.pem")  # Update with the path to your private key
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
      private_key = file("${path.module}/${aws_key_pair.deployer.key_name}.pem")  # Update with the path to your private key
      host        = aws_instance.benchmark_client.public_ip
    }
  }

  depends_on = [terraform_data.benchmarking_client_setup]
}

resource "local_file" "retrieve_csv_files" {
  file_permission = "0666"
  content = <<-EOT
    #!/bin/bash
    scp -i ${aws_key_pair.deployer.key_name}.pem admin@${aws_instance.benchmark_client.public_ip}:'~/csvfiles/app/*' ./results
    EOT
  filename = "${path.module}/get_results.sh"

  depends_on = [terraform_data.retrieve_results]

}



