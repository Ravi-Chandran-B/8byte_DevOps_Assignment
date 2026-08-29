output "repository_url" {
  description = "Full ECR repo URL to push/pull images"
  value       = aws_ecr_repository.app.repository_url
}

output "repository_arn" {
  value = aws_ecr_repository.app.arn
}

output "repository_name" {
  description = "Name of the ECR repository"
  value = aws_ecr_repository.app.name
}