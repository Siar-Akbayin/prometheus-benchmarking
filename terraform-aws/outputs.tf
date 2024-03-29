output "prometheus_server_ip" {
  value = aws_instance.prometheus_server.public_ip
}

output "benchmark_client_ip" {
  value = aws_instance.benchmark_client.public_ip
}

output "metrics_generator_ip" {
  value = aws_instance.metrics_generator.public_ip
}

output "prometheus_dashboard" {
  value = "http://${aws_instance.prometheus_server.public_ip}:9090"
}

output "results" {
  value = "The CSV files with the results are stored in the results folder"
}

