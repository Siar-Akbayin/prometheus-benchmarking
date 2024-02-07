variable "sudo_pw" {
  type        = string
  description = "Sudo password necessary for docker build"
  sensitive = true
}

variable "container_registry_link" {
  type        = string
  description = "Link to Container Registry where the benchmarking client image should be pushed to. Such as ghcr.io/siar-akbayin/"
}
variable "vpc_id" {
  type        = string
  description = "AWS VPC ID (use default)"
}

variable "subnet_id" {
  type        = string
  description = "AWS Subnet ID (use default)"
}