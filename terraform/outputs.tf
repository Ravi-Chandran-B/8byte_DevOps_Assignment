output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "rds_endpoint" {
  description = "RDS instance endpoint (address only)"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN holding DB credentials"
  value       = module.rds.secret_arn
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster (use with: aws eks update-kubeconfig)"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "bastion_instance_id" {
  description = "Use with: aws ssm start-session --target <this-value>"
  value       = module.bastion.instance_id
}

output "bastion_public_ip" {
  description = "SSH: ssh -i <your-key>.pem ec2-user@<this-value>"
  value       = module.bastion.public_ip
}

output "ecr_repository_url" {
  description = "docker push/pull target"
  value       = module.ecr.repository_url
}