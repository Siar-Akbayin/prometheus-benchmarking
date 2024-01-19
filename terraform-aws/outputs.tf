output "prometheus_server_ip" {
  value = aws_instance.prometheus_server.public_ip
}

output "benchmark_client_ip" {
  value = aws_instance.benchmark_client.public_ip
}

output "metrics_exposer_ip" {
  value = aws_instance.metrics_exposer.public_ip
}
