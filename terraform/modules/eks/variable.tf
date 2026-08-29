variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "ec2_sg_id" {
  description = "Security group shared with worker nodes (allows ALB -> node traffic)"
  type        = string
}

variable "bastion_role_arn" {
  description = "IAM role ARN of the bastion host, granted kubectl/helm admin access via EKS access entry"
  type        = string
}

variable "bastion_sg_id" {
  description = "Security group ID of the bastion, granted access to the EKS control plane API"
  type        = string
}

variable "rds_sg_id" {
  description = "RDS security group ID, to allow pod traffic from the EKS cluster SG to reach the database"
  type        = string
}