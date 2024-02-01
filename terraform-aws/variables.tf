variable "path_to_key" {
  type        = string
  description = "Path to the private key associated with the public key attached to the Prometheus instance"
  default = "aws.pem"
}

variable "public_key" {
  type        = string
  description = "Public key to be attached to the instance"
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDKVcO6lwQXlMyGqAWmKOfp0xc5v7UZSB5rLdzx+m9s8DuYB8vGCzXRF/lu6gA2LlXNeQoZoppoOi6IzMUAsszLOq8Q8NXIb3S5yDqVwK//FoNWOroU5SI9WsXYpvoZLe6PEgKjRIpj1+STWSEht6CMRCCu5GxqGlCkuGuDKjwkFxK+VafJBk9VK/9+GIdTNDcHwfjsiCQ+9VPPPAz0gMZjcGx5oT7TNzHWQsw/I2FI+jsXvg7y4JUE1MBUDKWu9wraFoKiCfCO3cbDnqhLz2Y7rNHXST1beWex43oQDVPEr+XQttUi+l0SBxz/W2sV7QaRh0kO2Vxi7QPW/wypNV3v0ixsFfqrtHKWIFBA/83BNFVLbkLrdplakfyrXg1Xcowr34Y575TyfmvvBHlgJftXOiKmkxjYsBawt3ptx4y7sqz0FhJLCdnx7J8gwNboWo7N9IdesQLsgE09HyaQ2DE4CcO7LQm74jt51eKICveG7bN2lN/U7qLuu5q0ponqBBQxicW2dcLC2Qz4UleimJAwqOqTVO8o5Bo/XJshh1Bf7NdZm/lDGYyqa0jIKetTXzRNAtsUk43LMyM7Jm1qhh/5e7svKqt7qvuxQIrVAL85zOO7zH3qSmK6XMmyG0BJTy/oDgUjt9Ob+ErxEkN1rrFbYXW7cFkz7T65mZm83VoAww== Siar@MacBook-Pro-929.fritz.box"
}

variable "sudo_pw" {
  type        = string
  description = "Sudo password necessary for docker build"
  sensitive = true
}

