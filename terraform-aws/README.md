
# Terraform Configuration for AWS Infrastructure Setup

This Terraform configuration sets up a comprehensive AWS infrastructure tailored for monitoring and benchmarking purposes. It automates the provisioning of AWS resources, including EC2 instances for a metrics generator, a benchmarking client, and a Prometheus server. Additionally, it handles the creation of a security group with predefined rules and generates an RSA key pair for secure SSH access.

## Components

### Providers

- **AWS**: Configured for the `us-east-2` region, utilizing version `~>5.0` of the AWS provider.

### Resources
#### `aws_key_pair.deployer`

- Uploads the generated public SSH key to AWS to create a key pair named `aws`.
- Ensures EC2 instances can be accessed securely via SSH using the generated key pair.
- Depends on the successful creation and local saving of the SSH key pair.

#### `aws_security_group.my-security-group-csb`

- Defines network access rules for the infrastructure, facilitating both inbound and outbound traffic.
- Allows inbound SSH access, Prometheus metrics access, metrics generator access, and benchmarking tool access.

#### EC2 Instances

- **Metrics Generator (`aws_instance.metrics_generator`)**: Configured with Docker to pull and run a metrics generator container. It's designed to generate metrics for Prometheus to scrape.
- **Benchmarking Client (`aws_instance.benchmark_client`)**: Set up to execute benchmarking tasks and interact with the Prometheus server.
- **Prometheus Server (`aws_instance.prometheus_server`)**: Runs a Prometheus container configured to scrape metrics from the metrics generator.

### Security

- The configuration ensures secure SSH access to EC2 instances by generating a key pair and applying it to instances.
- Network security is managed via a custom AWS security group that specifies allowed inbound and outbound traffic.

### Automation and Provisioning Scripts

- **User Data Scripts**: Automate the installation and setup of Docker, Prometheus, and other necessary tools on EC2 instances.
- **Local-exec Provisioners**: Used for tasks like SSH key generation, modifying local files, and running local scripts to interact with the infrastructure.

### Data Collection and Retrieval

- Executes scripts to collect benchmarking results from the benchmarking client and securely transfer them to the local machine for analysis. Results can be found in the generated `results` folder.
- The Terraform run will wait until the whole experiment is done and loop during waiting time. However, the benchmarking client will continue to run even if you stop the Terraform run. Then you will need to run `mkdir -p ./results && scp -o StrictHostKeyChecking=no -i ${aws_key_pair.deployer.key_name}.pem admin@${aws_instance.benchmark_client.public_ip}:'~/csvfiles/app/*' ./results` manually.

## Usage

### Prerequisites
The following cli tools need to be installed: docker, awk, ssh, ssh-keygen, scp, and terraform.

### Setup
Before applying this Terraform configuration, an RSA 4096-bit key pair named `aws` has to be generated and saved locally:

```shell
ssh-keygen -t rsa -b 4096 -N '' -f aws.pem
```

To apply this configuration:

1. Ensure you have Terraform installed and configured with your AWS credentials.
2. Run `terraform init` to initialize the Terraform working directory and download the required providers.
3. Run `terraform plan` to review the changes that will be made to your infrastructure.
4. Execute `terraform apply -auto-approve` to provision the resources on AWS as defined in this configuration.
5. You will need to provide your AWS VPC and Subnet ID, a Docker container registry URL where you have push access and your sudo password.

Ensure that you have the necessary permissions in your AWS account to create and manage the resources defined in this Terraform configuration.


## Cleanup
To destroy the infrastructure created by this Terraform configuration, run `terraform destroy -auto-approve` (provide registry URL and sudo pw again). This will remove all resources created by this configuration from your AWS account.

Delete the key pair manually.
