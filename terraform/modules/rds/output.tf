output "db_endpoint" {
  value     = aws_db_instance.main.address
  sensitive = true
}

output "db_port" {
  value = aws_db_instance.main.port
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}
