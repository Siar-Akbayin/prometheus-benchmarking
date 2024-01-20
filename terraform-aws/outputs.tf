output "prometheus_server_ip" {
  value = aws_instance.prometheus_server.public_ip
}

output "benchmark_client_ip" {
  value = aws_instance.benchmark_client.public_ip
}

output "prometheus_dashboard" {
  value = "${aws_instance.prometheus_server.public_ip}:9090"
}
