variable "path_to_key" {
  type        = string
  description = "Path to the private key associated with the public key attached to the Prometheus instance"
}

variable "public_key" {
  type        = string
  description = "Public key to be attached to the instance"
}

