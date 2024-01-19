provider "aws" {
  region = "us-east-2"
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC76iD0YS+IiRdo3meTmoxBipOjubxRVNmPtTamwA860NoLpvcqj0YlYyz4zeELmPCtJzrsuRdIRxoVJTLeJ5u8scUYVDQCMWoY/z16iPe6NVAgughzqjCftm5FAIQF7yh0f4Y3J1/I9wVeCMCQ9P0mdgGx9fr3j9uqWpw2Nsh0s8a7TIf7DsDkmkrIAGvA7YqMfTOhEtAXCiZJHTEKcv/Wf0+jo+XLFK0sVxv8anviJ1uNdh/DPstLEHjCveYxPcDJTubTAJ6hXHLWpmT3Coa/nqIE+OglyG3CfvUerT8wGuiAFspY9B/eNkW74TVRScPYJ2RxRYvwUgF5FHcZ7ny0rydWYKtPeu1yyIOB9FgMMj4C42TVz5Lv6UVchMge/lHAF4cCH2dpURYZi82jYrYAddjlzrgcG9iDUYPjqkVar5ARxbSPtwAUJkU1GpAV88TmBAv7Redm/aspvdniEDdVL7Vt2i32vp2MugJZOhxX7VRPL2y5GCL6gydsH5H2KQYwIu+ylZ2AKHFOEAYFGS9xPGkINMAQY3J8Iz/0NpMSZWf+HuU8SxONItEOHUdyyljxcvWKWVk4e3koBnymS7JrVeJkoguBTuNSZeIZyGEkQ5gdYM1K1m9louoidKGIMLUPZva+a9da2gJV+QwFLsFMSXYhe3CI0IppDUAJjeTBoQ== your_email@example.com"
}

# Create a new VPC
resource "aws_vpc" "example_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

# Create an internet gateway
resource "aws_internet_gateway" "example_igw" {
  vpc_id = aws_vpc.example_vpc.id
}

# Fetch the latest Amazon Linux AMI for x86_64 architecture
data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
}

# Create a subnet
resource "aws_subnet" "example_subnet" {
  vpc_id     = aws_vpc.example_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true # Enable public IP
}

# Create a security group
resource "aws_security_group" "my-security-group-csb" {
  name   = "my-security-group"
  vpc_id = aws_vpc.example_vpc.id

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

# Create EC2 instances
resource "aws_instance" "prometheus_server" {
  ami           = data.aws_ami.this.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.example_subnet.id
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  user_data = file("startup_sut.sh")

  tags = {
    Name = "Prometheus Server"
  }
}

resource "aws_instance" "benchmark_client" {
  ami           = data.aws_ami.this.id
  instance_type = "t3.large"
  subnet_id     = aws_subnet.example_subnet.id
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "Benchmarking Client"
  }
}

resource "aws_instance" "metrics_exposer" {
  ami           = data.aws_ami.this.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.example_subnet.id
  vpc_security_group_ids = [aws_security_group.my-security-group-csb.id]
  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name = "Metrics Exposer"
  }
}
